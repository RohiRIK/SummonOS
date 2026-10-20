#!/usr/bin/env python3
"""Validate the first-party macOS design skills without third-party dependencies.

The entrypoints use a deliberately small frontmatter subset: one scalar per line.
With --compile-swift, concatenate each Markdown file's Swift blocks and typecheck
that file as an independent Swift 6 unit targeting macOS 15. No snippets execute.
This checks types/API availability, not rendering, focus, or skill effectiveness.
"""
from __future__ import annotations

import argparse
import json
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_SKILLS = ("LiquidGlass", "MacAqua", "MacClassic", "MacLinen", "MacNeXT", "MacYosemite")
CATEGORIES = {"workflow", "reference", "delegation", "meta", "visual", "prompting", "quality"}
EFFORTS = {"low", "medium", "high"}
DOMAINS = {"dev", "security", "design", "data", "ops", "agents", "testing", "prompting", "meta", "docs"}
REFERENCE = re.compile(r"`((?:\.{1,2}/)?[\w./-]+\.md)(?:#[\w-]+)?`")
MARKDOWN_LINK = re.compile(r"\[[^\]\n]*\]\(([^)\s]+)\)")


def frontmatter(text: str) -> tuple[dict[str, str], list[str]]:
    """Parse only the scalar metadata format used by these public skills."""
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        return {}, ["missing frontmatter"]
    try:
        end = lines.index("---", 1)
    except ValueError:
        return {}, ["unclosed frontmatter"]
    fields: dict[str, str] = {}
    errors = []
    for line in lines[1:end]:
        match = re.fullmatch(r"([a-z][a-z-]*):\s*(.+)", line)
        if not match:
            errors.append(f"expected scalar metadata, got {line!r}")
            continue
        key, value = match.groups()
        if key in fields:
            errors.append(f"duplicate metadata {key}")
        if value.startswith('"'):
            try:
                value = json.loads(value)
            except json.JSONDecodeError:
                errors.append(f"invalid quoted metadata {key}")
                continue
            if not isinstance(value, str):
                errors.append(f"metadata {key} must be a string")
                continue
        elif value.startswith("'"):
            if not value.endswith("'") or len(value) < 2:
                errors.append(f"invalid quoted metadata {key}")
                continue
            value = value[1:-1].replace("''", "'")
        elif value in {"|", ">"} or value.startswith(("[", "{")):
            errors.append(f"metadata {key} must be a single scalar")
            continue
        fields[key] = value
    return fields, errors


def swift_blocks(text: str) -> tuple[list[str], list[str]]:
    """Extract fenced Swift blocks; report malformed fences rather than skip them."""
    blocks, errors, content = [], [], []
    fence: str | None = None
    language = ""
    for line in text.splitlines():
        if fence is None:
            match = re.fullmatch(r"\s*(`{3,}|~{3,})([^`~]*)", line)
            if match:
                fence, language = match.groups()
                language = language.strip()
                content = []
                if language.startswith("swift") and language != "swift":
                    errors.append(f"unsupported Swift fence {language!r}; use complete swift blocks")
        elif re.fullmatch(r"\s*" + re.escape(fence[0]) + "{" + str(len(fence)) + r",}\s*", line):
            if language == "swift":
                if not "\n".join(content).strip():
                    errors.append("empty Swift block")
                blocks.append("\n".join(content))
            fence = None
        else:
            content.append(line)
    if fence is not None:
        errors.append("unclosed code fence")
    return blocks, errors


