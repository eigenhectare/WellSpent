#!/bin/bash
set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly result_bundle="${1:?result bundle required}"
readonly report_directory="${2:?new report directory required}"
readonly expected_tests="${script_directory}/watch-resource-tests.txt"
readonly report_scope="${WATCH_RESOURCE_REPORT_SCOPE:-Accelerated watchOS Simulator test-host observations; not physical energy, wakeups, network, backup, WidgetKit delivery or an accepted resource budget.}"
[[ ! -e "${report_directory}" ]] || { echo 'Use a new report directory; existing evidence is preserved.' >&2; exit 1; }
bash "${script_directory}/ci-check-results.sh" "${result_bundle}" 4 "${expected_tests}"
mkdir -p "${report_directory}"
xcrun xcresulttool export attachments --path "${result_bundle}" --output-path "${report_directory}/attachments" \
    > "${report_directory}/export.log" 2>&1
readonly attachment_manifest="${report_directory}/attachments/manifest.json"
profiles=()
while IFS= read -r expected; do
    [[ -z "${expected}" || "${expected}" == \#* ]] && continue
    test_identifier="${expected#WellSpentWatchTests/}()"
    attachment="$(jq -er --arg identifier "${test_identifier}" '
        [.[] | select(.testIdentifier == $identifier) | .attachments[]
        | select(.suggestedHumanReadableName | startswith("watch-resource-profile_")) | .exportedFileName]
        | if length == 1 then .[0] else error("Expected one resource profile per test") end
    ' "${attachment_manifest}")"
    [[ "${attachment}" =~ ^[A-Za-z0-9_-]+\.json$ ]] || { echo 'Invalid attachment filename.' >&2; exit 1; }
    profile_path="${report_directory}/attachments/${attachment}"
    summary="${report_directory}/${expected##*/}.json"
    jq -e --arg test "${expected}" -f "${script_directory}/watch-resource-summary.jq" "${profile_path}" > "${summary}"
    profiles+=("${summary}")
done < "${expected_tests}"
jq -s --arg scope "${report_scope}" '{
    schemaVersion: 1,
    scope: $scope,
    tests: .
}' "${profiles[@]}" > "${report_directory}/summary.json"
jq -r '.tests[] | [.test, .wallSecondsBetweenSamples, .testHostCPUSecondsBetweenSamples,
    .peakObservedLogicalStoreBytes, .finalObservedLogicalStoreBytes, .peakOutboxCount, .finalOutboxCount] | @tsv' \
    "${report_directory}/summary.json"
echo "Resource report: ${report_directory}/summary.json"
