"""Behavioral failure-boundary tests. All install fixtures use a disposable HOME."""
import importlib.util
import json
import os
import pathlib
import plistlib
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "tools/build-metadata.py"
INSTALLER = ROOT / "incubator/summon/scripts/install.sh"
spec = importlib.util.spec_from_file_location("summon_build_metadata", GENERATOR)
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)

trace_spec = importlib.util.spec_from_file_location("summon_runtime_trace",
    ROOT / "incubator/summon/scripts/runtime-trace.py")
trace_parser = importlib.util.module_from_spec(trace_spec)
trace_spec.loader.exec_module(trace_parser)

class MetadataAndInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="summon-automation-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.source = self.root / "source"
        (self.source / "incubator/summon").mkdir(parents=True)
        (self.source / "incubator/summon/Package.swift").write_text("// fixture\n")
        (self.source / "VERSION").write_text("0.2.4\n")
        self.stage = self.root / "stage"
        (self.stage / "Sources/SummonCore").mkdir(parents=True)
        (self.stage / "Sources/SummonCore/Version.swift").write_text("public enum SummonVersion {}\n")
        (self.stage / "Resources").mkdir()
        (self.stage / "Resources/Info.plist").write_bytes(plistlib.dumps({"CFBundleName": "Summon"}))
        self.app = self.root / "Summon.app"
        (self.app / "Contents/Resources/Metadata.appintents").mkdir(parents=True)
        (self.app / "Contents/Resources/Metadata.appintents/extract.actionsdata").write_text("actions")
        (self.app / "Contents/MacOS").mkdir()
        self.macctl = self.root / "macctl"
        self.tool_bin = self.root / "bin"
        self.tool_bin.mkdir()
        self._executable(self.tool_bin / "codesign", "#!/bin/sh\nexit 0\n")
        self._executable(self.macctl, "#!/bin/sh\necho 'macctl 0.2.4'\n")
        self._executable(self.app / "Contents/MacOS/SummonMenu", "#!/bin/sh\nexit 0\n")
        self.revision = "a" * 40

    @staticmethod
    def _executable(path, content):
        path.write_text(content)
        path.chmod(0o755)

    def generate(self, channel="development", dirty=False):
        def git(command, *args, cwd=None):
            if command.endswith("git"):
                return " M VERSION" if "status" in args and dirty else self.revision if "rev-parse" in args else ""
            raise AssertionError(command)
        with mock.patch.object(metadata, "run", side_effect=git):
            data = metadata.identity(self.source, channel, "123", 1700000000, "release")
        metadata.validate(data)
        args = type("Arguments", (), dict(source_root=self.source, stage_root=self.stage, channel=channel,
                                            build_number="123", source_date_epoch=1700000000,
                                            configuration="release"))()
        with mock.patch.object(metadata, "run", side_effect=git):
            metadata.generate(args)
        (self.app / "Contents/Info.plist").write_bytes((self.stage / "Resources/Info.plist").read_bytes())
        (self.app / "Contents/Resources/BuildInfo.json").write_bytes((self.stage / "BuildInfo.json").read_bytes())
        self._executable(self.app / "Contents/MacOS/summon", "#!/bin/sh\ncase \"$1\" in\n"
                         f"--version) echo 'summon {data['current']}' ;;\n"
                         "*) exit 0 ;;\nesac\n")
        return data

    def installer(self, *args, env_extra=None):
        env = dict(os.environ, HOME=str(self.home), PATH=str(self.tool_bin) + ":" + os.environ["PATH"],
                   SUMMONOS_APP_SOURCE=str(self.app))
        if env_extra: env.update(env_extra)
        return subprocess.run(["/bin/bash", str(INSTALLER), *args], env=env, text=True, capture_output=True)

    def test_metadata_is_reproducible_staged_and_edge_is_not_marketing_version(self):
        original = (self.source / "VERSION").read_bytes()
        data = self.generate("edge")
        self.assertEqual(data["current"], "0.2.4-edge.aaaaaaa")
        self.assertEqual(plistlib.loads((self.app / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"], "0.2.4")
        self.assertEqual((self.source / "VERSION").read_bytes(), original)
        self.assertEqual(data["buildTimestamp"], "2023-11-14T22:13:20Z")
        args = type("Arguments", (), dict(manifest=self.stage / "BuildInfo.json", app=self.app,
                                            summon=self.app / "Contents/MacOS/summon", macctl=self.macctl))()
        metadata.verify(args)
        info = plistlib.loads((self.app / "Contents/Info.plist").read_bytes())
        info["SummonDisplayVersion"] = "tampered"
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "SummonDisplayVersion"):
            metadata.verify(args)
        (self.app / "Contents/Info.plist").write_bytes((self.stage / "Resources/Info.plist").read_bytes())
        self._executable(self.macctl, "#!/bin/sh\necho 'macctl 9.9.9'\n")
        with self.assertRaisesRegex(ValueError, "macctl base version"):
            metadata.verify(args)

    def test_dirty_development_labeled_and_dirty_release_rejected(self):
        data = self.generate(dirty=True)
        self.assertEqual(data["sourceState"], "dirty")
        self.assertEqual(data["sourceRevision"], self.revision)
        with self.assertRaisesRegex(metadata.Invalid, "clean identified"):
            self.generate(channel="stable", dirty=True)
        with self.assertRaisesRegex(metadata.Invalid, "build-number"):
            metadata.identity(self.source, "stable", "abc", 1700000000, "release")

    def test_verify_only_preserves_live_files_and_failure_prevents_staging(self):
        self.generate()
        live = self.home / "Applications/Summon.app"
        live.mkdir(parents=True)
        (live / "previous").write_text("before")
        result = self.installer("--verify-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((live / "previous").exists())
        self.assertFalse((self.home / "Applications/.summon-install.lock").exists())
        (self.app / "Contents/Resources/BuildInfo.json").write_text("{}")
        result = self.installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((live / "previous").exists())
        self.assertEqual(list((self.home / "Applications").glob(".summon-install.*")), [])

    def test_verify_only_accepts_signed_bundle_without_optional_app_intents(self):
        self.generate()
        (self.app / "Contents/Resources/Metadata.appintents/extract.actionsdata").unlink()
        result = self.installer("--verify-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / "Applications/Summon.app").exists())
        self.assertFalse((self.home / "Applications/.summon-install.lock").exists())

    def test_second_staging_allocation_failure_cleans_first_and_lock(self):
        self.generate()
        counter = self.root / "mktemp-count"
        self._executable(self.tool_bin / "mktemp", "#!/bin/sh\n"
                         f"if [ -f '{counter}' ]; then exit 71; fi\ntouch '{counter}'\n"
                         "exec /usr/bin/mktemp \"$@\"\n")
        result = self.installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / "Applications/.summon-install.lock").exists())
        self.assertEqual(list((self.home / "Applications").glob(".summon-install.*")), [])

    def test_app_promotion_failure_restores_prior_app(self):
        self.generate()
        live = self.home / "Applications/Summon.app"
        live.mkdir(parents=True)
        (live / "previous").write_text("before")
        marker = self.root / "failed-once"
        self._executable(self.tool_bin / "mv", "#!/bin/sh\n"
                         f"case \"$2\" in */Applications/Summon.app) if [ ! -f '{marker}' ]; then touch '{marker}'; exit 72; fi ;; esac\n"
                         "exec /bin/mv \"$@\"\n")
        result = self.installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((live / "previous").read_text(), "before")
        self.assertFalse((self.home / "Applications/.summon-install.lock").exists())

    def test_check_does_not_validate_stale_bundle_after_failed_build(self):
        check = ROOT / "incubator/summon/scripts/check.sh"
        package = self.root / "workspace/incubator/summon"
        (package / "scripts").mkdir(parents=True)
        (package / "themes").mkdir()
        (package / "Resources").mkdir()
        (package / "Resources/Info.plist").write_bytes(plistlib.dumps({"CFBundleName": "Summon"}))
        (package / "scripts/check.sh").write_bytes(check.read_bytes())
        self._executable(package / "scripts/test.sh", "#!/bin/sh\nexit 0\n")
        self._executable(package / "scripts/bundle.sh", "#!/bin/sh\nexit 63\n")
        self._executable(self.tool_bin / "swift", "#!/bin/sh\nexit 0\n")
        stale = package / "build/Summon.app/Contents/Resources/BuildInfo.json"
        stale.parent.mkdir(parents=True)
        stale.write_text('{"stale":true}')
        env = dict(os.environ, HOME=str(self.home), PATH=str(self.tool_bin) + ":" + os.environ["PATH"])
        result = subprocess.run(["/bin/bash", str(package / "scripts/check.sh"),
                                 "--report-dir", "build/audit-run"], env=env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        report = json.loads((package / "build/audit-run/check-report.json").read_text())
        stages = {stage["name"]:stage["status"] for stage in report["stages"]}
        self.assertEqual(stages["bundle"], "failed")
        self.assertEqual(stages["packaged-identity"], "skipped")
        self.assertEqual(report["first_failure"], "bundle")

    def test_trace_parses_real_exported_signpost_intervals(self):
        # Redacted cells from xctrace Logging export of an owned signpost process, Xcode 27.1.
        # Durations and reference IDs are retained; process/thread/backtrace cells are omitted.
        toc = '<trace-toc><run><data><table schema="OSSignpostIntervals"/></data></run></trace-toc>'
        rows = '''<trace-query-result><node><schema name="OSSignpostIntervals">
<col><mnemonic>start</mnemonic></col><col><mnemonic>duration</mnemonic></col>
<col><mnemonic>layout-qualifier</mnemonic></col><col><mnemonic>name</mnemonic></col>
<col><mnemonic>category</mnemonic></col><col><mnemonic>subsystem</mnemonic></col></schema>
<row><start-time id="1">4058406750</start-time><duration id="2" fmt="23.40 ms">23396083</duration>
<layout-id id="3">0</layout-id><signpost-name id="4" fmt="PanelOpen">PanelOpen</signpost-name>
<category id="5" fmt="panel">panel</category><subsystem id="6" fmt="local.macplugins.summon">local.macplugins.summon</subsystem>
<os-log-metadata id="13" fmt="ordered front">ordered front</os-log-metadata></row>
<row><start-time id="22">4081806958</start-time><duration id="23" fmt="28.39 ms">28388708</duration>
<layout-id ref="3"/><signpost-name id="24" fmt="PanelWindowUpdate">PanelWindowUpdate</signpost-name>
<category ref="5"/><subsystem ref="6"/>
<os-log-metadata id="26" fmt="window update after order-front">window update after order-front</os-log-metadata></row>
<row><start-time id="28">4110214458</start-time><duration id="29" fmt="20.09 ms">20093125</duration>
<layout-id ref="3"/><signpost-name ref="4"/><category ref="5"/><subsystem ref="6"/>
<os-log-metadata ref="13"/></row></node></trace-query-result>'''
        replies = iter([type("Export", (), {"stdout": text})() for text in (toc, rows)])
        with mock.patch.object(trace_parser.subprocess, "run", side_effect=lambda *a, **k: next(replies)):
            measured = trace_parser.extract(pathlib.Path("captured.trace"))
        self.assertEqual(measured["PanelOpen"], [20.093125, 23.396083])
        self.assertEqual(measured["PanelWindowUpdate"], [28.388708])


if __name__ == "__main__":
    unittest.main()
