#!/usr/bin/env python3
"""Controlled Core lifecycle benchmark and disposable-account UI audit (no agent execution)."""
import argparse
import datetime as dt
import json
import os
import pathlib
import platform
import select
import signal
import subprocess
import sys
import tempfile
import time
import uuid

PACKAGE = pathlib.Path(__file__).resolve().parents[1]
ROOT = PACKAGE.parents[1]


def command(args, *, timeout=120, env=None):
    result = subprocess.run(args, text=True, capture_output=True, timeout=timeout, env=env)
    if result.returncode != 0:
        if any(phrase in result.stderr.lower() for phrase in
               ("not authorized", "not permitted", "assistive access", "screen recording")):
            raise ValueError("GUI capture or Accessibility permission is unavailable on isolated runner")
        raise subprocess.CalledProcessError(result.returncode, args, output=result.stdout, stderr=result.stderr)
    return result.stdout.strip()


def environment():
    def probe(args):
        try:
            return command(args, timeout=10)
        except (OSError, subprocess.SubprocessError):
            return "unavailable"
    return {"source_revision": probe(["/usr/bin/git", "-C", str(ROOT), "rev-parse", "HEAD"]),
            "swift_toolchain": probe(["swift", "--version"]), "os": platform.mac_ver()[0],
            "hardware": platform.machine(), "configuration": "release (-O) Core; packaged UI",
            "timestamp_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "privacy": "no prompts, raw logs, personal paths or desktop captures in JSON"}


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def owned_process(args, *, env=None):
    # All children launched by this driver use their own group. Never terminate anything outside it.
    return subprocess.Popen(args, start_new_session=True, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def reap(children):
    for child in children:
        if child.poll() is None:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    for child in children:
        try:
            child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()


def compile_core(fixtures):
    source = sorted((PACKAGE / "Sources/SummonCore").glob("*.swift"))
    if not source:
        raise ValueError("Core source is unavailable")
    binary = fixtures / "core-audit"
    compile_args = ["swiftc", "-O", "-swift-version", "6", "-parse-as-library", *(str(s) for s in source),
                    str(PACKAGE / "scripts/runtime-audit-core.swift"), "-o", str(binary)]
    command(compile_args, timeout=300)
    return binary


def core(run, iterations, fixtures):
    binary = compile_core(fixtures)
    started = time.monotonic()
    command([str(binary), str(fixtures / "home"), str(run), str(iterations)], timeout=max(120, iterations * 15))
    metrics = json.loads((run / "core-metrics.json").read_text())
    scenarios = json.loads((run / "core-scenarios.json").read_text())
    write(run / "metrics.json", {"core": metrics, "duration_ms": round((time.monotonic()-started)*1000, 3)})
    write(run / "scenarios.json", {"core": scenarios})
    return all(s["status"] == "passed" for s in scenarios)


def visible_windows(helper, pid):
    output = command([str(helper), str(pid)], timeout=5)
    windows = []
    for line in output.splitlines():
        fields = line.split()
        if len(fields) == 6 and all(item.lstrip("-").isdigit() for item in fields):
            windows.append(tuple(map(int, fields)))
    return windows


def wait_window(helper, pid, condition, timeout=10):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        matched = condition(visible_windows(helper, pid))
        if matched:
            return matched
        time.sleep(0.1)  # polling interval, not readiness evidence
    return None


def owned_window_action(helper, pid, window_id, action):
    # The helper joins public CG/AX window identities only when unique, verifies keyboard focus,
    # and posts Command-W to this PID. Do not substitute a close-button click when keyboard handling fails.
    try:
        result = subprocess.run([str(helper), action, str(pid), str(window_id)],
                                text=True, capture_output=True, timeout=15)
    except subprocess.TimeoutExpired:
        return {"status":"failed", "stage":"helper deadline", "operation":action,
                "reason":"Owned-window action exceeded its 15-second deadline", "window_id":window_id}
    try:
        evidence = json.loads(result.stdout)
        expected = {"passed":0, "failed":1, "blocked":2}.get(evidence.get("status"))
        if expected != result.returncode or evidence.get("pid") != pid or evidence.get("window_id") != window_id:
            raise ValueError("invalid owned-window result")
        return evidence
    except (ValueError, AttributeError):
        return {"status":"failed", "stage":"helper result", "operation":action,
                "reason":"Owned-window helper did not return valid structured evidence",
                "exit_status":result.returncode, "window_id":window_id}


def stop_owned_app(pid, binary):
    # LaunchServices owns its process group. Recheck executable immediately before signaling this PID.
    def matches():
        found = subprocess.run(["/bin/ps", "-o", "command=", "-p", str(pid)],
                               text=True, capture_output=True)
        return found.returncode == 0 and found.stdout.strip().split(" ")[0] == str(binary)
    if not matches():
        return
    os.kill(pid, signal.SIGTERM)
    until = time.monotonic() + 3
    while matches() and time.monotonic() < until:
        time.sleep(.1)
    if matches():
        os.kill(pid, signal.SIGKILL)


def trace_window_cycle(pid, helper):
    command(["/usr/bin/open", "summon://menu/"], timeout=5)
    panel = wait_window(helper, pid, lambda windows: [w for w in windows if 270 <= w[4] <= 400 and w[5] > 180])
    if not panel:
        return False
    command(["/usr/bin/osascript", "-e", 'tell application "System Events" to keystroke "audit"'], timeout=5)
    command(["/usr/bin/osascript", "-e", 'tell application "System Events" to key code 53'], timeout=5)
    return bool(wait_window(helper, pid, lambda windows: not any(w[0] == panel[0][0] for w in windows)))


def instrument(pid, helper, trace, children):
    outcomes = {}
    for template in ("Logging", "SwiftUI", "Time Profiler", "Allocations"):
        target = trace / (template.lower().replace(" ", "-") + ".trace")
        child = subprocess.Popen(["xcrun", "xctrace", "record", "--template", template,
                                  "--attach", str(pid), "--time-limit", "6s", "--no-prompt",
                                  "--output", str(target)], start_new_session=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        children.append(child)
        started = False
        banner = ""
        until = time.monotonic() + 15
        while time.monotonic() < until and child.poll() is None:
            if select.select([child.stdout], [], [], max(0, until - time.monotonic()))[0]:
                banner = (banner + os.read(child.stdout.fileno(), 4096).decode(errors="replace"))[-512:]
                if "Ctrl-C to stop the recording" in banner:
                    started = True
                    break
        # A window cycle only after Instruments confirms recording, not after a blind sleep.
        cycle = started and trace_window_cycle(pid, helper)
        try:
            child.wait(timeout=45)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGTERM)
            try: child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
            cycle = False
        child.stdout.close()
        outcomes[template] = {"status":"passed" if cycle and child.returncode == 0 and target.is_dir() else "blocked",
                              "interactive_cycle":cycle, "trace_present":target.is_dir()}
    signposts = trace / "panel-signposts.json"
    logging_trace = trace / "logging.trace"
    parsed = subprocess.run([sys.executable, str(PACKAGE / "scripts/runtime-trace.py"),
                             str(logging_trace), str(signposts)], capture_output=True, timeout=150)
    outcome = json.loads(signposts.read_text()) if signposts.exists() else {}
    outcomes["panel signposts"] = {"status":"passed" if parsed.returncode == 0 else "blocked",
                                   "first_window_update_samples":len(outcome.get("PanelWindowUpdate", [])),
                                   "ordered_front_samples":len(outcome.get("PanelOpen", []))}
    return outcomes, outcome


def ui(run, app, iterations, fixtures, children, owned_apps):
    if not ((os.environ.get("GITHUB_ACTIONS") == "true" and
             os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted") or
            os.environ.get("VQA_ALLOW_LOCAL") == "1"):
        raise ValueError("UI requires a disposable VM/test account; personal desktop refused")
    if subprocess.run(["/usr/bin/pgrep", "-x", "SummonMenu"],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        raise ValueError("SummonMenu is already running; refusing to control an existing session")
    binary = app / "Contents/MacOS/SummonMenu"
    cli = app / "Contents/MacOS/summon"
    if not binary.is_file() or not cli.is_file() or not (app / "Contents/Resources/BuildInfo.json").is_file():
        raise ValueError("supplied app must be a packaged Summon.app with metadata")
    helper = fixtures / "windows"
    command(["swiftc", "-O", str(PACKAGE / "scripts/visual-qa/windows.swift"), "-o", str(helper)], timeout=90)
    ocr = fixtures / "window-text"
    command(["swiftc", "-O", str(PACKAGE / "scripts/visual-qa/window-text.swift"), "-o", str(ocr)], timeout=90)
    core_binary = compile_core(fixtures)
    trace = run / "traces"
    trace.mkdir()
    def screenshot(window, name):
        image = trace / (name + ".png")
        command(["/usr/sbin/screencapture", "-x", "-l", str(window[0]), str(image)], timeout=10)
        if not image.is_file() or image.stat().st_size == 0:
            raise ValueError("Screen Recording permission did not yield an app-window capture")
        return command([str(ocr), str(image)], timeout=30)
    # Open the exact supplied bundle; find only its new executable, never identify by an unrelated PID.
    launch = owned_process(["/usr/bin/open", "-n", "-a", str(app), "--args",
                            "-VisualQA", "YES", "--show-about"])
    children.append(launch)
    launch.wait(timeout=10)
    if launch.returncode != 0:
        raise RuntimeError("app launch failed")
    pid = None
    until = time.monotonic()+15
    while time.monotonic() < until:
        processes = command(["/bin/ps", "-axo", "pid=,command="], timeout=5)
        for entry in processes.splitlines():
            pieces = entry.strip().split(maxsplit=1)
            if len(pieces) == 2 and pieces[1].split()[0] == str(binary):
                pid = int(pieces[0]); break
        if pid is not None:
            break
        time.sleep(.1)
    if pid is None:
        raise RuntimeError("supplied app process did not appear")
    # Register only a PID belonging to the exact app path newly launched above.
    owned_apps.append((pid, binary))
    samples = []
    resources = []
    scenarios = []
    def close_window(window, name):
        evidence = owned_window_action(helper, pid, window[0], "close")
        scenarios.append({"name":name, **evidence})
        write(run / "scenarios.json", {"ui":scenarios})
        return evidence["status"]
    try:
        about = wait_window(helper, pid, lambda windows: [w for w in windows if w[4] > 220 and w[5] > 150])
        if not about:
            scenarios.append({"name":"native About ready", "status":"failed"})
            write(run / "scenarios.json", {"ui":scenarios}); return False
        manifest = json.loads((app / "Contents/Resources/BuildInfo.json").read_text())
        about_text = screenshot(about[0], "about")
        ready = all(value in about_text for value in (manifest["marketingVersion"], manifest["buildNumber"]))
        scenarios.append({"name":"packaged About metadata visible", "status":"passed" if ready else "failed",
                          "captured_bytes":(trace / "about.png").stat().st_size})
        if not ready:
            write(run / "scenarios.json", {"ui":scenarios}); return False
        closed = close_window(about[0], "native About close")
        if closed != "passed":
            return None if closed == "blocked" else False
        # A harmless shell child exits, Core writes its actual terminal JSONL record, and the real UI reads it.
        command([str(core_binary), "fixture-terminal", str(pathlib.Path.home())], timeout=30)
        command(["/usr/bin/open", "summon://activity"], timeout=5)
        activity = wait_window(helper, pid, lambda windows: [w for w in windows if w[4] >= 800 and w[5] > 200])
        observed = False
        if activity:
            until = time.monotonic() + 10
            while time.monotonic() < until:
                observed = "Audit completion fixture" in screenshot(activity[0], "completion")
                if observed: break
                time.sleep(.2)
        scenarios.append({"name":"terminal persistence and activity delivery",
                          "status":"passed" if observed else "failed"})
        if not observed:
            write(run / "scenarios.json", {"ui":scenarios}); return False
        closed = close_window(activity[0], "Activity keyboard close")
        if closed != "passed":
            return None if closed == "blocked" else False
        for index in range(iterations):
            start = time.monotonic()
            command(["/usr/bin/open", "summon://menu/"], timeout=5)
            panel = wait_window(helper, pid, lambda windows: [w for w in windows if 270 <= w[4] <= 400 and w[5] > 180])
            if not panel:
                scenarios.append({"name":"panel open/search/close", "iteration":index,"status":"failed"}); break
            if index == 0:
                first_text = screenshot(panel[0], "panel-first-captured-frame")
                scenarios.append({"name":"first captured panel frame", "status":"passed" if first_text else "failed",
                                  "evidence":"screenshot + OCR; capture latency is not first-frame time"})
            command(["/usr/bin/osascript", "-e", 'tell application "System Events" to keystroke "audit"'], timeout=5)
            command(["/usr/bin/osascript", "-e", 'tell application "System Events" to key code 53'], timeout=5)
            closed = wait_window(helper, pid, lambda windows: not any(w[0] == panel[0][0] for w in windows))
            if not closed:
                scenarios.append({"name":"panel close/reopen", "iteration":index,"status":"failed"}); break
            samples.append((time.monotonic()-start)*1000)
            if index % 10 == 0 or index == iterations - 1:
                rss = int(command(["/bin/ps", "-o", "rss=", "-p", str(pid)], timeout=5))
                threads = len(command(["/bin/ps", "-M", "-p", str(pid)], timeout=5).splitlines()) - 1
                descriptors = sum(line.startswith("f") for line in command(
                    ["/usr/sbin/lsof", "-nP", "-p", str(pid), "-Ff"], timeout=10).splitlines())
                resources.append({"cycle":index,"rss_kib":rss,"threads":threads,"fd_records":descriptors})
        else:
            scenarios.append({"name":"panel open/search/close", "status":"passed", "iterations":iterations})
        samples.sort()
        traces, signposts = instrument(pid, helper, trace, children)
        scenarios.extend({"name":"Instruments " + template, **result} for template, result in traces.items())
        def percentiles(values):
            return {"median_ms":values[len(values)//2],
                    "p95_ms":values[max(0, int(len(values)*.95+.999)-1)], "count":len(values)} if values else None
        write(run / "metrics.json", {"ui": {"cycle_median_ms": samples[len(samples)//2] if samples else None,
                                                "cycle_p95_ms": samples[max(0, int(len(samples)*.95+.999)-1)] if samples else None,
                                                "cycles":len(samples), "resources":resources,
                                                "ordered_front":percentiles(signposts.get("PanelOpen", [])),
                                                "first_window_update":percentiles(signposts.get("PanelWindowUpdate", [])),
                                                "measurement_boundary":"AppKit first window update pass before display, not a drawn or composited frame",
                                                "retained_heap":"Allocations trace required; RSS changes alone do not prove leaks"}})
        write(run / "scenarios.json", {"ui":scenarios})
        if any(s["status"] == "blocked" for s in scenarios):
            return None
        return all(s["status"] == "passed" for s in scenarios)
    finally:
        write(run / "scenarios.json", {"ui":scenarios})
        stop_owned_app(pid, binary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("core", "ui"), required=True)
    parser.add_argument("--iterations", type=int, default=100)
    parser.add_argument("--app", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.iterations < 1 or args.iterations > 10_000 or (args.mode == "ui" and not args.app):
        parser.error("iterations must be 1..10000; UI mode requires --app")
    run = args.out / ("audit-" + uuid.uuid4().hex)
    run.mkdir(parents=True, exist_ok=False)
    (run / ".summon-runtime-audit-owner").write_text(run.name)
    write(run / "environment.json", environment())
    children = []
    owned_apps = []
    try:
        with tempfile.TemporaryDirectory(prefix="summon-audit-fixture-") as temporary:
            fixtures = pathlib.Path(temporary)
            passed = core(run, args.iterations, fixtures) if args.mode == "core" else ui(
                run, args.app.resolve(), args.iterations, fixtures, children, owned_apps)
        print(run)
        return 2 if passed is None else 0 if passed else 1
    except (ValueError, FileNotFoundError) as exc:
        reason = "required executable or fixture missing" if isinstance(exc, FileNotFoundError) else str(exc)
        previous = json.loads((run / "scenarios.json").read_text()) if (run / "scenarios.json").exists() else {}
        write(run / "scenarios.json", {**previous, "prerequisite":{"status":"blocked","reason":reason}})
        print("runtime-audit: prerequisite blocked (see scenarios.json)", file=sys.stderr)
        print(run)
        return 2
    except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
        evidence = {"status":"failed", "error_type":type(exc).__name__}
        if isinstance(exc, subprocess.CalledProcessError):
            evidence.update(executable=pathlib.Path(exc.cmd[0]).name, exit_status=exc.returncode)
        previous = json.loads((run / "scenarios.json").read_text()) if (run / "scenarios.json").exists() else {}
        write(run / "scenarios.json", {**previous, "driver":evidence})
        print("runtime-audit: audit failed (see scenarios.json)", file=sys.stderr)
        print(run)
        return 1
    finally:
        for pid, binary in owned_apps:
            stop_owned_app(pid, binary)
        reap(children)


if __name__ == "__main__":
    sys.exit(main())
