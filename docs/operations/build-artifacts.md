# Build Artifacts

Local development produces a commit-named Android debug APK:

- `client/build/app/outputs/flutter-apk/Muyu-<short-commit>.apk` (Android debug)

Version-tag and published-release workflows produce version-named artifacts
after the backend, Android, and browser checks pass:

- `client/build/app/outputs/flutter-apk/Muyu-vX.Y.Z.apk` (Android debug release asset)
- `web/dist`, packaged as `web-release.tar.gz`

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

The local `client-build` target now carries the source commit in the debug APK
filename automatically. Flutter's `app-debug.apk` remains only as an internal
intermediate file:

```sh
ANDROID_BUILD_ENV=production API_BASE_URL=https://muyu.bkverse.space make client-build
# client/build/app/outputs/flutter-apk/Muyu-$(git rev-parse --short HEAD).apk
```

Local development may opt into a LAN or loopback API explicitly:

```sh
ANDROID_BUILD_ENV=local API_BASE_URL=http://10.0.2.2:8080 make client-build
```

Release assets use the version tag instead, for example
`Muyu-v0.1.0.apk`; CI does not generate or attach commit-named debug APKs.

Install the debug APK only on an internal/test device. Supply the API origin at
build time when it is not served from the same origin:

```sh
ANDROID_BUILD_ENV=production API_BASE_URL=https://muyu.bkverse.space make client-build
cd web
npm ci
VITE_API_BASE_URL=/ npm run build
tar -czf web-release.tar.gz -C dist .
```

The Caddy image builds `web/dist` from the checked-in Vite package and serves it
from `/srv`. FastAPI keeps `WEB_ORIGIN` only for server-side origin validation;
it is never passed to the browser bundle.

No iOS artifact is part of this release.
