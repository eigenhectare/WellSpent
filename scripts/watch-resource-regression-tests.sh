#!/bin/bash
set -euo pipefail
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentResourceReport.XXXXXX")"
trap 'rm -rf -- "${fixture_root}"' EXIT

jq -n '[{
    phase: "baseline", systemUptimeSeconds: 10, processCPUSeconds: 1,
    voluntaryContextSwitches: 1, involuntaryContextSwitches: 2,
    pendingCount: 1, quarantineCount: 0, acknowledgementCount: 0, receiptCount: 0, outboxPayloadBytes: 100,
    files: [{name: "fixture.store", logicalBytes: 200, allocatedBytes: 4096}]
}, {
    phase: "compacted", systemUptimeSeconds: 12, processCPUSeconds: 1.5,
    voluntaryContextSwitches: 3, involuntaryContextSwitches: 6,
    pendingCount: 0, quarantineCount: 0, acknowledgementCount: 1, receiptCount: 0, outboxPayloadBytes: 0,
    files: [{name: "fixture.store", logicalBytes: 300, allocatedBytes: 4096}]
}]' > "${fixture_root}/valid.json"
jq -e --arg test fixture -f "${script_directory}/watch-resource-summary.jq" "${fixture_root}/valid.json" \
    > "${fixture_root}/summary.json"
jq -e '.wallSecondsBetweenSamples == 2 and .testHostCPUSecondsBetweenSamples == 0.5
    and .peakObservedLogicalStoreBytes == 300 and .finalOutboxCount == 0
    and .voluntaryContextSwitchesBetweenSamples == 2 and .involuntaryContextSwitchesBetweenSamples == 4' \
    "${fixture_root}/summary.json" >/dev/null

expect_failure() {
    jq "$1" "${fixture_root}/valid.json" > "${fixture_root}/invalid.json"
    if jq -e --arg test fixture -f "${script_directory}/watch-resource-summary.jq" "${fixture_root}/invalid.json" \
        > "${fixture_root}/rejected.json" 2> "${fixture_root}/error.log"; then
        echo "Resource report accepted invalid fixture: $1" >&2
        exit 1
    fi
}
expect_failure '.[0:1]'
expect_failure '.[1].processCPUSeconds = 0'
expect_failure '.[1].systemUptimeSeconds = 9'
expect_failure '.[1].voluntaryContextSwitches = 0'
expect_failure '.[1].involuntaryContextSwitches = 0'
expect_failure '.[1].pendingCount = -1'
expect_failure 'del(.[1].acknowledgementCount)'
expect_failure '.[1].files = []'
expect_failure '.[1].files[0].logicalBytes = null'
expect_failure '.[1].files[0].allocatedBytes = -1'

# A filesystem may not expose allocated bytes: preserve unknown, never zero.
jq '.[1].files[0].allocatedBytes = null' "${fixture_root}/valid.json" > "${fixture_root}/unknown.json"
jq -e --arg test fixture -f "${script_directory}/watch-resource-summary.jq" "${fixture_root}/unknown.json" \
    > "${fixture_root}/unknown-summary.json"
jq -e '.peakObservedAllocatedStoreBytes == null and .finalObservedAllocatedStoreBytes == null' \
    "${fixture_root}/unknown-summary.json" >/dev/null
echo 'Resource-report arithmetic, unknown-value handling and 10 rejection guards passed.'
