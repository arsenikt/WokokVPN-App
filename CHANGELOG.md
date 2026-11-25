# Changelog

## Unreleased
- iOS core: Packet Tunnel extension running sing-box (libbox 1.11.15), Flutter bridge, extension target added by `tools/ios/add_tunnel.rb`. Builds in CI; needs your own signing with a paid Apple Developer account, not yet run on a device (see docs/IOS.md)
- Hub website: screens, install guide per platform, release stats

## 1.0.0
First public release.

- Flutter app for Windows, macOS, Android and iOS with one wok-on-fire brand and a native shell per platform (Material 3, Cupertino tab bar, sidebar, tray / menu bar)
- sing-box core with Auto-Switch: VLESS + Reality with an SSH fallback, picked automatically
- Recipes: *All in the wok*, *Smart* (banks and government sites direct), *Selected only*
- Tickets: import `wokok://` (same format as the Chrome extension and the server), `vless://`, QR scan, clipboard and file
- Kill switch (strict route), keystore-backed storage, biometric lock, "Extinguish" wipe
- Android core: `VpnService` + `libbox` built in CI from sing-box 1.11.15
- Windows and macOS: bundled sing-box sidecar, system proxy by default, optional TUN
- Release CI builds every platform and publishes `SHA256SUMS.txt`
- iOS: UI only for now, the Packet Tunnel extension is not implemented yet
