#!/usr/bin/env bash
set -Eeuo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-deploy/docker-compose.yml}"
COMPOSE_ENV_FILE="${COMPOSE_ENV_FILE:-deploy/.env.example}"
CONFIG_FILE="$(mktemp)"
trap 'rm -f "$CONFIG_FILE"' EXIT

docker compose --env-file "$COMPOSE_ENV_FILE" -f "$COMPOSE_FILE" config --format json >"$CONFIG_FILE"
python3 - "$CONFIG_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)
services = document["services"]
published = {name for name, service in services.items() if service.get("ports")}
if published != {"caddy"}:
    raise SystemExit(f"only caddy may publish ports, found: {sorted(published)}")
if services["api"].get("deploy", {}).get("replicas") != 1:
    raise SystemExit("api must run exactly one replica while realtime is in-memory")
if services["db"].get("ports") or services["api"].get("ports"):
    raise SystemExit("database and api must not have host ports")
for name in services:
    if name in {"api", "db", "backup"} and "internal" not in {
        network.split("_")[-1] for network in services[name].get("networks", {})
    }:
        # Compose's rendered names are project-prefixed, so inspect the suffix.
        if name != "backup":
            raise SystemExit(f"{name} must be attached to the private internal network")
for forbidden in ("AUTH_PASSWORD", "JWT_SECRET", "P2P", "NEARBY", "ELASTICSEARCH", "REDIS_URL"):
    rendered = json.dumps(document)
    if forbidden in rendered:
        raise SystemExit(f"legacy setting is present in rendered Compose: {forbidden}")
caddy = services["caddy"]
build_args = caddy.get("build", {}).get("args", {})
if "WEB_ORIGIN" in build_args:
    raise SystemExit("caddy must not receive backend WEB_ORIGIN as a build argument")
if caddy.get("depends_on", {}).get("api", {}).get("condition") != "service_healthy":
    raise SystemExit("caddy must depend on a healthy api service")
print("deployment topology check passed")
PY
