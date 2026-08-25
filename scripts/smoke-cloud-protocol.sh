#!/usr/bin/env bash
set -Eeuo pipefail

# Fast health/auth/workspace/task/snapshot smoke for a disposable fake-SMS
# stack. The opt-in Python protocol test covers partner signatures and QR.
API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"
OTP_CODE="${FAKE_OTP_CODE:-${OTP_CODE_A:-000000}}"
PHONE="${PHONE_A:-+14155552671}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

command -v curl >/dev/null
command -v python3 >/dev/null

json_value() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
for part in sys.argv[2].split("."):
    value = value[int(part)] if isinstance(value, list) else value[part]
print(value)
PY
}

request() {
  local method="$1" path="$2" output="$3" token="${4:-}" body="${5:-}"
  local args=(-sS --max-time 15 -o "$output" -w '%{http_code}' -X "$method")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' -d "$body")
  curl "${args[@]}" "$API_BASE_URL$path"
}

for _ in $(seq 1 60); do
  curl -fsS --max-time 3 "$API_BASE_URL/health/ready" >/dev/null && break
  sleep 1
done
curl -fsS --max-time 3 "$API_BASE_URL/health/ready" >/dev/null

status="$(request POST /api/v1/auth/sms/send "$WORK_DIR/send.json" '' "{\"phone\":\"$PHONE\"}")"
[[ "$status" == 202 ]] || { cat "$WORK_DIR/send.json" >&2; exit 1; }
status="$(request POST /api/v1/auth/sms/verify "$WORK_DIR/session.json" '' "{\"phone\":\"$PHONE\",\"code\":\"$OTP_CODE\",\"device\":{\"public_key_der\":\"AQID\",\"label\":\"smoke\"}}")"
[[ "$status" == 201 ]] || { cat "$WORK_DIR/session.json" >&2; exit 1; }
access="$(json_value "$WORK_DIR/session.json" access_token)"

status="$(request POST /api/v1/workspaces "$WORK_DIR/workspace.json" "$access" '{"name":"Smoke workspace"}')"
[[ "$status" == 201 ]] || { cat "$WORK_DIR/workspace.json" >&2; exit 1; }
workspace_id="$(json_value "$WORK_DIR/workspace.json" id)"
status="$(request POST /api/v1/tasks "$WORK_DIR/task.json" "$access" "{\"title\":\"Smoke task\",\"description\":\"\",\"request_id\":\"$(python3 -c 'import uuid; print(uuid.uuid4())')\"}")"
[[ "$status" == 201 ]] || { cat "$WORK_DIR/task.json" >&2; exit 1; }
status="$(request GET /api/v1/workspaces/current/snapshot "$WORK_DIR/snapshot.json" "$access")"
[[ "$status" == 200 ]] || { cat "$WORK_DIR/snapshot.json" >&2; exit 1; }

echo "cloud protocol smoke passed for auth, workspace, task, and snapshot"
