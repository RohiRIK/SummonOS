#!/usr/bin/env python3
"""tools/ci-plan.sh: which Swift jobs a change runs."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASH = os.environ.get("CI_PLAN_BASH", "bash")
PACKAGES = ["incubator/summon", "incubator/summon/templates/app", "incubator/summon/templates/menubar-panel", "macctl"]


def plan(files, event="pull_request"):
    with tempfile.NamedTemporaryFile("w", suffix=".txt") as listing:
        listing.write("\n".join(files))
        listing.flush()
        out = subprocess.run([BASH, str(ROOT / "tools/ci-plan.sh"), event, listing.name, json.dumps(PACKAGES)],
                             check=True, capture_output=True, text=True).stdout
    values = dict(line.split("=", 1) for line in out.splitlines())
    jobs = sorted((job["package"], job["os"]) for job in json.loads(values["matrix"])["include"])
    return jobs, json.loads(values["core"]), values["macctl"] == "true", values["skills"] == "true"


class CIPlanTests(unittest.TestCase):
    def test_summon_change_builds_only_summon_on_both_macos(self):
        jobs, core, macctl, skills = plan(["incubator/summon/Sources/SummonCore/Shell.swift"])
        self.assertEqual(jobs, [("incubator/summon", "macos-15"), ("incubator/summon", "macos-26")])
        self.assertEqual(core, ["incubator/summon"])
        self.assertFalse(macctl)
        self.assertFalse(skills)

    def test_template_change_builds_that_template_on_26_and_summon(self):
        jobs, _, macctl, _ = plan(["incubator/summon/templates/menubar-panel/Sources/StarterUI/StatusPanel.swift"])
        self.assertEqual(jobs, [("incubator/summon", "macos-15"), ("incubator/summon", "macos-26"),
                                ("incubator/summon/templates/menubar-panel", "macos-26")])
        self.assertFalse(macctl)

    def test_macctl_change_runs_the_crash_matrix(self):
        jobs, core, macctl, _ = plan(["macctl/Sources/MacCtlCore/Engine.swift"])
        self.assertEqual([p for p, _ in jobs], ["macctl", "macctl"])
        self.assertEqual(core, ["macctl"])
        self.assertTrue(macctl)

    def test_docs_and_workspace_files_build_nothing(self):
        jobs, core, macctl, skills = plan(["docs/features.md", "README.md", "tools/mp", "install.sh"])
        self.assertEqual(jobs, [])
        self.assertEqual(core, [])
        self.assertFalse(macctl or skills)

    def test_skill_examples_run_only_their_check(self):
        jobs, _, _, skills = plan([".claude/skills/LiquidGlass/Examples/Panel.swift"])
        self.assertEqual(jobs, [])
        self.assertTrue(skills)

    def test_package_markdown_counts_as_the_package(self):
        jobs, _, _, _ = plan(["incubator/summon/plugin/skills/mac-app/SKILL.md"])
        self.assertEqual({p for p, _ in jobs}, {"incubator/summon"})

    def test_workflow_or_unknown_file_builds_everything(self):
        for files in ([".github/workflows/swift.yml"], ["Brewfile"]):
            jobs, _, macctl, skills = plan(files)
            self.assertEqual(len(jobs), 6)  # summon + macctl on both, two templates on 26
            self.assertTrue(macctl and skills)

    def test_push_and_unknown_diff_build_everything(self):
        self.assertEqual(len(plan(["docs/x.md"], event="push")[0]), 6)
        self.assertEqual(len(plan([])[0]), 6)


if __name__ == "__main__":
    unittest.main()
