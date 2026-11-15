#!/usr/bin/env bash
# Build Tuck.app with only the Command Line Tools (no Xcode needed).
#   scripts/build-app.sh            -> build/Tuck.app (ad-hoc signed)
#   scripts/build-app.sh --zip      -> also build/Tuck.zip for a release
set -euo pipefail
cd "$(dirname "$0")/.."

# One build per architecture, merged with lipo: a single multi-arch
# `swift build` needs Xcode's build system, which the CLT lack.
# -Osize: Tuck spends its life asleep, so size beats speed everywhere.
flags=(-c release -Xswiftc -Osize)
for arch in arm64 x86_64; do
  swift build "${flags[@]}" --triple "$arch-apple-macosx13.0"
done
mkdir -p build
bin=build/Tuck-universal
lipo -create -output "$bin" \
  "$(swift build "${flags[@]}" --triple arm64-apple-macosx13.0 --show-bin-path)/Tuck" \
  "$(swift build "${flags[@]}" --triple x86_64-apple-macosx13.0 --show-bin-path)/Tuck"
strip -x "$bin"   # local symbols only; nothing at runtime needs them

app=build/Tuck.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Tuck"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# CI passes the tag's version (VERSION=1.2.0) so the app matches its release.
if [[ -n "${VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$app/Contents/Info.plist"
fi

# Ad-hoc signature: enough to run locally. Downloads of an ad-hoc build are
# quarantined by Gatekeeper; see README for the one-time "Open" step.
codesign --force --deep --sign - "$app"
codesign --verify --verbose=2 "$app"

if [[ "${1:-}" == "--zip" ]]; then
  rm -f build/Tuck.zip
  ditto -c -k --keepParent "$app" build/Tuck.zip
  echo "built build/Tuck.zip"
fi
echo "built $app"
