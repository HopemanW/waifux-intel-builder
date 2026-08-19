#!/bin/bash
set -euo pipefail

REPO="HopemanW/waifux-intel-builder"
SUPPORT_DIR="$HOME/Library/Application Support/WaifuX Intel Updater"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENTS/com.hopemanw.waifux-intel-updater.plist"
UPDATER="$SUPPORT_DIR/WaifuX-Intel-AutoUpdater.command"
CHECKER="$SUPPORT_DIR/check-for-waifux-update.sh"
RAW_UPDATER="https://raw.githubusercontent.com/${REPO}/main/mac/WaifuX-Intel-AutoUpdater.command"

mkdir -p "$SUPPORT_DIR" "$LAUNCH_AGENTS"

printf '\n=== Installing WaifuX Intel automatic update checker ===\n'

curl -fsSL --retry 3 "$RAW_UPDATER" -o "$UPDATER"
chmod 755 "$UPDATER"

cat > "$CHECKER" <<'EOS'
#!/bin/bash
set -u

APP="/Applications/WaifuX.app"
APPCAST="https://jipika.github.io/WaifuX/appcast.xml"
REPO="HopemanW/waifux-intel-builder"
SUPPORT_DIR="$HOME/Library/Application Support/WaifuX Intel Updater"
UPDATER="$SUPPORT_DIR/WaifuX-Intel-AutoUpdater.command"
STATE="$SUPPORT_DIR/last-prompt.txt"
RAW_UPDATER="https://raw.githubusercontent.com/${REPO}/main/mac/WaifuX-Intel-AutoUpdater.command"
TMP="$(mktemp /tmp/waifux-intel-check.XXXXXX)"
trap 'rm -f "$TMP"' EXIT

[[ "$(uname -m)" == "x86_64" ]] || exit 0
curl -fsSL --retry 2 "$APPCAST" -o "$TMP" || exit 0

LATEST=$(sed -n 's:.*<sparkle:shortVersionString>\([^<]*\)</sparkle:shortVersionString>.*:\1:p' "$TMP" | head -1)
[[ -n "$LATEST" ]] || exit 0

INSTALLED="none"
if [[ -d "$APP" ]]; then
  INSTALLED=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo unknown)
fi

VIDEO_OK=0
CLI_OK=0
file "$APP/Contents/Resources/Resources/wallpaper-video-renderer" 2>/dev/null | grep -q 'x86_64' && VIDEO_OK=1
file "$APP/Contents/Resources/Resources/wallpaperengine-cli" 2>/dev/null | grep -q 'x86_64' && CLI_OK=1

if [[ "$INSTALLED" == "$LATEST" && $VIDEO_OK -eq 1 && $CLI_OK -eq 1 ]]; then
  exit 0
fi

PATCH_URL="https://github.com/${REPO}/releases/download/intel-v${LATEST}/WaifuX-Intel-Patch-v${LATEST}-macOS-x86_64.zip"
curl -fsIL --retry 1 "$PATCH_URL" >/dev/null 2>&1 || exit 0

# Avoid repeatedly interrupting the user. If postponed, ask again after 6 hours.
NOW=$(date +%s)
if [[ -f "$STATE" ]]; then
  IFS='|' read -r OLD_VERSION OLD_TIME < "$STATE" || true
  OLD_TIME=${OLD_TIME:-0}
  if [[ "$OLD_VERSION" == "$LATEST" ]] && (( NOW - OLD_TIME < 21600 )); then
    exit 0
  fi
fi

printf '%s|%s\n' "$LATEST" "$NOW" > "$STATE"

# Refresh the updater itself before offering the update.
if curl -fsSL --retry 2 "$RAW_UPDATER" -o "$UPDATER.tmp"; then
  mv "$UPDATER.tmp" "$UPDATER"
  chmod 755 "$UPDATER"
fi

RESULT=$(osascript <<OSA 2>/dev/null || true
display dialog "WaifuX ${LATEST} 已发布，并且对应的 Intel x86_64 Video/Web 补丁已经构建完成。\n\n当前安装版本：${INSTALLED}\n\n不要使用 WaifuX 内置更新器；修改后的应用签名与官方 Developer ID 不同，Sparkle 会拒绝更新。" buttons {"稍后", "现在更新"} default button "现在更新" with title "WaifuX Intel Update Ready"
OSA
)

if echo "$RESULT" | grep -q '现在更新'; then
  open -a Terminal "$UPDATER"
fi
EOS

chmod 755 "$CHECKER"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.hopemanw.waifux-intel-updater</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$CHECKER</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>1800</integer>
  <key>StandardOutPath</key>
  <string>$SUPPORT_DIR/checker.log</string>
  <key>StandardErrorPath</key>
  <string>$SUPPORT_DIR/checker-error.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/com.hopemanw.waifux-intel-updater" >/dev/null 2>&1 || true

cat > "$SUPPORT_DIR/UNINSTALL_AUTO_CHECK.command" <<'EOS'
#!/bin/bash
set -euo pipefail
PLIST="$HOME/Library/LaunchAgents/com.hopemanw.waifux-intel-updater.plist"
SUPPORT_DIR="$HOME/Library/Application Support/WaifuX Intel Updater"
launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"
echo "Automatic update checking disabled. Backups and updater files remain in:"
echo "  $SUPPORT_DIR"
EOS
chmod 755 "$SUPPORT_DIR/UNINSTALL_AUTO_CHECK.command"

printf '\nInstalled successfully.\n'
echo "The checker runs at login and every 30 minutes."
echo "It watches WaifuX's official appcast and only prompts after the matching Intel patch is ready."
echo "Updater: $UPDATER"
echo "Uninstaller: $SUPPORT_DIR/UNINSTALL_AUTO_CHECK.command"
echo
echo "A check has been started now. If the new Intel patch is already published, you should receive a prompt shortly."
