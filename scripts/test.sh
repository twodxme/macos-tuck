#!/usr/bin/env bash
# Run the tests with only the Command Line Tools installed: SwiftPM doesn't
# look for swift-testing there on its own.
set -euo pipefail
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [[ -d "$F/Testing.framework" ]]; then
  swift test -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L"
else
  swift test
fi
