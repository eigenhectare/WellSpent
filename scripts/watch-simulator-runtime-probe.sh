#!/bin/bash

set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "Usage: $0 <watch-simulator-udid> <debug-watch-app> <fixture> <seconds> <new-report-directory>" >&2
    exit 64
fi

readonly simulator_id="$1"
readonly app_input="$2"
readonly fixture="$3"
readonly requested_seconds="$4"
report_input="$5"
readonly bundle_id="com.drewreilly.wellspent.watchkitapp"

fail() {
    echo "Watch simulator runtime probe failed: $1" >&2
    exit 1
}

[[ "${simulator_id}" =~ ^[0-9A-Fa-f-]{36}$ ]] || fail 'simulator identifier is invalid'
[[ -d "${app_input}" && ! -L "${app_input}" ]] || fail 'regular Watch app bundle required'
[[ "${fixture}" =~ ^[a-z][a-z0-9-]*$ ]] || fail 'fixture name is invalid'
[[ "${requested_seconds}" =~ ^[0-9]+$ ]] || fail 'seconds must be an integer'
(( requested_seconds >= 20 && requested_seconds <= 600 )) \
    || fail 'seconds must be between 20 and 600'
[[ ! -e "${report_input}" ]] || fail 'report directory already exists; preserve earlier evidence'

app_bundle="$(cd "${app_input}" && pwd -P)"
report_parent="$(cd "$(dirname "${report_input}")" && pwd -P)" \
    || fail 'report parent must already exist'
report_directory="${report_parent}/$(basename "${report_input}")"
readonly app_bundle report_directory

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app_bundle}/Info.plist" 2>/dev/null)" == "${bundle_id}" ]] \
    || fail 'unexpected Watch app bundle identifier'

scratch_directory="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentSimulatorRuntime.XXXXXX")"
readonly scratch_directory
sample_file="${scratch_directory}/samples.tsv"
launch_file="${scratch_directory}/launch.txt"
readonly sample_file launch_file
process_id=''

cleanup() {
    xcrun simctl terminate "${simulator_id}" "${bundle_id}" >/dev/null 2>&1 || true
    [[ -n "${scratch_directory}" && -d "${scratch_directory}" ]] || return
    rm -rf -- "${scratch_directory}"
}
trap cleanup EXIT

xcrun simctl bootstatus "${simulator_id}" -b >/dev/null
xcrun simctl install "${simulator_id}" "${app_bundle}"
xcrun simctl terminate "${simulator_id}" "${bundle_id}" >/dev/null 2>&1 || true
xcrun simctl launch --terminate-running-process "${simulator_id}" "${bundle_id}" \
    -ui-test-watch-fixture "${fixture}" >"${launch_file}"

process_id="$(awk -F ': ' -v expected="${bundle_id}" '$1 == expected { print $2 }' "${launch_file}")"
[[ "${process_id}" =~ ^[0-9]+$ ]] || fail 'could not resolve launched fixture process'

printf 'elapsedSeconds\tcpuPercent\tresidentKiB\n' >"${sample_file}"
for ((second = 0; second <= requested_seconds; second += 1)); do
    sample="$(LC_ALL=C /bin/ps -p "${process_id}" -o '%cpu=,rss=' 2>/dev/null \
        | awk 'NF == 2 { print $1 "\t" $2 }')"
    [[ -n "${sample}" ]] || fail "fixture process exited before sample ${second}"
    printf '%s\t%s\n' "${second}" "${sample}" >>"${sample_file}"
    (( second == requested_seconds )) || sleep 1
done

