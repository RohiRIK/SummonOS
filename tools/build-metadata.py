#!/usr/bin/env python3
"""Generate and validate one immutable Summon build identity in staged sources."""
import argparse
import datetime as dt
import json
import pathlib
import plistlib
import re
import subprocess
import sys

FIELDS = ("current", "marketingVersion", "buildNumber", "sourceRevision", "sourceState", "channel", "configuration", "buildTimestamp")
PLIST = {"current": "SummonDisplayVersion", "marketingVersion": "CFBundleShortVersionString",
         "buildNumber": "CFBundleVersion", "sourceRevision": "SummonBuildCommit",
         "sourceState": "SummonBuildSourceState", "channel": "SummonBuildChannel",
         "configuration": "SummonBuildConfiguration", "buildTimestamp": "SummonBuildTimestamp"}
VERSION = re.compile(r"[0-9]+(?:\.[0-9]+){1,3}\Z")
BUILD = re.compile(r"[0-9]+(?:\.[0-9]+)*\Z")
REVISION = re.compile(r"[0-9a-f]{40,64}\Z")


class Invalid(ValueError):
    pass


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, check=True).stdout.strip()


def identity(source, channel, build, epoch, configuration):
    root = pathlib.Path(source).resolve()
    if not (root / "VERSION").is_file() or not (root / "incubator/summon/Package.swift").is_file():
        raise Invalid("source-root must be the SummonOS workspace")
    version = (root / "VERSION").read_text().strip()
    if not VERSION.fullmatch(version):
        raise Invalid("VERSION must be a numeric dotted marketing version")
    if not BUILD.fullmatch(build) or len(build) > 32:
        raise Invalid("build-number must be numeric and bundle-compatible")
    if channel not in ("development", "stable", "edge") or configuration not in ("debug", "release"):
        raise Invalid("invalid channel or configuration")
    if epoch is None:
        raise Invalid("source-date-epoch is required for reproducible identity")
    if epoch < 0 or epoch > 253402300799:
        raise Invalid("source-date-epoch outside supported UTC range")
    timestamp = dt.datetime.fromtimestamp(epoch, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        revision = run("/usr/bin/git", "rev-parse", "HEAD", cwd=root)
        dirty = bool(run("/usr/bin/git", "status", "--porcelain", "--untracked-files=normal", cwd=root))
        if not REVISION.fullmatch(revision):
            revision = "unknown"
    except (OSError, subprocess.CalledProcessError):
        revision, dirty = "unknown", False
    source_state = "dirty" if dirty else ("unidentified" if revision == "unknown" else "clean")
    if channel != "development" and source_state != "clean":
        raise Invalid("release metadata requires a clean identified source")
    current = version + ("-edge." + revision[:7] if channel == "edge" else "")
    return dict(current=current, marketingVersion=version, buildNumber=build,
                sourceRevision=revision, sourceState=source_state, channel=channel,
                configuration=configuration, buildTimestamp=timestamp)


def validate(data):
    if not isinstance(data, dict) or set(data) != set(FIELDS) or any(not isinstance(data[k], str) for k in FIELDS):
        raise Invalid("manifest fields do not match compiled identity")
    if not VERSION.fullmatch(data["marketingVersion"]) or not BUILD.fullmatch(data["buildNumber"]):
        raise Invalid("invalid marketing or build version")
    if data["channel"] not in ("development", "stable", "edge") or data["configuration"] not in ("debug", "release"):
        raise Invalid("invalid channel/configuration")
    revision = data["sourceRevision"]
    if revision != "unknown" and not REVISION.fullmatch(revision):
        raise Invalid("invalid revision")
    if data["sourceState"] not in ("clean", "dirty", "unidentified"):
        raise Invalid("invalid source state")
    if data["sourceState"] == "unidentified" and revision != "unknown":
        raise Invalid("unidentified revision must be unknown")
    expected = data["marketingVersion"] + ("-edge." + revision[:7] if data["channel"] == "edge" else "")
    if data["current"] != expected or (data["channel"] != "development" and data["sourceState"] != "clean"):
        raise Invalid("display version/revision/channel disagree")
    try:
        if dt.datetime.strptime(data["buildTimestamp"], "%Y-%m-%dT%H:%M:%SZ").strftime("%Y-%m-%dT%H:%M:%SZ") != data["buildTimestamp"]:
            raise ValueError()
    except ValueError as exc:
        raise Invalid("invalid reproducible UTC timestamp") from exc


def generate(args):
    data = identity(args.source_root, args.channel, args.build_number, args.source_date_epoch, args.configuration)
    validate(data)
    stage = pathlib.Path(args.stage_root).resolve()
    source = stage / "Sources/SummonCore/Version.swift"
    plist = stage / "Resources/Info.plist"
    if not source.is_file() or not plist.is_file():
        raise Invalid("stage-root must be a copied Summon package with sources and Info.plist")
    source.write_text("/// Generated immutable build identity; do not edit the developer source during packaging.\n"
                      "public enum SummonVersion {\n" + "".join(
                          f"    public static let {key}: String = {json.dumps(data[key])}\n" for key in FIELDS) + "}\n")
    info = plistlib.loads(plist.read_bytes())
    for key, name in PLIST.items():
        info[name] = data[key]
    plist.write_bytes(plistlib.dumps(info, sort_keys=False))
    (stage / "BuildInfo.json").write_text(json.dumps(data, sort_keys=True, indent=2) + "\n")


def verify(args):
    manifest = pathlib.Path(args.manifest)
    data = json.loads(manifest.read_text())
    validate(data)
    if not pathlib.Path(args.summon).is_file() or (args.macctl and not pathlib.Path(args.macctl).is_file()):
        raise ValueError("packaged CLI is missing")
    app = pathlib.Path(args.app)
    packaged = app / "Contents/Resources/BuildInfo.json"
    if json.loads(packaged.read_text()) != data:
        raise ValueError("packaged build manifest differs")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    for key, plist_key in PLIST.items():
        if info.get(plist_key) != data[key]:
            raise ValueError(f"packaged Info.plist {plist_key} disagrees with manifest")
    if pathlib.Path(args.summon).resolve() != (app / "Contents/MacOS/summon").resolve():
        raise Invalid("summon must be the supplied app's packaged CLI")
    summon = run(args.summon, "--version")
    if summon != "summon " + data["current"]:
        raise ValueError("packaged summon version differs from manifest")
    if args.macctl and run(args.macctl, "--version") != "macctl " + data["marketingVersion"]:
        raise ValueError("macctl base version differs from manifest")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="command", required=True)
    gen = subs.add_parser("generate")
    gen.add_argument("--source-root", required=True)
    gen.add_argument("--stage-root", required=True)
    gen.add_argument("--channel", required=True, choices=("development", "stable", "edge"))
    gen.add_argument("--build-number", required=True)
    gen.add_argument("--source-date-epoch", type=int, required=True)
    gen.add_argument("--configuration", choices=("debug", "release"), default="release")
    check = subs.add_parser("verify")
    for name in ("manifest", "app", "summon"):
        check.add_argument("--" + name, required=True)
    check.add_argument("--macctl")
    args = parser.parse_args()
    try:
        (generate if args.command == "generate" else verify)(args)
    except Invalid as exc:
        print(f"build-metadata: invalid input: {exc}", file=sys.stderr)
        return 2
    except (OSError, ValueError, json.JSONDecodeError, plistlib.InvalidFileException, subprocess.CalledProcessError) as exc:
        print(f"build-metadata: mismatch: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
