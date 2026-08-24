# Cloud Deployment

This release deploys a new, empty PostgreSQL-backed workspace. It does not
reuse the legacy database volume and it does not migrate legacy passwords,
tokens, tasks, or P2P history.

## Topology

`Caddy` is the only public service. It terminates TLS, serves the Flutter Web
bundle, proxies `/api/*` and `/api/v1/realtime` to FastAPI, and adds security
headers. FastAPI and PostgreSQL are reachable only on Compose's private
networks. FastAPI runs as one instance because realtime subscriptions are
in-memory in this release.

The new named volumes are `muyu_cloud_pgdata`, `muyu_cloud_backup_repo`,
`muyu_cloud_caddy_data`, and `muyu_cloud_caddy_config`. Do not attach a legacy
volume to this project.

## First deployment

1. Create a private environment file from `deploy/.env.example`. Set a real
   domain, a PostgreSQL password, a random `OTP_PEPPER` of at least 32
   characters, production SMS credentials, and backup credentials/key.
2. Set `OTP_PROVIDER=production`, `WEB_COOKIE_SECURE=true`, and an exact
   `ALLOWED_ORIGINS`/`ALLOWED_HOSTS` value for the public origin.
3. Point DNS A/AAAA records at the host and allow TCP 80/443. Caddy obtains
   and renews the certificate automatically after DNS resolves.
4. Render and inspect the deployment before starting it:

   ```sh
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml config
   make check-deployment COMPOSE_ENV_FILE=deploy/.env
   ```

5. Start the new project and check both liveness and database readiness:

   ```sh
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build
   curl --fail https://example.com/health/live
   curl --fail https://example.com/health/ready
   ```

6. Apply the Alembic head if the API image is not configured to run migrations
   during startup:

   ```sh
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml \
     exec api alembic upgrade head
   ```

Never put SMS tokens, database passwords, backup keys, or Android signing
material in the repository, Web bundle, APK build arguments, or logs.

## Routine operations

Use `docker compose ps`, `/health/live`, and `/health/ready` for service health.
Inspect Caddy/API logs after redaction checks; authorization headers, cookies,
OTP values, QR proofs, device signatures, and raw database errors must not
appear in logs. Deploy migration changes before application changes and keep
the one-instance API setting until realtime state has an external broker.

For rollback, leave this project's volumes intact and start the previous stack
with its original project name and volumes. Do not point either stack at the
other stack's database volume.
