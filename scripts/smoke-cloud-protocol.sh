#!/usr/bin/env bash
set -Eeuo pipefail

# This smoke uses the fake SMS provider and intentionally accepts OTP values
# through the environment. It is never a production health check.
API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"
OTP_CODE_A="${OTP_CODE_A:?OTP_CODE_A is required for the fake-provider smoke}"
OTP_CODE_B="${OTP_CODE_B:?OTP_CODE_B is required for the fake-provider smoke}"
PHONE_A="${PHONE_A:-+15550000001}"
PHONE_B="${PHONE_B:-+15550000002}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

command -v curl >/dev/null || { echo "curl is required" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 2; }

json_value() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
for part in sys.argv[2].split("."):
    value = value[int(part)] if isinstance(value, list) else value[part]
print(json.dumps(value) if isinstance(value, (dict, list)) else value)
PY
}

request() {
  local method="$1" path="$2" output="$3" token="${4:-}" body="${5:-}"
  local args=(-sS --max-time 15 -o "$output" -w '%{http_code}' -X "$method")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' -d "$body")
  curl "${args[@]}" "$API_BASE_URL$path"
}

assert_status() {
  [[ "$1" == "$2" ]] || { echo "$3 failed with HTTP $1 (expected $2)" >&2; exit 1; }
}

for _ in $(seq 1 60); do
  if curl -fsS --max-time 3 "$API_BASE_URL/health/ready" >/dev/null; then
    break
  fi
  sleep 1
done
curl -fsS --max-time 3 "$API_BASE_URL/health/ready" >/dev/null

request_id_a="$(python3 -c 'import uuid; print(uuid.uuid4())')"
status="$(request POST /api/v1/auth/sms/send "$WORK_DIR/send-a.json" '' \
  "{\"phone\":\"$PHONE_A\",\"request_id\":\"$request_id_a\"}")"
assert_status "$status" 202 'send A OTP'
status="$(request POST /api/v1/auth/sms/verify "$WORK_DIR/session-a.json" '' \
  "{\"phone\":\"$PHONE_A\",\"code\":\"$OTP_CODE_A\",\"request_id\":\"$(python3 -c 'import uuid; print(uuid.uuid4())')\"}")"
assert_status "$status" 201 'verify A OTP'
ACCESS_A="$(json_value "$WORK_DIR/session-a.json" access_token)"

status="$(request POST /api/v1/workspaces "$WORK_DIR/workspace.json" "$ACCESS_A" \
  "{\"name\":\"Protocol smoke workspace\",\"request_id\":\"$(python3 -c 'import uuid; print(uuid.uuid4())')\"}")"
assert_status "$status" 201 'create workspace'
WORKSPACE_ID="$(json_value "$WORK_DIR/workspace.json" id)"
status="$(request POST /api/v1/workspaces/$WORKSPACE_ID/invites "$WORK_DIR/invite.json" "$ACCESS_A" \
  "{\"phone\":\"$PHONE_B\",\"request_id\":\"$(python3 -c 'import uuid; print(uuid.uuid4())')\"}")"
assert_status "$status" 201 'invite B'

request_id_b="$(python3 -c 'import uuid; print(uuid.uuid4())')"
status="$(request POST /api/v1/auth/sms/send "$WORK_DIR/send-b.json" '' \
  "{\"phone\":\"$PHONE_B\",\"request_id\":\"$request_id_b\"}")"
assert_status "$status" 202 'send B OTP'
status="$(request POST /api/v1/auth/sms/verify "$WORK_DIR/session-b.json" '' \
  "{\"phone\":\"$PHONE_B\",\"code\":\"$OTP_CODE_B\",\"request_id\":\"$(python3 -c 'import uuid; print(uuid.uuid4())')\"}")"
assert_status "$status" 201 'verify B OTP'
ACCESS_B="$(json_value "$WORK_DIR/session-b.json" access_token)"

status="$(request GET /api/v1/workspaces/current/snapshot "$WORK_DIR/snapshot.json" "$ACCESS_B")"
assert_status "$status" 200 'read workspace snapshot'
status="$(request GET "/api/v1/workspaces/current/changes?after_cursor=0" "$WORK_DIR/changes.json" "$ACCESS_B")"
assert_status "$status" 200 'read workspace changes'

echo "cloud protocol smoke passed for registration, workspace invitation, and sync reads"
