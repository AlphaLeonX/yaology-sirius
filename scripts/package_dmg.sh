#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="1.1.1"
DMG_NAME="Sirius-v${VERSION}.dmg"
ZIP_NAME="Sirius-v${VERSION}.zip"
DIST_DIR="${ROOT_DIR}/dist"
APP_PATH="${DIST_DIR}/Sirius.app"
STAGING_DIR="${DIST_DIR}/dmg_staging"
OUTPUT_DMG="${DIST_DIR}/${DMG_NAME}"
OUTPUT_ZIP="${DIST_DIR}/${ZIP_NAME}"
CHECKSUMS="${DIST_DIR}/checksums.txt"

echo "==> Building latest Sirius.app..."
bash "${SCRIPT_DIR}/build_app.sh"

echo "==> Ad-hoc code signing Sirius.app for Apple Silicon..."
codesign --force --deep -s - "${APP_PATH}"

echo "==> Preparing DMG staging area..."
rm -rf "${STAGING_DIR}" "${OUTPUT_DMG}" "${OUTPUT_ZIP}"
mkdir -p "${STAGING_DIR}"

# 复制 App
cp -R "${APP_PATH}" "${STAGING_DIR}/"

# 创建 /Applications 替身链接
ln -s /Applications "${STAGING_DIR}/Applications"

# 创建首次打开说明 README.txt
cat << 'README_EOF' > "${STAGING_DIR}/首次安装必读.txt"
=====================================================
  Sirius（天狼星）Mac 原生多屏自适应调光引擎 v1.1.1
=====================================================

【安装方法】
1. 将左侧的 Sirius.app 拖入右侧的 Applications 文件夹即可完成安装。

【首次打开提示“已损坏”或“无法验证开发者”？】
由于本软件为开源/个人独立构建，未支付苹果每年 $99 的商业公证税，
macOS 会对从网络下载的文件启用严格的 Gatekeeper 隔离保护。

请直接打开系统的「终端 (Terminal.app)」，复制并粘贴运行以下命令：
-----------------------------------------------------
sudo xattr -cr /Applications/Sirius.app
-----------------------------------------------------
回车后输入电脑密码，即可永久解除隔离，直接秒开！
README_EOF

echo "==> Generating disk image: ${OUTPUT_DMG}..."
hdiutil create \
    -volname "Sirius Installer" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${OUTPUT_DMG}" > /dev/null

rm -rf "${STAGING_DIR}"
echo "==> DMG successfully created at: ${OUTPUT_DMG} ($(du -h "${OUTPUT_DMG}" | cut -f1))"

echo "==> Generating release archive: ${OUTPUT_ZIP}..."
cd "${DIST_DIR}"
zip -r -q "${ZIP_NAME}" "Sirius.app"
echo "==> Zip successfully created at: ${OUTPUT_ZIP} ($(du -h "${OUTPUT_ZIP}" | cut -f1))"

# 额外创建指向 latest 的副本，便于固定 URL 下载
cp -f "${DMG_NAME}" "Sirius-latest.dmg"
cp -f "${ZIP_NAME}" "Sirius-latest.zip"

echo "==> Computing SHA-256 checksums..."
shasum -a 256 "${DMG_NAME}" "${ZIP_NAME}" "Sirius-latest.dmg" "Sirius-latest.zip" > "${CHECKSUMS}"
cat "${CHECKSUMS}"
echo "==> All release artifacts ready in ${DIST_DIR}/"
