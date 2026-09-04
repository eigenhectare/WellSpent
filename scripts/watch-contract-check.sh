#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly derived_data_root="${WATCH_CONTRACT_DERIVED_DATA_ROOT:-${repository_root}/.derivedData/WatchContracts}"
readonly check_mode="${WATCH_CONTRACT_CHECK_MODE:-full}"

fail() {
    echo "Watch contract check failed: $1" >&2
    exit 1
}

build_contract() {
    local configuration="$1"
    local destination="$2"
    local platform_name="$3"

    xcodebuild \
        -project WellSpent.xcodeproj \
        -scheme WellSpentWatchContracts \
        -configuration "${configuration}" \
        -destination "${destination}" \
        -derivedDataPath "${derived_data_root}/${platform_name}-${configuration}" \
        CODE_SIGNING_ALLOWED=NO \
        clean build
}

build_contract_tests() {
    local destination="$1"
    local platform_name="$2"

    xcodebuild \
        -project WellSpent.xcodeproj \
        -scheme WellSpentWatchContracts \
        -configuration Debug \
        -destination "${destination}" \
        -derivedDataPath "${derived_data_root}/${platform_name}-TestBuild" \
        CODE_SIGNING_ALLOWED=NO \
        build-for-testing
}

cd "${repository_root}"
command -v xcodegen >/dev/null || fail "xcodegen is not installed"
xcodegen generate --spec project.yml

readonly unexpected_imports="$({
    rg -n '^import ' WellSpentWatchContracts || true
} | rg -v '^.*:import Foundation$' || true)"
[[ -z "${unexpected_imports}" ]] || fail "the contract target imports an API beyond Foundation"

if rg -n \
    '(^import (SwiftData|ActivityKit|WatchConnectivity|UserNotifications|SwiftUI)$|WCSession[.(]|ModelContainer[<(]|UNUserNotificationCenter[.(])' \
    WellSpentWatchContracts
then
    fail "the contract target references a platform or persistence framework"
fi

if [[ "${check_mode}" == source ]]; then
    echo "Watch contract source boundary passed; CI separately builds both platforms and runs the golden fixtures."
    exit 0
fi
[[ "${check_mode}" == full ]] || fail 'unknown check mode'

build_contract Debug 'generic/platform=iOS Simulator' iOS-Simulator
build_contract Release 'generic/platform=iOS Simulator' iOS-Simulator
build_contract Debug 'generic/platform=watchOS Simulator' watchOS-Simulator
build_contract Release 'generic/platform=watchOS Simulator' watchOS-Simulator
build_contract_tests 'generic/platform=iOS Simulator' iOS-Simulator
build_contract_tests 'generic/platform=watchOS Simulator' watchOS-Simulator

for test_bundle in \
    "${derived_data_root}/iOS-Simulator-TestBuild/Build/Products/Debug-iphonesimulator/WellSpentWatchContractTests.xctest" \
    "${derived_data_root}/watchOS-Simulator-TestBuild/Build/Products/Debug-watchsimulator/WellSpentWatchContractTests.xctest"
do
    [[ -d "${test_bundle}" ]] || fail "a platform contract test bundle did not compile"
done

echo "Watch contract passed: one Foundation-only module and one golden-fixture suite compile for iOS and watchOS in Debug and Release."
