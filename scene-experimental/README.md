# Intel Scene Experimental

This branch is for local-only Intel macOS Scene compatibility experiments. It intentionally adds **no scheduled GitHub Actions**.

## Why this exists

The official WaifuX `wallpaper-wgpu` helper is currently distributed as an arm64-only Mach-O binary. Static analysis of the official binary shows that it is a Rust renderer built around wgpu/Metal, Naga, winit, DXC-to-SPIR-V shader conversion, and an embedded V8 SceneScript runtime. That architecture is not inherently Apple-Silicon-only; the current blocker is the lack of an x86_64 build of the private helper.

For the open-source fallback path, we will first test/port `wqLouis/linux-wallpaperengine` because it also uses Rust + wgpu 28 + winit and already contains a Metal backend and Wallpaper Engine package/texture/effect parsing code.

## Selected Windows Wallpaper Engine test set

The three primary workshop scenes below were selected from the user's installed Wallpaper Engine library to exercise progressively harder renderer features:

| Tier | Workshop ID | Title | Size | Why selected |
|---|---:|---|---:|---|
| A — basic | `2947302287` | Angled Waves | 0.8 MB | Very small Scene package; useful for proving package parsing, texture loading, basic transforms, and first successful Metal frame. |
| B — audio/effects | `3034129787` | Azusawa Kohane \| 4K \| PJSK \| Project Sekai \| AUDIO RESPONSIVE | 19.1 MB | Explicitly audio-responsive; useful for validating effects plus audio-uniform plumbing after basic rendering works. |
| C — complex/realtime | `3509243656` | 三体实时演算 \| Three-Body problem - SYKM | 152 MB | Large realtime Scene; useful as a stress/compatibility target after tiers A and B. |

Windows locations (assuming the current Steam library layout):

```text
E:\SteamLibrary\steamapps\workshop\content\431960\2947302287
E:\SteamLibrary\steamapps\workshop\content\431960\3034129787
E:\SteamLibrary\steamapps\workshop\content\431960\3509243656
```

## Development order

1. Make the open-source renderer compile on `x86_64-apple-darwin` with Linux/Wayland-only dependencies and modules gated by `cfg(target_os = "linux")`.
2. Use the winit adapter and wgpu Metal backend on macOS.
3. Prove Tier A can open and render a first frame.
4. Compare scene layout/effects against Wallpaper Engine on Windows.
5. Test Tier B audio-responsive behavior.
6. Test Tier C realtime/complex behavior.
7. Only after the renderer is stable, evaluate integrating it as a WaifuX Scene helper/drop-in adapter.

## Important constraints

- Keep experiments local initially; do not add scheduled Actions jobs.
- Do not redistribute Wallpaper Engine proprietary assets or Workshop content in this repository.
- Test content should remain on the user's machines and be copied locally only.
- `wqLouis/linux-wallpaperengine` is GPL-3.0, so any derived/distributed code must respect GPL-3.0 obligations.
- The preferred long-term solution remains an official x86_64/universal `wallpaper-wgpu` build from WaifuX's author.

## Windows preparation

Use `tools/windows-export-scene-testset.ps1` on the Windows machine to copy only the three selected Workshop directories to a transfer folder and generate a manifest. The script does not upload anything and does not copy the entire Wallpaper Engine installation.
