#!/bin/bash
set -euo pipefail

APP="/Applications/WaifuX.app"
APPCAST_URL="https://jipika.github.io/WaifuX/appcast.xml"
PATCH_REPO="ZhiWang-Andy/waifux-intel-builder"
SUPPORT_DIR="$HOME/Library/Application Support/WaifuX Intel Updater"
BACKUP_DIR="$SUPPORT_DIR/Backups"
TMP="$(mktemp -d /tmp/waifux-intel-update.XXXXXX)"
MOUNT_POINT=""
BACKUP_APP=""
REPLACED_APP=0

cleanup() {
  local status=$?
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
  if [[ $status -ne 0 && $REPLACED_APP -eq 1 && -n "$BACKUP_APP" && -d "$BACKUP_APP" ]]; then
    echo
    echo "Update failed after replacing WaifuX. Restoring backup..."
    sudo rm -rf "$APP" || true
    sudo ditto "$BACKUP_APP" "$APP" || true
    echo "Backup restored: $BACKUP_APP"
  fi
  exit $status
}
trap cleanup EXIT INT TERM

say() { printf '\n=== %s ===\n' "$1"; }

[[ "$(uname -m)" == "x86_64" ]] || { echo "ERROR: Intel x86_64 Mac required."; exit 1; }
mkdir -p "$BACKUP_DIR"

say "Checking official WaifuX update feed"
curl -fsSL --retry 3 --retry-delay 2 "$APPCAST_URL" -o "$TMP/appcast.xml"
LATEST_VERSION=$(grep -Eo '<sparkle:shortVersionString>[^<]+' "$TMP/appcast.xml" | head -1 | sed 's#.*>##')
DMG_URL=$(grep -Eo 'url="[^"]*WaifuX\.dmg"' "$TMP/appcast.xml" | head -1 | sed 's#^url="##; s#"$##')
[[ -n "$LATEST_VERSION" && -n "$DMG_URL" ]] || { echo "ERROR: Could not parse official appcast."; exit 1; }

INSTALLED_VERSION="none"
if [[ -d "$APP" ]]; then
  INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo unknown)
fi
PATCH_URL="https://github.com/${PATCH_REPO}/releases/download/intel-v${LATEST_VERSION}/WaifuX-Intel-Patch-v${LATEST_VERSION}-macOS-x86_64.zip"

echo "Installed version: $INSTALLED_VERSION"
echo "Latest official:   $LATEST_VERSION"
echo "Official DMG:      $DMG_URL"
echo "Intel patch:       $PATCH_URL"

VIDEO="$APP/Contents/Resources/Resources/wallpaper-video-renderer"
CLI="$APP/Contents/Resources/Resources/wallpaperengine-cli"
if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]] \
   && file "$VIDEO" 2>/dev/null | grep -q 'x86_64' \
   && file "$CLI" 2>/dev/null | grep -q 'x86_64' \
   && codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q 'com.apple.security.cs.disable-library-validation'; then
  echo "WaifuX $LATEST_VERSION is already installed with the Intel helpers and signing fix."
  exit 0
fi

say "Checking matching Intel patch"
curl -fsIL --retry 2 --retry-delay 2 "$PATCH_URL" >/dev/null || { echo "Matching Intel patch is not ready yet. No changes made."; exit 3; }

say "Downloading official WaifuX and Intel patch"
curl -fL --retry 3 --retry-delay 2 "$DMG_URL" -o "$TMP/WaifuX.dmg"
curl -fL --retry 3 --retry-delay 2 "$PATCH_URL" -o "$TMP/IntelPatch.zip"

say "Mounting and verifying official WaifuX"
hdiutil attach "$TMP/WaifuX.dmg" -nobrowse -readonly > "$TMP/hdiutil.txt"
MOUNT_POINT=$(sed -n 's#^.*\(/Volumes/.*\)$#\1#p' "$TMP/hdiutil.txt" | head -1)
[[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]] || { echo "ERROR: Could not determine mounted DMG path."; cat "$TMP/hdiutil.txt"; exit 1; }
NEW_APP=$(find "$MOUNT_POINT" -maxdepth 2 -type d -name 'WaifuX.app' -print -quit)
[[ -d "$NEW_APP" ]] || { echo "ERROR: WaifuX.app not found in DMG."; exit 1; }
NEW_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$NEW_APP/Contents/Info.plist" 2>/dev/null || echo unknown)
[[ "$NEW_VERSION" == "$LATEST_VERSION" ]] || { echo "ERROR: DMG version mismatch."; exit 1; }
codesign --verify --deep --strict --verbose=2 "$NEW_APP"
spctl --assess --type execute --verbose=2 "$NEW_APP"

