#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_ICNS="${1:-${ROOT_DIR}/Assets/AppIcon.icns}"
RENDER_SCRIPT="${SCRIPT_DIR}/render_app_icon.swift"
ICNS_BUILDER="${SCRIPT_DIR}/build_icns.py"

if [[ ! -f "${RENDER_SCRIPT}" ]]; then
  echo "Missing icon renderer: ${RENDER_SCRIPT}" >&2
  exit 1
fi

if [[ ! -f "${ICNS_BUILDER}" ]]; then
  echo "Missing ICNS builder: ${ICNS_BUILDER}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_ICNS}")"

TMP_DIR="$(mktemp -d /tmp/posterstudio-icon.XXXXXX)"
MODULE_CACHE_DIR="${ROOT_DIR}/.build/icon-module-cache"
trap 'rm -rf "${TMP_DIR}"' EXIT

MASTER_PNG="${TMP_DIR}/AppIcon.png"

mkdir -p "${MODULE_CACHE_DIR}"
swift -module-cache-path "${MODULE_CACHE_DIR}" "${RENDER_SCRIPT}" "${MASTER_PNG}" >/dev/null

if [[ ! -f "${MASTER_PNG}" ]]; then
  echo "Failed to render icon preview" >&2
  exit 1
fi

render_icon() {
  local size="$1"
  local name="$2"
  sips -z "${size}" "${size}" "${MASTER_PNG}" --out "${TMP_DIR}/${name}" >/dev/null
}

render_icon 16 icon_16.png
render_icon 32 icon_32.png
render_icon 64 icon_64.png
render_icon 128 icon_128.png
render_icon 256 icon_256.png
render_icon 512 icon_512.png
render_icon 1024 icon_1024.png

python3 "${ICNS_BUILDER}" "${OUTPUT_ICNS}" \
  "${TMP_DIR}/icon_16.png" \
  "${TMP_DIR}/icon_32.png" \
  "${TMP_DIR}/icon_64.png" \
  "${TMP_DIR}/icon_128.png" \
  "${TMP_DIR}/icon_256.png" \
  "${TMP_DIR}/icon_512.png" \
  "${TMP_DIR}/icon_1024.png"

echo "Created ${OUTPUT_ICNS}"
