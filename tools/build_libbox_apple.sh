#!/usr/bin/env bash
# Builds Libbox.xcframework (the sing-box core for iOS) into ios/Frameworks.
# Needs: macOS with Xcode, Go 1.23+.
set -euo pipefail
VERSION="${1:-1.11.15}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
git clone --depth 1 --branch "v$VERSION" https://github.com/SagerNet/sing-box.git "$WORK/sing-box"
cd "$WORK/sing-box"
export PATH="$PATH:$(go env GOPATH)/bin"
go install -v github.com/sagernet/gomobile/cmd/gomobile@v0.1.4
go install -v github.com/sagernet/gomobile/cmd/gobind@v0.1.4
go run ./cmd/internal/build_libbox -target apple -platform ios
mkdir -p "$ROOT/ios/Frameworks"
rm -rf "$ROOT/ios/Frameworks/Libbox.xcframework"
mv Libbox.xcframework "$ROOT/ios/Frameworks/"
echo "Libbox.xcframework -> ios/Frameworks"
