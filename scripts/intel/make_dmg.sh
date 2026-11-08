#!/bin/bash
# Builds the drag-to-install disk image for the Intel build from an already
# packaged app (scripts/intel/package_intel_app.sh), and prints its checksum.
#
#   scripts/intel/make_dmg.sh [APP] [OUTPUT_DIR]
#
# APP defaults to the Release build in this checkout; OUTPUT_DIR to
# artifacts/intel-release. The image carries the app, an Applications alias and
# the Gatekeeper notes the ad-hoc signature needs.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APP=${1:-"$ROOT/build/Build/Products/Release/WallpaperMachine.app"}
OUT=${2:-"$ROOT/artifacts/intel-release"}
PLIST="$APP/Contents/Info.plist"

[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
NAME="WallpaperMachine-$VERSION-intel-x86_64.dmg"

codesign --verify --deep --strict "$APP" || { echo "app signature does not verify" >&2; exit 1; }

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/wm-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/WallpaperMachine.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/安装说明.txt" <<TXT
WallpaperMachine $VERSION（Intel / x86_64 构建，非官方）

1. 把 WallpaperMachine.app 拖进「应用程序」文件夹。
2. 第一次打开如果被系统拦下（"无法验证开发者"）：
   打开「系统设置 → 隐私与安全性」，在页面底部点"仍要打开"；
   或者在终端执行：
     xattr -dr com.apple.quarantine /Applications/WallpaperMachine.app
3. 本应用为 ad-hoc 签名、未经 Apple 公证，属于个人构建，不是官方发布。

应用内的"检查更新"指向官方仓库，官方版本只有 Apple 芯片版，请不要用它覆盖安装。
新版本请回到 https://github.com/PotatoNR/WallpaperMachine/releases
TXT

mkdir -p "$OUT"
hdiutil create -volname "WallpaperMachine $VERSION (Intel)" -srcfolder "$STAGE" \
  -fs HFS+ -format UDZO -ov "$OUT/$NAME" >/dev/null
echo "$OUT/$NAME"
shasum -a 256 "$OUT/$NAME"
