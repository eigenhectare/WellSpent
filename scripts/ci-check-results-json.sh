#!/bin/bash
set -euo pipefail
readonly summary_file="${1:?summary JSON required}"
readonly tests_file="${2:?test-tree JSON required}"
readonly minimum="${3:?minimum executed test count required}"
readonly expected_file="${4:-}"
jq -e --argjson minimum "${minimum}" '
    .result == "Passed" and .failedTests == 0 and .expectedFailures == 0
    and .skippedTests == 0 and .passedTests == .totalTestCount
    and .totalTestCount >= $minimum
' "${summary_file}" >/dev/null || {
    echo "CI result failed: unsuccessful, skipped, or insufficient tests." >&2
    exit 1
}
if [[ -n "${expected_file}" ]]; then
    while IFS= read -r expected || [[ -n "${expected}" ]]; do
        [[ -z "${expected}" || "${expected}" == \#* ]] && continue
        jq -e --arg expected "${expected}" '
            [.. | objects | select(.nodeType? == "Test Case" and .result? == "Passed")
             | .nodeIdentifierURL | split("/") | .[4:] | join("/")]
            | any(. == $expected or startswith($expected + "/"))
        ' "${tests_file}" >/dev/null || {
            echo "CI result failed: required test did not pass: ${expected}" >&2
            exit 1
        }
    done < "${expected_file}"
fi
jq -r '"Verified \(.passedTests) passed tests; none skipped or expected to fail."' "${summary_file}"
