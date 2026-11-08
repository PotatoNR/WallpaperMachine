#!/bin/bash
# Post-process the Release app for this Intel build: vendor the conda dylibs into
# Contents/Frameworks, install a Dock icon (Xcode 16.4 cannot compile AppIcon.icon)
# and re-sign ad-hoc. Run after scripts/build.py; the app is then self-contained.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/build/Build/Products/Release/WallpaperMachine.app"
CONDA="$ROOT/.toolchain/conda"
[ -d "$APP" ] || { echo "missing $APP" >&2; exit 1; }

# Start from the conda copies: a stale dylib left by an earlier packaging would
# otherwise be "resolved" in place and keep older dependencies.
rm -f "$APP"/Contents/Frameworks/*.dylib
python3 "$ROOT/scripts/intel/bundle_dylibs.py" "$APP" "$CONDA"

# Vulkan ICD: the renderer reaches Metal through MoltenVK. The app looks for a bundled
# MoltenVK_icd.json (App/Bridge/BridgeEnvironment.swift) and the loader resolves its
# relative library_path against the manifest, so the dylib sits in Frameworks.
VENDOR="$ROOT/.toolchain/vendor/moltenvk"
install -m 755 "$VENDOR/libMoltenVK.dylib" "$APP/Contents/Frameworks/libMoltenVK.dylib"
install -m 644 "$VENDOR/MoltenVK_icd.json" "$APP/Contents/Resources/MoltenVK_icd.json"

for bin in "$APP/Contents/MacOS/WallpaperMachine" \
           "$APP/Contents/Extensions/WallpaperMachineExtension.appex/Contents/MacOS/WallpaperMachineExtension" \
           "$APP/Contents/Frameworks/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"; do
  otool -l "$bin" | grep -q 'path /usr/lib ' || install_name_tool -add_rpath /usr/lib "$bin"
  # The app must not depend on this build tree: every conda dylib now lives in Frameworks.
  for rpath in $(otool -l "$bin" | awk '/LC_RPATH/{getline; getline; print $2}'); do
    case "$rpath" in *toolchain*) install_name_tool -delete_rpath "$rpath" "$bin" 2>/dev/null || true;; esac
  done
done

# Keep the vendored dylibs loadable from their own directory and point the C++ runtime
# at the system libc++ (conda's newer libc++ exports symbols the system one lacks).
for dylib in "$APP"/Contents/Frameworks/*.dylib; do
  otool -l "$dylib" | grep -q 'path @loader_path ' || install_name_tool -add_rpath @loader_path "$dylib"
  for n in libc++.1 libc++abi.1 libiconv.2 libSystem.B libobjc.A; do
    install_name_tool -change "@rpath/$n.dylib" "/usr/lib/$n.dylib" "$dylib" 2>/dev/null || true
  done
done
for bin in "$APP/Contents/MacOS/WallpaperMachine" \
           "$APP/Contents/Extensions/WallpaperMachineExtension.appex/Contents/MacOS/WallpaperMachineExtension"; do
  for n in libc++.1 libc++abi.1 libiconv.2 libSystem.B libobjc.A; do
    install_name_tool -change "@rpath/$n.dylib" "/usr/lib/$n.dylib" "$bin" 2>/dev/null || true
  done
done

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC="$ROOT/App/Resources/Assets.xcassets/AppIconDay.imageset/day.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile AppIcon' "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$APP/Contents/Info.plist"

for dylib in "$APP"/Contents/Frameworks/*.dylib; do codesign --force --sign - "$dylib"; done
codesign --force --sign - "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --sign - --preserve-metadata=entitlements,requirements,flags,runtime \
  "$APP/Contents/Extensions/WallpaperMachineExtension.appex"
codesign --force --sign - --preserve-metadata=entitlements,requirements,flags,runtime "$APP"
codesign --verify --deep --strict "$APP"
echo "packaged $APP"
