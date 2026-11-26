#!/usr/bin/env python3
"""Writes the AltStore source for a built IPA. CI attaches it to the release.

Version, size and privacy texts are read from the IPA itself, because AltStore
refuses to install an app whose version or permissions differ from the source.

    python3 tools/ios/altstore_source.py app.ipa altstore-source.json v2.0.1
"""
import datetime
import json
import os
import plistlib
import re
import sys
import zipfile

REPO = "https://github.com/arsenikt/WokokVPN-App"
RAW = "https://raw.githubusercontent.com/arsenikt/WokokVPN-App/main"
SITE = "https://wokok.doepic.ai"
TINT = "#FF7A1A"

ipa, out, tag = sys.argv[1:4]
name = os.path.basename(ipa)
if re.fullmatch(r"v[\w.\-]+", tag):
    download = f"{REPO}/releases/download/{tag}/{name}"
else:  # manual run from a branch
    download = f"{REPO}/releases/latest/download/{name}"

with zipfile.ZipFile(ipa) as z:
    plists = [
        plistlib.loads(z.read(n))
        for n in z.namelist()
        if re.fullmatch(r"Payload/[^/]+\.app/(PlugIns/[^/]+\.appex/)?Info\.plist", n)
    ]
# the extension id is the app id plus a suffix
app = min(plists, key=lambda p: len(p["CFBundleIdentifier"]))
privacy = {k: v for p in plists for k, v in p.items() if k.endswith("UsageDescription")}

version = app["CFBundleShortVersionString"]
about = (
    "Your own VPN, localhost tunnel, VPS deploy, spy check and scam guard.\n"
    "Свой VPN, туннель до localhost, настройка VPS, проверка слежки и защита от мошенников.\n\n"
    "Early release, not yet tested on a real iPhone. The VPN itself needs a paid Apple "
    "Developer signature: with a free Apple ID the tunnel does not start.\n"
    "Ранняя версия, на настоящем iPhone ещё не проверялась. Для самого VPN нужна подпись с "
    "платным Apple Developer: с бесплатным Apple ID туннель не запустится."
)
icon = f"{RAW}/assets/brand/logo.png"

source = {
    "name": "Wokok Box",
    "subtitle": "Your own VPN and server toolbox",
    "description": "Official source of Wokok Box.",
    "iconURL": icon,
    "website": SITE,
    "tintColor": TINT,
    "featuredApps": [app["CFBundleIdentifier"]],
    "apps": [
        {
            "name": "Wokok Box",
            "bundleIdentifier": app["CFBundleIdentifier"],
            "developerName": "arsenikt",
            "subtitle": "VPN, tunnel, deploy, spy check, scam guard",
            "localizedDescription": about,
            "iconURL": icon,
            "tintColor": TINT,
            "category": "utilities",
            "screenshots": [
                f"{RAW}/docs/img/phone-{s}.png" for s in ("home", "off", "servers", "settings")
            ],
            "appPermissions": {
                "entitlements": ["com.apple.developer.networking.networkextension"],
                "privacy": privacy,
            },
            "versions": [
                {
                    "version": version,
                    "buildVersion": app["CFBundleVersion"],
                    "date": datetime.date.today().isoformat(),
                    "localizedDescription": f"Wokok Box {version}. {REPO}/blob/main/CHANGELOG.md",
                    "downloadURL": download,
                    "size": os.path.getsize(ipa),
                    "minOSVersion": app["MinimumOSVersion"],
                }
            ],
        }
    ],
    "news": [],
}

with open(out, "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
print(f"{out}: {app['CFBundleIdentifier']} {version} ({app['CFBundleVersion']}), privacy: {sorted(privacy)}")
