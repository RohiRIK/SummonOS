#!/usr/bin/env python3
"""tools/public-patterns.txt (the CI privacy scan) catches private values and lets documentation values through.
Samples are built by concatenation so this file never holds a value the scan would refuse."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PATTERNS = ROOT / "tools" / "public-patterns.txt"
SCAN = ROOT / "tools" / "private-scan.sh"

PRIVATE = [
    "host 192." + "168.1.20 up",
    "10." + "0.0.7",
    "172." + "20.1.1:8080",
    "tailnet 100." + "101.2.3",
    "mac " + ":".join(["a4", "83", "e7", "12", "34", "56"]),
    ":".join(["00", "00", "5e", "00", "54", "01"]),
    "mail me: someone" + "@" + "gmail.com",
    "first.last" + "@" + "icloud.com",
]
PUBLIC = [
    "fixture 192.0.2.10",
    "router " + ":".join(["00", "00", "5e", "00", "53", "1a"]),
    "macOS 10.15.7 and 26.0",
    "git" + "@" + "github.com:RohiRIK/SummonOS.git",
    "fixture" + "@" + "example.invalid",
    "menubar-icon" + "@" + "2x.png",
    "time 12:34:56",
    "sha " + ":".join(["ab"] * 20),
]


class PublicPatternsTests(unittest.TestCase):
    def scan(self, text):
        with tempfile.TemporaryDirectory() as tree:
            Path(tree, "sample.txt").write_text(text + "\n")
            return subprocess.run(["bash", str(SCAN), str(PATTERNS), tree], capture_output=True).returncode

    def test_private_values_refused(self):
        for text in PRIVATE:
            with self.subTest(text=text):
                self.assertEqual(self.scan(text), 1)

    def test_documentation_values_pass(self):
        for text in PUBLIC:
            with self.subTest(text=text):
                self.assertEqual(self.scan(text), 0)


if __name__ == "__main__":
    unittest.main()
