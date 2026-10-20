#!/usr/bin/env python3
"""Distribution regressions: only temporary files, local Git repos and mocked tools."""
import os
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
REAL_GIT = shutil.which("git")


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.home = self.work / "home"
        self.home.mkdir()
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin")
        for name in ("SUMMON_SIGN_IDENTITY", "SUMMON_NOTARY_PROFILE", "SUMMON_SIGN_ENTITLEMENTS",
                     "SUMMONOS_MACCTL_SOURCE", "SUMMON_PATH", "BASH_ENV", "ENV", "GIT_DIR",
                     "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS"):
            self.env.pop(name, None)
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        # An unexpected test path must never touch real keychain credentials or Apple services.
        for command in ("security", "xcrun", "spctl", "gh"):
            self.executable(self.bin / command, "exit 99")

    def run_script(self, script, *args, cwd=None):
        return subprocess.run(["bash", str(script), *map(str, args)], cwd=cwd or self.work, env=self.env,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def executable(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/bash\nset -eu\n" + body + "\n")
        path.chmod(0o755)

    def scan(self, patterns, content="ordinary text", name="file"):
        rules = self.work / "patterns"
        rules.write_text(patterns)
        tree = self.work / "tree"
        tree.mkdir()
        (tree / name).write_bytes(content.encode())
        return self.run_script(ROOT / "tools/private-scan.sh", rules, tree)

    def test_scan_allows_clean_tree(self):
        self.assertEqual(self.scan("private-value\n").returncode, 0)

    def test_scan_rejects_match_without_printing_secret(self):
        result = self.scan("private-value\n", "private-value")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("private-value", result.stdout + result.stderr)

    def test_scan_rejects_private_file_names_without_printing_them(self):
        result = self.scan("private-value\n", name="private-value.txt")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("private-value", result.stdout + result.stderr)

    def test_scan_rejects_invalid_regex(self):
        self.assertNotEqual(self.scan("[\n").returncode, 0)

    def test_scan_rejects_empty_rules(self):
        self.assertNotEqual(self.scan("").returncode, 0)

    def test_scan_rejects_missing_rules(self):
        result = self.run_script(ROOT / "tools/private-scan.sh", self.work / "missing", self.work)
        self.assertNotEqual(result.returncode, 0)

    def test_scan_checks_binary_named_assets(self):
        self.assertNotEqual(self.scan("private-value\n", "\x00private-value", "image.png").returncode, 0)

    def test_scan_rejects_private_symlink_target(self):
        rules = self.work / "patterns"
        rules.write_text("private-host\n")
        tree = self.work / "tree"
        tree.mkdir()
        (tree / "link").symlink_to("/private-host/missing")
        self.assertNotEqual(self.run_script(ROOT / "tools/private-scan.sh", rules, tree).returncode, 0)

    def test_scan_rejects_find_error(self):
        self.executable(self.bin / "find", "exit 7")
        self.assertNotEqual(self.scan("private-value\n").returncode, 0)

    def test_scan_rejects_runtime_read_error(self):
        # Validation is allowed through; reading an exported file reports an I/O error.
        self.executable(self.bin / "grep", '''
if [[ $1 == -aEf && ${3:-} == -- ]]; then exit 2; fi
exec /usr/bin/grep "$@"
''')
        self.assertNotEqual(self.scan("private-value\n").returncode, 0)

    def install_fixture(self):
        package = self.work / "summon"
        (package / "scripts").mkdir(parents=True)
        shutil.copy2(ROOT / "incubator/summon/scripts/install.sh", package / "scripts/install.sh")
        state_helper = ROOT / "incubator/summon/scripts/install-state.py"
        if state_helper.exists():
            shutil.copy2(state_helper, package / "scripts/install-state.py")
        self.executable(package / "build/Summon.app/Contents/MacOS/SummonMenu", "exit 0")
        self.executable(package / "build/Summon.app/Contents/MacOS/summon", '''
if [[ ${1:-} == menu && ${FAIL_INIT:-0} == 1 ]]; then exit 4; fi
echo new-summon
''')
        (package / "themes/test").mkdir(parents=True)
        (package / "themes/test/theme.json").write_text("{}")
        old = self.home / "Applications/Summon.app"
        old.mkdir(parents=True)
        (old / "old-version").write_text("previous")
        self.executable(self.home / ".local/bin/macctl", "echo old-macctl")
        self.executable(self.home / ".local/bin/summon", "echo old-summon")
        new_macctl = self.work / "new-macctl"
        self.executable(new_macctl, "echo new-macctl")
        self.env["SUMMONOS_MACCTL_SOURCE"] = str(new_macctl)
        self.executable(self.bin / "codesign", "exit 0")
        return package / "scripts/install.sh"

    def assert_old_install(self):
        self.assertTrue((self.home / "Applications/Summon.app/old-version").is_file())
        self.assertIn("old-macctl", (self.home / ".local/bin/macctl").read_text())
        self.assertIn("old-summon", (self.home / ".local/bin/summon").read_text())

    def test_failed_app_staging_preserves_both_binaries(self):
        script = self.install_fixture()
        self.executable(self.bin / "cp", "exit 8")
        result = self.run_script(script)
        self.assertNotEqual(result.returncode, 0)
        self.assert_old_install()

    def test_failed_initialization_rolls_back_both_binaries(self):
        script = self.install_fixture()
        self.env["FAIL_INIT"] = "1"
        result = self.run_script(script)
        self.assertNotEqual(result.returncode, 0)
        self.assert_old_install()

    def test_successful_install_replaces_both_after_staging(self):
        result = self.run_script(self.install_fixture())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / "Applications/Summon.app/old-version").exists())
        self.assertTrue((self.home / ".local/bin/summon").is_symlink())
        self.assertIn("new-macctl", (self.home / ".local/bin/macctl").read_text())

    def test_install_rejects_live_app_symlink(self):
        script = self.install_fixture()
        app = self.home / "Applications/Summon.app"
        saved = self.home / "Applications/other.app"
        app.rename(saved)
        app.symlink_to(saved)
        result = self.run_script(script)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(app.is_symlink())
        self.assertTrue((saved / "old-version").exists())

    def test_failed_recovery_retains_backups(self):
        script = self.install_fixture()
        self.env["FAIL_INIT"] = "1"
        self.executable(self.bin / "mv", '''
case $1 in *previous.app|*previous-macctl|*previous-summon) exit 8;; esac
exec /bin/mv "$@"
''')
        result = self.run_script(script)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("automatic recovery failed", result.stderr)
        self.assertTrue(list((self.home / "Applications").glob(".summon-install.*/previous.app/old-version")))
        self.assertTrue(list((self.home / ".local/bin").glob(".summon-install.*/previous-macctl")))

    def test_install_rejects_concurrent_installation(self):
        script = self.install_fixture()
        (self.home / "Applications/.summon-install.lock").mkdir()
        result = self.run_script(script)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Install lock exists", result.stderr)
        self.assert_old_install()

    def root_install_fixture(self):
        child = self.install_fixture()
        workspace = self.work / "workspace"
        package = workspace / "incubator/summon"
        package.parent.mkdir(parents=True)
        child.parent.parent.rename(package)
        shutil.copy2(ROOT / "install.sh", workspace / "install.sh")
        (workspace / "macctl").mkdir()
        self.executable(package / "scripts/bundle.sh", "exit ${FAIL_BUILD:-0}")
        self.executable(self.bin / "uname", "echo Darwin")
        self.executable(self.bin / "sw_vers", "echo 15.0")
        self.env["FIXTURE_MACCTL_BIN"] = str(self.work)
        (self.work / "new-macctl").rename(self.work / "macctl")
        self.executable(self.bin / "swift", '''
if [[ $1 == --version ]]; then echo 'Swift version 6.0'
elif [[ " $* " == *' --show-bin-path '* ]]; then echo "$FIXTURE_MACCTL_BIN"
fi
''')
        return workspace / "install.sh", package

    def test_summon_build_failure_keeps_previous_macctl(self):
        script, _ = self.root_install_fixture()
        self.env["FAIL_BUILD"] = "8"
        result = self.run_script(script)
        self.assertNotEqual(result.returncode, 0)
        self.assert_old_install()

    def test_root_installer_reports_doctor_failure_honestly(self):
        script, package = self.root_install_fixture()
        self.executable(package / "build/Summon.app/Contents/MacOS/summon", '''
if [[ ${1:-} == doctor ]]; then echo 'fixture doctor failure' >&2; exit 1; fi
''')
        result = self.run_script(script)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("doctor found failed checks", result.stderr)
        self.assertNotIn("SummonOS is installed.", result.stdout)

    def test_root_installer_success(self):
        script, _ = self.root_install_fixture()
        result = self.run_script(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SummonOS is installed.", result.stdout)

    def manifest(self):
        return self.home / "Library/Application Support/Summon/install-manifest.json"

    def uninstall(self, *args):
        return self.run_script(ROOT / "tools/uninstall.sh", *args)

    def test_install_records_private_manifest(self):
        result = self.run_script(self.install_fixture())
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(self.manifest().read_text())
        self.assertEqual(data["version"], 1)
        self.assertEqual(len(data["entries"]), 3)
        self.assertEqual(self.manifest().stat().st_mode & 0o777, 0o600)

    def test_uninstall_defaults_to_preview_and_preserves_user_data(self):
        self.run_script(self.install_fixture())
        project = self.home / "Summon/important.txt"
        project.write_text("user project")
        result = self.uninstall()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / "Applications/Summon.app").is_dir())
        self.assertTrue(self.manifest().exists())
        result = self.uninstall("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / "Applications/Summon.app").exists())
        self.assertFalse((self.home / ".local/bin/macctl").exists())
        self.assertFalse((self.home / ".local/bin/summon").is_symlink())
        self.assertTrue(project.exists())
        self.assertTrue((self.home / ".config/summon/themes/test/theme.json").exists())

    def test_uninstall_keeps_modified_binary(self):
        self.run_script(self.install_fixture())
        binary = self.home / ".local/bin/macctl"
        binary.write_text("user replacement")
        result = self.uninstall("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(binary.read_text(), "user replacement")
        self.assertTrue(self.manifest().exists())

    def test_uninstall_rejects_manifest_path_escape(self):
        self.run_script(self.install_fixture())
        victim = self.home / "important"
        victim.write_text("keep")
        data = json.loads(self.manifest().read_text())
        data["entries"][0]["path"] = str(victim)
        self.manifest().write_text(json.dumps(data))
        result = self.uninstall("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(victim.exists())
        self.assertTrue((self.home / "Applications/Summon.app").exists())

    def test_uninstall_rejects_missing_receipt(self):
        self.install_fixture()
        result = self.uninstall("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assert_old_install()

    def test_uninstall_preserves_app_with_new_user_file(self):
        self.run_script(self.install_fixture())
        added = self.home / "Applications/Summon.app/user-file"
        added.write_text("keep")
        result = self.uninstall("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(added.exists())

    def test_failed_receipt_update_rolls_back_and_retains_previous_receipt(self):
        installer = self.install_fixture()
        first = self.run_script(installer)
        self.assertEqual(first.returncode, 0, first.stderr)
        receipt = self.manifest().read_bytes()
        source = installer.parent.parent / "build/Summon.app/Contents/MacOS/summon"
        self.executable(source, "echo changed-version")
        (installer.parent / "install-state.py").write_text("raise SystemExit(7)\n")
        result = self.run_script(installer)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.manifest().read_bytes(), receipt)
        self.assertIn("echo new-summon", (self.home / "Applications/Summon.app/Contents/MacOS/summon").read_text())

    def test_uninstall_rejects_receipt_symlink(self):
        self.run_script(self.install_fixture())
        elsewhere = self.work / "elsewhere.json"
        self.manifest().rename(elsewhere)
        self.manifest().symlink_to(elsewhere)
        result = self.uninstall("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.home / "Applications/Summon.app").exists())
        self.assertTrue(elsewhere.exists())

    def test_uninstall_removes_only_recorded_skill_links(self):
        installer = self.install_fixture()
        skill = self.home / "Applications/Summon.app/Contents/share/summon/skills/summon"
        owned = self.home / ".codex/skills/summon"
        owned.parent.mkdir(parents=True)
        owned.symlink_to(skill)
        foreign = self.home / ".codex/skills/custom"
        foreign.symlink_to(self.home / "user-skills")
        self.run_script(installer)
        result = self.uninstall("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(owned.is_symlink())
        self.assertTrue(foreign.is_symlink())

    def signing_fixture(self):
        app = self.work / "Demo.app"
        self.executable(app / "Contents/MacOS/Demo", "echo input")
        self.executable(app / "Contents/MacOS/summon", "echo cli")
        self.executable(app / "Contents/Frameworks/Helper.framework/Versions/A/Helper", "echo framework")
        self.env["SUMMON_SIGN_IDENTITY"] = "Developer ID Application: Fixture (ABCDEFGHIJ)"
        self.env["SUMMON_NOTARY_PROFILE"] = "fixture-profile"
        self.env["FIXTURE_SIGN_LOG"] = str(self.work / "sign.log")
        self.executable(self.bin / "security", '''
echo '1) 0123456789 "Developer ID Application: Fixture (ABCDEFGHIJ)"'
''')
        self.executable(self.bin / "file", "echo 'Mach-O 64-bit executable arm64'")
        self.executable(self.bin / "codesign", '''
printf 'codesign %s\\n' "$*" >> "$FIXTURE_SIGN_LOG"
if [[ ${FAIL_SIGN:-0} == 1 ]]; then exit 8; fi
if [[ $1 == --force ]]; then
  target=${@: -1}
  if [[ -d $target ]]; then touch "$target/.fixture-signed"
  else printf '# signed\\n' >> "$target"; fi
fi
''')
        self.executable(self.bin / "xcrun", '''
printf 'xcrun %s\\n' "$*" >> "$FIXTURE_SIGN_LOG"
if [[ $1 == notarytool ]]; then printf '{"status":"%s"}\\n' "${NOTARY_STATUS:-Accepted}"; fi
if [[ $1 == stapler && ${FAIL_STAPLE:-0} == 1 ]]; then exit 9; fi
if [[ $1 == stapler && $2 == staple ]]; then touch "${@: -1}/.fixture-ticket"; fi
if [[ $1 == stapler && $2 == validate ]]; then test -f "${@: -1}/.fixture-ticket"; fi
''')
        self.executable(self.bin / "spctl", '''
printf 'spctl %s\\n' "$*" >> "$FIXTURE_SIGN_LOG"
exit "${FAIL_ASSESS:-0}"
''')
        self.executable(self.bin / "ditto", '''
source=${@: -2:1}
if [[ -f $source/.fixture-ticket ]]; then printf stapled-artifact > "${@: -1}"
else printf submission-artifact > "${@: -1}"; fi
''')
        return app, self.work / "signed"

    def sign(self, app, output):
        return self.run_script(ROOT / "tools/notarize-app.sh", app, output)

    def test_signing_uses_hardened_runtime_timestamp_and_stapling(self):
        app, output = self.signing_fixture()
        result = self.sign(app, output)
        self.assertEqual(result.returncode, 0, result.stderr)
        log = (self.work / "sign.log").read_text()
        self.assertIn("--options runtime --timestamp", log)
        self.assertIn("Contents/MacOS/summon", log)
        self.assertIn("notarytool submit", log)
        self.assertIn("stapler staple", log)
        self.assertIn("stapler validate", log)
        self.assertIn("spctl --assess", log)
        self.assertTrue((output / "Demo.zip").exists())
        self.assertTrue((output / "SHA256SUMS").exists())
        self.assertEqual((output / "Demo.zip").read_text(), "stapled-artifact")
        self.assertEqual((app / "Contents/MacOS/Demo").read_text().splitlines()[-1], "echo input")
        self.assertFalse((app / ".fixture-ticket").exists())
        self.assertIn("Helper.framework", log)

    def test_signing_rejects_non_developer_id(self):
        app, output = self.signing_fixture()
        self.env["SUMMON_SIGN_IDENTITY"] = "-"
        self.assertNotEqual(self.sign(app, output).returncode, 0)
        self.assertFalse((output / "Demo.zip").exists())

    def test_signing_rejects_notary_rejection(self):
        app, output = self.signing_fixture()
        self.env["NOTARY_STATUS"] = "Invalid"
        self.assertNotEqual(self.sign(app, output).returncode, 0)
        self.assertFalse((output / "Demo.zip").exists())

    def test_signing_rejects_missing_keychain_identity(self):
        app, output = self.signing_fixture()
        self.executable(self.bin / "security", "echo '0 valid identities found'")
        self.assertNotEqual(self.sign(app, output).returncode, 0)
        self.assertFalse((self.work / "sign.log").exists())

    def test_signing_rejects_codesign_failure(self):
        app, output = self.signing_fixture()
        self.env["FAIL_SIGN"] = "1"
        self.assertNotEqual(self.sign(app, output).returncode, 0)
        self.assertFalse((output / "Demo.zip").exists())
        self.assertNotIn("notarytool", (self.work / "sign.log").read_text())

    def test_signing_rejects_staple_failure(self):
        app, output = self.signing_fixture()
        self.env["FAIL_STAPLE"] = "1"
        self.assertNotEqual(self.sign(app, output).returncode, 0)
        self.assertFalse((output / "Demo.zip").exists())

    def test_signing_rejects_assessment_failure(self):
        app, output = self.signing_fixture()
        self.env["FAIL_ASSESS"] = "1"
        self.assertNotEqual(self.sign(app, output).returncode, 0)
        self.assertFalse((output / "Demo.zip").exists())

    def git(self, *args, cwd):
        return subprocess.run([REAL_GIT, "-c", "core.hooksPath=/dev/null", *args], cwd=cwd, env=self.env,
                              check=True, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.strip()

    def release_fixture(self):
        plugin = self.work / "demo"
        plugin.mkdir()
        self.git("init", "-b", "main", cwd=plugin)
        self.git("config", "user.name", "Fixture", cwd=plugin)
        self.git("config", "user.email", "fixture@example.invalid", cwd=plugin)
        (plugin / ".gitignore").write_text("build/\n")
        (plugin / "Resources").mkdir()
        (plugin / "Resources/Info.plist").write_text("fixture metadata read by mocked plutil\n")
        self.executable(plugin / "scripts/check.sh", '''
cd "$(dirname "$0")/.."
mkdir -p build/Demo.app/Contents/MacOS
printf fixture > build/Demo.app/Contents/MacOS/Demo
''')
        self.git("add", ".", cwd=plugin)
        self.git("commit", "-m", "fixture", cwd=plugin)
        public = self.work / "public.git"
        self.git("clone", "--bare", str(plugin), str(public), cwd=self.work)
        self.env["FIXTURE_PUBLIC"] = str(public)
        self.env["FIXTURE_RELEASE"] = str(self.work / "release-args")
        self.env["FIXTURE_NOTES"] = str(self.work / "release-notes")
        self.executable(self.bin / "gh", '''
if [[ $1 == api ]]; then echo fixture-owner
elif [[ $1 == repo ]]; then echo false
elif [[ $1 == release && $2 == create ]]; then
  printf '%s\\n' "$@" > "$FIXTURE_RELEASE"
  previous=''
  for argument in "$@"; do
    if [[ $previous == --notes-file ]]; then cp "$argument" "$FIXTURE_NOTES"; fi
    previous=$argument
  done
else exit 90; fi
''')
        real_git = REAL_GIT
        self.executable(self.bin / "git", f'''
if [[ $1 == clone ]]; then
  exec '{real_git}' clone --quiet "$FIXTURE_PUBLIC" "${{@: -1}}"
fi
exec '{real_git}' "$@"
''')
        self.executable(self.bin / "plutil", '''
case $2 in CFBundleExecutable) echo Demo;; CFBundleShortVersionString) echo 1.2.3;; *) exit 8;; esac
''')
        self.executable(self.bin / "ditto", '''
printf 'fixture zip' > "${@: -1}"
''')
        self.executable(self.bin / "codesign", "exit 0")
        return plugin

    def test_release_rejects_dirty_source(self):
        plugin = self.release_fixture()
        (plugin / "Resources/Info.plist").write_text("dirty\n")
        result = self.run_script(ROOT / "tools/release.sh", plugin)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.work / "release-args").exists())

    def test_release_rejects_unpublished_source(self):
        plugin = self.release_fixture()
        (plugin / "new-source").write_text("unpublished")
        self.git("add", ".", cwd=plugin)
        self.git("commit", "-m", "unpublished", cwd=plugin)
        result = self.run_script(ROOT / "tools/release.sh", plugin)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.work / "release-args").exists())

    def test_release_rejects_private_target(self):
        plugin = self.release_fixture()
        self.executable(self.bin / "gh", '''
if [[ $1 == api ]]; then echo fixture-owner; else echo true; fi
''')
        result = self.run_script(ROOT / "tools/release.sh", plugin)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("public repository", result.stderr)

    def test_release_rejects_invalid_signature(self):
        plugin = self.release_fixture()
        self.executable(self.bin / "codesign", "exit 6")
        result = self.run_script(ROOT / "tools/release.sh", plugin)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.work / "release-args").exists())

    def test_release_allows_private_context_only_difference(self):
        plugin = self.release_fixture()
        (plugin / "PROJECT-CONTEXT.md").write_text("private development context")
        self.git("add", ".", cwd=plugin)
        self.git("commit", "-m", "private context", cwd=plugin)
        public_sha = self.git("--git-dir", str(self.work / "public.git"), "rev-parse", "main", cwd=self.work)
        result = self.run_script(ROOT / "tools/release.sh", plugin)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(public_sha, (plugin / "build/release-source.txt").read_text())

    def test_release_targets_exact_commit_and_emits_checksum(self):
        plugin = self.release_fixture()
        sha = self.git("rev-parse", "HEAD", cwd=plugin)
        result = self.run_script(ROOT / "tools/release.sh", plugin)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = (self.work / "release-args").read_text()
        self.assertIn("--target\n" + sha, args)
        self.assertIn("SHA256SUMS", args)
        self.assertIn(sha, (plugin / "build/release-source.txt").read_text())

    def test_production_release_requires_both_signing_inputs(self):
        plugin = self.release_fixture()
        self.env["SUMMON_SIGN_IDENTITY"] = "Developer ID Application: Fixture (ABCDEFGHIJ)"
        result = self.run_script(ROOT / "tools/release.sh", plugin)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.work / "release-args").exists())

    def test_production_notary_rejection_blocks_release(self):
        plugin = self.release_fixture()
        self.signing_fixture()
        self.env["NOTARY_STATUS"] = "Invalid"
        result = self.run_script(ROOT / "tools/release.sh", plugin)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.work / "release-args").exists())
        self.assertFalse((plugin / "build/Demo-1.2.3.zip").exists())

    def test_production_assessment_failure_blocks_release(self):
        plugin = self.release_fixture()
        self.signing_fixture()
        self.env["FAIL_ASSESS"] = "1"
        result = self.run_script(ROOT / "tools/release.sh", plugin)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.work / "release-args").exists())

    def test_production_release_uses_notarized_artifact_and_accurate_notes(self):
        plugin = self.release_fixture()
        self.signing_fixture()
        result = self.run_script(ROOT / "tools/release.sh", plugin)
        self.assertEqual(result.returncode, 0, result.stderr)
        notes = (self.work / "release-notes").read_text()
        self.assertIn("notarized by Apple", notes)
        self.assertNotIn("Open Anyway", notes)
        self.assertNotIn("quarantine", notes)
        self.assertNotIn("not notarized", notes)
        self.assertIn("stapler validate", (self.work / "sign.log").read_text())


if __name__ == "__main__":
    unittest.main()
