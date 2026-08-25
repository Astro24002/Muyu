# Task 5 Report: Android-only Flutter Client

## Result

The Flutter client now has a single Android runtime path. `main.dart`
creates `SecureMobileSessionStore`, an Android `ApiClient`,
`AndroidDeviceSigningKey`, and `MobileLoginController`; `MuyuApp` accepts
only those Android dependencies and always renders the Android home flow.

The listed browser HTTP, Web login/session, obsolete transport, unsupported
device-key, Web screen, test, and static Web entrypoint files were removed.
`api_http_client.dart` now returns a normal `http.Client`, and the device key
interface directly imports the Android implementation. `qr_flutter` and
`web_socket_channel` were removed after confirming Android code has no
remaining imports; `mobile_scanner`, `WebQrScannerScreen`, and
`DeviceAuthorizationRepository.approveWebLogin` remain.

## Verification

- TDD red: `flutter test test/android_entrypoint_test.dart` initially failed
  on the existing `kIsWeb` branch.
- TDD green: the same boundary test passed after the Android-only refactor.
- `flutter pub get` completed and removed `qr`, `qr_flutter`, `web_socket`,
  and `web_socket_channel` from the resolved dependencies.
- `dart format --output=none --set-exit-if-changed .`: 36 files, 0 changed.
- `flutter analyze`: no issues found.
- `flutter test`: all tests passed.
- `flutter build apk --debug --dart-define=API_BASE_URL=https://example.invalid`:
  APK generated at `client/build/app/outputs/flutter-apk/app-debug.apk`.

The APK build emitted existing environment/plugin warnings for
`mobile_scanner`'s Kotlin Gradle Plugin usage and Android SDK XML version 4;
the build still completed and produced the debug APK.

## Follow-up Boundary Note

`client/test/android_entrypoint_test.dart` intentionally contains the banned
Web symbol strings as assertions. Any later repository-wide boundary scan
(including Task 6) must exclude that test file to avoid self-matching.
