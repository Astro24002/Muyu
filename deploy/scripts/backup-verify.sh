#!/usr/bin/env bash
set -Eeuo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-deploy/docker-compose.yml}"
COMPOSE_ENV_FILE="${COMPOSE_ENV_FILE:-deploy/.env.example}"
PROJECT="${COMPOSE_PROJECT_NAME:-muyu-cloud}"
NETWORK="${PROJECT}_backup"
BACKUP_VOLUME="${BACKUP_VOLUME:-muyu_cloud_backup_repo}"
VERIFY_VOLUME="${PROJECT}_backup_verify_${RANDOM}"
RESTORE_CONTAINER="${PROJECT}-backup-restore-${RANDOM}"
POSTGRES_CONTAINER="${PROJECT}-backup-check-${RANDOM}"

cleanup() {
  docker rm --force "$POSTGRES_CONTAINER" >/dev/null 2>&1 || true
  docker volume rm "$VERIFY_VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

command -v docker >/dev/null || { echo "docker is required" >&2; exit 2; }
docker compose --env-file "$COMPOSE_ENV_FILE" -f "$COMPOSE_FILE" exec -T backup \
  pgbackrest --stanza=muyu check

docker volume create "$VERIFY_VOLUME" >/dev/null
docker run --rm --name "$RESTORE_CONTAINER" --network "$NETWORK" \
  -v "$BACKUP_VOLUME:/var/lib/pgbackrest" \
  -v "$VERIFY_VOLUME:/var/lib/postgresql/data" \
  -v "$(pwd)/deploy/postgres/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf:ro" \
  postgres:16-alpine pgbackrest --stanza=muyu --pg1-path=/var/lib/postgresql/data restore

docker run -d --name "$POSTGRES_CONTAINER" --network "$NETWORK" \
  -e POSTGRES_PASSWORD=backup-check-only \
  -v "$VERIFY_VOLUME:/var/lib/postgresql/data" postgres:16-alpine \
  -c fsync=off >/dev/null
for _ in $(seq 1 30); do
  if docker exec "$POSTGRES_CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then
    docker exec "$POSTGRES_CONTAINER" psql -U postgres -d postgres -Atc \
      'select 1 from pg_catalog.pg_tables limit 1' >/dev/null
    echo "latest pgBackRest backup restored and opened successfully"
    exit 0
  fi
  sleep 1
done
echo "restored backup did not become ready" >&2
exit 1
