#!/bin/bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <iphone-device-id> <watch-device-id> <new-report-directory>" >&2
    exit 64
fi

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly iphone_id="$1"
readonly watch_id="$2"
report_directory="$3"
readonly phone_bundle_id='com.drewreilly.wellspent'
readonly watch_bundle_id='com.drewreilly.wellspent.watchkitapp'

fail() { echo "WellSpent device preflight failed: $1" >&2; exit 1; }
[[ ! -e "${report_directory}" ]] || fail 'report directory already exists; preserve earlier evidence'
report_parent="$(cd "$(dirname "${report_directory}")" && pwd -P)" \
    || fail 'report parent must already exist'
report_directory="${report_parent}/$(basename "${report_directory}")"
readonly report_directory

readonly expected_version="$(awk '$1 == "MARKETING_VERSION:" { print $2; exit }' "${repository_root}/project.yml")"
readonly expected_build="$(awk '$1 == "CURRENT_PROJECT_VERSION:" { print $2; exit }' "${repository_root}/project.yml")"
[[ "${expected_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'invalid configured marketing version'
[[ "${expected_build}" =~ ^[0-9]+$ ]] || fail 'invalid configured build version'

scratch_directory="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentDevicePreflight.XXXXXX")"
readonly scratch_directory
cleanup() {
    [[ -n "${scratch_directory}" && -d "${scratch_directory}" ]] || return
    rm -rf -- "${scratch_directory}"
}
trap cleanup EXIT

phone_details="${scratch_directory}/phone-details.json"
watch_details="${scratch_directory}/watch-details.json"
phone_apps="${scratch_directory}/phone-apps.json"
watch_apps="${scratch_directory}/watch-apps.json"
destinations="${scratch_directory}/destinations.txt"
readonly phone_details watch_details phone_apps watch_apps destinations

# These CoreDevice files contain identifiers and are destroyed by the EXIT trap.
# Only the explicitly selected, sanitized fields below enter the retained report.
xcrun devicectl device info details --device "${iphone_id}" \
    --json-output "${phone_details}" --timeout 30 >/dev/null
xcrun devicectl device info details --device "${watch_id}" \
    --json-output "${watch_details}" --timeout 30 >/dev/null
xcrun devicectl device info apps --device "${iphone_id}" \
    --bundle-id "${phone_bundle_id}" --json-output "${phone_apps}" --timeout 30 >/dev/null
xcrun devicectl device info apps --device "${watch_id}" \
    --bundle-id "${watch_bundle_id}" --json-output "${watch_apps}" --timeout 30 >/dev/null
xcodebuild -project "${repository_root}/WellSpent.xcodeproj" \
    -scheme WellSpentWatch -showdestinations >"${destinations}" 2>&1

[[ "$(jq -r '.result.apps | length' "${phone_apps}")" -le 1 ]] \
    || fail 'multiple phone apps matched the exact production bundle identifier'
[[ "$(jq -r '.result.apps | length' "${watch_apps}")" -le 1 ]] \
    || fail 'multiple Watch apps matched the exact production bundle identifier'

readonly watch_xcode_id="$(jq -r '.result.hardwareProperties.udid' "${watch_details}")"
[[ -n "${watch_xcode_id}" && "${watch_xcode_id}" != null ]] || fail 'Watch Xcode identifier unavailable'
if grep -Fq "id:${watch_xcode_id}" "${destinations}"; then
    xcode_destination_available=true
else
    xcode_destination_available=false
fi
readonly xcode_destination_available

readonly observed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
mkdir -p "${report_directory}"
jq -n \
    --arg observedAt "${observed_at}" \
    --arg expectedVersion "${expected_version}" \
    --arg expectedBuild "${expected_build}" \
    --arg phoneBundleID "${phone_bundle_id}" \
    --arg watchBundleID "${watch_bundle_id}" \
    --argjson xcodeDestinationAvailable "${xcode_destination_available}" \
    --slurpfile phoneDetails "${phone_details}" \
    --slurpfile watchDetails "${watch_details}" \
    --slurpfile phoneApps "${phone_apps}" \
    --slurpfile watchApps "${watch_apps}" \
    -f "${script_directory}/watch-product-device-preflight-summary.jq" \
    >"${report_directory}/summary.json"

if [[ "$(jq -r '.result' "${report_directory}/summary.json")" == ready ]]; then
    echo "WellSpent product device preflight ready. No device state changed. Evidence: ${report_directory}/summary.json"
else
    echo "WellSpent product device preflight blocked. No device state changed. Evidence: ${report_directory}/summary.json"
    exit 1
fi
