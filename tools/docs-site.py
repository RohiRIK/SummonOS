#!/usr/bin/env python3
"""Stage canonical public documents for MkDocs; also serve as its build hooks."""
from __future__ import annotations

import argparse
import html
from pathlib import Path, PurePosixPath
import posixpath
import re
import shutil
import subprocess
import sys
import tempfile
from html.parser import HTMLParser
from urllib.parse import quote, unquote, urlsplit, urlunsplit


ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "https://github.com/RohiRIK/SummonOS"
DOCUMENT_TREES = ("docs", "incubator/summon/docs", "macctl/docs")
ROOT_DOCUMENTS = (
    "README.md", "CONTRIBUTING.md", "SECURITY.md", "plugins.md",
    "incubator/summon/README.md", "incubator/summon/CHANGELOG.md",
    "incubator/summon/THIRD_PARTY_NOTICES.md", "macctl/README.md",
)
OMITTED = {"agents.md", "project-context.md", "claude.md", "skill.md", "tasks"}
ASSET_SUFFIXES = {".svg", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif", ".ico", ".pdf"}
SOURCES: dict[str, str] = {}


def public_path(path: Path) -> bool:
    relative = path.relative_to(ROOT)
    return not path.is_symlink() and all(
        not part.startswith(".") and part.lower() not in OMITTED for part in relative.parts
    )


def documents() -> list[str]:
    paths = {ROOT / name for name in ROOT_DOCUMENTS}
    for directory in DOCUMENT_TREES:
        paths.update((ROOT / directory).rglob("*.md"))
    paths.update((ROOT / "incubator/summon/templates").glob("*/README.md"))
    selected = sorted(path.relative_to(ROOT).as_posix() for path in paths if public_path(path))
    for name in selected:
        if not (ROOT / name).is_file():
            raise ValueError(f"Missing public document: {name}")
    if "docs/home.md" not in selected:
        raise ValueError("The wiki homepage docs/home.md is required")
    return selected


def destination(source: str) -> str:
    if source == "docs/home.md":
        return "index.md"
    path = PurePosixPath(source)
    return str(path.with_name("overview.md")) if path.name == "README.md" else source


def output_path(staged: str) -> str:
    path = PurePosixPath(staged)
    if path.suffix == ".md":
        return str(path.with_name("index.html")) if path.name == "index.md" else str(path.with_suffix("") / "index.html")
    return staged


def external_directory(path: Path) -> Path:
    path = path.expanduser().resolve()
    if path == ROOT or ROOT in path.parents or path in ROOT.parents:
        raise ValueError("Generated documentation must be outside the checkout and its ancestors; choose --site-dir in a dedicated cache or temporary directory")
    return path


def copy_asset(source: str, staged_root: Path) -> None:
    target = staged_root / source
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / source, target)


def rewrite_url(url: str, source: str, mapping: dict[str, str], staged_root: Path, ref: str, raw_html: bool = False) -> str:
    url = html.unescape(url)
    parts = urlsplit(url)
    if parts.scheme or parts.netloc or not parts.path:
        return url
    decoded = unquote(re.sub(r"\\([() ])", r"\1", parts.path))
    # Repository-root paths are accepted, but no filesystem escape or private path is.
    relative = posixpath.normpath(decoded.lstrip("/") if decoded.startswith("/") else posixpath.join(posixpath.dirname(source), decoded))
    if relative == ".." or relative.startswith("../"):
        raise ValueError(f"{source}: link escapes repository: {url}")
    original = ROOT / relative
    if not original.exists():
        raise ValueError(f"{source}: missing source link target: {url}")
    if original.is_symlink() or (ROOT not in original.resolve().parents and original.resolve() != ROOT):
        raise ValueError(f"{source}: linked symlinks are not public assets: {url}")
    target = mapping.get(relative)
    if target is None and original.is_file() and public_path(original) and original.suffix.lower() in ASSET_SUFFIXES:
        copy_asset(relative, staged_root)
        target = relative
    if target is None:
        kind = "tree" if original.is_dir() else "blob"
        path = f"{REPOSITORY}/{kind}/{quote(ref, safe='')}/{quote(relative, safe='/')}"
        return urlunsplit(("https", "github.com", urlsplit(path).path, parts.query, parts.fragment))
    current = mapping[source]
    if raw_html:
        # Raw HTML bypasses MkDocs' Markdown link processor and needs final output paths.
        start = posixpath.dirname(output_path(current)) or "."
        rendered = posixpath.relpath(output_path(target), start)
        if rendered.endswith("index.html"):
            rendered = rendered[:-10] or "./"
    else:
        rendered = posixpath.relpath(target, posixpath.dirname(current) or ".")
    return urlunsplit(("", "", quote(rendered, safe="/.-_~"), parts.query, parts.fragment))


