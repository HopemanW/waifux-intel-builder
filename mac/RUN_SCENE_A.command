#!/bin/bash
set -euo pipefail

WORKROOT="$HOME/Library/Application Support/WaifuX Intel Scene Experimental"
BIN="$WORKROOT/bin/linux-wallpaper-engine"
DEFAULT_TEST="$HOME/Desktop/WaifuX-Scene-Testset/A-basic-2947302287"
TEST_ROOT="${1:-$DEFAULT_TEST}"
MODE="${SCENE_MODE:-static}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "Run this on macOS."
[[ "$(uname -m)" == "x86_64" ]] || fail "This test is intended for an Intel Mac."
[[ -x "$BIN" ]] || fail "Experimental renderer not found. Run BUILD_SCENE_EXPERIMENTAL.command first."
[[ -d "$TEST_ROOT" ]] || fail "Scene test folder not found: $TEST_ROOT"

PKG="$(find "$TEST_ROOT" -type f -name 'scene.pkg' -print -quit)"
[[ -n "$PKG" ]] || fail "No scene.pkg found under: $TEST_ROOT"

echo "=== WaifuX Intel Scene Tier A Test ==="
echo "Renderer: $BIN"
echo "Scene:    $PKG"
echo "Mode:     $MODE"
echo
echo "The renderer opens a fullscreen test surface."
echo "Return to this Terminal and press Ctrl+C to stop it."
echo

export WGPU_BACKEND=metal
export RUST_BACKTRACE=1

if [[ "$MODE" == "full" ]]; then
  exec "$BIN" -p "$PKG" -m winit --target-fps 30 -l debug
else
  exec "$BIN" -p "$PKG" -m winit --no-effects -l debug
fi
