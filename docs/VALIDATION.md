# Validation

Verified on 2026-11-12.

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --dart-define=CAPTURE_SCREENS=true --update-goldens --timeout=45s`: 24 tests passed.
- `flutter build apk --release --no-pub`: succeeded.
- Android APK signature verification: valid APK Signature Scheme v2, one signer.
- Package: `dev.relayhome.relay_home`, version 1.0.0 (1).
- Android minimum API 24; target/compile API 36.
- Native ABIs: arm64-v8a, armeabi-v7a, x86_64.
- Local delivery APK: `dist/relay-home-1.0.0.apk`, 68,387,289 bytes, with a SHA-256 file alongside it. These generated deliverables are excluded from Git; build a fresh APK using the README instructions.

Rendered and visually inspected home light/dark, device controls, offline recovery, empty home, prepare, Wi-Fi setup, and personalization. Preview images are actual Flutter test renders, not design mockups. Rendering uses injected network/storage/relay service doubles; it does not claim physical hardware results.

Coverage includes exact bytes for all eight relay commands, real loopback TCP timing/delivery, no-payload connection probes, actual subnet boundaries, offline/unknown/uncertain UI, saved-state restoration without replay, demo separation, per-board command locking, cancellation while permission/native setup is pending, target changes during send, full pairing-to-save UI flow, and preservation of relay metadata/history after an IP change.

An Android emulator runtime attempt was blocked by disk space: the installed emulator required about 7.2 GiB available for its userdata partition. All task-created emulator downloads/system-image/AVD files were removed. No emulator runtime or physical relay pairing/switching is claimed. Verify SmartConfig radio provisioning and physical relay operation on an Android phone and the board.

This internal release uses the local Android development signing key. Store publishing requires an owned release keystore.