def rewrite_prose(text: str, convert) -> str:
    # Balanced Markdown destinations (including images), without touching labels or titles.
    cursor = 0
    pieces = []
    for match in re.finditer(r"\]\([ \t]*", text):
        start = match.end()
        if start < cursor or start >= len(text):
            continue
        angle = text[start] == "<"
        token_start = start + int(angle)
        end = token_start
        depth = 0
        while end < len(text):
            char = text[end]
            if char == "\\" and end + 1 < len(text):
                end += 2
                continue
            if angle and char == ">":
                break
            if not angle:
                if char.isspace() or char == ")" and depth == 0:
                    break
                if char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
            end += 1
        if end > token_start:
            pieces.extend((text[cursor:token_start], convert(text[token_start:end])))
            cursor = end
    pieces.append(text[cursor:])
    text = "".join(pieces)

    def reference(match):
        target = match.group(2) or match.group(3)
        return match.group(1) + ("<" + convert(target) + ">" if match.group(2) else convert(target))

    text = re.sub(r"(?m)^([ \t]{0,3}\[[^\]\n]+\]:[ \t]*)(?:<([^>\n]+)>|(\S+))", reference, text)

    def tag(match):
        def attribute(attr):
            value = html.unescape(attr.group(3))
            if attr.group(1).lower() == "srcset":
                value = ", ".join(
                    " ".join([convert(item.split()[0], True), *item.split()[1:]])
                    for item in value.split(",") if item.strip()
                )
            else:
                value = convert(value, True)
            return attr.group(1) + attr.group(2) + html.escape(value, quote=True) + attr.group(4)
        return re.sub(r"\b(href|src|poster|srcset)(\s*=\s*[\"'])(.*?)([\"'])", attribute, match.group(), flags=re.IGNORECASE | re.DOTALL)

    return re.sub(r"<[A-Za-z][^>]*>", tag, text)


def rewrite_markdown(text: str, convert) -> str:
    # Fenced blocks and inline code remain byte-for-byte source examples, never links.
    result = []
    prose = []
    fence = None

    def flush():
        block = "".join(prose)
        prose.clear()
        cursor = 0
        for match in re.finditer(r"`+", block):
            if match.start() < cursor:
                continue
            start = match.start()
            unescaped = start
            while unescaped > 0 and block[unescaped - 1] == "\\":
                unescaped -= 1
            if (start - unescaped) % 2:
                continue
            closer = re.search(r"(?<!`)" + re.escape(match.group()) + r"(?!`)", block[match.end():])
            if closer is None:
                continue
            end = match.end() + closer.end()
            result.append(rewrite_prose(block[cursor:match.start()], convert))
            result.append(block[match.start():end])
            cursor = end
        result.append(rewrite_prose(block[cursor:], convert))

    for line in text.splitlines(keepends=True):
        marker = re.match(r"^[ \t]*(?:>\s*)?(`{3,}|~{3,})(.*)$", line)
        if fence:
            result.append(line)
            if marker and marker.group(1)[0] == fence[0] and len(marker.group(1)) >= len(fence) and not marker.group(2).strip():
                fence = None
        elif marker:
            flush()
            fence = marker.group(1)
            result.append(line)
        else:
            prose.append(line)
    flush()
    return "".join(result)


def page_title(source: str) -> str:
    import yaml

    text = (ROOT / source).read_text(encoding="utf-8")
    if text.startswith("---\n"):
        end = text.find("\n---", 4)
        if end != -1:
            metadata = yaml.safe_load(text[4:end]) or {}
            if metadata.get("title"):
                return str(metadata["title"])
    heading = re.search(r"^#\s+(.+)", text, re.MULTILINE)
    return heading.group(1).strip() if heading else PurePosixPath(source).stem.replace("-", " ").title()


