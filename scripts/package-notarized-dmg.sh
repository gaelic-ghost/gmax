#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SELF_DIR/.." && pwd)

configuration="Release"
version="${GMAX_DMG_VERSION:-}"
output_dir="${GMAX_DMG_OUTPUT_DIR:-$REPO_ROOT/build/distribution}"
archive_path="${GMAX_DMG_ARCHIVE_PATH:-}"
export_path="${GMAX_DMG_EXPORT_PATH:-}"
export_options_plist="${GMAX_DMG_EXPORT_OPTIONS_PLIST:-$SELF_DIR/export-options-developer-id.plist}"
notary_profile="${GMAX_NOTARY_KEYCHAIN_PROFILE:-gmax-notary}"
skip_notarize="false"
upload_release="false"
release_tag=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/package-notarized-dmg.sh --version <vX.Y.Z> [--upload-release <vX.Y.Z>] [--notary-profile <name>] [--skip-notarize]

Creates a local Developer ID DMG for direct macOS distribution.

The default notarization credential lookup uses an existing notarytool keychain
profile named gmax-notary. Create it locally with:

  xcrun notarytool store-credentials gmax-notary --apple-id <apple-id> --team-id BC73766F69 --password <app-specific-password>

Environment:
  GMAX_DMG_VERSION                Version label used in the DMG filename.
  GMAX_DMG_OUTPUT_DIR             Output directory. Defaults to build/distribution.
  GMAX_DMG_ARCHIVE_PATH           Archive path. Defaults under build/distribution.
  GMAX_DMG_EXPORT_PATH            Export path. Defaults under build/distribution.
  GMAX_DMG_EXPORT_OPTIONS_PLIST   Export options plist. Defaults to scripts/export-options-developer-id.plist.
  GMAX_NOTARY_KEYCHAIN_PROFILE    notarytool keychain profile. Defaults to gmax-notary.
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
    --archive-path)
      archive_path="${2:-}"
      shift 2
      ;;
    --export-path)
      export_path="${2:-}"
      shift 2
      ;;
    --export-options-plist)
      export_options_plist="${2:-}"
      shift 2
      ;;
    --notary-profile)
      notary_profile="${2:-}"
      shift 2
      ;;
    --skip-notarize)
      skip_notarize="true"
      shift
      ;;
    --upload-release)
      upload_release="true"
      release_tag="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown package-notarized-dmg argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[ -n "$version" ] || {
  printf 'Pass --version vX.Y.Z when packaging a notarized DMG.\n' >&2
  exit 2
}

case "$version" in
  *[!A-Za-z0-9._-]*)
    printf 'DMG version contains unsupported filename characters: %s\n' "$version" >&2
    exit 2
    ;;
esac

if [ "$upload_release" = "true" ]; then
  [ -n "$release_tag" ] || {
    printf 'Pass a release tag after --upload-release.\n' >&2
    exit 2
  }
  command -v gh >/dev/null 2>&1 || {
    printf 'Uploading release assets requires gh.\n' >&2
    exit 1
  }
fi

[ -f "$export_options_plist" ] || {
  printf 'Expected Developer ID export options plist at %s.\n' "$export_options_plist" >&2
  exit 1
}

mkdir -p "$output_dir"

if [ -z "$archive_path" ]; then
  archive_path="$output_dir/Gmax-$version.xcarchive"
fi

if [ -z "$export_path" ]; then
  export_path="$output_dir/export-$version"
fi

dmg_path="$output_dir/Gmax-$version.dmg"
sha_path="$dmg_path.sha256"

rm -rf "$archive_path" "$export_path"

xcodebuild archive \
  -project "$REPO_ROOT/gmax.xcodeproj" \
  -scheme gmax \
  -configuration "$configuration" \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path"

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options_plist"

exported_app_path="$export_path/gmax.app"
[ -d "$exported_app_path" ] || exported_app_path="$export_path/Gmax.app"
[ -d "$exported_app_path" ] || {
  printf 'Expected exported app under %s, but no gmax.app or Gmax.app exists.\n' "$export_path" >&2
  exit 1
}

"$SELF_DIR/package-dmg.sh" \
  --version "$version" \
  --output-dir "$output_dir" \
  --app-path "$exported_app_path"

if [ "$skip_notarize" != "true" ]; then
  xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$notary_profile" \
    --wait

  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$dmg_path"
fi

spctl --assess --type open --verbose "$dmg_path"
shasum -a 256 "$dmg_path" >"$sha_path"

if [ "$upload_release" = "true" ]; then
  gh release upload "$release_tag" "$dmg_path" "$sha_path" --clobber
fi

printf 'Created %s\n' "$dmg_path"
printf 'Created %s\n' "$sha_path"
