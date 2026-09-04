#!/usr/bin/env python3
"""Keep CI limited to version tags and published GitHub Releases."""

from pathlib import Path


makefile = Path("Makefile").read_text(encoding="utf-8")
debug_builder = Path("scripts/build-android-debug.sh")
production_guard = Path("scripts/assert-production-api-base-url.sh")
assert "scripts/build-android-debug.sh" in makefile, (
    "client-build must use the shared Android debug artifact builder"
)
assert debug_builder.is_file(), "the shared Android debug artifact builder must exist"
assert debug_builder.stat().st_mode & 0o111, "the Android debug artifact builder must be executable"
assert production_guard.is_file(), "the production Android API guard must exist"
assert production_guard.stat().st_mode & 0o111, "the production Android API guard must be executable"

expected = "on:\n  push:\n    tags:\n      - 'v*.*.*'\n  release:\n    types: [published]"
for workflow in ("ci.yml", "release.yml"):
    text = Path(".github/workflows", workflow).read_text(encoding="utf-8")
    assert expected in text, f"{workflow} must use the version-tag and published-release trigger"
    assert "pull_request:" not in text, f"{workflow} must not start on pull requests"
    assert "\n  push:\n" not in text.replace(expected, ""), f"{workflow} retains an unfiltered push trigger"

release = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
assert "workflow_dispatch:" not in release, "manual dispatch must not bypass the release event gate"
assert "github.event_name == 'release'" in release, "protected artifact publication must only run for a Release"
assert "contents: write" in release, "release workflow must be able to attach the APK to a GitHub Release"
assert "gh release upload" in release, "release workflow must attach the version APK to the GitHub Release"
assert "--clobber" in release, "release APK upload must be repeatable"
assert 'apk_path="build/app/outputs/flutter-apk/Muyu-${RELEASE_TAG}.apk"' in release, (
    "only the version-named APK may be attached to a GitHub Release"
)
assert "actions/download-artifact@v4" in release, "tag publishing must consume the verified Android artifact"
assert "release-assets/Muyu-${RELEASE_TAG}.apk" in release, (
    "tag publishing must select only the version-named APK"
)
assert "github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')" in release, (
    "automatic Release creation must be limited to version tag pushes"
)
assert "vars.ENABLE_SIGNED_RELEASE == 'true'" in release, (
    "signed release artifacts must remain explicitly opt-in"
)

workflow_texts = (
    ("ci.yml", Path(".github/workflows/ci.yml").read_text(encoding="utf-8")),
    ("release.yml", release),
)
for workflow_name, workflow_text in workflow_texts:
    assert (
        "API_BASE_URL=https://muyu.bkverse.space" in workflow_text
        or "API_BASE_URL: https://muyu.bkverse.space" in workflow_text
    ), (
        f"{workflow_name} Android artifacts must target the production API"
    )
    assert "ANDROID_BUILD_ENV: production" in workflow_text, (
        f"{workflow_name} Android artifacts must use the production build gate"
    )
    assert "run: make client-build" in workflow_text, (
        f"{workflow_name} Android artifacts must use the shared production builder"
    )
    assert "API_BASE_URL=https://example.invalid" not in workflow_text, (
        f"{workflow_name} must not publish Android artifacts with a placeholder API"
    )
    assert 'Muyu-${version_name}.apk' in workflow_text, (
        f"{workflow_name} must publish a version-named Android APK"
    )
    assert 'Muyu-${commit_id}.apk' not in workflow_text, (
        f"{workflow_name} must not publish a local commit-named Android APK"
    )
    assert "Muyu-v*.apk" in workflow_text, (
        f"{workflow_name} artifact uploads must select version-named APKs only"
    )

builder = Path("scripts/build-android-debug.sh").read_text(encoding="utf-8")
assert 'commit_id="${commit_id:0:7}"' in builder
assert 'commit_apk="$output_dir/Muyu-${commit_id}.apk"' in builder
assert 'cp -- "$source_apk" "$commit_apk"' in builder
assert 'assert-production-api-base-url.sh' in builder
assert 'assets/flutter_assets/kernel_blob.bin' in builder
assert 'unzip -tq "$commit_apk"' in builder
print("CI and release trigger check passed")
