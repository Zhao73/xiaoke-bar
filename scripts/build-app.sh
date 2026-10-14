#!/bin/zsh
# 编译并打包成 小克额度栏.app（本机自签名），默认装到 ~/Applications
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="1.1.0"
APP="dist/小克额度栏.app"
swift build -c release --arch arm64
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Logos"
cp .build/release/XiaokeBar "$APP/Contents/MacOS/XiaokeBar"
cp Resources/Logos/*.pdf "$APP/Contents/Resources/Logos/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>小克额度栏</string>
  <key>CFBundleDisplayName</key><string>小克额度栏</string>
  <key>CFBundleIdentifier</key><string>com.zjp73.xiaokebar</string>
  <key>CFBundleExecutable</key><string>XiaokeBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>点桌面宠物的气泡时，切到这个会话所在的终端标签页。</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP"
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/小克额度栏.app
  cp -R "$APP" ~/Applications/
  echo "已安装到 ~/Applications/小克额度栏.app"
fi
echo "打包完成：$APP"
