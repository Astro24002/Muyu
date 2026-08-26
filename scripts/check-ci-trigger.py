#!/usr/bin/env python3
"""Keep CI limited to version tags and published GitHub Releases."""

from pathlib import Path


expected = "on:\n  push:\n    tags:\n      - 'v*.*.*'\n  release:\n    types: [published]"
for workflow in ("ci.yml", "release.yml"):
    text = Path(".github/workflows", workflow).read_text(encoding="utf-8")
    assert expected in text, f"{workflow} must use the version-tag and published-release trigger"
    assert "pull_request:" not in text, f"{workflow} must not start on pull requests"
    assert "\n  push:\n" not in text.replace(expected, ""), f"{workflow} retains an unfiltered push trigger"

release = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
assert "workflow_dispatch:" not in release, "manual dispatch must not bypass the release event gate"
assert "github.event_name == 'release'" in release, "protected artifact publication must only run for a Release"
print("CI and release trigger check passed")
