#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.release/build"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/.release/dmg"
APP_PATH="$BUILD_DIR/Build/Products/Release/CodexLinxDisplay.app"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

cd "$ROOT_DIR"
xcodegen generate

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
ARCHIVE_NAME="CodexLinxDisplay-v$VERSION"

rm -rf "$BUILD_DIR" "$STAGING_DIR"
mkdir -p "$DIST_DIR" "$STAGING_DIR"
rm -f "$DIST_DIR/$ARCHIVE_NAME.zip" "$DIST_DIR/$ARCHIVE_NAME.dmg"

BUILD_SETTINGS=(
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
  CODE_SIGNING_REQUIRED=YES
  ONLY_ACTIVE_ARCH=NO
  ARCHS="arm64 x86_64"
)

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  BUILD_SETTINGS+=(ENABLE_HARDENED_RUNTIME=NO)
else
  BUILD_SETTINGS+=(ENABLE_HARDENED_RUNTIME=YES)
fi

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  BUILD_SETTINGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Manual)
fi

xcodebuild \
  -project CodexLinxDisplay.xcodeproj \
  -scheme CodexLinxDisplay \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  build \
  "${BUILD_SETTINGS[@]}"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  SIGNING_INFO="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
  if [[ "$SIGNING_INFO" == *"runtime"* ]]; then
    echo "adhoc 预览包不能启用 Hardened Runtime，否则无法加载 Sparkle。" >&2
    exit 1
  fi
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "公证需要 Developer ID Application 签名。" >&2
    exit 1
  fi

  PRE_NOTARY_ZIP="$ROOT_DIR/.release/$ARCHIVE_NAME-notary.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$PRE_NOTARY_ZIP"
  xcrun notarytool submit "$PRE_NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  rm -f "$PRE_NOTARY_ZIP"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST_DIR/$ARCHIVE_NAME.zip"

ditto "$APP_PATH" "$STAGING_DIR/CodexLinxDisplay.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
  -volname "Codex 屏显" \
  -srcfolder "$STAGING_DIR" \
  -fs APFS \
  -format ULFO \
  -ov \
  "$DIST_DIR/$ARCHIVE_NAME.dmg"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DIST_DIR/$ARCHIVE_NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DIST_DIR/$ARCHIVE_NAME.dmg"
fi

echo "发布文件已生成："
echo "  $DIST_DIR/$ARCHIVE_NAME.dmg"
echo "  $DIST_DIR/$ARCHIVE_NAME.zip"