def navigation(mapping: dict[str, str]) -> list[dict]:
    remaining = set(mapping)

    def page(source, label=None):
        remaining.remove(source)
        return {label or page_title(source): mapping[source]}

    def chosen(sources):
        return [page(source, label) for source, label in sources if source in remaining]

    def tree(prefix):
        entries = []
        direct = sorted((name for name in remaining if posixpath.dirname(name) == prefix), key=lambda name: (PurePosixPath(name).name != "index.md", name))
        entries.extend(page(name) for name in direct)
        children = sorted({name[len(prefix) + 1:].split("/")[0] for name in remaining if name.startswith(prefix + "/")})
        for child in children:
            entries.append({child.replace("-", " ").title(): tree(prefix + "/" + child)})
        return entries

    nav = [{"Overview": mapping["docs/home.md"]}]
    remaining.remove("docs/home.md")
    nav.append({"Get started": chosen([
        ("docs/getting-started.md", "Installation & first steps"),
        ("docs/status.md", "Release & source status"),
        ("docs/install-ai.md", "Installation for agents"),
        ("README.md", "About SummonOS"),
        ("docs/configuration.md", "Configuration & state"),
        ("docs/uninstall.md", "Uninstall & data preservation"),
    ])})
    nav.append({"Use SummonOS": chosen([
        ("docs/features.md", "Feature reference"),
        ("docs/troubleshooting.md", "Troubleshooting"),
        ("docs/security-model.md", "Security & recovery"),
        ("plugins.md", "Apps & plugins"),
    ]) + [
        {"Summon": chosen([
            ("docs/cli-reference.md", "Command reference"),
            ("incubator/summon/README.md", "App & CLI guide"),
            ("incubator/summon/CHANGELOG.md", "Changelog"),
            ("incubator/summon/THIRD_PARTY_NOTICES.md", "Third-party notices"),
        ]) + tree("incubator/summon/docs")},
        {"macctl": chosen([("macctl/README.md", "CLI guide")]) + tree("macctl/docs")},
    ]})
    templates = [{PurePosixPath(name).parent.name.replace("-", " ").title(): mapping[name]} for name in sorted(remaining) if name.startswith("incubator/summon/templates/")]
    remaining.difference_update(name for name in list(remaining) if name.startswith("incubator/summon/templates/"))
    nav.append({"Build apps": chosen([
        ("docs/workflow.md", "App lifecycle"), ("docs/tools.md", "Workspace tools"),
        ("CONTRIBUTING.md", "Contributing"), ("docs/documentation.md", "Documentation website"),
    ]) + [{"Templates": templates}]})
    nav.append({"Knowledge base": [
        {"Architecture decisions": tree("docs/adr")},
        {"Historical archive": [
            {"Plans & reports": tree("docs/plans")}, {"Research": tree("docs/research")},
            {"Mac UX research": tree("docs/ux-surfaces")},
        ]},
    ] + chosen([
        ("docs/index.md", "Complete documentation index"),
        ("docs/log.md", "Documentation history"), ("SECURITY.md", "Report a vulnerability"),
    ]) + [page(name) for name in sorted(remaining)]})
    return [entry for entry in nav if next(iter(entry.values()))]


def on_serve(server, config, builder):
    # Staging is rebuilt from the canonical watch paths. Watching our own output
    # would schedule another build every time a source is staged.
    server.unwatch(config["docs_dir"])
    return server


def on_pre_build(config):
    """Refresh staging and discovered navigation on builds and live-reload rebuilds."""
    global SOURCES
    stage = external_directory(Path(config["docs_dir"]))
    shutil.rmtree(stage)
    stage.mkdir()
    mapping = {source: destination(source) for source in documents()}
    if len(set(mapping.values())) != len(mapping):
        raise ValueError("Public documents collide after homepage/README mapping")
    SOURCES = {target: source for source, target in mapping.items()}
    ref = config["extra"]["source_ref"]
    for key in ("logo", "favicon"):
        copy_asset(config["theme"][key], stage)
    for directory in DOCUMENT_TREES:
        for asset in (ROOT / directory).rglob("*"):
            if asset.is_file() and public_path(asset) and asset.suffix.lower() in ASSET_SUFFIXES | {".txt", ".css"}:
                copy_asset(asset.relative_to(ROOT).as_posix(), stage)
    for source, target in mapping.items():
        text = (ROOT / source).read_text(encoding="utf-8")
        convert = lambda url, raw_html=False, source=source: rewrite_url(url, source, mapping, stage, ref, raw_html)
        target_path = stage / target
        target_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.write_text(rewrite_markdown(text, convert), encoding="utf-8")
    config["nav"] = navigation(mapping)


def on_page_context(context, page, config, nav):
    source = SOURCES[page.file.src_uri]
    ref = quote(config["extra"]["source_ref"], safe="")
    page.edit_url = f"{REPOSITORY}/edit/{ref}/{quote(source, safe='/')}"
    return context


