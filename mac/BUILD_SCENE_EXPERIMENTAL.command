#!/bin/bash
set -euo pipefail

UPSTREAM_REPO="https://github.com/wqLouis/linux-wallpaperengine.git"
UPSTREAM_COMMIT="664f2a10f7252f6996da6b4e0d1ac5a2bce364c4"
WORKROOT="$HOME/Library/Application Support/WaifuX Intel Scene Experimental"
SRC="$WORKROOT/src/linux-wallpaperengine"
BIN_DIR="$WORKROOT/bin"
OUT_BIN="$BIN_DIR/linux-wallpaper-engine"

fail() {
  echo
  echo "ERROR: $*" >&2
  exit 1
}

echo "=== WaifuX Intel Scene Experimental Builder ==="
echo

[[ "$(uname -s)" == "Darwin" ]] || fail "This builder must run on macOS."
[[ "$(uname -m)" == "x86_64" ]] || fail "This experimental build is intended for an Intel Mac (x86_64)."

if ! xcode-select -p >/dev/null 2>&1; then
  fail "Xcode Command Line Tools are missing. Run: xcode-select --install"
fi

command -v git >/dev/null 2>&1 || fail "git is required."
command -v python3 >/dev/null 2>&1 || fail "python3 is required."

if ! command -v cargo >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Rust is not installed yet.
Install the official Rust toolchain, then re-run this builder:

  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  source "$HOME/.cargo/env"

EOF
  exit 2
fi

if command -v rustup >/dev/null 2>&1; then
  echo "Updating Rust stable toolchain..."
  rustup update stable
  rustup default stable
fi

mkdir -p "$WORKROOT/src" "$BIN_DIR"

if [[ -d "$SRC/.git" ]]; then
  echo "Refreshing upstream source..."
  git -C "$SRC" fetch --all --tags --prune
else
  echo "Cloning upstream renderer..."
  rm -rf "$SRC"
  git clone --recurse-submodules "$UPSTREAM_REPO" "$SRC"
fi

cd "$SRC"
git reset --hard
git clean -fdx
git checkout "$UPSTREAM_COMMIT"
git submodule sync --recursive
git submodule update --init --recursive

echo "Applying Intel/macOS compatibility + diagnostics patch..."
python3 - "$SRC" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

def replace_once(path: Path, old: str, new: str):
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected patch pattern not found in {path}:\n{old}")
    path.write_text(text.replace(old, new, 1))

# 1) Keep Linux/Wayland-only crates out of the macOS dependency graph.
cargo = root / "Cargo.toml"
text = cargo.read_text()
linux_deps = [
    'smithay-client-toolkit = "0.20.0"',
    'wayland-client = "0.31.12"',
    'wayland-protocols = { version = "0.32", features = ["client", "staging"] }',
]
for dep in linux_deps:
    line = dep + "\n"
    if line not in text:
        raise SystemExit(f"Expected dependency not found in Cargo.toml: {dep}")
    text = text.replace(line, "", 1)
marker = "\n[[example]]\n"
if marker not in text:
    raise SystemExit("Could not locate [[example]] marker in Cargo.toml")
linux_block = "\n[target.'cfg(target_os = \"linux\")'.dependencies]\n" + "\n".join(linux_deps) + "\n"
text = text.replace(marker, linux_block + marker, 1)

# Diagnostic build: upstream release profile uses panic=abort + strip=true.
# That makes texture-thread catch_unwind ineffective and removes useful symbols.
# For Intel bring-up we want panics to unwind, backtraces to contain symbols,
# and the renderer to report the failing stage instead of only producing SIGABRT.
text = text.replace('debug = false', 'debug = true', 1)
text = text.replace('strip = true', 'strip = false', 1)
text = text.replace('panic = "abort"', 'panic = "unwind"', 1)
cargo.write_text(text)

# 2) Do not compile the wlr/Wayland adapter on macOS.
adapters = root / "src/scene/adapters/mod.rs"
replace_once(adapters, "pub mod wlr_app;", '#[cfg(target_os = "linux")]\npub mod wlr_app;')

