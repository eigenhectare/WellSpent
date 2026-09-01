#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly fixture_directory="$(mktemp -d "${TMPDIR:-/tmp}/wellspent-privacy-audit.XXXXXX")"
readonly fixture_file="${fixture_directory}/ProhibitedFixture.swift"
readonly output_file="${fixture_directory}/audit-output.txt"

trap 'rm -rf -- "${fixture_directory}"' EXIT

run_rejected_fixture() {
    local fixture_name="$1"
    local fixture_source="$2"
    local expected_failure="$3"

    printf '%s\n' "${fixture_source}" >"${fixture_file}"
    if PRIVACY_AUDIT_EXTRA_SOURCE_PATH="${fixture_directory}" \
        "${script_directory}/privacy-audit.sh" >"${output_file}" 2>&1
    then
        echo "Privacy audit regression failed: ${fixture_name} was accepted." >&2
        exit 1
    fi

    if ! grep -qF -- "${expected_failure}" "${output_file}"; then
        echo "Privacy audit regression failed: ${fixture_name} failed for the wrong reason." >&2
        cat "${output_file}" >&2
        exit 1
    fi
}

run_rejected_fixture \
    "URLSession egress" \
    'import Foundation; let client = URLSession.shared' \
    'unexpected network, tracking, or diagnostics API'

run_rejected_fixture \
    "hard-coded remote URL" \
    'let endpoint = "https://example.com/upload"' \
    'hard-coded remote URL'

run_rejected_fixture \
    "interpolated crash data" \
    'fatalError("Store failed: \(error)")' \
    'interpolated production crash/assertion message'

echo "Privacy audit regression tests passed."
