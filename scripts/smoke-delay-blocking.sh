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
    value = value[int(part)] if isinstance(value, list) else value[part]
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

request() {
  local method="$1"
  local path="$2"
  local output="$3"
  local token="${4:-}"
  local body="${5:-}"
  local args=(-sS --max-time 10 -o "$output" -w '%{http_code}' -X "$method")
  if [[ -n "$token" ]]; then
    args+=(-H "Authorization: Bearer $token")
  fi
  if [[ -n "$body" ]]; then
    args+=(-H 'Content-Type: application/json' -d "$body")
  fi
  curl "${args[@]}" "$API_BASE_URL$path"
}

login() {
  local phone="$1"
  local label="$2"
  local output="$WORK_DIR/$label.json"
  local status
  status="$(request POST /api/auth/login "$output" '' "{\"phone\":\"$phone\",\"password\":\"$AUTH_PASSWORD\"}")"
  assert_status "$status" 200 "login $label"
}

for _attempt in $(seq 1 60); do
  if curl -fsS --max-time 3 "$API_BASE_URL/healthz" >/dev/null; then
    break
  fi
  sleep 1
done
curl -fsS --max-time 3 "$API_BASE_URL/healthz" >/dev/null || {
  printf 'API did not become healthy at %s\n' "$API_BASE_URL" >&2
  exit 1
}

login "$USER_A_PHONE" user-a
login "$USER_B_PHONE" user-b
ACCESS_A="$(json_value "$WORK_DIR/user-a.json" access_token)"
ACCESS_B="$(json_value "$WORK_DIR/user-b.json" access_token)"
USER_A_ID="$(json_value "$WORK_DIR/user-a.json" user.id)"
USER_B_ID="$(json_value "$WORK_DIR/user-b.json" user.id)"

read -r ORIGINAL_DUE FIRST_DUE SECOND_DUE THIRD_DUE <<<"$(python3 - <<'PY'
from datetime import datetime, timedelta, timezone

base = datetime.now(timezone.utc).replace(second=0, microsecond=0) + timedelta(days=1)
values = [base + timedelta(days=offset) for offset in range(4)]
print(" ".join(value.isoformat().replace("+00:00", "Z") for value in values))
PY
)"

TASK_BODY="{\"title\":\"Phase 3 delay blocking smoke\",\"description\":\"two-user delay and blocking acceptance\",\"assignee_ids\":[\"$USER_A_ID\",\"$USER_B_ID\"],\"current_handler_id\":\"$USER_A_ID\",\"due_at\":\"$ORIGINAL_DUE\"}"
status="$(request POST /api/tasks "$WORK_DIR/task.json" "$ACCESS_A" "$TASK_BODY")"
assert_status "$status" 201 'create task with due date'
TASK_ID="$(json_value "$WORK_DIR/task.json" id)"
[[ "$(json_value "$WORK_DIR/task.json" status)" == 'TODO' ]] || {
  printf 'created task is not TODO\n' >&2
  exit 1
}
[[ "$(json_value "$WORK_DIR/task.json" delay_count)" == '0' ]] || {
  printf 'created task has unexpected delay count\n' >&2
  exit 1
}

status="$(request POST "/api/tasks/$TASK_ID/delay" "$WORK_DIR/delay-1.json" "$ACCESS_A" "{\"new_due_at\":\"$FIRST_DUE\",\"reason\":\"NO_TIME\"}")"
assert_status "$status" 200 'first delay'
status="$(request POST "/api/tasks/$TASK_ID/delay" "$WORK_DIR/delay-2.json" "$ACCESS_B" "{\"new_due_at\":\"$SECOND_DUE\",\"reason\":\"OTHER\",\"note\":\"需要重新协调共同时间\"}")"
assert_status "$status" 200 'second delay'
status="$(request POST "/api/tasks/$TASK_ID/delay" "$WORK_DIR/delay-3.json" "$ACCESS_A" "{\"new_due_at\":\"$THIRD_DUE\",\"reason\":\"WAITING_PARTNER\"}")"
assert_status "$status" 200 'third delay'
[[ "$(json_value "$WORK_DIR/delay-3.json" delay_count)" == '3' ]] || {
  printf 'three delays were not counted\n' >&2
  exit 1
}
[[ "$(json_value "$WORK_DIR/delay-3.json" total_delay_minutes)" == '4320' ]] || {
  printf 'delay aggregate is not 4320 minutes\n' >&2
  exit 1
}

