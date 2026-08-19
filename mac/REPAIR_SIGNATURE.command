#!/bin/bash
set -euo pipefail

APP="/Applications/WaifuX.app"
TMP="$(mktemp -d /tmp/waifux-sign-repair.XXXXXX)"
ENT="$TMP/app-entitlements.plist"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "ERROR: This repair is intended for Intel x86_64 Macs."
  exit 1
fi

if [[ ! -d "$APP" ]]; then
  echo "ERROR: $APP not found."
  exit 1
fi

echo "WaifuX version:"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || true

echo
echo "Current main executable signature:"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'Identifier=|TeamIdentifier=|Runtime Version|flags=' || true

echo
echo "Current Sparkle signature:"
codesign -dv --verbose=4 "$APP/Contents/Frameworks/Sparkle.framework" 2>&1 | grep -E 'Identifier=|TeamIdentifier=|Runtime Version|flags=' || true

# Preserve the app's current entitlements, then add the narrow Hardened Runtime
# exception that allows a locally ad-hoc signed main executable to load the
# upstream Developer-ID-signed Sparkle framework.
codesign -d --entitlements :- "$APP" > "$ENT" 2>/dev/null || true
if ! plutil -lint "$ENT" >/dev/null 2>&1; then
  cat > "$ENT" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EOF
fi

/usr/libexec/PlistBuddy -c "Set :com.apple.security.cs.disable-library-validation true" "$ENT" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENT"

echo
echo "Repair entitlement:"
/usr/libexec/PlistBuddy -c "Print :com.apple.security.cs.disable-library-validation" "$ENT"

echo
echo "Administrator authorization is required to re-sign /Applications/WaifuX.app."
sudo -v

osascript -e 'tell application "WaifuX" to quit' 2>/dev/null || true
pkill -f '/WaifuX.app/' 2>/dev/null || true
pkill -f 'wallpaper-video-renderer' 2>/dev/null || true
pkill -f 'wallpaperengine-cli' 2>/dev/null || true
sleep 1

DEST="$APP/Contents/Resources/Resources"
for BIN in wallpaper-video-renderer wallpaperengine-cli; do
  if [[ -f "$DEST/$BIN" ]]; then
    sudo codesign --force --sign - "$DEST/$BIN"
  fi
done

# Important: do NOT --deep re-sign Sparkle or the app extension. Keep upstream
# nested code signatures intact and only re-sign the outer app with the library
# validation exception.
sudo codesign --force --sign - --options runtime --entitlements "$ENT" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

echo
echo "Final app entitlements:"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -A2 -B2 'disable-library-validation' || true

echo
echo "Repair complete. Opening WaifuX..."
open "$APP"
