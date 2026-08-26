# Release Checklist

## Before release

- [ ] Confirm the source commit and application version.
- [ ] Confirm PostgreSQL migration head is reviewed and tested on a new empty
      database.
- [ ] Render `deploy/docker-compose.yml` with the production environment and
      run `make check-deployment`.
- [ ] Confirm only Caddy publishes ports, API replicas are `1`, and the legacy
      volume is not referenced.
- [ ] Confirm Guoyangyun AppCode, SMS sign/template identifiers,
      cookie-secure mode, allowed origin, backup repository credentials, and
      backup encryption key are injected from the secret store.
- [ ] Run `make verify` and inspect the generated Android/Web artifacts.
- [ ] Take and verify a fresh encrypted full backup.

## Deliverables

- [ ] Android debug APK: `app-debug.apk` for internal installation/testing.
- [ ] Signed Android App Bundle: `app-release.aab`, produced only by the
      protected signing workflow.
- [ ] Web static bundle: `web-release.tar.gz` containing `web/dist`.
- [ ] SHA-256 checksums for every artifact, mapped to the source commit and
      release version.
- [ ] No iOS artifact is produced in this release.

## After release

- [ ] Verify `/health/live` and `/health/ready` through the public TLS origin.
- [ ] Verify the first Android user can create a Workspace and then complete Web QR
      login at the public HTTPS origin.
- [ ] Register the first Android account and verify the two-person workspace
      approval path.
- [ ] Verify Web QR login, the 18-hour maximum cookie lifetime, and Android
      Web-session revocation.
- [ ] Record migration head, artifact checksums, backup verification time, and
      the operator in the release log.
