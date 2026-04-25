#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SELF_DIR/../.." && pwd)
BUILD_DIR="$REPO_ROOT/build/GhosttyPaneSpike"
SHIM_SOURCE="$SELF_DIR/GhosttyShim.c"
GHOSTTY_HEADER_URL="${GHOSTTY_HEADER_URL:-https://raw.githubusercontent.com/ghostty-org/ghostty/4ceeba4851030e75398cf1e5d3f7d8c7ed645e87/include/ghostty.h}"

mkdir -p "$BUILD_DIR"

printf 'Downloading Ghostty embedding header...\n'
curl -fsSL "$GHOSTTY_HEADER_URL" -o "$BUILD_DIR/ghostty.h"

printf 'Building Ghostty pane spike shim...\n'
xcrun clang \
  -dynamiclib \
  -std=c17 \
  -Wall \
  -Wextra \
  -Werror \
  -I"$BUILD_DIR" \
  "$SHIM_SOURCE" \
  -o "$BUILD_DIR/libgmax-ghostty-shim.dylib"

codesign --force --sign - "$BUILD_DIR/libgmax-ghostty-shim.dylib"

printf 'Built %s\n' "$BUILD_DIR/libgmax-ghostty-shim.dylib"