readonly warmup_seconds=10
summary_values="$(awk -F '\t' -v warmup="${warmup_seconds}" '
    NR == 1 { next }
    {
        count += 1
        cpuSum += $2
        if (count == 1 || $2 > cpuMax) cpuMax = $2
        if (count == 1 || $3 < rssMin) rssMin = $3
        if (count == 1 || $3 > rssMax) rssMax = $3
        if ($1 >= warmup) {
            steadyCount += 1
            steadyCPUSum += $2
            if (steadyCount == 1 || $2 > steadyCPUMax) steadyCPUMax = $2
            if (steadyCount == 1 || $3 < steadyRSSMin) steadyRSSMin = $3
            if (steadyCount == 1 || $3 > steadyRSSMax) steadyRSSMax = $3
        }
    }
    END {
        if (count == 0 || steadyCount == 0) exit 1
        printf "%d\t%.3f\t%.3f\t%d\t%d\t%d\t%.3f\t%.3f\t%d\t%d", \
            count, cpuSum / count, cpuMax, rssMin, rssMax, \
            steadyCount, steadyCPUSum / steadyCount, steadyCPUMax, steadyRSSMin, steadyRSSMax
    }
' "${sample_file}")" || fail 'could not summarize samples'

IFS=$'\t' read -r sample_count average_cpu maximum_cpu minimum_rss maximum_rss \
    steady_sample_count steady_average_cpu steady_maximum_cpu steady_minimum_rss steady_maximum_rss \
    <<<"${summary_values}"
[[ "${sample_count}" == "$((requested_seconds + 1))" ]] || fail 'sample count mismatch'
[[ "${steady_sample_count}" == "$((requested_seconds - warmup_seconds + 1))" ]] \
    || fail 'steady-state sample count mismatch'

mkdir -p "${report_directory}"
cp "${sample_file}" "${report_directory}/samples.tsv"
jq -n \
    --arg fixture "${fixture}" \
    --argjson requestedSeconds "${requested_seconds}" \
    --argjson sampleCount "${sample_count}" \
    --argjson warmupSeconds "${warmup_seconds}" \
    --argjson averageCPUPercent "${average_cpu}" \
    --argjson maximumCPUPercent "${maximum_cpu}" \
    --argjson minimumResidentKiB "${minimum_rss}" \
    --argjson maximumResidentKiB "${maximum_rss}" \
    --argjson steadySampleCount "${steady_sample_count}" \
    --argjson steadyAverageCPUPercent "${steady_average_cpu}" \
    --argjson steadyMaximumCPUPercent "${steady_maximum_cpu}" \
    --argjson steadyMinimumResidentKiB "${steady_minimum_rss}" \
    --argjson steadyMaximumResidentKiB "${steady_maximum_rss}" \
    '{
        schemaVersion: 1,
        result: "observed",
        scope: "Host-side sampling of a debug-only fictitious Watch Simulator fixture; not physical-device or release-budget evidence.",
        environment: {
            physical: false,
            simulatorClass: "40mm",
            debuggerAttached: false,
            profilerAttached: false
        },
        fixture: $fixture,
        requestedSeconds: $requestedSeconds,
        observedSeconds: $requestedSeconds,
        sampleCount: $sampleCount,
        processMetrics: {
            startupInclusive: {
                sampleCount: $sampleCount,
                averageHostCPUPercent: $averageCPUPercent,
                maximumHostCPUPercent: $maximumCPUPercent,
                minimumResidentKiB: $minimumResidentKiB,
                maximumResidentKiB: $maximumResidentKiB
            },
            steadyState: {
                beginsAtSecond: $warmupSeconds,
                sampleCount: $steadySampleCount,
                averageHostCPUPercent: $steadyAverageCPUPercent,
                maximumHostCPUPercent: $steadyMaximumCPUPercent,
                minimumResidentKiB: $steadyMinimumResidentKiB,
                maximumResidentKiB: $steadyMaximumResidentKiB
            }
        },
        measured: ["host process CPU percentage", "host process resident memory"],
        notMeasured: ["battery", "energy", "wakeups", "WidgetKit execution", "network", "physical Watch CPU", "physical Watch memory"],
        rawIdentifiersRetained: false,
        resourceBudgetPassed: false,
        releaseApproved: false
    }' >"${report_directory}/summary.json"

echo "Watch Simulator runtime observation complete. This is not physical resource acceptance: ${report_directory}/summary.json"
