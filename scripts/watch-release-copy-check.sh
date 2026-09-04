#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
fail() { echo "Watch release-copy check failed: $1" >&2; exit 1; }

required_files=(
    APP-STORE-RELEASE.md
    BETA-TESTING.md
    ACCESSIBILITY.md
    PRIVACY.md
    SUPPORT.md
    WAT-27-STORE-MATERIALS-DRAFT.md
)
for file in "${required_files[@]}"; do
    [[ -s "${repository_root}/${file}" ]] || fail "missing ${file}"
done

require_text() {
    local file="$1" text="$2"
    rg -q -F "${text}" "${repository_root}/${file}" || fail "${file} is missing: ${text}"
}

require_pattern() {
    local file="$1" pattern="$2"
    rg -U -q "${pattern}" "${repository_root}/${file}" || fail "${file} is missing required paired-product copy"
}

require_pattern APP-STORE-RELEASE.md 'there is no[[:space:]]+countdown'
require_text APP-STORE-RELEASE.md 'Watch Connectivity provides paired device-to-device exchange'
require_text APP-STORE-RELEASE.md 'Unsynchronized Watch changes are'
require_text APP-STORE-RELEASE.md '416 × 496'
require_text SUPPORT.md 'WC Probe is not part of WellSpent'
require_text SUPPORT.md 'Review Required'
require_text SUPPORT.md 'Unsynchronized Watch time is device-local'
require_text PRIVACY.md 'User-facing paired-data disclosure draft'
require_text PRIVACY.md 'timer and summary-annotation mutations'
require_text ACCESSIBILITY.md 'Apple Watch accessibility and layout'
require_text ACCESSIBILITY.md 'Remaining physical Watch checks'
require_text BETA-TESTING.md 'paired iPhone + Apple Watch beta package'
require_text BETA-TESTING.md 'BETA-W06 — Authorized retention and long-run case'
require_text BETA-TESTING.md 'greater than the'
require_text README.md 'versioned SwiftData v6 schema'

public_drafts=(
    "${repository_root}/APP-STORE-RELEASE.md"
    "${repository_root}/BETA-TESTING.md"
    "${repository_root}/PRIVACY.md"
    "${repository_root}/SUPPORT.md"
)
if rg -q -F 'stays on this iPhone' "${public_drafts[@]}"; then
    fail 'paired-product copy contains the obsolete iPhone-only retention claim'
fi
if rg -q '^[-] Product: WellSpent for iPhone$|^[-] Build: `1`$|SwiftData v2 with migration' \
    "${repository_root}/BETA-TESTING.md"; then
    fail 'beta package contains stale iPhone-only candidate identity'
fi

echo 'Watch App Store, support, privacy, accessibility and beta copy boundaries passed.'
