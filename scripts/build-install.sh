#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if pgrep -x CodexSpeed >/dev/null; then
  echo "请先退出 CodexSpeed 及只读探测进程，再安装更新。"
  exit 1
fi
swift build -c release
root="$PWD"
app="$root/dist/CodexSpeed.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$HOME/Applications"
cp .build/release/CodexSpeed "$app/Contents/MacOS/CodexSpeed"
# The app loads its bundled vocabulary directly; SwiftPM supplies test resources.
cp Sources/MonitorCore/o200k_base.tiktoken "$app/Contents/Resources/"
cp Vendor/swift-tiktoken/LICENSE "$app/Contents/Resources/SwiftTiktoken-LICENSE"
cp Vendor/tiktoken-LICENSE "$app/Contents/Resources/Tiktoken-LICENSE"
cp LICENSE "$app/Contents/Resources/CodexSpeed-LICENSE"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.lmq.CodexSpeed</string>
<key>CFBundleName</key><string>CodexSpeed</string>
<key>CFBundleDisplayName</key><string>CodexSpeed</string>
<key>CFBundleExecutable</key><string>CodexSpeed</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.3</string>
<key>CFBundleVersion</key><string>11</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAccessibilityUsageDescription</key><string>只读识别 Codex 当前查看的对话，用于自动跟随输出速度。</string>
</dict></plist>
PLIST
sign_identity="${CODEX_SPEED_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/"Apple Development:/ {print $2; exit}')}"
if [[ -z "$sign_identity" ]]; then
  echo "缺少 Apple Development 签名证书。请配置本机开发证书，或通过 CODEX_SPEED_SIGN_IDENTITY 指定稳定的签名身份。"
  exit 1
fi
codesign --force --sign "$sign_identity" --identifier local.lmq.CodexSpeed "$app"
codesign --verify --deep --strict "$app"
if pgrep -x CodexSpeed >/dev/null; then
  echo 'CodexSpeed 正在运行；请从菜单栏退出后重新运行此脚本，以安装新版本。'
  exit 1
fi
ditto "$app" "$HOME/Applications/CodexSpeed.app"
echo "已安装：$HOME/Applications/CodexSpeed.app"
