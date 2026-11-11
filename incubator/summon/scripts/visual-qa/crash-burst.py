#!/usr/bin/env python3
"""Exercise the owned app's real crash watcher, alert consumer and post-burst search.

Called by runtime-audit.py only after its disposable-session launch. Does not launch
agents, change preferences, write the app's cursor, or synthesize an announcement.
The 13 same-timestamp .ips files exceed CrashWatcher's five-file batch size. A
shared FileLease keeps their publication atomic with respect to the real scanner.
Native Notification Center banners and VoiceOver are deliberately not asserted.
"""
import argparse
import fcntl
import json
import os
import pathlib
import stat
import subprocess
import time
import uuid


COUNT = 13


class AuditProblem(Exception):
    def __init__(self, status, reason):
        super().__init__(reason)
        self.status = status


def command(args, timeout=5):
    result = subprocess.run([str(arg) for arg in args], text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        permission = any(word in result.stderr.lower() for word in
                         ("not authorized", "not permitted", "assistive access", "screen recording"))
        raise AuditProblem("blocked" if permission else "failed",
                           "GUI permission unavailable" if permission else "Owned scenario command failed")
    return result.stdout.strip()


def require_owned(pid, binary):
    result = subprocess.run(["/bin/ps", "-ww", "-p", str(pid), "-o", "command="],
                            text=True, capture_output=True, timeout=5)
    invocation = result.stdout.strip()
    if result.returncode or not (invocation == str(binary) or invocation.startswith(str(binary) + " ")):
        raise AuditProblem("failed", "Owned app exited or its executable identity changed")
    result = subprocess.run(["/usr/bin/pgrep", "-u", str(os.geteuid()), "-x", "SummonMenu"],
                            text=True, capture_output=True, timeout=5)
    if result.returncode or result.stdout.split() != [str(pid)]:
        raise AuditProblem("blocked", "Testing account no longer has exactly the owned SummonMenu process")


def visible_windows(helper, pid):
    windows = []
    for line in command([helper, pid]).splitlines():
        fields = line.split()
        if len(fields) != 6 or not all(item.lstrip("-").isdigit() for item in fields):
            raise AuditProblem("failed", "Window helper returned malformed geometry")
        windows.append(tuple(map(int, fields)))
    return windows


def action(helper, operation, pid, window_id):
    args = [helper, operation, pid, window_id]
    result = subprocess.run([str(arg) for arg in args], text=True, capture_output=True, timeout=15)
    try:
        evidence = json.loads(result.stdout)
        expected = {"passed": 0, "failed": 1, "blocked": 2}[evidence["status"]]
        if result.returncode != expected or evidence["pid"] != pid or evidence["window_id"] != window_id:
            raise ValueError("identity mismatch")
        return evidence
    except (ValueError, KeyError, TypeError):
        raise AuditProblem("failed", "Owned action did not return valid identity-bound evidence") from None


def audit(args, evidence, created):
    if not ((os.environ.get("GITHUB_ACTIONS") == "true" and
             os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted") or
            os.environ.get("VQA_ALLOW_LOCAL") == "1"):
        raise AuditProblem("blocked", "Crash fixtures require a disposable runner or explicitly allowed test account")
    run = args.run.resolve()
    marker = run / ".summon-runtime-audit-owner"
    if not marker.is_file() or marker.read_text() != run.name:
        raise AuditProblem("blocked", "Runtime audit ownership marker is missing or mismatched")
    app = args.app.resolve()
    binary = app / "Contents/MacOS/SummonMenu"
    require_owned(args.pid, binary)
    home = pathlib.Path.home()
    reports = home / "Library/Logs/DiagnosticReports"
    state = home / ".local/state/summon"
    if not reports.is_dir() or reports.resolve() != home.resolve() / "Library/Logs/DiagnosticReports":
        raise AuditProblem("blocked", "DiagnosticReports must exist in the disposable home before app launch")
    cursor_file = state / "crash-marker"
    health_file = state / "app.json"
    baseline = None
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        require_owned(args.pid, binary)
        if cursor_file.is_file() and health_file.is_file():
            health = json.loads(health_file.read_text())
            cursor = json.loads(cursor_file.read_text())
            if health.get("pid") == args.pid:
                baseline = cursor.get("modified") if isinstance(cursor, dict) else cursor
                if isinstance(baseline, (int, float)):
                    break
        time.sleep(0.1)
    if not isinstance(baseline, (int, float)):
        raise AuditProblem("blocked", "Owned app health and crash-scanner baseline were not ready")
    evidence["owned_baseline_ready"] = True
    before = {window[0] for window in visible_windows(args.windows, args.pid)}
    # Use one exactly representable whole-second timestamp newer than the live cursor.
    deadline = time.monotonic() + 2.5
    while int(time.time()) <= baseline and time.monotonic() < deadline:
        time.sleep(0.05)
    timestamp = int(time.time())
    if timestamp <= baseline:
        raise AuditProblem("blocked", "Live crash cursor is ahead of the fixture clock")
    token = uuid.uuid4().hex
    fixtures = []
    for index in range(COUNT):
        path = reports / f"summon-runtime-audit-{token}-{index:02}.ips"
        name = f"Summon Audit Crash {index:02}"
        header = {"bug_type": "309", "app_name": name, "incident_id": str(uuid.uuid4())}
        body = {"procName": name, "exception": {"type": "EXC_BAD_ACCESS", "signal": "SIGSEGV"}}
        fixtures.append((path, json.dumps(header) + "\n" + json.dumps(body) + "\n"))
    lock_path = state / "locks/crashes.lock"
    require_owned(args.pid, binary)
    fd = os.open(lock_path, os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
            raise AuditProblem("blocked", "Crash scanner lock is not a regular file owned by the testing account")
        deadline = time.monotonic() + 3
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise AuditProblem("blocked", "Crash scanner lease remained busy") from None
                time.sleep(0.02)
        for path, content in fixtures:
            with path.open("x") as output:
                created.append(path)
                output.write(content)
            os.utime(path, ns=(timestamp * 1_000_000_000, timestamp * 1_000_000_000))
    finally:
        os.close(fd)
    expected_paths = {str(path) for path in created}
    evidence["fixture_count"] = len(created)
    evidence["same_timestamp"] = len({path.stat().st_mtime_ns for path in created}) == 1
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        require_owned(args.pid, binary)
        cursor = json.loads(cursor_file.read_text())
        consumed = expected_paths.intersection(cursor.get("files", [])) if isinstance(cursor, dict) else set()
        evidence["cursor_consumed_count"] = len(consumed)
        if consumed == expected_paths:
            break
        if isinstance(cursor, dict) and cursor.get("modified", 0) > timestamp:
            raise AuditProblem("blocked", "An unrelated newer report advanced the shared cursor before fixture observation")
        time.sleep(0.1)
    else:
        raise AuditProblem("failed", "Real app did not consume all 13 same-timestamp reports across batch boundaries")
    image = run / "traces/crash-burst.png"
    deadline = time.monotonic() + 10
    alert = None
    while time.monotonic() < deadline:
        require_owned(args.pid, binary)
        candidates = [window for window in visible_windows(args.windows, args.pid)
                      if window[0] not in before and 438 <= window[4] <= 442 and window[5] > 150]
        if len(candidates) > 1:
            raise AuditProblem("failed", "Crash burst opened multiple alert-sized windows")
        if candidates:
            candidate = candidates[0]
            # Do not capture a coincidental real system crash shown by the disposable app.
            identity = action(args.dismiss, "inspect", args.pid, candidate[0])
            evidence["alert_identity"] = identity
            if identity["status"] == "blocked":
                raise AuditProblem("blocked", "Fixture alert identity could not be established before capture")
            if identity["status"] != "passed":
                time.sleep(0.1)
                continue
            command(["/usr/sbin/screencapture", "-x", "-l", candidate[0], image], timeout=10)
            if not image.is_file() or image.stat().st_size == 0:
                raise AuditProblem("blocked", "Screen Recording did not yield an owned alert capture")
            text = " ".join(command([args.ocr, image], timeout=10).split())
            evidence["newest_report_visible"] = "Summon Audit Crash 12 crashed" in text
            evidence["remaining_count_visible"] = "12 more new reports in the Summon panel" in text
            if evidence["newest_report_visible"] and evidence["remaining_count_visible"]:
                alert = candidate
                break
        time.sleep(0.1)
    if alert is None:
        raise AuditProblem("failed", "Real crash alert did not display the newest fixture and 12 other reports")
    evidence["alert_window_id"] = alert[0]
    evidence["captured_bytes"] = image.stat().st_size
    require_owned(args.pid, binary)
    dismissed = action(args.dismiss, "dismiss", args.pid, alert[0])
    evidence["dismissal"] = dismissed
    if dismissed["status"] != "passed":
        raise AuditProblem(dismissed["status"], "Owned crash alert could not be dismissed through its native button")
    require_owned(args.pid, binary)
    command(["/usr/bin/open", "-g", "-a", app, "summon://menu/"])
    deadline = time.monotonic() + 10
    panel = None
    while time.monotonic() < deadline:
        candidates = [window for window in visible_windows(args.windows, args.pid)
                      if window[4] == 320 and window[5] > 180]
        if len(candidates) == 1:
            panel = candidates[0]
            break
        time.sleep(0.1)
    if panel is None:
        raise AuditProblem("failed", "App did not reopen its panel after the crash burst")
    search = action(args.windows, "search", args.pid, panel[0])
    evidence["post_burst_search"] = search
    if search["status"] != "passed":
        raise AuditProblem(search["status"], "App did not receive and expose typed search after the crash burst")
    command(["/usr/bin/open", "-g", "-a", app, "summon://panel/close"])
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        require_owned(args.pid, binary)
        if not any(window[0] == panel[0] for window in visible_windows(args.windows, args.pid)):
            evidence["post_burst_panel_closed"] = True
            return
        time.sleep(0.05)
    raise AuditProblem("failed", "Post-burst panel did not close through its normal URL route")


def check(*, pid, app, run, windows, ocr, dismiss):
    args = argparse.Namespace(pid=pid, app=app, run=run, windows=windows, ocr=ocr, dismiss=dismiss)
    evidence = {"pid": args.pid, "status": "failed", "requested_reports": COUNT,
                "measurement_boundary": "Real crash scan, rendered Summon alert, native dismissal and typed search; not macOS banners or VoiceOver"}
    created = []
    try:
        audit(args, evidence, created)
        evidence.update(status="passed", reason="All 13 reports consumed; newest and aggregate rendered; dismissal and post-burst search completed")
    except AuditProblem as error:
        evidence.update(status=error.status, reason=str(error))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        evidence.update(status="failed", reason="Crash burst helper failed", error_type=type(error).__name__)
    finally:
        removed = 0
        for path in created:
            try:
                path.unlink()
                removed += 1
            except OSError:
                evidence.update(status="failed", reason="Owned crash fixture cleanup failed")
        evidence["removed_fixtures"] = removed
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    for name in ("app", "run", "windows", "ocr", "dismiss"):
        parser.add_argument("--" + name, type=pathlib.Path, required=True)
    evidence = check(**vars(parser.parse_args()))
    print(json.dumps(evidence, sort_keys=True))
    return {"passed": 0, "failed": 1, "blocked": 2}[evidence["status"]]


if __name__ == "__main__":
    raise SystemExit(main())