def validate_skill(path: Path, skills_root: Path) -> tuple[list[str], dict[Path, list[str]]]:
    errors: list[str] = []
    sources: dict[Path, list[str]] = {}
    entry = path / "SKILL.md"
    if not entry.is_file():
        return [f"{path.name}: missing SKILL.md"], sources
    text = entry.read_text(encoding="utf-8")
    fields, metadata_errors = frontmatter(text)
    errors.extend(f"{entry.name}: {error}" for error in metadata_errors)
    if not re.fullmatch(r"[A-Z][A-Za-z0-9]*", path.name) or fields.get("name") != path.name:
        errors.append("name must match the TitleCase directory")
    for key, allowed in (("category", CATEGORIES), ("effort", EFFORTS), ("domain", DOMAINS)):
        if fields.get(key) not in allowed:
            errors.append(f"missing or invalid {key}")
    description = fields.get("description", "")
    if "USE WHEN" not in description or description.startswith("USE WHEN"):
        errors.append("description needs a WHAT clause followed by USE WHEN")
    if "NOT FOR" not in description:
        errors.append("description needs NOT FOR to distinguish modern and retro design")
    if len(description.split()) > 30:
        errors.append("description exceeds 30 words")
    for key in ("triggers", "workflows"):
        if key in fields:
            errors.append(f"legacy {key} metadata is unsupported")
    if len(text.splitlines()) > 50:
        errors.append("SKILL.md exceeds 50 lines; move detail into references")
    for heading in ("Workflow Routing", "Gotchas", "Examples"):
        if f"## {heading}\n" not in text:
            errors.append(f"missing {heading} section")
    if not re.search(r"\*\*Example 1[^\n]*", text) or not re.search(r"\*\*Example 2[^\n]*", text):
        errors.append("include two concrete examples")
    if not REFERENCE.search(text):
        errors.append("entrypoint must route to a reference file")
    if "macOS 15" not in text:
        errors.append("entrypoint must state the macOS 15 deployment target")
    if path.name == "LiquidGlass" and "macOS 26" not in text:
        errors.append("LiquidGlass must state the macOS 26 glass availability boundary")
    if path.name != "LiquidGlass" and "LiquidGlass" not in description:
        errors.append("retro descriptions must route modern UI to LiquidGlass")
    if path.name == "LiquidGlass" and any(name not in description for name in DEFAULT_SKILLS[1:]):
        errors.append("modern description must distinguish all explicit retro skills")
    for document in sorted(path.rglob("*.md")):
        body = document.read_text(encoding="utf-8")
        blocks, fence_errors = swift_blocks(body)
        errors.extend(f"{document.name}: {error}" for error in fence_errors)
        if blocks:
            sources[document] = blocks
        refs = set(REFERENCE.findall(body))
        for ref in MARKDOWN_LINK.findall(body):
            if not re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", ref) and not ref.startswith("#"):
                refs.add(ref.split("#", 1)[0])
        for ref in refs:
            target = document.parent / ref
            if Path(ref).is_absolute() or not target.resolve().is_relative_to(skills_root.resolve()):
                errors.append(f"{document.name}: reference escapes skills root: {ref}")
            elif not target.is_file():
                errors.append(f"{document.name}: missing reference: {ref}")
        if re.search(r"official (?:hex )?palettes?", body, re.I) and not re.search(r"not an official|not official", body, re.I):
            errors.append(f"{document.name}: palette needs documented provenance or an approximation label")
    return [f"{path.name}: {error}" for error in errors], sources


def compile_sources(sources: dict[Path, list[str]], target: str) -> list[str]:
    if platform.system() != "Darwin" or shutil.which("xcrun") is None:
        return ["--compile-swift requires macOS and an Xcode Swift toolchain"]
    errors = []
    with tempfile.TemporaryDirectory(prefix="summon-skills-") as work:
        temp = Path(work)
        for index, (document, blocks) in enumerate(sources.items()):
            source = temp / f"SkillExample{index}.swift"
            source.write_text("import SwiftUI\n\n" + "\n\n".join(blocks) + "\n", encoding="utf-8")
            try:
                result = subprocess.run(
                    ["xcrun", "swiftc", "-typecheck", "-swift-version", "6", "-target", target,
                     "-module-cache-path", str(temp / "modules"), str(source)],
                    capture_output=True, text=True, timeout=120, check=False,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                errors.append(f"{document}: Swift compiler failed: {exc}")
                continue
            if result.returncode:
                errors.append(f"{document}: Swift 6 typecheck failed\n{result.stderr.strip()}")
            else:
                print(f"Swift PASS {document.parent.name}/{document.name}", flush=True)
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                        help="workspace root (default: parent of tools)")
    parser.add_argument("--skills", nargs="+", default=DEFAULT_SKILLS, help="first-party skill directory names")
    parser.add_argument("--compile-swift", action="store_true", help="typecheck every Swift example on macOS")
    parser.add_argument("--swift-target", default=f"{platform.machine()}-apple-macosx15.0",
                        help="Swift target triple (default: host architecture, macOS 15)")
    args = parser.parse_args(argv)
    skills_root = args.root / ".claude" / "skills"
    errors, sources = [], {}
    for name in args.skills:
        if not re.fullmatch(r"[A-Z][A-Za-z0-9]*", name):
            errors.append(f"invalid first-party skill name: {name}")
            continue
        skill_errors, skill_sources = validate_skill(skills_root / name, skills_root)
        errors.extend(skill_errors)
        sources.update(skill_sources)
    if not errors and args.compile_swift:
        errors.extend(compile_sources(sources, args.swift_target))
    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1
    print(f"PASS {len(args.skills)} design skills; {len(sources)} Swift example files"
          + (" typechecked" if args.compile_swift else " (Swift typecheck not requested)"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
