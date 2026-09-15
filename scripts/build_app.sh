#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 版本号单一数据源：见 scripts/version.sh（正式发布取 git tag，开发构建自动加 -dev.N 后缀）
# shellcheck source=version.sh
source "${SCRIPT_DIR}/version.sh"
VERSION="$(resolve_sirius_version "${ROOT_DIR}")"
BUILD_NUMBER="$(resolve_sirius_build_number "${ROOT_DIR}")"

APP_NAME="Sirius"

echo "==> Building Sirius in release mode (version ${VERSION}, build ${BUILD_NUMBER})..."
cd "${ROOT_DIR}"
swift build -c release

BUILD_BIN="${ROOT_DIR}/.build/release/${APP_NAME}"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Packaging into ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BUILD_BIN}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# 复制 AppIcon.icns 资源
if [ -f "${ROOT_DIR}/assets/AppIcon.icns" ]; then
    cp "${ROOT_DIR}/assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

cat << EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Sirius</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.yaology.sirius.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Sirius</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Yaology Universe. All rights reserved.</string>
</dict>
</plist>
EOF

echo "==> Sirius.app packaging complete at: ${APP_BUNDLE}"
echo "You can launch it via: open ${APP_BUNDLE}"
