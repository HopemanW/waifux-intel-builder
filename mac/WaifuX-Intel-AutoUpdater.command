#!/bin/bash
set -euo pipefail

# WaifuX Intel external updater
# Uses the same official appcast as WaifuX/Sparkle, installs a fresh official DMG,
# applies the matching x86_64 helper patch, and ad-hoc re-signs the modified app.

APP="/Applications/WaifuX.app"
APPCAST_URL="https://jipika.github.io/WaifuX/appcast.xml"
PATCH_REPO="HopemanW/waifux-intel-builder"
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

say() {
  printf '\n=== %s ===\n' "$1"
}

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "ERROR: This updater is only for Intel x86_64 Macs."
  echo "Detected: $(uname -m)"
  exit 1
fi

mkdir -p "$BACKUP_DIR"

say "Checking the official WaifuX update feed"
curl -fsSL --retry 3 --retry-delay 2 "$APPCAST_URL" -o "$TMP/appcast.xml"

LATEST_VERSION=$(sed -n 's:.*<sparkle:shortVersionString>\([^<]*\)</sparkle:shortVersionString>.*:\1:p' "$TMP/appcast.xml" | head -1)
DMG_URL=$(sed -n 's:.*url="\([^"]*WaifuX\.dmg\)".*:\1:p' "$TMP/appcast.xml" | head -1)

if [[ -z "$LATEST_VERSION" || -z "$DMG_URL" ]]; then
  echo "ERROR: Could not parse the official WaifuX appcast."
  exit 1
fi

INSTALLED_VERSION="none"
if [[ -d "$APP" ]]; then
  INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "unknown")
fi

PATCH_URL="https://github.com/${PATCH_REPO}/releases/download/intel-v${LATEST_VERSION}/WaifuX-Intel-Patch-v${LATEST_VERSION}-macOS-x86_64.zip"

echo "Installed version: $INSTALLED_VERSION"
echo "Latest official:   $LATEST_VERSION"
echo "Official DMG:      $DMG_URL"
echo "Intel patch:       $PATCH_URL"

CURRENT_VIDEO_ARCH="missing"
CURRENT_CLI_ARCH="missing"
if [[ -f "$APP/Contents/Resources/Resources/wallpaper-video-renderer" ]]; then
  CURRENT_VIDEO_ARCH=$(file "$APP/Contents/Resources/Resources/wallpaper-video-renderer")
fi
if [[ -f "$APP/Contents/Resources/Resources/wallpaperengine-cli" ]]; then
  CURRENT_CLI_ARCH=$(file "$APP/Contents/Resources/Resources/wallpaperengine-cli")
fi

if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]] \
   && echo "$CURRENT_VIDEO_ARCH" | grep -q 'x86_64' \
   && echo "$CURRENT_CLI_ARCH" | grep -q 'x86_64'; then
  echo
  echo "WaifuX $LATEST_VERSION is already installed and both Intel helpers are present."
  exit 0
fi

say "Checking whether the matching Intel patch is ready"
if ! curl -fsIL --retry 2 --retry-delay 2 "$PATCH_URL" >/dev/null; then
  echo "The official WaifuX update is available, but the matching Intel patch is not published yet."
  echo "The GitHub Actions watcher normally builds it automatically within about 30–60 minutes."
  echo "Please run this updater again later."
  exit 3
fi

echo "Matching Intel patch is ready."

say "Downloading official WaifuX and Intel patch"
curl -fL --retry 3 --retry-delay 2 "$DMG_URL" -o "$TMP/WaifuX.dmg"
curl -fL --retry 3 --retry-delay 2 "$PATCH_URL" -o "$TMP/IntelPatch.zip"

say "Mounting and verifying the official WaifuX DMG"
hdiutil attach "$TMP/WaifuX.dmg" -nobrowse -readonly > "$TMP/hdiutil.txt"
MOUNT_POINT=$(sed -n 's#^.*\(/Volumes/.*\)$#\1#p' "$TMP/hdiutil.txt" | head -1)

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "ERROR: Could not determine the mounted DMG path."
  cat "$TMP/hdiutil.txt"
  exit 1
fi

NEW_APP=$(find "$MOUNT_POINT" -maxdepth 2 -type d -name 'WaifuX.app' -print -quit)
if [[ -z "$NEW_APP" || ! -d "$NEW_APP" ]]; then
  echo "ERROR: WaifuX.app was not found inside the official DMG."
  exit 1
fi

NEW_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$NEW_APP/Contents/Info.plist" 2>/dev/null || echo "unknown")
if [[ "$NEW_VERSION" != "$LATEST_VERSION" ]]; then
  echo "ERROR: Official DMG version mismatch: expected $LATEST_VERSION, found $NEW_VERSION"
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$NEW_APP"
if ! spctl --assess --type execute --verbose=2 "$NEW_APP"; then
  echo "ERROR: macOS Gatekeeper did not accept the downloaded official WaifuX app."
  echo "For safety, this updater will not install it."
  exit 1
