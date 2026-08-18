# WaifuX Intel Builder

Build an **Intel (`x86_64`) compatibility patch** for [WaifuX](https://github.com/jipika/WaifuX) so that **Media video wallpapers** and **Wallpaper Engine Video/Web wallpapers** can run on Intel-based Macs.

> [!IMPORTANT]
> This is an **unofficial community compatibility project**. It is not affiliated with or endorsed by the WaifuX project or its author.

## Why this exists

Recent WaifuX releases include several helper executables compiled for **Apple Silicon (`arm64`)**. On an Intel Mac, attempting to launch those helpers can fail with errors such as:

```text
Bad CPU type in executable
```

For WaifuX's normal video wallpaper feature, the relevant helper is:

```text
wallpaper-video-renderer
```

For Wallpaper Engine **Video** and **Web** wallpapers, the relevant helper is:

```text
wallpaperengine-cli
```

This repository uses GitHub Actions on an **Intel macOS runner** to rebuild those two public Swift components for `x86_64`, package them, and generate installation/restore scripts.

## Supported features

| Feature | Intel patch status |
|---|---|
| WaifuX Media / video dynamic wallpaper | ✅ Supported |
| Wallpaper Engine Video | ✅ Supported |
| Wallpaper Engine Web | ✅ Supported |
| Wallpaper Engine Scene | ❌ Not included |

### Why Scene is not included

Wallpaper Engine Scene rendering uses additional components such as:

```text
wallpaper-wgpu
dxc
libdxcompiler.dylib
```

The current workflow intentionally does **not** modify or replace those components. This project currently focuses only on Video and Web support.

## Requirements

On the target Mac:

- Intel-based Mac (`x86_64`)
- WaifuX installed at `/Applications/WaifuX.app`
- The patch must be built for the **same WaifuX version** that is installed on the Mac
- Administrator access is required during installation because files inside `/Applications/WaifuX.app` must be replaced and re-signed

No macOS build environment is required on your Windows/Linux computer. GitHub Actions performs the compilation on an Intel macOS runner.

## Build the patch

1. Open the **Actions** tab in this repository.
2. Select **Build WaifuX Intel Video + Web**.
3. Click **Run workflow**.
4. Enter your installed WaifuX version **without the leading `v`**.

Example:

```text
38.0.143
```

5. Start the workflow and wait for it to complete successfully.
6. Download the generated artifact from the workflow run.
7. Extract the outer GitHub artifact ZIP.
8. Inside it, you will find a Mac-ready ZIP similar to:

```text
WaifuX-Intel-Video-Web-v38.0.143-macOS-x86_64.zip
```

For best results, transfer this inner ZIP to the Intel Mac before extracting it.

## Install on the Intel Mac

Extract the Mac-ready ZIP. The resulting folder contains files similar to:

```text
WaifuX-Intel-Video-Web/
├── wallpaper-video-renderer
├── wallpaperengine-cli
├── CHECK_ON_MAC.command
├── INSTALL_ON_MAC.command
├── RESTORE_ORIGINAL.command
└── README.txt
```

Open Terminal and enter the extracted folder, for example:

```bash
cd ~/Downloads/WaifuX-Intel-Video-Web
```

### 1. Check the current installation

```bash
bash CHECK_ON_MAC.command
```

Confirm that the Mac reports:

```text
CPU:
x86_64
```

Also confirm that the installed WaifuX version matches the version used when running the GitHub Actions build.

### 2. Install the Intel helpers

```bash
bash INSTALL_ON_MAC.command
```

The installer will:

- verify the Mac is `x86_64`
- verify the WaifuX version
- quit WaifuX and its rendering helpers
- create a full backup of the original `WaifuX.app`
- replace `wallpaper-video-renderer`
- replace `wallpaperengine-cli`
- set executable permissions
- ad-hoc sign the replacement binaries
- re-sign the WaifuX application bundle
- verify the resulting code signature

When `sudo` asks for your administrator password, Terminal does not display password characters while typing. This is normal.

## Verify installation

Run:

```bash
bash CHECK_ON_MAC.command
```

The two patched components should report `x86_64`:

```text
wallpaper-video-renderer: Mach-O 64-bit executable x86_64
wallpaperengine-cli:      Mach-O 64-bit executable x86_64
```

`wallpaper-wgpu` may still report `arm64`; that is expected because Scene rendering is not part of this patch.

You can also verify manually:

```bash
file /Applications/WaifuX.app/Contents/Resources/Resources/wallpaper-video-renderer
file /Applications/WaifuX.app/Contents/Resources/Resources/wallpaperengine-cli
```

## Recommended test order

After installation, test these features in order:

1. **Media → dynamic desktop → normal MP4/video**
2. **Wallpaper Engine → Video**
3. **Wallpaper Engine → Web**

Do not use this project as a fix for Wallpaper Engine Scene wallpapers.

## Restore the original WaifuX installation

The installer makes a complete backup of the original application before changing it.

To restore:

```bash
bash RESTORE_ORIGINAL.command
```

Follow the prompt and type:

```text
RESTORE
```

The backup is normally stored on the Desktop with a timestamped name similar to:

```text
WaifuX-backup-before-intel-20260818-123456.app
```

## How the build works

The workflow clones the requested WaifuX release and modifies the Swift build target for these components from Apple Silicon:

```text
arm64-apple-macosx14.4
```

to Intel:

```text
x86_64-apple-macosx14.4
```

It then runs the upstream WaifuX build scripts on a GitHub-hosted Intel macOS runner and verifies that both resulting Mach-O executables contain the `x86_64` architecture before packaging them.

The workflow source is located at:

```text
.github/workflows/build-intel.yml
```

## Updating for a different WaifuX release

You do not normally need to edit the workflow for each release. Run it manually and supply the desired WaifuX version.

The installer checks the installed WaifuX version and refuses to continue if it does not exactly match the patch build version. This helps avoid replacing helpers with binaries built from a different release.

Because WaifuX updates may overwrite the patched helpers with upstream ARM64 versions, you may need to rebuild and reinstall this patch after updating WaifuX.

## Troubleshooting

### `Bad CPU type in executable`

Check the installed helper architectures:

```bash
file /Applications/WaifuX.app/Contents/Resources/Resources/wallpaper-video-renderer
file /Applications/WaifuX.app/Contents/Resources/Resources/wallpaperengine-cli
```

Both should report `x86_64` after successful installation.

### WaifuX version mismatch

Build a new artifact using the exact version shown by:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/WaifuX.app/Contents/Info.plist
```

### Need to undo the patch

Run:

```bash
bash RESTORE_ORIGINAL.command
```

## Credits

- [WaifuX](https://github.com/jipika/WaifuX) — original application and source code
- GitHub Actions — Intel macOS build environment used by this compatibility workflow

## Disclaimer

Use this project at your own risk. It modifies executables inside an installed macOS application and re-signs the application bundle using an ad-hoc signature. Keep the automatically created backup until you have confirmed that the patched application works correctly.
