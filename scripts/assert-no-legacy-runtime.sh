#!/usr/bin/env bash
set -Eeuo pipefail

# The cloud replacement is intentionally incompatible with the password/P2P
# runtime.  Keep this gate narrow so historical design documents can still
# mention the retired architecture without becoming executable dependencies.
for path in \
  backend/app/auth/passwords.py \
  backend/app/auth/tokens.py \
  backend/app/auth/session_repository.py \
  client/lib/auth/auth_repository.dart \
  client/lib/auth/session_controller.dart \
  client/lib/task/task_repository.dart; do
  if [[ -f "$path" ]]; then
    echo "legacy runtime path remains: $path" >&2
    exit 1
  fi
done

for path in backend/app/activity backend/app/task backend/app/user; do
  if find "$path" -type f ! -path '*/__pycache__/*' -print -quit 2>/dev/null | grep -q .; then
    echo "legacy runtime path remains: $path" >&2
    exit 1
  fi
done

if rg -n --glob '!**/__pycache__/**' \
  'from app\.(activity|task|user)(\b|\.)|app\.auth\.(passwords|tokens|session_repository)|/api/auth/(login|refresh)|/api/tasks(\b|/)|P2P|NEARBY|ELASTICSEARCH|REDIS_URL' \
  backend/app client/lib >/dev/null; then
  echo "legacy runtime reference remains" >&2
  exit 1
fi

echo "legacy runtime check passed"
