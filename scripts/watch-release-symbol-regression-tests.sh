#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly filter="${script_directory}/watch-release-symbols.jq"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentReleaseSymbols.XXXXXX")"
readonly fixture_root
cleanup() {
    [[ -n "${fixture_root}" && -d "${fixture_root}" ]] || return
    rm -rf -- "${fixture_root}"
}
trap cleanup EXIT

readonly phone='["11111111-2222-3333-4444-555555555555 (arm64)"]'
readonly watch='["AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (arm64_32)","01234567-89AB-CDEF-0123-456789ABCDEF (arm64)"]'

render() {
    jq -n --argjson binarySymbols "$1" --argjson dSYMIdentifiers "$2" \
        -f "${filter}" >"${fixture_root}/result.json"
}

render "${phone}" "${phone}"
jq -e '.checked and .identifiers == [{uuid:"11111111-2222-3333-4444-555555555555",architecture:"arm64"}]' \
    "${fixture_root}/result.json" >/dev/null
render "${watch}" "${watch}"
jq -e '.checked and (.identifiers | length) == 2' "${fixture_root}/result.json" >/dev/null

expect_rejection() {
    if render "$1" "$2" 2>"${fixture_root}/error.log"; then
        echo "Release-symbol guard accepted an invalid fixture." >&2
        exit 1
    fi
}

expect_rejection "${watch}" '["AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (arm64_32)"]'
expect_rejection "${phone}" '["11111111-2222-3333-4444-555555555555 (arm64)","AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (arm64_32)"]'
expect_rejection "${phone}" '["99999999-2222-3333-4444-555555555555 (arm64)"]'
expect_rejection "${phone}" '["11111111-2222-3333-4444-555555555555 (arm64_32)"]'
expect_rejection "${phone}" '["11111111-2222-3333-4444-555555555555 (arm64)","11111111-2222-3333-4444-555555555555 (arm64)"]'
expect_rejection '["not-a-uuid (arm64)"]' '["not-a-uuid (arm64)"]'

echo 'Release dSYM policy passed two valid fixtures and rejected missing, extra, stale, wrong-architecture, duplicate and malformed identifiers.'
