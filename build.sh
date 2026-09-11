#!/bin/zsh
# Build from any working directory. Installation is deliberately a separate step.
set -euo pipefail
cd "${0:A:h}"
if [[ $# -gt 0 ]]; then
  print -u2 'Usage: zsh build.sh (copy build/Bosun.app to Applications to install)'
  exit 64
fi
APP=Bosun
zsh scripts/fetch-sparkle.sh
SPARKLE="$PWD/build/dependencies/Sparkle-2.9.6"
# Preserve the installed app's identity so macOS accessibility grants survive updates.
# Ad-hoc builds require an explicit SIGN_IDENTITY=- and must not replace the installed app.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY=$(codesign -dv --verbose=4 "/Applications/$APP.app" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)
  if [[ -z "$SIGN_IDENTITY" ]]; then
    print -u2 'No installed signing identity. Set SIGN_IDENTITY to a Developer ID certificate; use - only for isolated test builds.'
    exit 65
  fi
fi
STAGING=$(mktemp -d "$PWD/build-stage.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/$APP.app/Contents/MacOS" build/module-cache-v080
xcrun swiftc -swift-version 5 -O -module-cache-path build/module-cache-v080 \
  -target "${ARCH:-arm64}-apple-macosx14.0" Sources/*.swift \
  -o "$STAGING/$APP.app/Contents/MacOS/$APP" \
  -framework AppKit -framework ApplicationServices -framework AVFoundation \
  -framework Speech -framework ServiceManagement \
  -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks
cp Info.plist "$STAGING/$APP.app/Contents/Info.plist"
ditto Resources "$STAGING/$APP.app/Contents/Resources"
cp docs/THIRD-PARTY-NOTICES.txt "$STAGING/$APP.app/Contents/Resources/THIRD-PARTY-NOTICES.txt"
mkdir -p "$STAGING/$APP.app/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.framework" "$STAGING/$APP.app/Contents/Frameworks/Sparkle.framework"
# Sign nested executables from the inside out with the app's identity.
FRAMEWORK="$STAGING/$APP.app/Contents/Frameworks/Sparkle.framework"
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" == '-' ]] || SIGN_ARGS+=(--options runtime --timestamp)
for COMPONENT in "$FRAMEWORK/Versions/B/Autoupdate" \
  "$FRAMEWORK/Versions/B/Updater.app" \
  "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
  "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" "$FRAMEWORK"; do
  codesign "${SIGN_ARGS[@]}" "$COMPONENT"
done
plutil -lint "$STAGING/$APP.app/Contents/Info.plist"
if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != '-' ]]; then
  codesign --force --options runtime --timestamp --entitlements Entitlements.plist \
    --sign "$SIGN_IDENTITY" "$STAGING/$APP.app"
else
  codesign --force --sign - "$STAGING/$APP.app"
fi
codesign --verify --deep --strict "$STAGING/$APP.app"
rm -rf "build/$APP.app"
mv "$STAGING/$APP.app" "build/$APP.app"
print "Built: $PWD/build/$APP.app"
