#!/bin/bash
set -euo pipefail
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentCIGuards.XXXXXX")"
readonly validator="${script_directory}/ci-check-results-json.sh"
echo "CI guard regression evidence: ${fixture_root}"

printf '%s\n' '{"result":"Passed","failedTests":0,"expectedFailures":0,"skippedTests":0,"passedTests":1,"totalTestCount":1}' \
    > "${fixture_root}/summary.json"
printf '%s\n' '{"testNodes":[{"nodeType":"Test Case","result":"Passed","nodeIdentifierURL":"test://com.apple.xcode/App/Tests/Suite/testRequired"}]}' \
    > "${fixture_root}/tests.json"
printf '%s\n' 'Tests/Suite/testRequired' > "${fixture_root}/required.txt"
bash "${validator}" "${fixture_root}/summary.json" "${fixture_root}/tests.json" 1 "${fixture_root}/required.txt"

expect_rejected() {
    local label="$1"
    shift
    if "$@" > "${fixture_root}/${label}.log" 2>&1; then
        echo "CI guard falsely accepted: ${label}" >&2; exit 1
    fi
}

for mutation in '.result = "Failed"' '.failedTests = 1' '.expectedFailures = 1' '.skippedTests = 1' \
    '.passedTests = 0 | .totalTestCount = 0' '.totalTestCount = 2'; do
    jq "${mutation}" "${fixture_root}/summary.json" > "${fixture_root}/rejected.json"
    expect_rejected summary bash "${validator}" "${fixture_root}/rejected.json" "${fixture_root}/tests.json" 1
done
printf '%s\n' 'Tests/Suite/testMissing' > "${fixture_root}/missing.txt"
expect_rejected missing-required bash "${validator}" "${fixture_root}/summary.json" \
    "${fixture_root}/tests.json" 1 "${fixture_root}/missing.txt"
jq '.testNodes[0].result = "Skipped"' "${fixture_root}/tests.json" > "${fixture_root}/skipped.json"
expect_rejected skipped-required bash "${validator}" "${fixture_root}/summary.json" \
    "${fixture_root}/skipped.json" 1 "${fixture_root}/required.txt"

# Exercise the actual stage runner, with a successful command following a
# failure inside the same function. The second command must never execute.
mkdir -p "${fixture_root}/stage/logs"
expect_rejected fail-fast bash -e -c '
    source "$1/ci-run-stage.sh"
    run_root="$2/stage"
    report="$run_root/stages.tsv"
    fails_before_success() { false; touch "$run_root/masked-failure"; }
    run_stage injected-failure fails_before_success
' guard-test "${script_directory}" "${fixture_root}"
[[ ! -e "${fixture_root}/stage/masked-failure" ]]
rg -q $'injected-failure\tfailed\t' "${fixture_root}/stage/stages.tsv"

readonly app="${fixture_root}/Release.app"
for executable in WellSpent Watch/WellSpentWatch.app/WellSpentWatch \
    PlugIns/WellSpentWidgets.appex/WellSpentWidgets \
    Watch/WellSpentWatch.app/PlugIns/WellSpentWatchWidgets.appex/WellSpentWatchWidgets; do
    mkdir -p "$(dirname "${app}/${executable}")"
    printf 'ordinary executable bytes\n' > "${app}/${executable}"
done
bash "${script_directory}/release-fixture-check.sh" "${app}"
printf 'WAT22_FAULT_FIXTURE\n' > "${app}/Watch/WellSpentWatch.app/fixture-canary"
expect_rejected fixture-canary bash "${script_directory}/release-fixture-check.sh" "${app}"
# Use a separate clean package for the embedded-test-bundle rejection.
readonly second_app="${fixture_root}/EmbeddedTest.app"
mkdir -p "${second_app}"
for executable in WellSpent Watch/WellSpentWatch.app/WellSpentWatch \
    PlugIns/WellSpentWidgets.appex/WellSpentWidgets \
    Watch/WellSpentWatch.app/PlugIns/WellSpentWatchWidgets.appex/WellSpentWatchWidgets; do
    mkdir -p "$(dirname "${second_app}/${executable}")"
    printf 'ordinary executable bytes\n' > "${second_app}/${executable}"
done
mkdir -p "${second_app}/Unexpected.xctest"
expect_rejected embedded-test bash "${script_directory}/release-fixture-check.sh" "${second_app}"
echo 'CI fail-fast, executed-test accounting and Release isolation negative checks passed.'
