#!/usr/bin/env python3
"""Extract redacted panel signpost durations from a disposable runner's Logging trace."""
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
    for table in tables.iter("table"):
        schema = table.get("schema", "")
        if schema.lower() not in ("os-signpost-interval", "ossignpostintervals"):
            continue
        xpath = f'/trace-toc/run/data/table[@schema="{schema}"]'
        output = subprocess.run(["xcrun", "xctrace", "export", "--input", str(trace), "--xpath", xpath],
                                text=True, capture_output=True, check=True, timeout=120).stdout
        data = ET.fromstring(output)
        by_id = {node.get("id"): node for node in data.iter() if node.get("id") is not None}
        def resolve(node):
            return by_id.get(node.get("ref"), node) if node is not None else None
        def formatted(node):
            node = resolve(node)
            return (node.get("fmt") or "".join(node.itertext())).strip() if node is not None else ""
        columns = [column.get("mnemonic") or column.findtext("mnemonic")
                   for column in data.iter() if column.tag in ("col", "column")]
        for row in data.iter("row"):
            cells = list(row)
            fields = {name: cells[index] for index, name in enumerate(columns)
                      if name and index < len(cells)}
            def cell(name):
                found = fields.get(name)
                return found if found is not None else row.find(name)
            def value(name):
                return formatted(cell(name))
            # Instruments can export the schema as positioned <string> cells or as named elements.
            # Match only these two exact signposts, subsystem and category; never publish trace messages.
            values = [formatted(cell) for cell in cells]
            name = value("name") or value("signpost-name") or next((v for v in values if v in NAMES), "")
            if name not in NAMES or "local.macplugins.summon" not in values or "panel" not in values:
                continue
            expected = "window update after order-front" if name == "PanelWindowUpdate" else "ordered front"
            if expected not in values:
                continue
            duration = resolve(cell("duration"))
            if duration is None:
                continue
            raw = (duration.text or "").strip()
            try:
                millis = int(raw) / 1_000_000
            except ValueError:
                display = formatted(duration)
                if not display.endswith(" ms"):
                    continue
                try: millis = float(display.removesuffix(" ms"))
                except ValueError: continue
            if millis > 0:
                samples[name].append(millis)
    return {name: sorted(values) for name, values in samples.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=pathlib.Path)
    parser.add_argument("out", type=pathlib.Path)
    args = parser.parse_args()
    try:
        result = extract(args.trace)
        args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        return 0 if all(result.values()) else 1
    except (OSError, ValueError, ET.ParseError, subprocess.SubprocessError) as exc:
        args.out.write_text(json.dumps({"status":"blocked", "reason":type(exc).__name__}) + "\n")
        return 2


if __name__ == "__main__":
    sys.exit(main())
