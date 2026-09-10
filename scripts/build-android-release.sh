#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
client_dir="$repo_root/client"
output_dir="$client_dir/build/app/outputs/flutter-apk"
flutter_bin="${FLUTTER:-flutter}"
api_base_url="${API_BASE_URL-}"
release_tag="${RELEASE_TAG-}"
keystore_path="${ANDROID_KEYSTORE_PATH-}"
keystore_password="${ANDROID_KEYSTORE_PASSWORD-}"
key_alias="${ANDROID_KEY_ALIAS-}"
key_password="${ANDROID_KEY_PASSWORD-}"

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    printf '%s is required for a signed Android release build.\n' "$name" >&2
    exit 2
  fi
}

require_value API_BASE_URL "$api_base_url"
require_value RELEASE_TAG "$release_tag"
require_value ANDROID_KEYSTORE_PATH "$keystore_path"
require_value ANDROID_KEYSTORE_PASSWORD "$keystore_password"
require_value ANDROID_KEY_ALIAS "$key_alias"
require_value ANDROID_KEY_PASSWORD "$key_password"

if [[ ! "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'RELEASE_TAG must use the vX.Y.Z format: %s\n' "$release_tag" >&2
  exit 2
fi

if [[ ! -s "$keystore_path" ]]; then
  printf 'ANDROID_KEYSTORE_PATH must point to a non-empty keystore: %s\n' "$keystore_path" >&2
  exit 2
fi

"$repo_root/scripts/assert-production-api-base-url.sh" "$api_base_url"

# Validate the alias before Gradle starts. The password is never printed.
keytool -list \
  -keystore "$keystore_path" \
  -alias "$key_alias" \
  -storepass "$keystore_password" \
  >/dev/null

(
  cd "$client_dir"
  "$flutter_bin" pub get
  "$flutter_bin" build apk --release --dart-define=API_BASE_URL="$api_base_url"
)

source_apk="$output_dir/app-release.apk"
test -s "$source_apk"
release_apk="$output_dir/Muyu-${release_tag}.apk"
cp -- "$source_apk" "$release_apk"
test -s "$release_apk"

if ! unzip -tq "$release_apk" >/dev/null; then
  printf 'Android release APK archive is invalid: %s\n' "$release_apk" >&2
  exit 1
fi

apksigner_bin="${APKSIGNER-}"
if [[ -z "$apksigner_bin" ]]; then
  apksigner_bin="$(command -v apksigner || true)"
fi
if [[ -z "$apksigner_bin" && -n "${ANDROID_SDK_ROOT-}" ]]; then
  apksigner_bin="$(find "$ANDROID_SDK_ROOT/build-tools" -type f -name apksigner 2>/dev/null | sort -V | tail -n 1 || true)"
fi
if [[ -z "$apksigner_bin" && -n "${ANDROID_HOME-}" ]]; then
  apksigner_bin="$(find "$ANDROID_HOME/build-tools" -type f -name apksigner 2>/dev/null | sort -V | tail -n 1 || true)"
fi
if [[ -z "$apksigner_bin" || ! -x "$apksigner_bin" ]]; then
  printf 'apksigner is required to verify the signed Android release APK.\n' >&2
  exit 1
fi
"$apksigner_bin" verify --verbose --print-certs "$release_apk" >/dev/null

app_binary="$(mktemp)"
trap 'rm -f -- "$app_binary"' EXIT
if ! unzip -p "$release_apk" 'lib/*/libapp.so' >"$app_binary" || [[ ! -s "$app_binary" ]]; then
  printf 'Android release APK is missing Flutter libapp.so: %s\n' "$release_apk" >&2
  exit 1
fi
if ! strings "$app_binary" | grep -F -- "$api_base_url" >/dev/null; then
  printf 'Android release APK does not contain API_BASE_URL=%s: %s\n' "$api_base_url" "$release_apk" >&2
  exit 1
fi

printf 'Android signed release APK: %s\n' "$release_apk"
