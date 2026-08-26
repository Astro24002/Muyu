#!/usr/bin/env python3
"""Keep CI limited to version tags and published GitHub Releases."""

from pathlib import Path


text = Path(".github/workflows/ci.yml").read_text(encoding="utf-8")
expected = "on:\n  push:\n    tags:\n      - 'v*.*.*'\n  release:\n    types: [published]"
assert expected in text, "CI must use the version-tag and published-release trigger"
assert "pull_request:" not in text, "pull requests must not start CI"
assert "\n  push:\n" not in text.replace(expected, ""), "unfiltered push trigger remains"
print("CI trigger check passed")
