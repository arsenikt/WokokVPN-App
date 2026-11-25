# iOS: how the core works and how to ship it

Wokok on iOS runs sing-box inside a **Packet Tunnel** Network Extension, the only way Apple allows a
system-wide VPN. The Flutter app only sends it the ready JSON config and starts or stops the tunnel.

```
Flutter UI ──MethodChannel──▶ AppDelegate (TunnelBridge, NETunnelProviderManager)
                                     │ startVPNTunnel(options: ["config": …])
                                     ▼
                         PacketTunnel extension (separate process, ~50 MB limit)
                         PacketTunnelProvider ─▶ Libbox (sing-box 1.11.15) ─▶ WokokPlatform (NEPacketTunnelNetworkSettings)
```

Where things live:

| Path | What |
|---|---|
| `ios/PacketTunnel/` | extension: provider, platform glue, Info.plist, entitlements |
| `ios/Runner/AppDelegate.swift` | `TunnelBridge`: channel `com.wokok.vpn/engine` and events `com.wokok.vpn/events` |
| `tools/build_libbox_apple.sh` | builds `ios/Frameworks/Libbox.xcframework` from sing-box (needs macOS, Xcode, Go) |
| `tools/ios/add_tunnel.rb` | adds the extension target to `Runner.xcodeproj` (idempotent, CI runs it) |

The extension target is added by script instead of being checked into `project.pbxproj`, because the
project is edited on Windows. On a Mac you can run `bash tools/build_libbox_apple.sh && ruby tools/ios/add_tunnel.rb`
once and commit the resulting project if you prefer.

## The signing wall (important)

Network Extensions need a special entitlement that Apple only grants to the **paid Apple Developer Program**
(99 USD per year). Consequences:

- The unsigned IPA from CI shows the UI, but **the VPN will not start** when it is re-signed with a free Apple ID
  (AltStore, Sideloadly): free accounts cannot get `packet-tunnel-provider`.
- To make the tunnel work you need your own signing:

1. In the Apple Developer portal create two App IDs with the **Network Extensions** capability:
   `com.wokok.wokokVpn` and `com.wokok.wokokVpn.PacketTunnel` (change the base ID if you fork).
2. Create a development or ad-hoc provisioning profile for each.
3. On a Mac: open `ios/Runner.xcworkspace`, select both targets, set your Team, profiles and bundle IDs, then
   Product → Archive → Distribute (Ad Hoc / Development).

## Known limits

- The code was written against the libbox API of sing-box 1.11.15 and builds in CI, but has **not been run on a
  real iPhone**.
- The extension runs without app groups. Traffic stats in the UI read the core's local Clash API
  (`127.0.0.1:19090`) from the app process.
- Per-app routing is not available on iOS (no connection-owner lookup in the extension).
- iOS kills extensions above roughly 50 MB, so `LibboxSetMemoryLimit(true)` is on. Very large rule sets will not fit.