class Links(HTMLParser):
    def __init__(self, runtime_scripts=()):
        super().__init__(convert_charrefs=True)
        self.ids: set[str] = set()
        self.targets: list[str] = []
        self.runtime_scripts = frozenset(runtime_scripts)

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if attributes.get("id"):
            self.ids.add(attributes["id"])
        if tag == "a" and attributes.get("name"):
            self.ids.add(attributes["name"])
        for key in ("href", "src", "poster"):
            if attributes.get(key):
                # Vercel serves this opted-in script at runtime, not from the static output.
                if tag == "script" and key == "src" and attributes[key] in self.runtime_scripts:
                    continue
                self.targets.append(attributes[key])
        if attributes.get("srcset"):
            self.targets.extend(item.split()[0] for item in attributes["srcset"].split(",") if item.strip())

    handle_startendtag = handle_starttag


def on_post_build(config):
    """Validate rendered HTML too: raw HTML images/links bypass MkDocs' checks."""
    site = Path(config["site_dir"]).resolve()
    pages = {}
    runtime_scripts = {"/_vercel/insights/script.js"} if config.get("extra", {}).get("vercel_analytics") else set()
    for path in site.rglob("*.html"):
        parser = Links(runtime_scripts)
        parser.feed(path.read_text(encoding="utf-8"))
        pages[path] = parser
    base_path = urlsplit(config["site_url"] or "").path.rstrip("/")
    errors = []
    for path, parser in pages.items():
        for url in parser.targets:
            parts = urlsplit(url)
            if parts.scheme or parts.netloc:
                continue
            decoded = unquote(parts.path)
            if decoded.startswith("/"):
                if base_path and (decoded == base_path or decoded.startswith(base_path + "/")):
                    decoded = decoded[len(base_path):]
                target = site / decoded.lstrip("/")
            else:
                target = path.parent / decoded if decoded else path
            target = target.resolve()
            if target.is_dir():
                target /= "index.html"
            if (target != site and site not in target.parents) or not target.is_file():
                errors.append(f"{path.relative_to(site)}: missing local target {url}")
            elif parts.fragment and target in pages and unquote(parts.fragment) not in pages[target].ids:
                errors.append(f"{path.relative_to(site)}: missing anchor {url}")
    if errors:
        raise ValueError("Rendered documentation links failed:\n" + "\n".join(sorted(set(errors))))


def on_page_markdown(markdown, page, config, files):
    source = SOURCES[page.file.src_uri]
    if source.startswith(("docs/plans/", "docs/research/", "docs/ux-surfaces/")):
        return (
            '!!! note "Historical archive"\n'
            '    This page records a dated plan, audit, or research context, not a current product contract. '
            '[Project status](' + relative_status(page.file.src_uri) + ') distinguishes current source behavior, '
            'published releases, and unfinished acceptance gates.\n\n' + markdown
        )
    return markdown


def relative_status(staged: str) -> str:
    return posixpath.relpath("docs/status.md", posixpath.dirname(staged) or ".")


def main() -> int:
    import yaml

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("build", "serve"))
    cache = Path.home() / ("Library/Caches" if sys.platform == "darwin" else ".cache") / "SummonOS/docs/site"
    parser.add_argument("--site-dir", type=Path, default=cache, help="Build output outside the checkout")
    parser.add_argument("--ref", default="main", help="GitHub source/edit branch or commit (default: main)")
    parser.add_argument("--dev-addr", default="127.0.0.1:8000", help="Local preview bind address")
    arguments = parser.parse_args()
    try:
        site_dir = external_directory(arguments.site_dir)
        with tempfile.TemporaryDirectory(prefix="summonos-docs-") as temporary:
            temporary_path = external_directory(Path(temporary))
            stage = temporary_path / "sources"
            stage.mkdir()
            config = {"INHERIT": str(ROOT / "mkdocs.yml")}
            config.update({
                "docs_dir": str(stage), "site_dir": str(site_dir),
                "hooks": [str(ROOT / "tools/docs-site.py")],
                "theme": {"custom_dir": str(ROOT / "docs/theme")},
                "watch": [str(ROOT / name) for name in (*ROOT_DOCUMENTS, *DOCUMENT_TREES, "incubator/summon/templates", "incubator/summon/design/brand", "mkdocs.yml")],
                "extra": {"source_ref": arguments.ref},
            })
            config_path = temporary_path / "mkdocs.yml"
            config_path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
            command = [sys.executable, "-m", "mkdocs", arguments.command, "--strict", "--config-file", str(config_path)]
            if arguments.command == "serve":
                command.extend(("--dev-addr", arguments.dev_addr))
            print(f"Documentation output: {site_dir}", flush=True)
            return subprocess.call(command, cwd=ROOT)
    except (ValueError, OSError) as error:
        parser.exit(1, f"docs-site: {error}\n")
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
