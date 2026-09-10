#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Sirius（天狼星 · α CMa）一键安装脚本
# https://sirius.yaology.com
# ==============================================================================

BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${CYAN}${BOLD}"
cat << 'EOF'
     ★  S I R I U S  ·  α  C M a
     Mac 原生双星自适应物理背光调光引擎
     https://sirius.yaology.com
EOF
echo -e "${RESET}"

# 1. 操作系统环境检查
OS="$(uname -s)"
if [ "${OS}" != "Darwin" ]; then
    echo -e "${YELLOW}错误：Sirius 仅支持 macOS 操作系统 (Apple Silicon / Intel Mac)。${RESET}"
    exit 1
fi

ARCH="$(uname -m)"
echo -e "==> 检测到系统架构: ${BOLD}${ARCH}${RESET} (${OS})"

# 2. 检查安装目标路径
TARGET_DIR="/Applications"
APP_NAME="Sirius.app"
DEST="${TARGET_DIR}/${APP_NAME}"

# 3. 下载或从本地安装
RELEASE_URL="https://github.com/AlphaLeonX/yaology-sirius/releases/latest/download/Sirius-latest.dmg"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

echo -e "==> 准备安装到 ${BOLD}${DEST}${RESET}..."

# 如果本机已有编译好的 dist/Sirius.app，支持本地直接一键直装
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
LOCAL_APP="${SCRIPT_DIR}/../dist/Sirius.app"

if [ -d "${LOCAL_APP}" ]; then
    echo -e "==> 发现本地构建版本，直接安装中..."
    rm -rf "${DEST}"
    cp -R "${LOCAL_APP}" "${DEST}"
else
    echo -e "==> 正在从官方节点下载 Sirius 最新发布版..."
    DMG_PATH="${TEMP_DIR}/Sirius.dmg"
    curl -fL --progress-bar "${RELEASE_URL}" -o "${DMG_PATH}" || {
        echo -e "${YELLOW}提示：线上公开发行包尚未同步至 CDN，请先使用本地构建：make dmg${RESET}"
        exit 1
    }

    echo -e "==> 挂载磁盘镜像..."
    MOUNT_POINT="${TEMP_DIR}/mount"
    mkdir -p "${MOUNT_POINT}"
    hdiutil attach "${DMG_PATH}" -mountpoint "${MOUNT_POINT}" -nobrowse -quiet

    echo -e "==> 复制应用到 /Applications..."
    rm -rf "${DEST}"
    cp -R "${MOUNT_POINT}/Sirius.app" "${DEST}"

    hdiutil detach "${MOUNT_POINT}" -quiet
fi

# 4. 彻底移除 macOS Gatekeeper 隔离属性（免证书秒开核心）
echo -e "==> 解除 macOS Gatekeeper 隔离标记..."
xattr -cr "${DEST}" 2>/dev/null || true

echo -e "${GREEN}${BOLD}✓ Sirius 安装成功！${RESET}"
echo -e "-----------------------------------------------------"
echo -e "  启动方式：在访达、启动台或终端中运行："
echo -e "  ${CYAN}open /Applications/Sirius.app${RESET}"
echo -e "  默认快捷键：${BOLD}⌥ + S (Option + S)${RESET} 一键启闭调光"
echo -e "-----------------------------------------------------"
