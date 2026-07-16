#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${1:-$ROOT_DIR/dist}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
TAG="${2:-v$VERSION}"
ARCHIVE_NAME="CodexLinxDisplay-v$VERSION"
TOOLS_DIR="$ROOT_DIR/.build/SourcePackages/artifacts/sparkle/Sparkle/bin"
WORK_DIR="$ROOT_DIR/.release/appcast"
DOWNLOAD_URL="https://github.com/luweihuang/CodexLinxDisplay/releases/download/$TAG/"
PROJECT_URL="https://github.com/luweihuang/CodexLinxDisplay"

if [[ ! -x "$TOOLS_DIR/generate_appcast" ]]; then
  xcodebuild \
    -resolvePackageDependencies \
    -project "$ROOT_DIR/CodexLinxDisplay.xcodeproj" \
    -scheme CodexLinxDisplay \
    -derivedDataPath "$ROOT_DIR/.build"
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cp "$DIST_DIR/$ARCHIVE_NAME.zip" "$WORK_DIR/"
cp "$ROOT_DIR/CHANGELOG.md" "$WORK_DIR/$ARCHIVE_NAME.md"

APPCAST_ARGS=(
  --download-url-prefix "$DOWNLOAD_URL"
  --link "$PROJECT_URL"
  --maximum-versions 1
  --embed-release-notes
  -o "$WORK_DIR/appcast.xml"
  "$WORK_DIR"
)

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS_DIR/generate_appcast" --ed-key-file - "${APPCAST_ARGS[@]}"
else
  "$TOOLS_DIR/generate_appcast" --account com.olivia.CodexLinxDisplay "${APPCAST_ARGS[@]}"
fi

cp "$WORK_DIR/appcast.xml" "$DIST_DIR/appcast.xml"
echo "更新清单已生成：$DIST_DIR/appcast.xml"
