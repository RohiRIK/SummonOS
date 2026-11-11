#!/usr/bin/env python3
"""Website links survive source relocation without rewriting literal examples."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("docs_site", ROOT / "tools/docs-site.py")
site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(site)


class DocumentationLinkTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve() / "repository"
        self.stage = Path(temporary.name) / "stage"
        (self.root / "docs").mkdir(parents=True)
        (self.root / "docs/target.md").write_text("# Target\n")
        (self.root / "source.swift").write_text("// Source-only link target.\n")
        self.mapping = {"docs/from.md": "index.md", "docs/target.md": "docs/target.md"}
        replacement = patch.object(site, "ROOT", self.root)
        replacement.start()
        self.addCleanup(replacement.stop)

    def rewrite(self, text):
        def convert(url, raw_html=False):
            return site.rewrite_url(url, "docs/from.md", self.mapping, self.stage, "main", raw_html)
        return site.rewrite_markdown(text, convert)

    def test_escaped_backtick_does_not_swallow_following_links(self):
        text = "Shortcut \\` then [`Target`](target.md) and [source](../source.swift).\n"
        self.assertEqual(self.rewrite(text),
                         "Shortcut \\` then [`Target`](docs/target.md) and "
                         "[source](https://github.com/RohiRIK/SummonOS/blob/main/source.swift).\n")

    def test_code_examples_remain_literal_while_real_links_relocate(self):
        examples = "`[example](missing.md)`\n\n```markdown\n[example](missing.md)\n```\n"
        self.assertEqual(self.rewrite(examples + "[Target](target.md)\n"),
                         examples + "[Target](docs/target.md)\n")
        even_backslashes = "\\\\`[example](missing.md)` "
        self.assertEqual(self.rewrite(even_backslashes + "[Target](target.md)"),
                         even_backslashes + "[Target](docs/target.md)")

    def test_raw_html_and_reference_links_use_their_respective_routes(self):
        self.assertEqual(self.rewrite('<a href="target.md#section">Target</a>\n\n[Target][t]\n[t]: target.md#section\n'),
                         '<a href="docs/target/#section">Target</a>\n\n[Target][t]\n[t]: docs/target.md#section\n')

    def test_missing_and_outside_source_targets_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "missing source link target"):
            self.rewrite("[Missing](missing.md)")
        with self.assertRaisesRegex(ValueError, "escapes repository"):
            self.rewrite("[Outside](../../private.md)")


class VercelDeploymentTests(unittest.TestCase):
    def test_static_deployment_uses_canonical_builder_and_requested_domain(self):
        import json
        config_path = ROOT / "vercel.json"
        self.assertTrue(config_path.is_file(), "Vercel static deployment configuration is missing")
        config = json.loads(config_path.read_text())
        self.assertIsNone(config["framework"])
        self.assertEqual(config["outputDirectory"], "public")
        self.assertIn("requirements-docs.txt", config["installCommand"])
        self.assertIn("tools/docs-site.py build --site-dir", config["buildCommand"])
        self.assertIn("mktemp -d", config["buildCommand"])
        self.assertIn("https://sumonos.rohi-lab.org/", (ROOT / "mkdocs.yml").read_text())
        workflow = (ROOT / ".github/workflows/docs.yml").read_text()
        self.assertNotIn("actions/deploy-pages@", workflow)
        self.assertNotIn("pages: write", workflow)


if __name__ == "__main__":
    unittest.main()