# 3) Default to winit on macOS and guard the wlr match arm.
main = root / "src/main.rs"
replace_once(
    main,
    "use crate::scene::adapters::{winit_adapter, wlr_app};",
    'use crate::scene::adapters::winit_adapter;\n#[cfg(target_os = "linux")]\nuse crate::scene::adapters::wlr_app;',
)
replace_once(
    main,
    '#[arg(short = \'m\', default_value = "wlr")]',
    '#[arg(short = \'m\', default_value = "winit")]',
)
replace_once(
    main,
    '        "wlr" => wlr_app::start(cli.path, fit_mode, cli.no_effects, cli.no_mdl, cli.assets_path, target_fps, show_progress),',
    '''        "wlr" => {\n            #[cfg(target_os = "linux")]\n            {\n                wlr_app::start(cli.path, fit_mode, cli.no_effects, cli.no_mdl, cli.assets_path, target_fps, show_progress)\n            }\n            #[cfg(not(target_os = "linux"))]\n            {\n                eprintln!("wlr mode is Linux-only; use -m winit on macOS");\n            }\n        },''',
)

# 4) Prefer the discrete AMD GPU and Metal-only backend on this Intel Mac.
app = root / "src/scene/renderer/app.rs"
replace_once(
    app,
    "            backends: Backends::VULKAN | Backends::METAL,",
    '''            backends: if cfg!(target_os = "macos") {\n                Backends::METAL\n            } else {\n                Backends::VULKAN | Backends::METAL\n            },''',
)
replace_once(
    app,
    "                power_preference: PowerPreference::LowPower,",
    "                power_preference: PowerPreference::HighPerformance,",
)
needle = "        let required = Features::TEXTURE_BINDING_ARRAY\n"
if needle not in app.read_text():
    raise SystemExit("Could not locate required-feature block in app.rs")
text = app.read_text().replace(
    needle,
    '        eprintln!("[scene-experimental] WGPU adapter: {:?}", adapter.get_info());\n'
    '        eprintln!("[scene-experimental] WGPU features: {:?}", adapter.features());\n'
    '        eprintln!("[scene-experimental] WGPU limits: {:?}", adapter.limits());\n\n' + needle,
    1,
)
app.write_text(text)

# 5) Catch renderer initialization/load panics inside the winit callback.
# This is especially important on macOS because an uncaught panic during an
# AppKit callback otherwise surfaces as a generic Abort trap crash report.
winit = root / "src/scene/adapters/winit_adapter.rs"
text = winit.read_text()
old = '''        let mut wgpu_app = block_on(WgpuApp::new(
            self.pkg_path.clone(),
            crate::scene::renderer::app::InitAppSurface::Winit(Arc::clone(&window)),
            [size.width, size.height],
            self.no_effects,
            self.no_mdl,
            self.assets_path.clone(),
            self.show_progress,
        ));

        wgpu_app.load();

        self.app.lock().unwrap().replace(wgpu_app);
        self.window = Some(window);'''
new = '''        eprintln!("[scene-experimental] phase=wgpu_init begin");
        let init = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            block_on(WgpuApp::new(
                self.pkg_path.clone(),
                crate::scene::renderer::app::InitAppSurface::Winit(Arc::clone(&window)),
                [size.width, size.height],
                self.no_effects,
                self.no_mdl,
                self.assets_path.clone(),
                self.show_progress,
            ))
        }));

        let mut wgpu_app = match init {
            Ok(app) => {
                eprintln!("[scene-experimental] phase=wgpu_init ok");
                app
            }
            Err(payload) => {
                eprintln!("[scene-experimental] phase=wgpu_init PANIC: {}", panic_payload(&payload));
                event_loop.exit();
                return;
            }
        };

        eprintln!("[scene-experimental] phase=scene_load begin");
        let load = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            wgpu_app.load();
        }));
        if let Err(payload) = load {
            eprintln!("[scene-experimental] phase=scene_load PANIC: {}", panic_payload(&payload));
            event_loop.exit();
            return;
        }
        eprintln!("[scene-experimental] phase=scene_load ok");

        self.app.lock().unwrap().replace(wgpu_app);
        self.window = Some(window);
        self.window.as_ref().unwrap().request_redraw();'''
