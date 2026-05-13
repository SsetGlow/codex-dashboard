#!/usr/bin/env bash
set -euo pipefail

APP_NAME="codex-dashboard"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf build
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

swiftc \
  -target arm64-apple-macos13.0 \
  -O \
  -framework AppKit \
  -framework SwiftUI \
  Sources/CodexDashboard/*.swift \
  -o "${MACOS_DIR}/CodexDashboard"

cp CodexDashboard/Info.plist "${CONTENTS_DIR}/Info.plist"

echo "Built ${BUNDLE_DIR}"
