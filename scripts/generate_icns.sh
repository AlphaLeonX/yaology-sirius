#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SOURCE_IMG="${1:-${ROOT_DIR}/assets/icons/01_gravitational_eclipse.jpg}"

if [ ! -f "${SOURCE_IMG}" ]; then
    echo "Error: Source image not found at: ${SOURCE_IMG}"
    exit 1
fi

echo "==> Generating AppIcon.icns from: $(basename "${SOURCE_IMG}")..."

ICONSET_DIR="${ROOT_DIR}/assets/AppIcon.iconset"
OUTPUT_ICNS="${ROOT_DIR}/assets/AppIcon.icns"
BUILDER_BIN="${SCRIPT_DIR}/build_retina_iconset"

# Ensure builder binary is compiled
if [ ! -x "${BUILDER_BIN}" ]; then
    echo "==> Compiling build_retina_iconset..."
    swiftc -O "${SCRIPT_DIR}/build_retina_iconset.swift" -o "${BUILDER_BIN}"
fi

# Run the optical multi-scale builder
echo "==> Running optical multi-scale icon engine..."
"${BUILDER_BIN}" "${SOURCE_IMG}" "${ICONSET_DIR}"

# Compile into .icns
echo "==> Compiling iconset into .icns..."
iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICNS}"
rm -rf "${ICONSET_DIR}"

echo "==> Successfully generated: ${OUTPUT_ICNS} ($(du -h "${OUTPUT_ICNS}" | cut -f1))"
