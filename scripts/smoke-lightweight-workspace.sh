#!/usr/bin/env bash
set -Eeuo pipefail
API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"
AUTH_PASSWORD="${AUTH_PASSWORD:-}"
response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT
curl --fail --silent --show-error "$API_BASE_URL/health/ready" -o "$response_file"
status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' "$API_BASE_URL/api/v1/workspaces/current/snapshot")"
printf 'http_status=%s\n' "$status"
if command -v jq >/dev/null 2>&1; then
  jq -r '"cursor=" + ((.cursor // "unknown")|tostring), "tasks=" + ((.tasks // [])|length|tostring), "status=" + (((.tasks // [])[0].status // "none")|tostring)' "$response_file" 2>/dev/null || true
fi
unset AUTH_PASSWORD
