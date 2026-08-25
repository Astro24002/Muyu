# Build Artifacts

Pull requests produce reproducible, unsigned test artifacts after the backend
and client checks pass:

- `client/build/app/outputs/flutter-apk/app-debug.apk`
- `client/build/web`, uploaded as `web-release.tar.gz`

The protected tag workflow produces `app-release.aab` only after required CI
checks pass and all Android signing secrets are present and valid. The
keystore is written to a temporary file, used for the build, and removed in an
always-run cleanup step. A missing or invalid keystore fails the release; an
unsigned AAB is never published as a release artifact.

For each published artifact, generate a checksum and retain the source commit
and version beside it:

```sh
sha256sum app-debug.apk app-release.aab web-release.tar.gz > SHA256SUMS
git rev-parse HEAD > SOURCE_COMMIT
```

Install the debug APK only on an internal/test device. Supply the API origin at
build time when it is not served from the same origin:

```sh
flutter build apk --debug \
  --dart-define=API_BASE_URL=https://example.invalid
flutter build web --release \
  --dart-define=API_BASE_URL=/ \
  --dart-define=WEB_ORIGIN=https://muyu.bkverse.space
```

The production Compose image receives the same `WEB_ORIGIN` from
`deploy/.env`; the checked-in `deploy/.env.production.example` is the
domain-specific starting point and contains placeholders only.

No IPA, Xcode setup, iOS runner, or iOS artifact is part of this release.
