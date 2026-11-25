# Contributing

Thanks for helping Wokok get hotter. 🔥

## Setup
```bash
flutter pub get
flutter analyze
flutter test
```
Flutter **3.29.3** is pinned in CI; please use the same version.

## Ground rules
- Keep the logic in `lib/core` testable without Flutter widgets (see `test/core_test.dart`).
- A new feature that changes the generated sing-box config needs a test, and the config should pass `sing-box check` (1.11.x).
- UI text is Russian today; if you add strings, keep them short and in the wok voice.
- Never log or commit keys, UUIDs or `wokok://` tickets.

## Good first issues
Translations, new recipes, widget tests, the iOS Packet Tunnel extension.

## Screenshots
`SHOTS=1 SHOTS_FLUTTER=<flutter sdk> flutter test test/screenshots_test.dart` renders the README screenshots into `docs/img`.
