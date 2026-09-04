#!/bin/bash
set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly derived_data_root="${CI_DERIVED_DATA_ROOT:-${repository_root}/.derivedData/CI}"
readonly simulator_destination="${CI_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5}"
readonly watch_simulator_destination="${CI_WATCH_SIMULATOR_DESTINATION:-platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5}"
cd "${repository_root}"

for command in xcodegen xcodebuild xcrun jq rg; do
    command -v "${command}" >/dev/null || { echo "Missing CI prerequisite: ${command}" >&2; exit 1; }
done
mkdir -p "${derived_data_root}"
readonly run_root="$(mktemp -d "${derived_data_root}/run.XXXXXX")"
mkdir -p "${run_root}/logs" "${run_root}/results"
readonly report="${run_root}/stages.tsv"
printf 'stage\tresult\tseconds\n' > "${report}"
echo "CI evidence: ${run_root}"

source "${script_directory}/ci-run-stage.sh"

toolchain() {
    xcodebuild -version
    xcodegen --version
    xcrun swift --version
    xcodebuild -showsdks
    xcrun simctl list devices available
}

structural_checks() {
    bash -n "${script_directory}"/*.sh
    bash "${script_directory}/ci-guard-regression-tests.sh"
    bash "${script_directory}/lint.sh"
    bash "${script_directory}/privacy-audit.sh"
    bash "${script_directory}/privacy-audit-regression-tests.sh"
    bash "${script_directory}/watch-localization-regression-tests.sh"
    bash "${script_directory}/watch-resource-regression-tests.sh"
    bash "${script_directory}/watch-release-guard-tests.sh"
    bash "${script_directory}/watch-release-symbol-regression-tests.sh"
    bash "${script_directory}/watch-product-device-preflight-regression-tests.sh"
    bash "${script_directory}/watch-physical-storage-regression-tests.sh"
    bash "${script_directory}/watch-physical-matrix-regression-tests.sh"
    bash "${script_directory}/watch-release-copy-check.sh"
    WATCH_CONTRACT_CHECK_MODE=source bash "${script_directory}/watch-contract-check.sh"
    for check in watch-store timer-run watch-connectivity watch-reconciliation watch-project-picker \
        watch-start watch-metrics watch-controls watch-summary watch-companion watch-widget \
        watch-intents watch-goal watch-live-activity watch-localization; do
        bash "${script_directory}/${check}-check.sh"
    done
    bash "${script_directory}/watch-release-source-receipt.sh" "${run_root}/source-provenance"
}

build_pair() {
    local configuration="$1"
    local platform="$2"
    local directory="$3"
    xcodebuild -project WellSpent.xcodeproj -scheme WellSpent -configuration "${configuration}" \
        -destination "generic/platform=${platform}" -derivedDataPath "${run_root}/${directory}" \
        CODE_SIGNING_ALLOWED=NO clean build
}

run_tests() {
    local label="$1" scheme="$2" destination="$3" directory="$4" minimum="$5" expected="$6"
    shift 6
    local allowance=90 maximum=120
    if [[ "${label}" == watch-ui ]]; then
        # Reading both edges of all five doubled-English help paragraphs on
        # the smallest Watch takes about three minutes of real scroll actions.
        allowance=240
        maximum=300
    fi
    xcodebuild -project WellSpent.xcodeproj -scheme "${scheme}" -configuration Debug \
        -destination "${destination}" -destination-timeout 60 \
        -derivedDataPath "${run_root}/${directory}" -resultBundlePath "${run_root}/results/${label}.xcresult" \
        -parallel-testing-enabled NO -test-timeouts-enabled YES \
        -default-test-execution-time-allowance "${allowance}" -maximum-test-execution-time-allowance "${maximum}" \
        "$@" test
    # Standard simulator signing preserves App Group access. Unsigned builds are
    # a separate compile gate, never a substitute for entitled runtime tests.
    bash "${script_directory}/ci-check-results.sh" "${run_root}/results/${label}.xcresult" "${minimum}" "${expected}"
}

run_ui() {
    local label="$1" scheme="$2" destination="$3" directory="$4" manifest="$5" target="$6"
    local selections=() selected minimum=0
    while IFS= read -r selected || [[ -n "${selected}" ]]; do
        [[ -z "${selected}" || "${selected}" == \#* ]] && continue
        [[ "${selected}" =~ ^[A-Za-z0-9_]+/[A-Za-z0-9_]+/test[A-Za-z0-9_]+$ ]] || return 1
        selections+=("-only-testing:${selected}")
        minimum=$((minimum + 1))
    done < "${manifest}"
    if [[ "${CI_FULL_UI:-0}" == 1 ]]; then
        selections=("-only-testing:${target}")
    fi
    run_tests "${label}" "${scheme}" "${destination}" "${directory}" "${minimum}" "${manifest}" "${selections[@]}"
}

verify_products() {
    local phone_app="${run_root}/Release-Simulator/Build/Products/Release-iphonesimulator/WellSpent.app"
    local device_app="${run_root}/Release-Device/Build/Products/Release-iphoneos/WellSpent.app"
    WATCH_FOUNDATION_VERIFY_ONLY=1 WATCH_FOUNDATION_IPHONE_APP="${phone_app}" \
        WATCH_FOUNDATION_TEST_PRODUCTS="${run_root}/WatchTests/Build/Products/Debug-watchsimulator" \
        bash "${script_directory}/watch-foundation-check.sh"
    WATCH_INTENTS_APP_BUNDLE="${phone_app}/Watch/WellSpentWatch.app" \
        bash "${script_directory}/watch-intents-check.sh"
    PRIVACY_AUDIT_APP_BUNDLE="${phone_app}" bash "${script_directory}/privacy-audit.sh"
    PRIVACY_AUDIT_APP_BUNDLE="${run_root}/Release-Device/Build/Products/Release-iphoneos/WellSpent.app" \
        bash "${script_directory}/privacy-audit.sh"
    bash "${script_directory}/release-fixture-check.sh" "${phone_app}"
    bash "${script_directory}/release-fixture-check.sh" \
        "${run_root}/Release-Device/Build/Products/Release-iphoneos/WellSpent.app"
    bash "${script_directory}/watch-localization-check.sh" \
        "${run_root}/Release-Simulator/Build/Intermediates.noindex/WellSpent.build/Release-watchsimulator"
    # Inspect this run's exact joint device product. Unsigned evidence never
    # substitutes for a signed archive, provisioning, upload or release gate.
    bash "${script_directory}/watch-release-check.sh" unsigned-device-app "${device_app}" \
        "${run_root}/release-package-inspection"
    bash "${script_directory}/watch-release-guard-tests.sh" "${device_app}"
    jq -e -n \
        --slurpfile source "${run_root}/source-provenance/summary.json" \
        --slurpfile product "${run_root}/release-package-inspection/summary.json" '
        ($source[0]) as $s | ($product[0]) as $p |
        if $s.sourceClean == true
            and ($s.sourceCommit | test("^[0-9a-f]{40}$"))
            and ($s.productionSourceManifestSHA256 | test("^[0-9a-f]{64}$"))
            and $p.inspection == "passed"
            and $p.releaseApproved == false
            and ([ $p.components[].version ] | unique) == [$s.version]
            and ([ $p.components[].build ] | unique) == [$s.build]
        then {
            schemaVersion: 1,
            sourceCommit: $s.sourceCommit,
            sourceTree: $s.sourceTree,
            productionSourceManifestSHA256: $s.productionSourceManifestSHA256,
            productFileManifestSHA256: $p.productFileManifestSHA256,
            version: $s.version,
            build: $s.build,
            packageInspectionMode: $p.mode,
            releaseApproved: false
        }
        else error("Clean source and inspected product identity do not match")
        end
    ' > "${run_root}/source-product-provenance.json"
}

run_stage toolchain toolchain
run_stage generate bash "${script_directory}/xcodegen-drift-check.sh"
run_stage source-gates structural_checks
# Each joint build compiles/embeds iPhone, Watch, and both widgets for its SDK.
run_stage debug-simulator build_pair Debug 'iOS Simulator' Debug-Simulator
run_stage release-simulator build_pair Release 'iOS Simulator' Release-Simulator
run_stage debug-device build_pair Debug iOS Debug-Device
run_stage release-device build_pair Release iOS Release-Device
run_stage golden-ios run_tests golden-ios WellSpentWatchContracts "${simulator_destination}" Contracts 19 "" \
    -only-testing:WellSpentWatchContractTests
# The Watch unit target includes exactly the same golden-fixture source files.
run_stage watch-unit run_tests watch-unit WellSpentWatch "${watch_simulator_destination}" WatchTests 123 \
    "${script_directory}/ci-watch-critical-tests.txt" -only-testing:WellSpentWatchTests
run_stage phone-unit run_tests phone-unit WellSpent "${simulator_destination}" PhoneTests 161 \
    "${script_directory}/ci-phone-critical-tests.txt" -only-testing:WellSpentTests
run_stage release-products verify_products
run_stage watch-ui run_ui watch-ui WellSpentWatch "${watch_simulator_destination}" WatchTests \
    "${script_directory}/ci-watch-ui-tests.txt" WellSpentWatchUITests
run_stage phone-ui run_ui phone-ui WellSpent "${simulator_destination}" PhoneTests \
    "${script_directory}/ci-phone-ui-tests.txt" WellSpentUITests
echo "CI passed. Complete stage/result evidence: ${report}"
