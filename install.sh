#!/usr/bin/env bash
set -euo pipefail

APP_NAME="codex-dashboard"
SOURCE_APP="build/${APP_NAME}.app"
TARGET_APP="/Applications/${APP_NAME}.app"

if [[ ! -d "${SOURCE_APP}" ]]; then
  ./build.sh
fi

if [[ -d "${TARGET_APP}" ]]; then
  rm -rf "${TARGET_APP}"
fi

ditto "${SOURCE_APP}" "${TARGET_APP}"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${TARGET_APP}" >/dev/null 2>&1 || true
fi

echo "Installed ${TARGET_APP}"
