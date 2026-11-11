#!/usr/bin/env python3
"""Extract exact panel intervals and sanitized schema/count diagnostics, never raw trace text."""
import argparse
import json
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET

NAMES = ("PanelOpen", "PanelWindowUpdate")


def extract(trace):
    toc = subprocess.run(["xcrun", "xctrace", "export", "--input", str(trace), "--toc"],
                         text=True, capture_output=True, check=True, timeout=90).stdout
    tables = ET.fromstring(toc)
    samples = {name: [] for name in NAMES}
    diagnostics = {"interval_schemas": [], "interval_tables": 0, "rows": 0,
                   "matching_panel_rows": dict.fromkeys(NAMES, 0),
                   "unexpected_end_message": dict.fromkeys(NAMES, 0),
                   "invalid_duration": dict.fromkeys(NAMES, 0)}
    for table in tables.iter("table"):
        schema = table.get("schema", "")
        if schema.lower() not in ("os-signpost-interval", "ossignpostintervals"):
            continue
        diagnostics["interval_tables"] += 1
        if schema in diagnostics["interval_schemas"]:
            continue  # The XPath already exports this schema from every run/table.
        diagnostics["interval_schemas"].append(schema)
        xpath = f'/trace-toc/run/data/table[@schema="{schema}"]'
        output = subprocess.run(["xcrun", "xctrace", "export", "--input", str(trace), "--xpath", xpath],
                                text=True, capture_output=True, check=True, timeout=120).stdout
        data = ET.fromstring(output)
        for node in list(data.iter("node")) or [data]:
            # Each exported table has its own column order and reference dictionary.
            by_id = {cell.get("id"): cell for cell in node.iter() if cell.get("id") is not None}
            def resolve(cell):
                return by_id.get(cell.get("ref"), cell) if cell is not None else None
            def formatted(cell):
                cell = resolve(cell)
                return (cell.get("fmt") or "".join(cell.itertext())).strip() if cell is not None else ""
            columns = [column.get("mnemonic") or column.findtext("mnemonic")
                       for column in node.iter() if column.tag in ("col", "column")]
            for row in node.iter("row"):
                diagnostics["rows"] += 1
                cells = list(row)
                fields = {name: cells[index] for index, name in enumerate(columns)
                          if name and index < len(cells)}
                def cell(name):
                    found = fields.get(name)
                    return found if found is not None else row.find(name)
                name = formatted(cell("name")) or formatted(cell("signpost-name"))
                if (name not in NAMES or formatted(cell("subsystem")) != "local.macplugins.summon"
                        or formatted(cell("category")) != "panel"):
                    continue
                diagnostics["matching_panel_rows"][name] += 1
                expected = "window update after order-front" if name == "PanelWindowUpdate" else "ordered front"
                end = cell("end-message")
                messages = [formatted(end)] if end is not None else [formatted(c) for c in row.findall("os-log-metadata")]
                if expected not in messages:
                    diagnostics["unexpected_end_message"][name] += 1
                    continue
                duration = resolve(cell("duration"))
                try:
                    # xctrace's duration engineering type stores integer nanoseconds.
                    millis = int((duration.text or "").strip()) / 1_000_000 if duration is not None else 0
                except ValueError:
                    millis = 0
                if millis <= 0:
                    diagnostics["invalid_duration"][name] += 1
                    continue
                samples[name].append(millis)
    missing = [name for name in NAMES if not samples[name]]
    diagnostics["sample_counts"] = {name: len(values) for name, values in samples.items()}
    diagnostics["missing_samples"] = missing
    diagnostics["prerequisites"] = {name: (
        "Recorded status-item mouse-down followed by ordered front; URL opens do not start PanelOpen"
        if name == "PanelOpen" else
        "Recorded panel open followed by its AppKit window update and the exact successful end signpost")
        for name in missing}
    return {**{name: sorted(values) for name, values in samples.items()},
            "status": "blocked" if missing else "passed", "diagnostics": diagnostics,
            "reason": ("Trace has no signpost interval table" if not diagnostics["interval_tables"] else
                       "Required successful panel intervals are missing; see prerequisites" if missing else
                       "Exact successful panel intervals exported"),
            "measurement_boundary": "AppKit update before display, not a drawn/composited frame or retained-heap bound"}


HITCH_BUDGET_MS_PER_S = 5  # Apple's hitch-time ratio: under 5 ms/s is "good", 10+ ms/s is "critical".


def hitch_summary(xml_text, pid, workload_ms):
    """Hitches the app itself caused (system hitches excluded), as a hitch-time ratio over the workload."""
    durations = []
    data = ET.fromstring(xml_text)
    for node in list(data.iter("node")) or [data]:
        by_id = {cell.get("id"): cell for cell in node.iter() if cell.get("id") is not None}
        columns = [column.findtext("mnemonic") for column in node.iter("col")]
        for row in node.iter("row"):
            cells = {name: by_id.get(cell.get("ref"), cell) for name, cell in zip(columns, row)}
            process, system, duration = cells.get("process"), cells.get("is-system"), cells.get("duration")
            if process is None or duration is None or process.findtext(".//pid") != str(pid):
                continue
            if system is not None and (system.text or "").strip() == "1":
                continue
            durations.append(int(duration.text.strip()) / 1_000_000)  # nanoseconds
    durations.sort()
    seconds = workload_ms / 1000
    ratio = sum(durations) / seconds if seconds > 0 else None
    return {"status": "blocked" if ratio is None else "passed" if ratio < HITCH_BUDGET_MS_PER_S else "failed",
            "hitches": len(durations), "max_hitch_ms": durations[-1] if durations else 0,
            "p95_hitch_ms": durations[max(0, int(len(durations) * .95 + .999) - 1)] if durations else 0,
            "hitch_time_ratio_ms_per_s": round(ratio, 3) if ratio is not None else None,
            "budget_ms_per_s": HITCH_BUDGET_MS_PER_S, "workload_ms": workload_ms,
            "measurement_boundary": "WindowServer-displayed frame hitches for the app process during the panel workload"}


def hitches(trace, pid, workload_ms):
    output = subprocess.run(["xcrun", "xctrace", "export", "--input", str(trace), "--xpath",
                             '/trace-toc/run/data/table[@schema="hitches"]'],
                            text=True, capture_output=True, check=True, timeout=120).stdout
    return hitch_summary(output, pid, workload_ms)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=pathlib.Path)
    parser.add_argument("out", type=pathlib.Path)
    parser.add_argument("--hitches-pid", type=int, help="export displayed-frame hitches for this process instead")
    parser.add_argument("--workload-ms", type=float, default=0)
    args = parser.parse_args()
    try:
        if not args.trace.is_dir():
            raise FileNotFoundError("Recording directory unavailable")
        result = (hitches(args.trace, args.hitches_pid, args.workload_ms) if args.hitches_pid
                  else extract(args.trace))
        args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        return 0 if result["status"] == "passed" else 1
    except (OSError, ValueError, ET.ParseError, subprocess.SubprocessError) as exc:
        # Exception messages, commands and stderr may contain personal paths or trace messages.
        evidence = {"status": "blocked", "reason": "Trace export unavailable or invalid", "error_type": type(exc).__name__}
        if isinstance(exc, subprocess.CalledProcessError):
            evidence["exit_status"] = exc.returncode
        if isinstance(exc, subprocess.TimeoutExpired):
            evidence["timeout_seconds"] = exc.timeout
        if isinstance(exc, FileNotFoundError):
            evidence["reason"] = "Recording directory or xctrace executable unavailable"
        args.out.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
        return 2


if __name__ == "__main__":
    sys.exit(main())
