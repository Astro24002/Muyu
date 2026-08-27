# Release Checklist

## Observed acceptance evidence (2026-08-27)

The following checks were run against the repository and a disposable
PostgreSQL instance. They do not constitute production deployment or real
device acceptance.

- `RUN_CLOUD_PROTOCOL=1` focused two-user task E2E: `1 passed`.
- `make backend-test` with disposable PostgreSQL: `64 passed, 3 skipped`;
  `compileall` completed successfully. One existing Starlette/httpx
  deprecation warning was emitted.
- `make client-test`: Dart format unchanged, `flutter analyze` clean, `33
  tests` passed.
- `cd web && npm ci && npm run typecheck && npm test -- --run && npm run build`:
  `7` test files and `51 tests` passed; Vite build completed.
- `make boundary-check`: passed.
- `make check-deployment`: passed for the checked-in Compose example topology.
- `API_BASE_URL=https://muyu.bkverse.space make client-build`: passed at source
  commit `2b07d27b178b339dd960e2eee2195ed1be88edfb`.
- Commit-named debug artifact:
  `client/build/app/outputs/flutter-apk/Muyu-2b07d27.apk`; SHA-256
  `0146fc682fb639a52e457d5df0b16b73ae6bf7aa0de90e3c64149dd15a7b2203`.
- APK inspection found `https://muyu.bkverse.space` in the packaged Flutter
  assets.
- Real Android device acceptance: pending because no connected device was
  available during this run.

Items below remain unchecked unless the described release evidence is produced.

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

- [x] Android debug APK: `Muyu-2b07d27.apk` for internal installation/testing;
      SHA-256 is recorded above.
- [ ] Signed Android App Bundle: `app-release.aab`, produced only by the
      protected signing workflow.
- [ ] Web static bundle: `web-release.tar.gz` containing `web/dist`.
- [ ] SHA-256 checksums for every artifact, mapped to the source commit and
      release version.
- [x] No iOS artifact is produced in this release.

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
