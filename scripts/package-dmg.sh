#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
MODE=${1:---preview}
[[ "$MODE" == '--preview' || "$MODE" == '--release' ]] || { print -u2 'Usage: package-dmg.sh [--preview|--release]'; exit 64; }
if [[ "$MODE" == '--release' ]]; then
  [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != '-' && -n "${NOTARY_PROFILE:-}" ]] || {
    print -u2 'Release requires SIGN_IDENTITY and a notarytool keychain NOTARY_PROFILE.'; exit 1
  }
else
  export SIGN_IDENTITY=-
fi
zsh build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
LABEL="Bosun-$VERSION-${ARCH:-arm64}"
[[ "$MODE" == '--preview' ]] && LABEL="$LABEL-preview"
mkdir -p dist
STAGING=$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto build/Bosun.app "$STAGING/Bosun.app"
ln -s /Applications "$STAGING/Applications"
cp docs/INSTALL.txt "$STAGING/Read Me.txt"
if [[ "$MODE" == '--preview' ]]; then
  print 'LOCAL PREVIEW: ad-hoc signed, not notarized. Not a public release.' > "$STAGING/PREVIEW.txt"
fi
hdiutil create -volname Bosun -srcfolder "$STAGING" -ov -format UDZO "dist/$LABEL.dmg"
if [[ "$MODE" == '--release' ]]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "dist/$LABEL.dmg"
  xcrun notarytool submit "dist/$LABEL.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "dist/$LABEL.dmg"
  xcrun stapler validate "dist/$LABEL.dmg"
  spctl --assess --type open --context context:primary-signature --verbose "dist/$LABEL.dmg"
fi
hdiutil verify "dist/$LABEL.dmg"
(cd dist && shasum -a 256 "$LABEL.dmg" > "$LABEL.dmg.sha256")
print "Created: $PWD/dist/$LABEL.dmg"
