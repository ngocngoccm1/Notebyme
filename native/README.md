# Notes native

Flutter clients for Windows, macOS, Android and iOS. The UI runs as a native Flutter application, without a browser or WebView. The existing website remains available.

## Keep editing responsive

- Editing updates only the text controller and a small save-status notifier.
- A 300 ms idle debounce combines keystrokes into a per-note SQLite write. Pause/exit flushes pending edits.
- SQLite runs on a background thread on mobile and a separate isolate on Windows.
- Lists read title, date and a 100-character preview, then build visible rows with ListView.builder.
- Large JSON encoding and note decoding run in a background isolate.
- Sync is debounced after typing, serialized per account, and stops polling while the app is inactive.
- Supabase keys/JWTs stay in the backend. The app stores only its opaque app session in OS secure storage.

Local notes are not end-to-end encrypted. Keep secrets out of note bodies. Signing and data-storage behavior should be verified on a real device before broad distribution.

## Builds

`.github/workflows/native.yml` builds Windows, Android, macOS and an unsigned iOS package on GitHub-hosted runners. Successful packages are published to the `native-latest` release.

| Target | Package | Status/requirements |
| --- | --- | --- |
| Windows x64 | Notes-windows-x64.zip | Unzip the complete folder, then run Notes.exe. No WebView installation. |
| Android 7+ | Notes-android.apk | AOT release build with development signing for initial testing. A private, persistent release keystore is needed for reliable upgrades and Play Store distribution. |
| macOS | Notes-macos.zip | Standalone .app, not Developer ID signed/notarized. Public distribution needs Apple signing. |
| iOS 13+ | Notes-ios-unsigned.zip | Compile verification/source for developer signing. Not directly installable on iPhone; requires Apple provisioning and a signed build. |

CI does not register developer accounts, enroll devices, accept agreements, or publish to an app store. The app bundle identifier is `com.ngocngoccm1.notebyme`.

## Develop

Use Flutter 3.38.9 / Dart 3.10.8, matching CI, and the native toolchain for your OS. Dependency versions are locked in pubspec.lock.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

For the other targets use `flutter build apk --release`, `flutter build macos --release`, or `flutter build ios --release --no-codesign` on the corresponding build host. The Android project requires Java 17 and Android SDK; Windows needs Visual Studio C++ including ATL/CMake and Windows SDK. macOS/iOS require Xcode.

`backend.dart` contains only the public backend URL. The backend's allowed_origins setting must include `notebyme://native`, in addition to the existing website origin. This is client configuration, not an authorization boundary; the backend verifies every app session.

## Performance verification

Unit/widget tests cover 5,000-note lazy lists, 100 rapid edits producing a single save, account isolation, upload/edit races and failed disk writes.

The Windows CI job also runs a profile-mode integration workload: scroll 5,000 notes and type into a long document. Reports are uploaded as `Notes-performance-windows`:

```sh
flutter drive --profile -d windows --driver=test_driver/performance.dart --target=integration_test/performance_test.dart
```

Review `build/performance/*_summary.json` for build/raster timings and missed frame budgets. A CI VM is not a substitute for profiling the user's phone or Mac; no device-wide "zero lag" guarantee is made.
