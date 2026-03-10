#!/bin/zsh
set -euo pipefail

APP_NAME="PosterStudio"
VERSION="${1:-0.1.0}"
BUILD_DIR="${2:-.build/release}"
DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
EXECUTABLE_PATH="${BUILD_DIR}/${APP_NAME}"

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "Missing executable: ${EXECUTABLE_PATH}" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources" "${DIST_DIR}"
cp "${EXECUTABLE_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
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
