#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <watch-device-id> <new-report-directory>" >&2
    exit 64
fi

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly watch_id="$1"
report_directory="$2"
readonly watch_bundle_id='com.drewreilly.wellspent.watchkitapp'
readonly watch_group_id='group.com.drewreilly.wellspent.watch'

fail() { echo "WellSpent physical storage observation failed: $1" >&2; exit 1; }
[[ ! -e "${report_directory}" ]] || fail 'report directory already exists; preserve earlier evidence'
report_parent="$(cd "$(dirname "${report_directory}")" && pwd -P)" \
    || fail 'report parent must already exist'
report_directory="${report_parent}/$(basename "${report_directory}")"
readonly report_directory

for command in xcrun jq; do
    command -v "${command}" >/dev/null || fail "missing prerequisite: ${command}"
done

readonly expected_version="$(awk '$1 == "MARKETING_VERSION:" { print $2; exit }' "${repository_root}/project.yml")"
readonly expected_build="$(awk '$1 == "CURRENT_PROJECT_VERSION:" { print $2; exit }' "${repository_root}/project.yml")"
[[ "${expected_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'invalid configured marketing version'
[[ "${expected_build}" =~ ^[0-9]+$ ]] || fail 'invalid configured build version'

scratch_directory="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentPhysicalStorage.XXXXXX")"
readonly scratch_directory
cleanup() {
    [[ -n "${scratch_directory}" && -d "${scratch_directory}" ]] || return
    rm -rf -- "${scratch_directory}"
}
trap cleanup EXIT

readonly watch_details="${scratch_directory}/watch-details.json"
readonly watch_apps="${scratch_directory}/watch-apps.json"
readonly group_files="${scratch_directory}/group-files.json"
readonly app_files="${scratch_directory}/app-files.json"

# Raw CoreDevice results contain device identifiers and are destroyed by the
# EXIT trap. Only fixed aliases, candidate fields and WellSpent-owned generic
# path roles/sizes enter the retained report.
xcrun devicectl device info details --device "${watch_id}" \
    --json-output "${watch_details}" --timeout 30 >/dev/null
xcrun devicectl device info apps --device "${watch_id}" \
    --bundle-id "${watch_bundle_id}" --json-output "${watch_apps}" --timeout 30 >/dev/null
xcrun devicectl device info files --device "${watch_id}" \
    --domain-type appGroupDataContainer --domain-identifier "${watch_group_id}" \
    --columns '*' --json-output "${group_files}" --timeout 30 >/dev/null
xcrun devicectl device info files --device "${watch_id}" \
    --domain-type appDataContainer --domain-identifier "${watch_bundle_id}" \
    --columns '*' --json-output "${app_files}" --timeout 30 >/dev/null

readonly observed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
mkdir -p "${report_directory}"
jq -n \
    --arg observedAt "${observed_at}" \
    --arg expectedVersion "${expected_version}" \
    --arg expectedBuild "${expected_build}" \
    --arg watchBundleID "${watch_bundle_id}" \
    --slurpfile watchDetails "${watch_details}" \
    --slurpfile watchApps "${watch_apps}" \
    --slurpfile groupFiles "${group_files}" \
    --slurpfile appFiles "${app_files}" \
    -f "${script_directory}/watch-physical-storage-summary.jq" \
    >"${report_directory}/summary.json"

if [[ "$(jq -r '.result' "${report_directory}/summary.json")" == observed ]]; then
    echo "WellSpent physical Watch storage metadata observed. Raw device data deleted. Evidence: ${report_directory}/summary.json"
else
    echo "WellSpent physical Watch storage observation blocked. Raw device data deleted. Evidence: ${report_directory}/summary.json"
    exit 1
fi
