#!/usr/bin/env python3
"""Private install receipt and conservative uninstall. Never delete user configuration or projects."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile

HOME = Path(os.path.abspath(os.path.expanduser("~")))
APP = HOME / "Applications/Summon.app"
BIN = HOME / ".local/bin"
STATE = HOME / "Library/Application Support/Summon/install-manifest.json"
LOCK = HOME / "Applications/.summon-install.lock"
SKILL_FOLDERS = (".claude/skills", ".codex/skills", ".config/opencode/skills",
                 ".gemini/config/skills", ".pi/agent/skills")


def fingerprint(path, kind):
    digest = hashlib.sha256()

    def visit(item, relative):
        info = item.lstat()
        mode = stat.S_IMODE(info.st_mode)
        if stat.S_ISLNK(info.st_mode):
            metadata = [relative, "symlink", mode, os.readlink(item)]
        elif stat.S_ISREG(info.st_mode):
            metadata = [relative, "file", mode, info.st_size]
        elif stat.S_ISDIR(info.st_mode):
            metadata = [relative, "directory", mode]
        else:
            raise ValueError("Unsupported installed file type")
        digest.update(json.dumps(metadata, ensure_ascii=True).encode() + b"\0")
        if stat.S_ISREG(info.st_mode):
            with item.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
        elif stat.S_ISDIR(info.st_mode):
            for child in sorted(item.iterdir(), key=lambda value: value.name):
                visit(child, relative + "/" + child.name)

    mode = path.lstat().st_mode
    if not {"file": stat.S_ISREG, "tree": stat.S_ISDIR, "symlink": stat.S_ISLNK}[kind](mode):
        raise ValueError("Installed entry changed type")
    visit(path, ".")
    return digest.hexdigest()


def allowed_kind(path):
    fixed = {str(APP): "tree", str(BIN / "summon"): "symlink", str(BIN / "macctl"): "file"}
    if str(path) in fixed:
        return fixed[str(path)]
    if path.parent in [HOME / folder for folder in SKILL_FOLDERS] and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", path.name):
        return "symlink"
    raise ValueError("Receipt contains a path outside the installation allowlist")


def load_state():
    if STATE.is_symlink() or not STATE.is_file():
        raise ValueError("No valid install receipt. Reinstall with the current installer before automatic uninstall")
    data = json.loads(STATE.read_text())
    if not isinstance(data, dict) or data.get("version") != 1 or not isinstance(data.get("entries"), list):
        raise ValueError("Unsupported install receipt")
    seen = set()
    for entry in data["entries"]:
        path = Path(entry["path"])
        if str(path) != entry["path"] or str(path) in seen or entry["kind"] != allowed_kind(path):
            raise ValueError("Invalid or duplicated install receipt path")
        if not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"]):
            raise ValueError("Invalid install receipt fingerprint")
        if not isinstance(entry.get("parent"), str):
            raise ValueError("Missing original installation directory")
        seen.add(str(path))
    return data


def save_state(entries):
    STATE.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if STATE.is_symlink():
        raise ValueError("Refusing to replace an install receipt symlink")
    fd, temporary = tempfile.mkstemp(prefix=".install-", dir=str(STATE.parent))
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump({"version": 1, "entries": entries}, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, STATE)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def describe(path, kind):
    return {"path": str(path), "kind": kind, "parent": str(path.parent.resolve()),
            "sha256": fingerprint(path, kind)}


def record(include_macctl):
    # Preserve previous macctl ownership when only the app is upgraded.
    previous = load_state()["entries"] if STATE.exists() or STATE.is_symlink() else []
    entries = [describe(APP, "tree"), describe(BIN / "summon", "symlink")]
    if include_macctl:
        entries.append(describe(BIN / "macctl", "file"))
    else:
        entries.extend(entry for entry in previous if entry["path"] == str(BIN / "macctl"))
    for folder in SKILL_FOLDERS:
        directory = HOME / folder
        if directory.is_dir():
            for link in directory.iterdir():
                expected = str(APP / "Contents/share/summon/skills" / link.name)
                if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", link.name) and link.is_symlink() and os.readlink(link) == expected:
                    entries.append(describe(link, "symlink"))
    save_state(entries)


def uninstall(apply):
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    try:
        LOCK.mkdir()
    except FileExistsError:
        raise ValueError("An installer or uninstaller may already be running; inspect the install lock first")
    try:
        data = load_state()  # Validate the ENTIRE receipt before deleting any entry.
        kept = []
        for entry in data["entries"]:
            path = Path(entry["path"])
            if not path.exists() and not path.is_symlink():
                continue
            try:
                matches = (str(path.parent.resolve()) == entry["parent"]
                           and fingerprint(path, entry["kind"]) == entry["sha256"])
                if entry["kind"] == "symlink":
                    expected = (str(APP / "Contents/MacOS/summon") if path == BIN / "summon"
                                else str(APP / "Contents/share/summon/skills" / path.name))
                    matches = matches and os.readlink(path) == expected
            except (OSError, ValueError):
                matches = False
            if not matches:
                print("Kept changed or unowned entry: " + str(path))
                kept.append(entry)
                continue
            print(("Removing: " if apply else "Would remove: ") + str(path))
            if apply:
                try:
                    if entry["kind"] == "tree":
                        shutil.rmtree(path)
                    else:
                        path.unlink()
                except OSError:
                    kept.append(entry)
                    print("Could not remove entry: " + str(path), file=sys.stderr)
        if apply:
            if kept:
                save_state(kept)
            else:
                STATE.unlink()
        print("Projects, themes, preferences, checkpoints and scheduled tasks are preserved.")
        if not apply:
            print("Quit Summon, then run tools/uninstall.sh --apply to remove the verified installation entries.")
        return 2 if kept else 0
    finally:
        LOCK.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("record", "uninstall"))
    parser.add_argument("--macctl", action="store_true")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        if args.action == "record":
            record(args.macctl)
            return 0
        return uninstall(args.apply)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("Install ownership check failed: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
