#!/usr/bin/env bash
# Build a Release Scout.app, package it as a DMG, and publish as a GitHub
# Release on the current repo. Ad-hoc signed — first launch on the target
# machine needs right-click → Open → Open to clear Gatekeeper.
#
# Usage:
#   scripts/release.sh 0.1.0
#
# Requirements: xcodebuild, hdiutil, gh (logged in, with write access to the repo).

set -euo pipefail

VERSION="${1:?usage: release.sh <version> (e.g. 0.1.0)}"
TAG="v$VERSION"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
RELEASE_DIR="$BUILD_DIR/release"
DMG="$RELEASE_DIR/Scout-$VERSION.dmg"

echo "→ Cleaning previous build"
rm -rf "$BUILD_DIR"
mkdir -p "$RELEASE_DIR"

echo "→ Building Release configuration (universal, ad-hoc signed)"
xcodebuild \
  -project "$REPO_ROOT/Scout.xcodeproj" \
  -scheme Scout \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="arm64 x86_64" \
  clean build >/dev/null

APP="$BUILD_DIR/Build/Products/Release/Scout.app"
if [[ ! -d "$APP" ]]; then
  echo "✗ Scout.app not found at $APP" >&2
  exit 1
fi

echo "→ Codesigning Scout.app ad-hoc"
codesign --force --deep --sign - "$APP"

echo "→ Packaging as DMG"
# Stage directory with the app and a symlink to /Applications so the DMG
# window shows a drag-and-drop install layout.
STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "Scout $VERSION" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

echo "→ DMG ready: $DMG"
ls -lh "$DMG" | awk '{print "  size:", $5}'

if [[ "${SKIP_RELEASE:-0}" == "1" ]]; then
  echo "→ SKIP_RELEASE=1 set; not tagging or uploading."
  exit 0
fi

echo "→ Tagging $TAG and creating GitHub release"
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "  tag $TAG already exists locally — skipping tag/push"
else
  git tag -a "$TAG" -m "Release $VERSION"
  git push origin "$TAG"
fi

gh release create "$TAG" "$DMG" \
  --title "Scout $VERSION" \
  --notes "## Install

1. Download \`Scout-$VERSION.dmg\` from the Assets below.
2. Open the DMG and drag **Scout.app** into the **Applications** folder.
3. The first time you launch it, macOS will refuse because the build is ad-hoc signed. Right-click Scout.app in /Applications → **Open** → **Open**. After that it launches normally.

## Configure

Open the app, press ⌘, to open Settings. Fill in your Linear workspace and author name so deep-links and comment authorship work correctly.

The app expects a Scout instance at \`~/Scout\`. Install the [scout-plugin](https://github.com/jordanrburger/scout-plugin) into Claude Code and run \`/scout-setup\` first if you don't have one yet."

echo "✓ Released $TAG"
