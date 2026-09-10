#!/usr/bin/env python3
"""Keep CI limited to version tags and published GitHub Releases."""

from pathlib import Path


makefile = Path("Makefile").read_text(encoding="utf-8")
debug_builder = Path("scripts/build-android-debug.sh")
release_builder = Path("scripts/build-android-release.sh")
production_guard = Path("scripts/assert-production-api-base-url.sh")
assert "scripts/build-android-debug.sh" in makefile, (
    "client-build must use the shared Android debug artifact builder"
)
assert debug_builder.is_file(), "the shared Android debug artifact builder must exist"
assert debug_builder.stat().st_mode & 0o111, "the Android debug artifact builder must be executable"
assert release_builder.is_file(), "the signed Android release artifact builder must exist"
assert release_builder.stat().st_mode & 0o111, "the signed Android release artifact builder must be executable"
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
assert 'apk_path="release-assets/Muyu-${RELEASE_TAG}.apk"' in release, (
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
ci = workflow_texts[0][1]
assert "API_BASE_URL: https://muyu.bkverse.space" in ci
assert "ANDROID_BUILD_ENV: production" in ci
assert "run: make client-build" in ci
assert "Muyu-*.apk" in ci
assert "Muyu-v*.apk" not in ci
assert "Muyu-${version_name}.apk" not in ci

assert "API_BASE_URL: https://muyu.bkverse.space" in release
assert "Validate release signing inputs" in release
assert "ANDROID_KEYSTORE_BASE64" in release
assert "./scripts/build-android-release.sh" in release
assert "release-android-apk-${{ github.event.release.tag_name || github.ref_name }}" in release
assert "Muyu-v*.apk" in release
assert "release-android-debug-apk" not in release
assert "Muyu-${version_name}.apk" not in release

builder = Path("scripts/build-android-debug.sh").read_text(encoding="utf-8")
assert 'commit_id="${commit_id:0:7}"' in builder
assert 'commit_apk="$output_dir/Muyu-${commit_id}.apk"' in builder
assert 'cp -- "$source_apk" "$commit_apk"' in builder
assert 'assert-production-api-base-url.sh' in builder
assert 'assets/flutter_assets/kernel_blob.bin' in builder
assert 'unzip -tq "$commit_apk"' in builder

release_builder_text = release_builder.read_text(encoding="utf-8")
assert 'build apk --release' in release_builder_text
assert 'ANDROID_KEYSTORE_PATH' in release_builder_text
assert 'ANDROID_KEYSTORE_PASSWORD' in release_builder_text
assert 'ANDROID_KEY_ALIAS' in release_builder_text
assert 'ANDROID_KEY_PASSWORD' in release_builder_text
assert 'apksigner_bin' in release_builder_text
assert 'Muyu-${release_tag}.apk' in release_builder_text

gradle = Path("client/android/app/build.gradle.kts").read_text(encoding="utf-8")
assert "signingConfig = releaseSigningConfig" in gradle
assert 'signingConfigs.getByName("debug")' not in gradle
assert "Release Android builds require" in gradle
print("CI and release trigger check passed")
