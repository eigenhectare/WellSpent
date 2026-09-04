#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly derived_data_root="${WATCH_SMOKE_DERIVED_DATA_ROOT:-${repository_root}/.derivedData/WatchSimulatorSmoke}"
readonly phone_id="${WATCH_PHONE_SIMULATOR_ID:-}"
readonly watch_id="${WATCH_SIMULATOR_ID:-}"
readonly phone_bundle_id="com.drewreilly.wellspent.connectivityspike"
readonly watch_bundle_id="${phone_bundle_id}.watchkitapp"

fail() {
    echo "Watch Simulator smoke failed: $1" >&2
    exit 1
}

[[ -n "${phone_id}" ]] || fail "set WATCH_PHONE_SIMULATOR_ID"
[[ -n "${watch_id}" ]] || fail "set WATCH_SIMULATOR_ID"

pair_listing="$(xcrun simctl list pairs)"
[[ "${pair_listing}" == *"${phone_id}"* && "${pair_listing}" == *"${watch_id}"* ]] \
    || fail "the supplied iPhone and Watch simulators are not in the device-pair listing"

cd "${repository_root}"
xcodegen generate --spec project.yml

xcrun simctl bootstatus "${phone_id}" -b
xcrun simctl bootstatus "${watch_id}" -b

xcodebuild \
    -project WellSpent.xcodeproj \
    -scheme WellSpentConnectivitySpikePhone \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=${phone_id}" \
    -derivedDataPath "${derived_data_root}/Phone" \
    -parallel-testing-enabled NO \
    -only-testing:WellSpentConnectivitySpikePhoneUITests \
    test

xcodebuild \
    -project WellSpent.xcodeproj \
    -scheme WellSpentConnectivitySpikeWatch \
    -configuration Debug \
    -destination "platform=watchOS Simulator,id=${watch_id}" \
    -derivedDataPath "${derived_data_root}/Watch" \
    -parallel-testing-enabled NO \
    -only-testing:WellSpentConnectivitySpikeWatchUITests \
    test

xcrun simctl get_app_container "${phone_id}" "${phone_bundle_id}" app >/dev/null
xcrun simctl get_app_container "${watch_id}" "${watch_bundle_id}" app >/dev/null

echo "Paired Simulator Xcode UI install/launch smoke passed."
echo "This is UI evidence only; Simulator cannot validate transferUserInfo."
