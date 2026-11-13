#!/usr/bin/env python3
"""Keep project-new help aligned with the starters accepted by the CLI."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "incubator/summon/Sources/SummonCore"


class CommandCatalogTests(unittest.TestCase):
    def test_project_new_help_lists_every_accepted_starter(self):
        source = (CORE / "Projects.swift").read_text()
        enum = source.split("public enum ProjectStarter:", 1)[1].split("public var kind:", 1)[0]
        starters = [raw or name for name, raw in re.findall(
            r'^\s*case (\w+)(?: = "([^"]+)")?\s*$', enum, re.MULTILINE)]
        self.assertTrue(starters)
        catalog = (CORE / "CommandCatalog.swift").read_text()
        route = catalog.split('CommandInfo(route: "project new"', 1)[1].split('CommandInfo(route:', 1)[0]
        args_match = re.search(r'args: "([^"]+)"', route)
        assert args_match is not None, "project new has no catalog arguments"
        kind_match = re.search(r'--kind ([^ ]+)', args_match.group(1))
        assert kind_match is not None, "project new help omits --kind"
        documented = kind_match.group(1).split("|")
        self.assertEqual(set(documented), set(starters))


if __name__ == "__main__":
    unittest.main()