if old not in text:
    raise SystemExit("Could not locate WgpuApp init/load block in winit_adapter.rs")
text = text.replace(old, new, 1)
insert = '''
fn panic_payload(payload: &Box<dyn std::any::Any + Send>) -> String {
    if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else if let Some(s) = payload.downcast_ref::<&str>() {
        (*s).to_string()
    } else {
        "non-string panic payload".to_string()
    }
}

'''
marker = 'struct WinitApp {'
if marker not in text:
    raise SystemExit("Could not locate WinitApp marker")
text = text.replace(marker, insert + marker, 1)
winit.write_text(text)

# 6) Add explicit load-stage markers so a failing subsystem is obvious.
load = root / "src/scene/renderer/load.rs"
text = load.read_text()
repls = [
    ('        let mut scene = Scene::new(self.scene_path.clone(), self.show_progress);',
     '        eprintln!("[scene-experimental] load=package begin");\n        let mut scene = Scene::new(self.scene_path.clone(), self.show_progress);\n        eprintln!("[scene-experimental] load=package ok objects={} textures={}", scene.root.objects.len(), scene.textures.len());'),
    ('        let post_process =\n            PostProcess::new(&self.device, &self.queue, size, self.has_clear_texture);',
     '        eprintln!("[scene-experimental] load=post_process begin size={}x{}", size[0], size[1]);\n        let post_process =\n            PostProcess::new(&self.device, &self.queue, size, self.has_clear_texture);\n        eprintln!("[scene-experimental] load=post_process ok");'),
    ('        let (pipeline, copy_pipeline) = create_pipelines(&self, &post_process.layout);',
     '        eprintln!("[scene-experimental] load=base_pipelines begin");\n        let (pipeline, copy_pipeline) = create_pipelines(&self, &post_process.layout);\n        eprintln!("[scene-experimental] load=base_pipelines ok");'),
    ('        let objects = ObjectMap::with_clear_color(',
     '        eprintln!("[scene-experimental] load=object_map begin");\n        let objects = ObjectMap::with_clear_color('),
    ('        // Pre-compute total geometry so we can allocate GPU buffers once.',
     '        eprintln!("[scene-experimental] load=object_map ok textures={} audio={}", objects.texture.len(), objects.audio.len());\n\n        // Pre-compute total geometry so we can allocate GPU buffers once.'),
    ('        let draw_queue = DrawQueue::new(',
     '        eprintln!("[scene-experimental] load=draw_queue begin");\n        let draw_queue = DrawQueue::new('),
    ('        load_audios(&self.audio_stream, objects.audio, &scene);',
     '        eprintln!("[scene-experimental] load=draw_queue ok");\n        eprintln!("[scene-experimental] load=audio begin");\n        load_audios(&self.audio_stream, objects.audio, &scene);\n        eprintln!("[scene-experimental] load=audio ok");'),
]
for old, new in repls:
    if old not in text:
        raise SystemExit(f"Could not locate load.rs diagnostic insertion pattern: {old[:70]}")
    text = text.replace(old, new, 1)
load.write_text(text)

print("macOS compatibility + diagnostics patch applied successfully")
PY

echo
echo "Building diagnostic x86_64 Rust/wgpu renderer..."
export CARGO_TERM_COLOR=always
cargo build --release --target x86_64-apple-darwin

BUILT="$SRC/target/x86_64-apple-darwin/release/linux-wallpaper-engine"
[[ -f "$BUILT" ]] || fail "Build completed but expected binary was not found."

cp "$BUILT" "$OUT_BIN"
chmod 755 "$OUT_BIN"

echo
echo "=== Binary verification ==="
file "$OUT_BIN"
if ! file "$OUT_BIN" | grep -q "x86_64"; then
  fail "The resulting binary is not x86_64."
fi

echo
echo "Build complete."
echo "Binary:"
echo "  $OUT_BIN"
echo
echo "This diagnostic build keeps symbols and panic unwinding enabled."
echo "Next: run mac/RUN_SCENE_A.command against the transferred A-basic test scene."