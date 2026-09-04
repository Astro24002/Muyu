#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
client_dir="$repo_root/client"
output_dir="$client_dir/build/app/outputs/flutter-apk"
flutter_bin="${FLUTTER:-flutter}"
build_env="${ANDROID_BUILD_ENV:-development}"
requested_api_base_url="${API_BASE_URL-}"
commit_id="${COMMIT_ID:-$(git -C "$repo_root" rev-parse --short HEAD)}"
commit_id="${commit_id:0:7}"

case "$build_env" in
  development|local)
    ;;
  production|release)
    "$repo_root/scripts/assert-production-api-base-url.sh" "$requested_api_base_url"
    ;;
  *)
    printf 'ANDROID_BUILD_ENV must be development, local, production, or release: %s\n' "$build_env" >&2
    exit 2
    ;;
esac

api_base_url="${requested_api_base_url:-http://localhost:8080}"

if [[ ! "$commit_id" =~ ^[0-9a-fA-F]{7}$ ]]; then
  printf 'COMMIT_ID must resolve to a 7-character commit prefix: %s\n' "$commit_id" >&2
  exit 2
fi

(
  cd "$client_dir"
  "$flutter_bin" pub get
  "$flutter_bin" build apk --debug --dart-define=API_BASE_URL="$api_base_url"
)

source_apk="$output_dir/app-debug.apk"
test -s "$source_apk"
commit_apk="$output_dir/Muyu-${commit_id}.apk"
cp -- "$source_apk" "$commit_apk"
test -s "$commit_apk"

if ! unzip -tq "$commit_apk" >/dev/null; then
  printf 'Android APK archive is invalid: %s\n' "$commit_apk" >&2
  exit 1
fi

kernel_blob="$(mktemp)"
trap 'rm -f -- "$kernel_blob"' EXIT
if ! unzip -p "$commit_apk" assets/flutter_assets/kernel_blob.bin >"$kernel_blob"; then
  printf 'Android APK is missing Flutter kernel_blob.bin: %s\n' "$commit_apk" >&2
  exit 1
fi
if ! strings "$kernel_blob" | grep -F -- "$api_base_url" >/dev/null; then
  printf 'Android APK does not contain API_BASE_URL=%s: %s\n' "$api_base_url" "$commit_apk" >&2
  exit 1
fi

printf 'Android debug APK: %s\n' "$commit_apk"
