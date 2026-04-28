#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SELF_DIR/.." && pwd)

configuration="Release"
version="${GMAX_DMG_VERSION:-}"
output_dir="${GMAX_DMG_OUTPUT_DIR:-$REPO_ROOT/build/distribution}"
derived_data_path="${GMAX_DMG_DERIVED_DATA_PATH:-}"
skip_build="false"

usage() {
  cat <<'USAGE'
Usage:
  scripts/package-dmg.sh [--version <version>] [--configuration Release] [--output-dir <path>] [--derived-data-path <path>] [--skip-build]

Builds gmax.app and packages it into a compressed DMG with an Applications symlink.

Environment:
  GMAX_DMG_VERSION            Version label used in the DMG filename.
  GMAX_DMG_OUTPUT_DIR         Output directory. Defaults to build/distribution.
  GMAX_DMG_DERIVED_DATA_PATH  DerivedData path. Defaults to a temporary directory.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      version="${2:-}"
      shift 2
      ;;
    --configuration)
      configuration="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --derived-data-path)
      derived_data_path="${2:-}"
      shift 2
      ;;
    --skip-build)
      skip_build="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown package-dmg argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$version" ]; then
  version="$(git -C "$REPO_ROOT" describe --tags --exact-match 2>/dev/null || git -C "$REPO_ROOT" describe --tags --always --dirty)"
fi

case "$version" in
  *[!A-Za-z0-9._-]*)
    printf 'DMG version contains unsupported filename characters: %s\n' "$version" >&2
    exit 2
    ;;
esac

if [ -z "$derived_data_path" ]; then
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gmax-package-dmg.XXXXXX")"
  derived_data_path="$work_dir/DerivedData"
else
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gmax-package-dmg-stage.XXXXXX")"
fi

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

app_path="$derived_data_path/Build/Products/$configuration/gmax.app"

if [ "$skip_build" != "true" ]; then
  xcodebuild \
    -project "$REPO_ROOT/gmax.xcodeproj" \
    -scheme gmax \
    -configuration "$configuration" \
    -derivedDataPath "$derived_data_path" \
    build
fi

[ -d "$app_path" ] || {
  printf 'Expected built app at %s, but it does not exist.\n' "$app_path" >&2
  exit 1
}

mkdir -p "$output_dir"

stage_dir="$work_dir/stage"
mkdir -p "$stage_dir"
cp -R "$app_path" "$stage_dir/Gmax.app"
ln -s /Applications "$stage_dir/Applications"

dmg_path="$output_dir/Gmax-$version.dmg"
sha_path="$dmg_path.sha256"

hdiutil create \
  -volname Gmax \
  -srcfolder "$stage_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

hdiutil imageinfo "$dmg_path" >/dev/null
shasum -a 256 "$dmg_path" >"$sha_path"

printf 'Created %s\n' "$dmg_path"
printf 'Created %s\n' "$sha_path"