status="$(request GET "/api/tasks/$TASK_ID/delays" "$WORK_DIR/delays.json" "$ACCESS_B")"
assert_status "$status" 200 'list delay history as second user'
python3 - "$WORK_DIR/delays.json" "$ORIGINAL_DUE" "$FIRST_DUE" "$SECOND_DUE" "$THIRD_DUE" <<'PY'
import json
import sys
from datetime import datetime

records = json.load(open(sys.argv[1], encoding="utf-8"))
if len(records) != 3:
    raise SystemExit(f"expected three delay records, got {len(records)}")
expected_reasons = ["NO_TIME", "OTHER", "WAITING_PARTNER"]
if [record["reason"] for record in records] != expected_reasons:
    raise SystemExit(f"unexpected delay reasons: {[record['reason'] for record in records]}")
if records[1]["note"] != "需要重新协调共同时间":
    raise SystemExit("OTHER delay note was not retained")
expected_dates = sys.argv[2:]
for index, (record, expected) in enumerate(zip(records, expected_dates)):
    actual = datetime.fromisoformat(record["original_due_at"].replace("Z", "+00:00"))
    target = datetime.fromisoformat(expected.replace("Z", "+00:00"))
    if actual != target:
        raise SystemExit(f"record {index + 1} has wrong original due date")
    if record["delay_duration_minutes"] != 1440:
        raise SystemExit(f"record {index + 1} has wrong duration")
PY

BLOCK_BODY="{\"blocked_reason\":\"等待确认共同行程\",\"resume_handler_id\":\"$USER_B_ID\",\"waiting_for_user_id\":\"$USER_A_ID\"}"
status="$(request POST "/api/tasks/$TASK_ID/block" "$WORK_DIR/blocked.json" "$ACCESS_A" "$BLOCK_BODY")"
assert_status "$status" 200 'block task'
[[ "$(json_value "$WORK_DIR/blocked.json" status)" == 'WAITING' ]] || {
  printf 'blocked task has wrong status\n' >&2
  exit 1
}
[[ "$(json_value "$WORK_DIR/blocked.json" current_handler_id)" == "$USER_A_ID" ]] || {
  printf 'blocking changed the current handler unexpectedly\n' >&2
  exit 1
}
[[ "$(json_value "$WORK_DIR/blocked.json" resume_handler_id)" == "$USER_B_ID" ]] || {
  printf 'blocking did not retain the resume handler\n' >&2
  exit 1
}

status="$(request GET "/api/tasks/$TASK_ID" "$WORK_DIR/blocked-b.json" "$ACCESS_B")"
assert_status "$status" 200 'read blocked task as second user'
[[ "$(json_value "$WORK_DIR/blocked-b.json" blocked_reason)" == '等待确认共同行程' ]] || {
  printf 'second user did not observe the blocking reason\n' >&2
  exit 1
}
[[ "$(json_value "$WORK_DIR/blocked-b.json" delay_count)" == '3' ]] || {
  printf 'second user observed the wrong delay count\n' >&2
  exit 1
}

status="$(request POST "/api/tasks/$TASK_ID/unblock" "$WORK_DIR/unblocked.json" "$ACCESS_B")"
assert_status "$status" 200 'unblock task'
[[ "$(json_value "$WORK_DIR/unblocked.json" status)" == 'IN_PROGRESS' ]] || {
  printf 'unblocked task has wrong status\n' >&2
  exit 1
}
[[ "$(json_value "$WORK_DIR/unblocked.json" current_handler_id)" == "$USER_B_ID" ]] || {
  printf 'unblock did not restore the resume handler\n' >&2
  exit 1
}
[[ "$(json_value "$WORK_DIR/unblocked.json" blocked_reason)" == 'None' ]] || {
  printf 'unblock did not clear blocking metadata\n' >&2
  exit 1
}

status="$(request GET "/api/tasks/$TASK_ID/events" "$WORK_DIR/events.json" "$ACCESS_A")"
assert_status "$status" 200 'list delay and blocking events'
python3 - "$WORK_DIR/events.json" <<'PY'
import json
import sys

events = json.load(open(sys.argv[1], encoding="utf-8"))
actions = [event["action"] for event in events]
expected = [
    "TASK_CREATED",
    "TASK_DELAYED",
    "TASK_DELAYED",
    "TASK_DELAYED",
    "TASK_BLOCKED",
    "TASK_UNBLOCKED",
]
if actions != expected:
    raise SystemExit(f"unexpected delay/blocking activity sequence: {actions}")
PY

printf 'delay/blocking smoke test passed for three delays, shared WAITING state, handler restore, and audit\n'
