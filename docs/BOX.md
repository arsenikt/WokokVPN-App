# Wokok Box

One app, five compartments. Everything runs on your device and your own server: no accounts, no backend, no telemetry.

## Tunnel: your own ngrok

```
dart compile exe bin/wokok_box.dart -o wokok-box
wokok-box login root@203.0.113.7
wokok-box share 3000 --ttl 1d --password noodles --guests
```

- Link: `https://<name>.<ip-with-dashes>.sslip.io`, or `<name>.<your domain>` with a `*.domain` A record.
- Lifetime, password, live request log, webhook replay (app) and guest notes are handled on your computer; the server only runs Caddy.
- If the VPN owns port 443, HAProxy is placed behind Reality's `dest` and routes `*.sslip.io` and your domains to Caddy. Tickets do not change.
- The CLI prints requests and notes; replay is in the app.

## Deploy

Check before the order, then VPN, a site (folder, ZIP, GitHub) or a Telegram bot (Python / Node.js), optionally in Docker. Auto-update every 5 minutes with automatic return to the previous release, manual rollback, Doctor, and a recipe showcase. Needs Debian or Ubuntu, root or passwordless sudo.

The server agent is `server/box.sh`. After editing it run `python tools/embed_server.py`.

## Spy Check

| Platform | Source | Per app | Bytes |
|---|---|---|---|
| Windows | netstat + DNS cache, or the VPN core | yes | only with VPN on |
| macOS | lsof, or the VPN core | yes | only with VPN on |
| Android | VPN core | yes | yes |
| iOS | VPN core | addresses only | yes |

Receipt with an A–F grade, "lid" (reject rules while the VPN is on), night watch, leak trap, alerts on new owners. "Country" is the owner's home country from the offline database, not the server's location. Observation runs while the app is running.

## Guard

Offline rules for links, QR codes and messages in Russian, English and Macedonian; traffic-light verdict, reasons, read aloud, ask a relative (WhatsApp / SMS / Telegram, you press send), VPN shield, ten one-minute lessons, simple mode for parents, Android share target. Rules reduce risk; a green result is not a guarantee.
