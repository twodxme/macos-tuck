#!/usr/bin/env bash
# Redraw docs/privacy-light.png and docs/privacy-dark.png from scripts/make-trust-card.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -O scripts/make-trust-card.swift -o "$tmp/make-trust-card"
"$tmp/make-trust-card" docs