say "Verifying Intel patch"
mkdir -p "$TMP/patch"
unzip -q "$TMP/IntelPatch.zip" -d "$TMP/patch"
PATCH_VIDEO=$(find "$TMP/patch" -type f -name 'wallpaper-video-renderer' -print -quit)
PATCH_CLI=$(find "$TMP/patch" -type f -name 'wallpaperengine-cli' -print -quit)
[[ -f "$PATCH_VIDEO" && -f "$PATCH_CLI" ]] || { echo "ERROR: Patch helpers missing."; exit 1; }
file "$PATCH_VIDEO" | grep -q 'x86_64' || { echo "ERROR: video helper not x86_64"; exit 1; }
file "$PATCH_CLI" | grep -q 'x86_64' || { echo "ERROR: CLI helper not x86_64"; exit 1; }

# Preserve the pristine upstream outer-app entitlements and add the narrow
# Hardened Runtime exception needed after the outer app becomes ad-hoc signed.
APP_ENT="$TMP/app-entitlements.plist"
codesign -d --entitlements :- "$NEW_APP" > "$APP_ENT" 2>/dev/null || true
if ! plutil -lint "$APP_ENT" >/dev/null 2>&1; then
  cat > "$APP_ENT" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
EOF
fi
/usr/libexec/PlistBuddy -c "Set :com.apple.security.cs.disable-library-validation true" "$APP_ENT" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$APP_ENT"

say "Administrator authorization"
sudo -v

say "Closing WaifuX"
osascript -e 'tell application "WaifuX" to quit' 2>/dev/null || true
pkill -f '/WaifuX.app/' 2>/dev/null || true
pkill -f 'wallpaper-video-renderer' 2>/dev/null || true
pkill -f 'wallpaperengine-cli' 2>/dev/null || true
sleep 2

say "Backing up current installation"
if [[ -d "$APP" ]]; then
  STAMP=$(date +%Y%m%d-%H%M%S)
  BACKUP_APP="$BACKUP_DIR/WaifuX-${INSTALLED_VERSION}-${STAMP}.app"
  ditto "$APP" "$BACKUP_APP"
  echo "Backup: $BACKUP_APP"
fi

say "Installing fresh official WaifuX $LATEST_VERSION"
sudo rm -rf "$APP"
sudo ditto "$NEW_APP" "$APP"
REPLACED_APP=1
codesign --verify --deep --strict --verbose=2 "$APP"

DEST="$APP/Contents/Resources/Resources"
[[ -d "$DEST" ]] || { echo "ERROR: Missing resources directory: $DEST"; exit 1; }

say "Applying Intel x86_64 Video/Web helpers"
sudo cp "$PATCH_VIDEO" "$DEST/wallpaper-video-renderer"
sudo cp "$PATCH_CLI" "$DEST/wallpaperengine-cli"
sudo chmod 755 "$DEST/wallpaper-video-renderer" "$DEST/wallpaperengine-cli"
sudo codesign --force --sign - "$DEST/wallpaper-video-renderer"
sudo codesign --force --sign - "$DEST/wallpaperengine-cli"

say "Disabling built-in Sparkle automatic checks"
sudo /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$APP/Contents/Info.plist" 2>/dev/null || true

say "Re-signing outer app with the library-validation exception"
# Do not --deep re-sign here. Keep upstream nested code such as Sparkle.framework
# signed by the original developer. The outer locally modified app is ad-hoc
# signed and explicitly allowed to load differently signed embedded frameworks.
sudo codesign --force --sign - --options runtime --entitlements "$APP_ENT" "$APP"

say "Verifying patched application"
codesign --verify --deep --strict --verbose=2 "$APP"
file "$DEST/wallpaper-video-renderer" | grep -q 'x86_64'
file "$DEST/wallpaperengine-cli" | grep -q 'x86_64'
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q 'com.apple.security.cs.disable-library-validation' || { echo "ERROR: signing fix entitlement missing."; exit 1; }

REPLACED_APP=0
ls -1dt "$BACKUP_DIR"/WaifuX-*.app 2>/dev/null | tail -n +4 | while IFS= read -r old; do rm -rf "$old" || true; done

say "Update complete"
echo "WaifuX $LATEST_VERSION is installed and patched for Intel Video/Web."
echo "The Sparkle Team-ID launch crash is handled by Disable Library Validation on the locally signed outer app."
echo "Use this external updater for future updates."
open "$APP"
