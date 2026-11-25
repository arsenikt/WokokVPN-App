#!/usr/bin/env bash
# Builds libbox.aar (the sing-box core for Android) into android/app/libs.
# Needs: Go 1.23+, JDK 17, Android SDK + NDK (ANDROID_HOME set).
set -euo pipefail
VERSION="${1:-1.11.15}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
git clone --depth 1 --branch "v$VERSION" https://github.com/SagerNet/sing-box.git "$WORK/sing-box"
cd "$WORK/sing-box"
export PATH="$PATH:$(go env GOPATH)/bin"
go install -v github.com/sagernet/gomobile/cmd/gomobile@v0.1.4
go install -v github.com/sagernet/gomobile/cmd/gobind@v0.1.4
go run ./cmd/internal/build_libbox -target android
mkdir -p "$ROOT/android/app/libs"
cp libbox.aar "$ROOT/android/app/libs/libbox.aar"
echo "libbox.aar -> android/app/libs ($(du -h libbox.aar | cut -f1))"
