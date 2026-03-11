#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
SWIFT_CACHE_ENV=(
  "CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache"
  "SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swift-module-cache"
)
APP_NAME="PosterStudio"
VERSION="${1:-0.1.0}"
if [[ $# -ge 2 ]]; then
  BUILD_DIR="$2"
else
  BUILD_DIR="$(cd "${PROJECT_DIR}" && env "${SWIFT_CACHE_ENV[@]}" swift build -c release --show-bin-path)"
fi
DIST_DIR="${PROJECT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
EXECUTABLE_PATH="${BUILD_DIR}/${APP_NAME}"
ICON_PREVIEW_PATH="${DIST_DIR}/AppIcon-preview.png"
ICON_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/posterstudio-icon.XXXXXX")"
ICONSET_DIR="${ICON_WORK_DIR}/AppIcon.iconset"
ICON_PATH="${ICON_WORK_DIR}/AppIcon.icns"

trap 'rm -rf "${ICON_WORK_DIR}"' EXIT

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "Missing executable: ${EXECUTABLE_PATH}" >&2
  exit 1
fi

env "${SWIFT_CACHE_ENV[@]}" swift "${SCRIPT_DIR}/generate_app_icon.swift" "${ICONSET_DIR}" "${ICON_PREVIEW_PATH}"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

sips -z 16 16 "${ICON_PREVIEW_PATH}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
sips -z 32 32 "${ICON_PREVIEW_PATH}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${ICON_PREVIEW_PATH}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
sips -z 64 64 "${ICON_PREVIEW_PATH}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${ICON_PREVIEW_PATH}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
sips -z 256 256 "${ICON_PREVIEW_PATH}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${ICON_PREVIEW_PATH}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
sips -z 512 512 "${ICON_PREVIEW_PATH}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${ICON_PREVIEW_PATH}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "${ICON_PREVIEW_PATH}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

iconutil -c icns "${ICONSET_DIR}" -o "${ICON_PATH}"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources" "${DIST_DIR}"
cp "${EXECUTABLE_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "${ICON_PATH}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.indincys.posterstudio</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSArchitecturePriority</key>
  <array>
    <string>arm64</string>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${DIST_DIR}/${APP_NAME}-arm64-${VERSION}.zip"

echo "Created ${DIST_DIR}/${APP_NAME}-arm64-${VERSION}.zip"
