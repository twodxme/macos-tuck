#!/usr/bin/env bash
# Rebuild Resources/AppIcon.icns (and docs/icon.png) from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -O scripts/make-icon.swift -o "$tmp/make-icon"
"$tmp/make-icon" "$tmp"
set_dir="$tmp/AppIcon.iconset"
mkdir "$set_dir"
# 16 and 32 pt use the simplified art; the tiles are just noise that small.
for spec in "16 16 small" "16@2x 32 small" "32 32 small" "32@2x 64 full" \
            "128 128 full" "128@2x 256 full" "256 256 full" "256@2x 512 full" \
            "512 512 full" "512@2x 1024 full"; do
  read -r name px kind <<<"$spec"
  src="$tmp/icon-app.png"; [[ $kind == small ]] && src="$tmp/icon-app-small.png"
  sips -s format png -z "$px" "$px" "$src" --out "$set_dir/icon_$name.png" >/dev/null
done
iconutil -c icns "$set_dir" -o Resources/AppIcon.icns
sips -z 256 256 "$tmp/icon.png" --out docs/icon.png >/dev/null
echo "wrote Resources/AppIcon.icns and docs/icon.png"
