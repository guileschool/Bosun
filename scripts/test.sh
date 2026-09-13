#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/tests
xcrun swiftc -swift-version 5 -module-cache-path build/module-cache-v080 \
 Sources/LatencyTrace.swift Sources/Commands.swift Sources/Accessibility.swift Sources/ChatGPTControl.swift Sources/Localization.swift Tests/main.swift \
 -framework AppKit -framework ApplicationServices -framework AVFoundation -framework Speech -framework ServiceManagement \
 -o build/tests/commands
build/tests/commands
python3 scripts/check-localizations.py

if [[ -d build/Bosun.app ]]; then
  xcrun swiftc -parse-as-library -module-cache-path build/module-cache-v080 Tests/BundleCheck.swift -o build/tests/bundle-check
  build/tests/bundle-check "$PWD/build/Bosun.app"
fi
