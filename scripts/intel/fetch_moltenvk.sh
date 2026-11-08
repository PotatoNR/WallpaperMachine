#!/bin/bash
# Fetch the last MoltenVK release with an x86_64 slice (the Homebrew `sonoma` bottle
# of 1.4.2) into .toolchain/vendor/moltenvk, where the Intel packaging script picks it
# up. Homebrew stopped shipping Intel macOS bottles, so the tarball is pinned by
# checksum instead of resolved from a formula.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENDOR="$ROOT/.toolchain/vendor/moltenvk"
SRC="$ROOT/.toolchain/src"
TARBALL="$SRC/moltenvk-bottle.tar.gz"
URL="https://ghcr.io/v2/homebrew/core/molten-vk/blobs/sha256:4d72464ad51723c9afeea216088deb733596fc6b544d4738e90824f4eb04a039"
SHA256="4d72464ad51723c9afeea216088deb733596fc6b544d4738e90824f4eb04a039"

mkdir -p "$VENDOR" "$SRC"
if [ ! -f "$TARBALL" ]; then
  token=$(curl -fsSL \
    "https://ghcr.io/token?scope=repository:homebrew/core/molten-vk:pull&service=ghcr.io" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["token"])')
  curl -fL --retry 3 -H "Authorization: Bearer $token" -o "$TARBALL" "$URL"
fi
echo "$SHA256  $TARBALL" | shasum -a 256 -c -

rm -rf "$SRC/moltenvk"
mkdir -p "$SRC/moltenvk"
tar xzf "$TARBALL" -C "$SRC/moltenvk"
BASE="$SRC/moltenvk/molten-vk/1.4.2"

install -m 755 "$BASE/lib/libMoltenVK.dylib" "$VENDOR/libMoltenVK.dylib"
install_name_tool -id @rpath/libMoltenVK.dylib "$VENDOR/libMoltenVK.dylib"
# The app looks for a bundled manifest (BridgeEnvironment.configureVulkanICDIfNeeded)
# and the loader resolves library_path relative to it, so the dylib lives in Frameworks.
cat > "$VENDOR/MoltenVK_icd.json" <<'JSON'
{
    "file_format_version" : "1.0.0",
    "ICD": {
        "library_path": "../Frameworks/libMoltenVK.dylib",
        "api_version" : "1.4.0",
        "is_portability_driver" : true
    }
}
JSON
echo "installed $(lipo -archs "$VENDOR/libMoltenVK.dylib") MoltenVK into $VENDOR"
