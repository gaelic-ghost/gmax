#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_MAINTENANCE_COMMON_SOURCE="$SELF_DIR/../lib/common.sh"
. "$REPO_MAINTENANCE_COMMON_SOURCE"

for required in \
  "$REPO_MAINTENANCE_ROOT/validate-all.sh" \
  "$REPO_MAINTENANCE_ROOT/sync-shared.sh" \
  "$REPO_MAINTENANCE_ROOT/release.sh" \
  "$REPO_MAINTENANCE_ROOT/lib/common.sh"
do
  [ -f "$required" ] || die "The repo-maintenance toolkit is missing the required file $required."
done
