#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
VERSION=2.9.6
SHA256=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
DEST="build/dependencies/Sparkle-$VERSION"
ARCHIVE="build/dependencies/Sparkle-$VERSION.tar.xz"
mkdir -p build/dependencies
if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --retry 3 "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$ARCHIVE.download"
  mv "$ARCHIVE.download" "$ARCHIVE"
fi
print "$SHA256  $ARCHIVE" | shasum -a 256 -c - >&2
# Re-extract the verified archive so a stale or modified framework is never reused.
rm -rf "$DEST"
mkdir -p "$DEST"
tar -xf "$ARCHIVE" -C "$DEST"
