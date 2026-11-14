# Validation

## Wi-Fi migration update — 1.0.2 (3), 2026-11-14

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --timeout=45s --dart-define=CAPTURE_SCREENS=true --update-goldens`: all 43 tests passed.
- Final `flutter build apk --release --no-pub`: succeeded; APK Signature Scheme v2 verified.
- `dist/relay-home-1.0.2.apk`: 68,469,229 bytes; SHA-256 `01079153a28b091f25b5fef3e738e523fc3bd815df388baeb22e7c568bca9b62`. APK/checksum are ignored local build outputs.
- Installed with `adb install -r` on the vivo V2045. Android reports version 1.0.2 / code 3; cold launch returned `Status: ok`. USB disconnected before the on-device menu inspection could finish; menu and migration-flow validation is covered by widget tests below.
- The full Home-menu migration flow was checked again after pinning Continue to the bottom of the prepare screen. New prepare/completion screenshots were rendered and visually inspected at 390 × 844.
- Widget tests cover migration from an offline Home card, the device-screen menu, explicit response selection for a board without a saved MAC, another board replying, timeout, and cancellation followed by a late response. Successful migration goes directly to completion instead of personalization.
- Controller tests verify preservation of the existing device ID, names, room, icons, custom image paths, command timestamps, states and uncertainty through JSON persistence. They also check mismatched identities, unverified responses, changed phone Wi-Fi, duplicate destinations, and failed local storage. No migration test sends a relay command.
- The flow uses the existing classic ESPTouch implementation. Hardware pairing was previously confirmed by the user; moving a physical board to a different Wi-Fi has not been exercised in this update's validation.

## Responsiveness update — 1.0.1 (2), 2026-11-14

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --timeout=45s`: all 33 tests passed.
- `flutter build apk --release --no-pub`: succeeded; APK Signature Scheme v2 verified.
- `dist/relay-home-1.0.1.apk`: 68,452,829 bytes; SHA-256 `503ed1dca0597cb20c90ec8a6b398629d6ed4fe7b170e625e36261a97235091b`. APK and checksum are local, ignored build outputs.
- Installed with `adb install -r` on the connected vivo V2045. Android reports version 1.0.1 / code 2; cold launch returned `Status: ok`. The home screen retained the saved board, room, four relay histories, and showed the board as reachable.
- Added regression checks that command completion precedes background socket closure, rapid writes preserve order over one connection, idle connections are retired, and disposal/disconnection before sending never replays a command.
- Home and device-screen widget tests exercise the real controller with a delayed transport: switch and artwork change before completion, no spinner appears, failure restores the previous value and displays an error.
- Controller tests verify requested visual values are never persisted before a successful send; failed or ambiguous sends retain the previous saved value and appropriate uncertainty.

The user confirmed that Android SmartConfig pairing and physical switching worked with the original app, and reported that the UI lagged behind the physical relay. This update removes the two-second wait from the UI while retaining it as a background socket idle timer. No physical-state feedback is added; the firmware still provides no acknowledgement or state query.

Updated switching behavior was verified with loopback sockets and controller/widget tests. Installation validation did not send additional commands to the physical relays.

## Original release — 1.0.0 (1), 2026-11-12

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

An Android emulator runtime attempt was blocked by disk space: the installed emulator required about 7.2 GiB available for its userdata partition. All task-created emulator downloads/system-image/AVD files were removed. The original build-time validation did not include hardware operation; subsequent user feedback is recorded above.

This internal release uses the local Android development signing key. Store publishing requires an owned release keystore.
