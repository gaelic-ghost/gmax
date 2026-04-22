#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/../lib"
. "$SELF_DIR/../lib/common.sh"

swiftformat_config="$REPO_ROOT/.swiftformat"
swiftlint_config="$REPO_ROOT/.swiftlint.yml"

[ -f "$swiftformat_config" ] || die "Expected $swiftformat_config to exist so repo formatting has a checked-in SwiftFormat source of truth."
[ -f "$swiftlint_config" ] || die "Expected $swiftlint_config to exist so repo linting has a checked-in SwiftLint source of truth."

command -v swiftformat >/dev/null 2>&1 || die "SwiftFormat CLI is required for repo-maintenance validation, but \`swiftformat\` was not found on PATH."
command -v swiftlint >/dev/null 2>&1 || die "SwiftLint CLI is required for repo-maintenance validation, but \`swiftlint\` was not found on PATH."

log "Linting Swift formatting with SwiftFormat..."
swiftformat --lint --config "$swiftformat_config" "$REPO_ROOT/gmax" "$REPO_ROOT/gmaxTests" "$REPO_ROOT/gmaxUITests"

log "Linting Swift sources with SwiftLint..."
swiftlint lint --strict --config "$swiftlint_config"
