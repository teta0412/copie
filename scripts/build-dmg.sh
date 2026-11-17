#!/usr/bin/env zsh
set -euo pipefail

# Script to build Copie and package it into a distributable .dmg file.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DERIVED_DATA="${BUILD_DIR}/DerivedData"
STAGING_DIR="${BUILD_DIR}/dmg-staging"
OUTPUT_DIR="${BUILD_DIR}/dist"

echo "==> Cleaning previous build outputs..."
rm -rf "${BUILD_DIR}"
mkdir -p "${STAGING_DIR}" "${OUTPUT_DIR}"

echo "==> Building Copie in Release configuration..."
xcodebuild \
  -project "${ROOT_DIR}/Copie.xcodeproj" \
  -scheme Copie \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="${DERIVED_DATA}/Build/Products/Release/Copie.app"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Error: Built application not found at ${APP_PATH}" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1.0")
DMG_NAME="Copie-${VERSION}-macOS.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

echo "==> Preparing DMG staging area..."
cp -R "${APP_PATH}" "${STAGING_DIR}/Copie.app"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "==> Creating DMG: ${DMG_PATH}..."
rm -f "${DMG_PATH}"
hdiutil create \
  -volname "Copie" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "==> DMG successfully created!"
echo "    Path: ${DMG_PATH}"
echo "    Size: $(du -h "${DMG_PATH}" | cut -f1)"
