#!/usr/bin/env bash
set -euo pipefail

APP_NAME="codex-dashboard"
VERSION="0.1.8"
BUILD_APP="build/${APP_NAME}.app"
DIST_DIR="dist"
STAGING_DIR="build/dmg-staging"
RW_DMG="${DIST_DIR}/${APP_NAME}-${VERSION}-rw.dmg"
FINAL_DMG="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
VOLUME_NAME="${APP_NAME}"

./build.sh

rm -rf "${STAGING_DIR}" "${RW_DMG}" "${FINAL_DMG}"
mkdir -p "${STAGING_DIR}" "${DIST_DIR}"

ditto "${BUILD_APP}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "${STAGING_DIR}/${APP_NAME}.app" || true
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${STAGING_DIR}/${APP_NAME}.app" >/dev/null
fi

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDRW \
  "${RW_DMG}" >/dev/null

MOUNT_POINT="/Volumes/${VOLUME_NAME}"
hdiutil attach "${RW_DMG}" -readwrite -noverify -noautoopen >/dev/null

osascript <<APPLESCRIPT >/dev/null
tell application "Finder"
  tell disk "${VOLUME_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 780, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 13
    set position of item "${APP_NAME}.app" of container window to {170, 190}
    set position of item "Applications" of container window to {410, 190}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT

hdiutil detach "${MOUNT_POINT}" >/dev/null

hdiutil convert "${RW_DMG}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "${FINAL_DMG}" >/dev/null

rm -f "${RW_DMG}"

hdiutil verify "${FINAL_DMG}" >/dev/null

echo "Created ${FINAL_DMG}"
