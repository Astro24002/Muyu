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

TASK_BODY="{\"title\":\"Phase 2 smoke task\",\"description\":\"two-user acceptance\",\"assignee_ids\":[\"$USER_A_ID\",\"$USER_B_ID\"],\"current_handler_id\":\"$USER_A_ID\",\"estimated_minutes\":30}"
status="$(request POST /api/tasks "$WORK_DIR/task.json" "$ACCESS_A" "$TASK_BODY")"
assert_status "$status" 201 'create task'
TASK_ID="$(json_value "$WORK_DIR/task.json" id)"
[[ "$(json_value "$WORK_DIR/task.json" status)" == 'TODO' ]] || { printf 'created task is not TODO\n' >&2; exit 1; }

status="$(request GET /api/tasks "$WORK_DIR/tasks-b.json" "$ACCESS_B")"
assert_status "$status" 200 'list tasks as second user'
python3 - "$WORK_DIR/tasks-b.json" "$TASK_ID" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    tasks = json.load(stream)
if not any(task["id"] == sys.argv[2] for task in tasks):
    raise SystemExit("created task is not visible to the second user")
PY

status="$(request POST "/api/tasks/$TASK_ID/start" "$WORK_DIR/started.json" "$ACCESS_A")"
assert_status "$status" 200 'start task'
[[ "$(json_value "$WORK_DIR/started.json" status)" == 'IN_PROGRESS' ]] || { printf 'started task has wrong status\n' >&2; exit 1; }

status="$(request POST "/api/tasks/$TASK_ID/transfer" "$WORK_DIR/transferred.json" "$ACCESS_A" "{\"new_handler_id\":\"$USER_B_ID\"}")"
assert_status "$status" 200 'transfer task'
[[ "$(json_value "$WORK_DIR/transferred.json" current_handler_id)" == "$USER_B_ID" ]] || { printf 'task handler was not transferred\n' >&2; exit 1; }

CHILD_BODY="{\"title\":\"Phase 2 smoke subtask\",\"description\":\"subtask acceptance\",\"assignee_ids\":[\"$USER_B_ID\"],\"current_handler_id\":\"$USER_B_ID\",\"parent_task_id\":\"$TASK_ID\"}"
status="$(request POST /api/tasks "$WORK_DIR/child.json" "$ACCESS_B" "$CHILD_BODY")"
assert_status "$status" 201 'create subtask'
CHILD_ID="$(json_value "$WORK_DIR/child.json" id)"

status="$(request GET "/api/tasks?parent_task_id=$TASK_ID" "$WORK_DIR/children.json" "$ACCESS_A")"
assert_status "$status" 200 'list subtasks'
[[ "$(json_value "$WORK_DIR/children.json" 0.id)" == "$CHILD_ID" ]] || { printf 'subtask query returned the wrong child\n' >&2; exit 1; }

status="$(request POST "/api/tasks/$TASK_ID/complete" "$WORK_DIR/completed.json" "$ACCESS_B")"
assert_status "$status" 200 'complete task'
[[ "$(json_value "$WORK_DIR/completed.json" status)" == 'DONE' ]] || { printf 'completed task has wrong status\n' >&2; exit 1; }

status="$(request GET "/api/tasks/$TASK_ID" "$WORK_DIR/task-b.json" "$ACCESS_B")"
assert_status "$status" 200 'read completed task as second user'
[[ "$(json_value "$WORK_DIR/task-b.json" current_handler_id)" == "$USER_B_ID" ]] || { printf 'second user observed the wrong handler\n' >&2; exit 1; }

status="$(request GET "/api/tasks/$TASK_ID/events" "$WORK_DIR/events.json" "$ACCESS_A")"
assert_status "$status" 200 'list task events'
python3 - "$WORK_DIR/events.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    actions = [event["action"] for event in json.load(stream)]
expected = ["TASK_CREATED", "TASK_STARTED", "TASK_HANDLER_CHANGED", "TASK_COMPLETED"]
if actions != expected:
    raise SystemExit(f"unexpected task activity sequence: {actions}")
PY

printf 'task smoke test passed for shared task, transfer, subtask, completion, and audit\n'
