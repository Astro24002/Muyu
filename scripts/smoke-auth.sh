#!/usr/bin/env bash

set -Eeuo pipefail

API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"
AUTH_PASSWORD="${AUTH_PASSWORD:-}"
USER_A_PHONE="${USER_A_PHONE:-15028180169}"
USER_B_PHONE="${USER_B_PHONE:-15068128726}"

if [[ -z "$AUTH_PASSWORD" ]]; then
  printf 'AUTH_PASSWORD is required\n' >&2
  exit 2
fi
command -v curl >/dev/null || { printf 'curl is required\n' >&2; exit 2; }
command -v python3 >/dev/null || { printf 'python3 is required\n' >&2; exit 2; }

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

json_value() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
for part in sys.argv[2].split("."):
    value = value[part]
if isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=True, separators=(",", ":")))
else:
    print(value)
PY
}

assert_status() {
  local actual="$1"
  local expected="$2"
  local operation="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf '%s failed with HTTP %s (expected %s)\n' "$operation" "$actual" "$expected" >&2
    exit 1
  fi
}

wait_for_api() {
  local attempt
  for attempt in $(seq 1 60); do
    if curl -fsS --max-time 3 "$API_BASE_URL/healthz" >/dev/null; then
      return
    fi
    sleep 1
  done
  printf 'API did not become healthy at %s\n' "$API_BASE_URL" >&2
  exit 1
}

login() {
  local phone="$1"
  local label="$2"
  local response="$WORK_DIR/${label}-login.json"
  local status
  status="$(curl -sS --max-time 10 -o "$response" -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -d "{\"phone\":\"$phone\",\"password\":\"$AUTH_PASSWORD\"}" \
    "$API_BASE_URL/api/auth/login")"
  assert_status "$status" 200 "login $label"
  [[ -n "$(json_value "$response" access_token)" ]] || { printf 'login %s returned no access token\n' "$label" >&2; exit 1; }
  [[ -n "$(json_value "$response" refresh_token)" ]] || { printf 'login %s returned no refresh token\n' "$label" >&2; exit 1; }
  [[ "$(json_value "$response" user.phone)" == "$phone" ]] || { printf 'login %s returned the wrong user\n' "$label" >&2; exit 1; }
}

wait_for_api
login "$USER_A_PHONE" user-a
login "$USER_B_PHONE" user-b

ACCESS_A="$(json_value "$WORK_DIR/user-a-login.json" access_token)"
REFRESH_A="$(json_value "$WORK_DIR/user-a-login.json" refresh_token)"
ACCESS_B="$(json_value "$WORK_DIR/user-b-login.json" access_token)"
REFRESH_B="$(json_value "$WORK_DIR/user-b-login.json" refresh_token)"

status="$(curl -sS --max-time 10 -o "$WORK_DIR/me.json" -w '%{http_code}' \
  -H "Authorization: Bearer $ACCESS_A" "$API_BASE_URL/api/me")"
assert_status "$status" 200 'current profile'

status="$(curl -sS --max-time 10 -o "$WORK_DIR/profile.json" -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $ACCESS_A" -H 'Content-Type: application/json' \
  -d '{"nickname":"Muyu Smoke User","role":"smoke"}' "$API_BASE_URL/api/me")"
assert_status "$status" 200 'profile update'
[[ "$(json_value "$WORK_DIR/profile.json" nickname)" == 'Muyu Smoke User' ]] || { printf 'profile update did not persist nickname\n' >&2; exit 1; }

status="$(curl -sS --max-time 10 -o "$WORK_DIR/users.json" -w '%{http_code}' \
  -H "Authorization: Bearer $ACCESS_B" "$API_BASE_URL/api/users")"
assert_status "$status" 200 'users list'
[[ "$(python3 - "$WORK_DIR/users.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    print(len(json.load(stream)))
PY
)" == 2 ]] || { printf 'users list did not contain exactly two users\n' >&2; exit 1; }

status="$(curl -sS --max-time 10 -o "$WORK_DIR/refresh.json" -w '%{http_code}' \
  -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$REFRESH_A\"}" \
  "$API_BASE_URL/api/auth/refresh")"
assert_status "$status" 200 'refresh rotation'
REFRESH_REPLACEMENT="$(json_value "$WORK_DIR/refresh.json" refresh_token)"
[[ "$REFRESH_REPLACEMENT" != "$REFRESH_A" ]] || { printf 'refresh token was not rotated\n' >&2; exit 1; }

status="$(curl -sS --max-time 10 -o "$WORK_DIR/old-refresh.json" -w '%{http_code}' \
  -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$REFRESH_A\"}" \
  "$API_BASE_URL/api/auth/refresh")"
assert_status "$status" 401 'revoked old refresh token'

status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' \
  -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$REFRESH_REPLACEMENT\"}" \
  "$API_BASE_URL/api/auth/logout")"
assert_status "$status" 204 'logout'

status="$(curl -sS --max-time 10 -o "$WORK_DIR/revoked-refresh.json" -w '%{http_code}' \
  -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$REFRESH_REPLACEMENT\"}" \
  "$API_BASE_URL/api/auth/refresh")"
assert_status "$status" 401 'revoked refresh token'

status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' \
  -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$REFRESH_B\"}" \
  "$API_BASE_URL/api/auth/logout")"
assert_status "$status" 204 'second user logout'

printf 'authentication smoke test passed for both fixed users\n'
