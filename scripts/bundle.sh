#!/bin/zsh
# Build a release binary and wrap it in a double-clickable, ad-hoc-signed Lanternwright.app.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
APP=Lanternwright.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Lanternwright "$APP/Contents/MacOS/Lanternwright"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Lanternwright</string>
  <key>CFBundleDisplayName</key><string>Lanternwright</string>
  <key>CFBundleIdentifier</key><string>io.supermanzer.lanternwright</string>
  <key>CFBundleExecutable</key><string>Lanternwright</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.adventure-games</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"
echo "Built $APP"
