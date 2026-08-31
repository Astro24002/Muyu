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
  commit `5e1fa66`.
- Commit-named debug artifact:
  `client/build/app/outputs/flutter-apk/Muyu-5e1fa66.apk`; SHA-256
  `cb9b2d07901442a3bca746aa08d4aa44827a33d8f57894989fa6ea992941c5c4`.
- APK inspection found `https://muyu.bkverse.space` in the packaged Flutter
  assets.
- Real Android device acceptance: pending because no connected device was
  available during this run.

Items below remain unchecked unless the described release evidence is produced.

## 0.1.2 pre-release evidence (2026-08-28)

- [x] Backend full suite: `124 passed, 3 skipped` in disposable PostgreSQL;
      approval target: `40 passed`; two-person smoke: `1 passed`.
- [x] Flutter: format unchanged, `flutter analyze` clean, `61 tests` passed.
- [x] Web: `10` test files / `65 tests` passed, typecheck and Vite build passed.
- [x] Client boundary, legacy-runtime, CI-trigger and Compose topology checks passed.
- [x] Version set to `0.1.2+1`; release APK filename reserved as
      `Muyu-v0.1.2.apk`.
- [ ] Release APK build, checksum, GitHub tag/release and successful Action run.

## 0.1.2 final verification (2026-08-31)

- [x] Final source commit before release: `4180ce82ead7df2aef674f6bd9bcf242aa8645d4`.
- [x] Android release build on that commit: `client/build/app/outputs/flutter-apk/Muyu-v0.1.2.apk`;
      `aapt` reports package `com.muyu.app`, `versionName=0.1.2`, `versionCode=1`.
- [x] Release APK SHA-256:
      `ae119c802e0d40f51b639eb5ac1f084a51d3d2c3f24e231705117128fca51f1e`.
- [x] APK contains the configured origin `https://muyu.bkverse.space`.
- [x] Final backend full suite: `124 passed, 3 skipped`; approval suite: `40 passed`;
      two-person smoke: `1 passed` with `APPROVED` and final cursor `14`.
- [x] Final Flutter: format unchanged, `flutter analyze` clean, `61 tests` passed.
- [x] Final Web: `10` test files / `65 tests` passed, typecheck and Vite build passed.
- [ ] GitHub tag, Release asset and successful GitHub Actions run; complete after publication.

The Tsinghua PyPI mirror returned HTTP 403 during one fresh dependency-install attempt.
The same focused tests were then run in the prepared Python 3.12 dependency image
`muyu-backend-test-deps:20260828`; this is an environment limitation, not a test failure.

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

- [x] Android debug APK: `Muyu-5e1fa66.apk` for internal installation/testing;
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
