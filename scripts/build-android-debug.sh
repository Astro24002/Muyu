#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
client_dir="$repo_root/client"
output_dir="$client_dir/build/app/outputs/flutter-apk"
flutter_bin="${FLUTTER:-flutter}"
api_base_url="${API_BASE_URL:-http://localhost:8080}"
commit_id="${COMMIT_ID:-$(git -C "$repo_root" rev-parse --short HEAD)}"
commit_id="${commit_id:0:7}"

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
test -f "$source_apk"
commit_apk="$output_dir/Muyu-${commit_id}.apk"
cp -- "$source_apk" "$commit_apk"

printf 'Android debug APK: %s\n' "$commit_apk"
