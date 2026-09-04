#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly derived_data_root="${WATCH_DERIVED_DATA_ROOT:-${repository_root}/.derivedData/WatchPreflight}"
readonly simulator_destination="${WATCH_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"
readonly watch_info="${repository_root}/Spikes/WatchConnectivity/Watch/Info.plist"
readonly phone_bundle_id="com.drewreilly.wellspent.connectivityspike"
readonly watch_bundle_id="${phone_bundle_id}.watchkitapp"

fail() {
    echo "Watch preflight failed: $1" >&2
    exit 1
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2"
}

command -v xcodegen >/dev/null || fail "xcodegen is not installed"

cd "${repository_root}"
xcodegen generate --spec project.yml

[[ "$(plist_value WKCompanionAppBundleIdentifier "${watch_info}")" == "${phone_bundle_id}" ]] \
    || fail "WKCompanionAppBundleIdentifier does not match the iOS bundle ID"
[[ "$(plist_value WKRunsIndependentlyOfCompanionApp "${watch_info}")" == "false" ]] \
    || fail "the dependent Watch app must set WKRunsIndependentlyOfCompanionApp to false"

if /usr/libexec/PlistBuddy -c 'Print :WKWatchOnly' "${watch_info}" >/dev/null 2>&1; then
    fail "WKWatchOnly must be absent for a companion Watch app"
fi

rg -q 'WellSpentConnectivitySpikeWatch.app in Embed Watch Content.*RemoveHeadersOnCopy' \
    WellSpent.xcodeproj/project.pbxproj \
    || fail "the iOS target does not embed the Watch app with RemoveHeadersOnCopy"
rg -q -F 'dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";' WellSpent.xcodeproj/project.pbxproj \
    || fail "the generated project does not use Xcode's native Watch embed directory"
rg -q -F 'dstSubfolderSpec = 16;' WellSpent.xcodeproj/project.pbxproj \
    || fail "the generated project does not use the native Watch content destination"

xcodebuild \
    -project WellSpent.xcodeproj \
    -scheme WellSpentConnectivitySpikePhone \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${derived_data_root}/Phone" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

readonly phone_app="${derived_data_root}/Phone/Build/Products/Debug-iphonesimulator/WellSpentConnectivitySpikePhone.app"
readonly embedded_watch_app="${phone_app}/Watch/WellSpentConnectivitySpikeWatch.app"

[[ -d "${embedded_watch_app}" ]] \
    || fail "the built iOS app does not contain the companion under Watch"
[[ "$(plist_value CFBundleIdentifier "${embedded_watch_app}/Info.plist")" == "${watch_bundle_id}" ]] \
    || fail "the embedded Watch bundle ID is incorrect"
[[ "$(plist_value WKCompanionAppBundleIdentifier "${embedded_watch_app}/Info.plist")" == "${phone_bundle_id}" ]] \
    || fail "the embedded Watch companion ID is incorrect"

readonly phone_build="$(plist_value CFBundleVersion "${phone_app}/Info.plist")"
readonly watch_build="$(plist_value CFBundleVersion "${embedded_watch_app}/Info.plist")"
[[ "${phone_build}" == "${watch_build}" ]] \
    || fail "the iOS and Watch build versions do not match"

xcodebuild \
    -project WellSpent.xcodeproj \
    -scheme WellSpentConnectivitySpikeWatch \
    -configuration Debug \
    -destination 'generic/platform=watchOS Simulator' \
    -derivedDataPath "${derived_data_root}/Watch" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

xcodebuild \
    -project WellSpent.xcodeproj \
    -scheme WellSpentConnectivitySpikePhone \
    -configuration Debug \
    -destination "${simulator_destination}" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 30 \
    -maximum-test-execution-time-allowance 60 \
    -derivedDataPath "${derived_data_root}/Tests" \
    -only-testing:WellSpentConnectivitySpikeTests \
    test

echo "Watch preflight passed: configuration, embedded package, both Simulator builds, and protocol tests."
echo "Physical paired-device testing is still required for Watch Connectivity transport acceptance."
