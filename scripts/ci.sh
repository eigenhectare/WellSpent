#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly derived_data_root="${CI_DERIVED_DATA_ROOT:-${repository_root}/.derivedData/CI}"
readonly simulator_destination="${CI_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"

cd "${repository_root}"

"${script_directory}/lint.sh"
"${script_directory}/privacy-audit.sh"

xcodebuild \
    -project BillableHours.xcodeproj \
    -scheme BillableHours \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${derived_data_root}/Debug" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

xcodebuild \
    -project BillableHours.xcodeproj \
    -scheme BillableHours \
    -configuration Release \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${derived_data_root}/Release" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

xcodebuild \
    -project BillableHours.xcodeproj \
    -scheme BillableHours \
    -configuration Debug \
    -destination "${simulator_destination}" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 30 \
    -maximum-test-execution-time-allowance 60 \
    -derivedDataPath "${derived_data_root}/Tests" \
    -only-testing:BillableHoursTests \
    test
