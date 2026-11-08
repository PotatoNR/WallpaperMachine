# Intel (x86_64) local build

A build of this tree on an Intel Mac with Xcode 16.4 / SDK 15.5. It is a **local
developer build**: not a release configuration, not notarized, and built against
libraries compiled on the same machine. Apple-silicon releases keep using
[build.md](build.md).

## Toolchain

Everything lives in the ignored `.toolchain/` directory; nothing is installed into
`/usr/local` or `/opt/homebrew`.

| Path | Contents |
|---|---|
| `.toolchain/conda` | Single prefix with the dependencies (eigen, nlohmann-json, freetype, lz4, glslang, vulkan-loader/headers, quickjs-ng, dav1d, FFmpeg) |
| `.toolchain/bin` | `xcodegen`, `cmake`, `ninja`, `meson`, `nasm`, a `git` shim for this source snapshot |
| `.toolchain/homebrew` | Symlink farm shaped like a Homebrew prefix, so `scripts/build.py` finds the dependencies unchanged |
| `.toolchain/env.sh` | Exports the prefix, Rust toolchain and `PKG_CONFIG_PATH` |
| `scripts/intel/package_intel_app.sh` | Makes the built app self-contained (see below) |
| `scripts/intel/fetch_moltenvk.sh` | Downloads the pinned MoltenVK bottle into `.toolchain/vendor/moltenvk` |
| `scripts/intel/make_dmg.sh` | Wraps the packaged app into the release disk image and prints its SHA-256 |

Rust is the x86_64 stable toolchain under `.toolchain/cargo`; the cargo registry
mirror is in `.toolchain/cargo/config.toml`.

## Build

```sh
source .toolchain/env.sh
python3 scripts/build.py --configuration Release
scripts/intel/fetch_moltenvk.sh   # once, needs network
scripts/intel/package_intel_app.sh
scripts/intel/make_dmg.sh         # artifacts/intel-release/WallpaperMachine-<version>-intel-x86_64.dmg
```

`build.py` builds the renderer with Cargo, regenerates `App/Bridge/Generated/`,
runs XcodeGen and `xcodebuild`. The packaging script then vendors the non-system
dylibs into `Contents/Frameworks`, rewrites their install names, adds the Dock icon
and re-signs the bundle ad-hoc; the result runs from any directory.

The script also installs MoltenVK 1.4.2 (the `sonoma` Homebrew bottle, the last one
with an x86_64 slice) as `Contents/Frameworks/libMoltenVK.dylib` together with
`Contents/Resources/MoltenVK_icd.json`. That manifest is what
`BridgeEnvironment.configureVulkanICDIfNeeded()` hands to the Vulkan loader, and its
`library_path` is relative (`../Frameworks/libMoltenVK.dylib`), so the bundle stays
relocatable. Without it the renderer fails with `required vulkan instance extension
"VK_KHR_surface" is not supported` and every wallpaper activation times out; the
`scripts/intel/fetch_moltenvk.sh` pins and downloads them into `.toolchain/vendor/moltenvk/`.

## Deviations from the arm64 tree

- `project.yml`: `ARCHS: x86_64` and library search paths point into `.toolchain/conda`;
  everything else stays as the arm64 tree has it. The XcodeGen release bundle must be
  installed with its `share/xcodegen/SettingPresets`, or the generated project loses
  Xcode's base settings (empty `PRODUCT_NAME`, no Debug testability).
- `scripts/build.py`: `CMAKE_PREFIX_PATH` is joined with `:`; CMake 4 reads the
  variable as a PATH-style list, so a `;`-joined string is one bogus path.
- `scripts/test.py`: the destination arch follows `platform.machine()`.
- `App/Services/Steam/SteamCMDRuntime.swift`: a native SteamCMD is the host
  architecture instead of always arm64, and the symlink read uses an explicit
  `withUnsafeMutableBytes` buffer — `readlinkat(parent, name, &link, link.count)`
  miscompiles with Swift 6.1 on x86_64 (the array count reads as garbage and the
  process dies with `EXC_BAD_ACCESS`), which crashed SteamCMD validation.
- Control panel: the macOS 26 glass effects fall back to pre-26 materials, since
  SDK 15.5 has no `glassEffect`/`sharedBackgroundVisibility`.
- glslang, SPIRV-Tools and quickjs-ng are built from source against the system
  libc++; the conda-forge glslang links a newer libc++ that exports symbols the
  system runtime lacks.
- `App/Services/GitHub/AppUpdateModels.swift`: the update checker follows this fork's
  releases (`PotatoNR/WallpaperMachine`), accepts the `v1.5.6-intel.1` tag shape and
  expects the disk image `scripts/intel/make_dmg.sh` writes,
  `WallpaperMachine-<version>-intel-x86_64.dmg`.

## Known gaps

- `AppIcon.icon` is an Icon Composer document; Xcode 16.4's `actool` ignores it, so
  the packaging script installs an `.icns` generated from `AppIconDay.imageset`.
- Launch smoke-tested on the target machine (MacBookPro13,3, Radeon Pro 460): the app
  starts, finishes `bootstrapAsync`, checks workshop updates and quits cleanly.
- Still not verified on Intel: wallpaper rendering on Metal, the sandboxed lock-screen
  extension, downloads and SteamCMD setup.
- SteamCMD validation and setup are covered by the `SteamCMD*` unit tests on Intel;
  a real Valve download, the security approval prompt and a Steam login are not.
