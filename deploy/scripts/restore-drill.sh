#!/usr/bin/env bash
set -Eeuo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-deploy/docker-compose.yml}"
PROJECT="${COMPOSE_PROJECT_NAME:-muyu-cloud}"
BACKUP_VOLUME="${BACKUP_VOLUME:-muyu_cloud_backup_repo}"
DRILL_DATABASE="${DRILL_DATABASE:-muyu_cloud_restore_drill}"
TARGET_TIME="${TARGET_TIME:?TARGET_TIME must be an ISO-8601 recovery target}"
EXPECTED_CHECKPOINT="${EXPECTED_CHECKPOINT:?EXPECTED_CHECKPOINT cursor value is required}"

case "$DRILL_DATABASE" in
  muyu|muyu_cloud|postgres|template0|template1)
    echo "refusing to target a production database name: $DRILL_DATABASE" >&2
    exit 2
    ;;
esac
[[ "$EXPECTED_CHECKPOINT" =~ ^[0-9]+$ ]] || {
  echo "EXPECTED_CHECKPOINT must be an integer" >&2
  exit 2
}

DRILL_VOLUME="${PROJECT}_restore_drill_${RANDOM}"
RESTORE_CONTAINER="${PROJECT}-restore-drill-${RANDOM}"
cleanup() {
  docker rm --force "$RESTORE_CONTAINER" >/dev/null 2>&1 || true
  docker volume rm "$DRILL_VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "$DRILL_VOLUME" >/dev/null
docker run --rm --name "$RESTORE_CONTAINER" \
  -v "$BACKUP_VOLUME:/var/lib/pgbackrest" \
  -v "$DRILL_VOLUME:/var/lib/postgresql/data" \
  -v "$(pwd)/deploy/postgres/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf:ro" \
  postgres:16-alpine pgbackrest --stanza=muyu --pg1-path=/var/lib/postgresql/data \
  --type=time --target="$TARGET_TIME" --target-action=promote restore

docker run -d --name "$RESTORE_CONTAINER" \
  -e POSTGRES_PASSWORD=restore-drill-only \
  -e POSTGRES_DB="$DRILL_DATABASE" \
  -v "$DRILL_VOLUME:/var/lib/postgresql/data" postgres:16-alpine >/dev/null
for _ in $(seq 1 60); do
  if docker exec "$RESTORE_CONTAINER" pg_isready -U postgres -d "$DRILL_DATABASE" >/dev/null 2>&1; then
    actual="$(docker exec "$RESTORE_CONTAINER" psql -U postgres -d "$DRILL_DATABASE" -Atc \
      'select coalesce(max(cursor), 0) from workspace_cursors')"
    [[ "$actual" == "$EXPECTED_CHECKPOINT" ]] || {
      echo "restore cursor checkpoint mismatch: expected $EXPECTED_CHECKPOINT, got $actual" >&2
      exit 1
    }
    echo "restore drill passed for $DRILL_DATABASE at $TARGET_TIME (cursor $actual)"
    exit 0
  fi
  sleep 1
done
echo "restore drill database did not become ready" >&2
exit 1
