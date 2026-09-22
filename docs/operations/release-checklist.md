# Release Checklist

## Observed acceptance evidence (2026-08-27)

The following checks were run against the repository and a disposable
PostgreSQL instance. They do not constitute production deployment or real
device acceptance.

## 2026-09-22 Runtime Update (Not Release)

- [x] Production backup `/root/backups/muyu-pre-0018-20260922T024646Z.dump`
      was created before migration, retained with mode `600`, and verified by
      `pg_restore --list`; SHA-256 is recorded in `docs/05-development-status.md`.
- [x] Production Alembic head advanced from `0016_life_domains` to
      `0018_task_invitations`; existing production data was retained.
- [x] API, Web-session-cleanup and Caddy were replaced with the staged images;
      `/health/live` and `/health/ready` returned HTTP 200, and unauthenticated
      life-domain and invitation requests returned the expected authentication
      boundary.
- [ ] Rollback/restore drill, real-account writes, two-person E2E, device
      acceptance and signed APK/AAB release remain pending.

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
- [x] Release APK build, checksum, GitHub tag/release and successful Action run.

The historical `0.1.2` evidence above predates the stable APK signing guard.
For new releases, `Muyu-vX.Y.Z.apk` must be produced by the signed release
builder and must not be copied from `app-debug.apk`.

## 0.1.2 final verification (2026-08-31)

- [x] Final runtime source commit before release: `89bd456ce655b995af5a8a484950580667c6e761`.
- [x] Android release build from the final runtime source: `client/build/app/outputs/flutter-apk/Muyu-v0.1.2.apk`;
      `aapt` reports package `com.muyu.app`, `versionName=0.1.2`, `versionCode=1`.
- [x] Release APK SHA-256:
      `ae119c802e0d40f51b639eb5ac1f084a51d3d2c3f24e231705117128fca51f1e`.
- [x] APK contains the configured origin `https://muyu.bkverse.space`.
- [x] Final backend full suite: `124 passed, 3 skipped`; approval suite: `40 passed`;
      two-person smoke: `1 passed` with `APPROVED` and final cursor `14`.
- [x] Final Flutter: format unchanged, `flutter analyze` clean, `61 tests` passed.
- [x] Final Web: `10` test files / `65 tests` passed, typecheck and Vite build passed.
- [x] GitHub tag `v0.1.2` points to `7fa776284b8dace75b827d3057cabffda1e606e8`.
      CI run [33348660152](https://github.com/Astro24002/Muyu/actions/runs/33348660152)
      and Release run [33348660116](https://github.com/Astro24002/Muyu/actions/runs/33348660116)
      completed successfully. The published [GitHub Release](https://github.com/Astro24002/Muyu/releases/tag/v0.1.2)
      contains exactly one asset, `Muyu-v0.1.2.apk` (180,784,798 bytes),
      SHA-256 `5abca32227b80e822bfb07b25538fb8dfadcfb27145358606a3a713486e2ca67`.

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
- [x] Run `make verify` in the isolated PostgreSQL environment and inspect the
      generated Android/Web artifacts; the 2026-09-22 result is recorded above.
- [ ] Configure the fixed release keystore only in the CI secret store:
      `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
      `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`.
- [ ] Confirm the version APK workflow validates the keystore and runs
      `apksigner verify`; never publish an APK when a signing input is missing.
- [ ] Take and verify a fresh encrypted full backup.

## Deliverables

- [x] Android debug APK: `Muyu-5e1fa66.apk` for internal installation/testing;
      SHA-256 is recorded above.
- [x] 2026-09-22 internal debug APK: `Muyu-c4f6f71.apk`; size and SHA-256 are
      recorded in `docs/05-development-status.md`. This is not a signed release.
- [ ] Signed Android version APK: `Muyu-v<version>.apk`, built by the fixed
      release keystore workflow and attached as the only APK release asset.
- [ ] Signed Android App Bundle: `app-release.aab`, produced only by the
      protected signing workflow.
- [ ] Web static bundle: `web-release.tar.gz` containing `web/dist`.
- [ ] SHA-256 checksums for every artifact, mapped to the source commit and
      release version.
- [x] No iOS artifact is produced in this release.

## After release

- [x] Verify `/health/live` and `/health/ready` through the public TLS origin;
      both returned HTTP 200 (`{"status":"live"}` and `{"status":"ready"}`).
- [ ] Verify the first Android user can create a Workspace and then complete Web QR
      login at the public HTTPS origin.
- [ ] Register the first Android account and verify the two-person workspace
      approval path.
- [ ] Verify Web QR login, the 18-hour maximum cookie lifetime, and Android
      Web-session revocation.
- [ ] Record migration head, artifact checksums, backup verification time, and
      the operator in the release log.
