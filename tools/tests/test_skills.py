#!/usr/bin/env python3
"""Regression tests for public design-skill structure and example verification."""
from __future__ import annotations

import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

WORKSPACE = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("check_skills", WORKSPACE / "tools" / "check-skills.py")
assert SPEC is not None and SPEC.loader is not None
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)

ENTRY = '''---
name: MacAqua
description: "Retro Aqua design. USE WHEN requesting Aqua. NOT FOR modern macOS (LiquidGlass)."
category: visual
effort: medium
domain: design
---

# MacAqua
Support macOS 15.

## Workflow Routing
Read `Components.md` for components.

## Gotchas
Preserve working native window controls.

## Examples
**Example 1:** Create an Aqua player with real controls.
**Example 2:** Add a scoped retro theme.
'''


class SkillValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="summon-skills-test-")
        self.addCleanup(self.temp.cleanup)
        self.skills = Path(self.temp.name) / ".claude" / "skills"
        self.skill = self.skills / "MacAqua"
        self.skill.mkdir(parents=True)
        self.entry = self.skill / "SKILL.md"
        self.entry.write_text(ENTRY, encoding="utf-8")
        self.component = self.skill / "Components.md"
        self.component.write_text("# Components\n\n```swift\nstruct Sample: View { var body: some View { Text(\"Ready\") } }\n```\n", encoding="utf-8")

    def errors(self):
        return checker.validate_skill(self.skill, self.skills)[0]

    def test_valid_progressively_disclosed_skill(self):
        errors, sources = checker.validate_skill(self.skill, self.skills)
        self.assertEqual(errors, [])
        self.assertEqual(len(sources), 1)
        self.assertIn("Text(\"Ready\")", sources[self.component][0])

    def test_missing_routing_target_is_rejected(self):
        self.component.unlink()
        self.assertTrue(any("missing reference: Components.md" in error for error in self.errors()))

    def test_workflow_references_resolve_from_workflow_directory(self):
        workflow = self.skill / "Workflows" / "Build.md"
        workflow.parent.mkdir()
        workflow.write_text("Read `../Components.md`.\n", encoding="utf-8")
        self.assertEqual(self.errors(), [])

    def test_reference_cannot_escape_skills_root(self):
        self.component.write_text("Read `../../../private.md`.\n", encoding="utf-8")
        self.assertTrue(any("reference escapes skills root" in error for error in self.errors()))

    def test_symlink_reference_cannot_escape_skills_root(self):
        outside = Path(self.temp.name) / "private.md"
        outside.write_text("private", encoding="utf-8")
        self.component.unlink()
        self.component.symlink_to(outside)
        self.assertTrue(any("reference escapes skills root" in error for error in self.errors()))

    def test_markdown_links_are_validated_too(self):
        self.component.write_text("[Guide](Missing.md)\n", encoding="utf-8")
        self.assertTrue(any("missing reference: Missing.md" in error for error in self.errors()))

    def test_external_links_are_not_local_file_paths(self):
        self.component.write_text("[Apple](https://developer.apple.com/documentation/swiftui)\n", encoding="utf-8")
        self.assertEqual(self.errors(), [])

    def test_missing_metadata_and_mutual_routing_are_rejected(self):
        self.entry.write_text(ENTRY.replace("category: visual\n", "").replace("NOT FOR modern macOS (LiquidGlass).", ""), encoding="utf-8")
        errors = self.errors()
        self.assertTrue(any("category" in error for error in errors))
        self.assertTrue(any("NOT FOR" in error for error in errors))
        self.assertTrue(any("route modern UI" in error for error in errors))

    def test_duplicate_frontmatter_is_rejected(self):
        self.entry.write_text(ENTRY.replace("effort: medium", "effort: medium\neffort: low"), encoding="utf-8")
        self.assertTrue(any("duplicate metadata effort" in error for error in self.errors()))

    def test_unclosed_frontmatter_and_multiline_values_fail(self):
        self.assertIn("unclosed frontmatter", checker.frontmatter("---\nname: Aqua")[1])
        self.assertTrue(checker.frontmatter("---\ndescription: |\n---")[1])

    def test_entrypoint_size_and_two_examples_are_enforced(self):
        self.entry.write_text(ENTRY.replace("**Example 2:**", "Another sample:") + "\n" * 40, encoding="utf-8")
        errors = self.errors()
        self.assertTrue(any("50 lines" in error for error in errors))
        self.assertTrue(any("two concrete examples" in error for error in errors))

    def test_official_palette_requires_provenance_or_approximation(self):
        self.component.write_text("Use the official hex palette.\n", encoding="utf-8")
        self.assertTrue(any("palette needs documented provenance" in error for error in self.errors()))

    def test_unclosed_swift_fence_does_not_silently_skip_example(self):
        self.component.write_text("```swift\nlet bad = 1\n", encoding="utf-8")
        self.assertTrue(any("unclosed code fence" in error for error in self.errors()))

    def test_unknown_swift_fence_does_not_bypass_typechecking(self):
        self.component.write_text("```swift excerpt\nlet bad = 1\n```\n", encoding="utf-8")
        self.assertTrue(any("unsupported Swift fence" in error for error in self.errors()))

    def test_swift_blocks_combine_but_other_languages_do_not(self):
        blocks, errors = checker.swift_blocks("```sh\necho ready\n```\n```swift\nstruct A {}\n```\n```swift\nlet a = A()\n```\n")
        self.assertEqual(errors, [])
        self.assertEqual(blocks, ["struct A {}", "let a = A()"])

    def test_compile_gate_uses_swift6_minimum_target_and_never_executes_snippet(self):
        observed = []

        def compiler(args, **kwargs):
            observed.append((args, Path(args[-1]).read_text(encoding="utf-8")))
            return subprocess.CompletedProcess(args, 0, "", "")

        with patch.object(checker.platform, "system", return_value="Darwin"), patch.object(checker.shutil, "which", return_value="/usr/bin/xcrun"), patch.object(checker.subprocess, "run", side_effect=compiler), contextlib.redirect_stdout(io.StringIO()):
            errors = checker.compile_sources({self.component: ["struct A {}", "let a = A()"]}, "arm64-apple-macosx15.0")
        self.assertEqual(errors, [])
        self.assertEqual(len(observed), 1)
        args, source = observed[0]
        self.assertIn("-typecheck", args)
        self.assertEqual(args[args.index("-swift-version") + 1], "6")
        self.assertEqual(args[args.index("-target") + 1], "arm64-apple-macosx15.0")
        self.assertIn("struct A {}\n\nlet a = A()", source)

    def test_compiler_failure_and_missing_toolchain_fail_closed(self):
        with patch.object(checker.platform, "system", return_value="Darwin"), patch.object(checker.shutil, "which", return_value="/usr/bin/xcrun"), patch.object(checker.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "unavailable on macOS 15")):
            errors = checker.compile_sources({self.component: ["broken"]}, "arm64-apple-macosx15.0")
        self.assertTrue(any("unavailable on macOS 15" in error for error in errors))
        with patch.object(checker.platform, "system", return_value="Linux"):
            self.assertTrue(checker.compile_sources({}, "x86_64-apple-macosx15.0"))

    def test_cli_rejects_path_instead_of_skill_name(self):
        with contextlib.redirect_stderr(io.StringIO()):
            status = checker.main(["--root", self.temp.name, "--skills", "../../private"])
        self.assertEqual(status, 1)

    def test_shipped_design_skills_validate(self):
        with contextlib.redirect_stdout(io.StringIO()):
            status = checker.main(["--root", str(WORKSPACE)])
        self.assertEqual(status, 0)


if __name__ == "__main__":
    unittest.main()
