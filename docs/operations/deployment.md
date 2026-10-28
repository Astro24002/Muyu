# Cloud Deployment

This release deploys a new, empty PostgreSQL-backed workspace. It does not
reuse the legacy database volume and it does not migrate legacy passwords,
tokens, tasks, or P2P history.

## Topology

`Caddy` is the only public service. It terminates TLS, serves the Vite static
files from `web/dist`, proxies `/api/*` and `/api/v1/realtime` to FastAPI, and
adds security headers. FastAPI exposes JSON/WebSocket APIs only; it does not
render browser pages. FastAPI and PostgreSQL are reachable only on Compose's
private networks. FastAPI runs as one instance because realtime subscriptions
are in-memory in this release.

## SSH access

The current production host accepts SSH on TCP port `27001`; port `22` is not
open. Use the configured deployment identity and the pinned host key with
strict host-key checking. Do not bypass host-key verification when diagnosing
or deploying.

The new named volumes are `muyu_cloud_pgdata`, `muyu_cloud_backup_repo`,
`muyu_cloud_caddy_data`, and `muyu_cloud_caddy_config`. Do not attach a legacy
volume to this project.

## First deployment

1. Create a private environment file from
   `deploy/.env.production.example` for `muyu.bkverse.space` (or from
   `deploy/.env.example` for a different domain). Set a PostgreSQL password,
   a random `OTP_PEPPER` of at least 32 characters, the Guoyangyun AppCode,
   SMS sign/template identifiers, and backup credentials/key.
2. Set `OTP_PROVIDER=production`, `WEB_COOKIE_SECURE=true`, and an exact
   `ALLOWED_ORIGINS`/`ALLOWED_HOSTS` value for the public origin.
3. Point DNS A/AAAA records at the host and allow TCP 80/443. Caddy obtains
   and renews the certificate automatically after DNS resolves.
4. Render and inspect the deployment before starting it. The stack includes a small
   `web-session-cleanup` worker; it uses the same database and runs once per day:

   ```sh
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml config
   make check-deployment COMPOSE_ENV_FILE=deploy/.env
   ```

5. Start the new project and check both liveness and database readiness:

   ```sh
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build
   curl --fail https://muyu.bkverse.space/health/live
   curl --fail https://muyu.bkverse.space/health/ready
   ```

6. Apply the Alembic head if the API image is not configured to run migrations
   during startup:

   ```sh
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml \
     exec api alembic upgrade head
   ```

## External PostgreSQL deployment

When PostgreSQL is provided by the host's 1Panel network, use the external
override instead of the local `db` service. The override connects API and the
cleanup worker to `1Panel-postgresql-lJTO` and passes the password through
`PGPASSWORD`; the URI intentionally contains no password, so passwords with
`@` remain valid.

Run these commands from the repository root. Do not pass `--project-directory`
pointing at the root: the external override's `./Caddyfile.server` mount must
resolve relative to `deploy/`. A wrong base directory can leave Caddy unable
to start even if the API is healthy.

```sh
docker compose --env-file deploy/.env \
  -f deploy/docker-compose.yml \
  -f deploy/docker-compose.external-db.yml config --quiet

docker compose --env-file deploy/.env \
  -f deploy/docker-compose.yml \
  -f deploy/docker-compose.external-db.yml \
  run --rm --no-deps api alembic upgrade head

docker compose --env-file deploy/.env \
  -f deploy/docker-compose.yml \
  -f deploy/docker-compose.external-db.yml \
  up -d --no-build api web-session-cleanup caddy
```

Before advancing a live Alembic head, verify the current revision, create a
restricted custom-format database backup, and restore it in an isolated
PostgreSQL instance. Preserve the prior API/Caddy images under distinct tags.
Downgrading `0016_life_domains` drops ledger, habit and anniversary records;
after the first live write, use a reviewed forward fix or a verified restore
plan instead of assuming a schema-only downgrade is lossless.

Never put SMS tokens, database passwords, backup keys, or Android signing
material in the repository, Web bundle, APK build arguments, or logs.

## 2026-10-27 due-soon API update

The rolling 14-day Home entry adds response fields and a read-only pagination
entry. It requires no schema migration; production remains at
`0018_task_invitations`. The deployed image was built from local HEAD
`fe65033` plus the uncommitted Home implementation, tagged
`muyu-cloud-api:due-soon-20261027`, and transferred as an image archive.
Its image ID is
`sha256:70660deba5f8d708125eca15f50f3fd0fe50d2d2a8c135433ee26837de08570f`.
The remote worktree contains existing changes and was left intact.

The previous image is retained as `muyu-cloud-api:pre-due-soon-20261027`
(`sha256:839571e33ddd619d4e3e7411acfcb887f45f7b0696d8988224f1548b0b8a7872`).
The API was recreated with the existing external-database override. For an
authorized rollback, keep the database and volumes unchanged, retag the
previous image as `muyu-cloud-api:latest`, and run from `deploy/`:

```sh
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.external-db.yml \
  up -d --no-build api
```

After the update, API container health and public live/ready checks passed;
the unauthenticated `due_soon` entry returned `401 authentication_required`.
The running image exposes the new entry and response field. No production
business writes, authenticated-user smoke test, or Web deployment were
performed in this update.

## Routine operations

Use `docker compose ps`, `/health/live`, and `/health/ready` for service health.
Inspect Caddy/API logs after redaction checks; authorization headers, cookies,
OTP values, QR proofs, device signatures, and raw database errors must not
appear in logs. Deploy migration changes before application changes and keep
the one-instance API setting until realtime state has an external broker.

For rollback, leave this project's volumes intact and start the previous stack
with its original project name and volumes. Do not point either stack at the
other stack's database volume.