fi

echo "Official WaifuX signature/Gatekeeper verification passed."

say "Verifying Intel patch"
mkdir -p "$TMP/patch"
unzip -q "$TMP/IntelPatch.zip" -d "$TMP/patch"
PATCH_VIDEO=$(find "$TMP/patch" -type f -name 'wallpaper-video-renderer' -print -quit)
PATCH_CLI=$(find "$TMP/patch" -type f -name 'wallpaperengine-cli' -print -quit)

if [[ -z "$PATCH_VIDEO" || -z "$PATCH_CLI" ]]; then
  echo "ERROR: Required helper binaries are missing from the Intel patch archive."
  exit 1
fi

file "$PATCH_VIDEO"
file "$PATCH_CLI"
file "$PATCH_VIDEO" | grep -q 'x86_64' || { echo "ERROR: video renderer is not x86_64"; exit 1; }
file "$PATCH_CLI" | grep -q 'x86_64' || { echo "ERROR: wallpaperengine-cli is not x86_64"; exit 1; }

say "Administrator authorization"
echo "The next steps replace /Applications/WaifuX.app and re-sign the modified Intel build."
sudo -v

say "Closing WaifuX"
osascript -e 'tell application "WaifuX" to quit' 2>/dev/null || true
pkill -f '/WaifuX.app/' 2>/dev/null || true
pkill -f 'wallpaper-video-renderer' 2>/dev/null || true
pkill -f 'wallpaperengine-cli' 2>/dev/null || true
sleep 2

say "Backing up the current installation"
if [[ -d "$APP" ]]; then
  STAMP=$(date +%Y%m%d-%H%M%S)
  BACKUP_APP="$BACKUP_DIR/WaifuX-${INSTALLED_VERSION}-${STAMP}.app"
  ditto "$APP" "$BACKUP_APP"
  echo "Backup: $BACKUP_APP"
fi

say "Installing the fresh official WaifuX $LATEST_VERSION"
sudo rm -rf "$APP"
sudo ditto "$NEW_APP" "$APP"
REPLACED_APP=1

# Verify the pristine official copy one more time before modifying it.
codesign --verify --deep --strict --verbose=2 "$APP"

DEST="$APP/Contents/Resources/Resources"
if [[ ! -d "$DEST" ]]; then
  echo "ERROR: Expected resources directory is missing: $DEST"
  exit 1
fi

say "Applying Intel x86_64 Video/Web helpers"
sudo cp "$PATCH_VIDEO" "$DEST/wallpaper-video-renderer"
sudo cp "$PATCH_CLI" "$DEST/wallpaperengine-cli"
sudo chmod 755 "$DEST/wallpaper-video-renderer" "$DEST/wallpaperengine-cli"

file "$DEST/wallpaper-video-renderer"
file "$DEST/wallpaperengine-cli"

say "Disabling Sparkle automatic installation for the locally re-signed build"
# Once we modify and ad-hoc sign WaifuX, its signing identity no longer matches the
# upstream Developer ID identity. Sparkle will reject a future in-app update.
# The external Intel updater watches the exact same official appcast instead.
sudo /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$APP/Contents/Info.plist" 2>/dev/null || true

say "Re-signing the Intel-modified WaifuX"
sudo codesign --force --sign - "$DEST/wallpaper-video-renderer"
sudo codesign --force --sign - "$DEST/wallpaperengine-cli"
sudo codesign --force --deep --sign - \
  --preserve-metadata=identifier,entitlements,flags,runtime \
  "$APP"

say "Verifying the patched application"
codesign --verify --deep --strict --verbose=2 "$APP"

FINAL_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "Installed WaifuX: $FINAL_VERSION"
file "$DEST/wallpaper-video-renderer"
file "$DEST/wallpaperengine-cli"

if ! file "$DEST/wallpaper-video-renderer" | grep -q 'x86_64'; then
  echo "ERROR: Final video renderer is not x86_64."
  exit 1
fi
if ! file "$DEST/wallpaperengine-cli" | grep -q 'x86_64'; then
  echo "ERROR: Final wallpaperengine-cli is not x86_64."
  exit 1
fi

REPLACED_APP=0

# Keep only the newest three backups.
ls -1dt "$BACKUP_DIR"/WaifuX-*.app 2>/dev/null | tail -n +4 | while IFS= read -r old; do
  rm -rf "$old" || true
done

say "Update complete"
echo "WaifuX $LATEST_VERSION has been installed and patched for Intel Video/Web."
echo "Wallpaper Engine Scene is still not patched."
echo "Use this external updater for future updates instead of WaifuX's built-in Sparkle installer."
echo
echo "Opening WaifuX..."
open "$APP"
