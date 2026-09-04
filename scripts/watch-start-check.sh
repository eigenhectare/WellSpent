#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

fail() {
    echo "Watch Start check failed: $1" >&2
    exit 1
}

cd "${repository_root}"

for path in \
    WellSpentWatch/Features/Timer/WatchTimerStartBoundary.swift \
    WellSpentWatch/Features/Timer/WatchStartedTimerView.swift \
    WellSpentWatchTests/WatchTimerStartBoundaryTests.swift \
    WAT-13-IMMEDIATE-START.md
do
    [[ -f "${path}" ]] || fail "missing ${path}"
done

if rg -n -i 'countdown|tap to skip|ready for countdown' \
    APPLE-WATCH-PLAN.md \
    WAT-01-WATCH-UX-CONTRACT.md \
    WAT-12-PROJECT-PICKER.md \
    WellSpentWatch \
    WellSpentWatchTests \
    WellSpentWatchUITests
then
    fail "removed pre-start delay remains in the product contract or implementation"
fi

rg -q 'let capturedAt = now\(\)' \
    WellSpentWatch/Features/Timer/WatchTimerStartBoundary.swift \
    || fail "Start does not capture one timestamp"
rg -q 'performLocalCommand\(' WellSpentWatch/App/WellSpentWatchRuntime.swift \
    || fail "runtime is not connected to the atomic Watch store command"
rg -q 'WKInterfaceDevice.current\(\).play\(.start\)' \
    WellSpentWatch/App/WellSpentWatchRuntime.swift \
    || fail "durable Start has no confirmation haptic"
rg -q 'retryPendingTransfers\(forceDurable: true\)' \
    WellSpentWatch/App/WellSpentWatchRuntime.swift \
    || fail "durable Start is not handed to connectivity"

for test_name in \
    startCapturesOneImmediateBoundaryAndPersistsExactGoal \
    rapidRepeatedStartCannotCreateASecondRunOrOutboxEntry \
    persistenceFailureDoesNotReportACommit \
    testPopulatedPickerImmediatelyStartsOpenTimer \
    testPresetGoalImmediatelyStartsTimer \
    testPersistedActiveRunReconstructsWithoutAnIntermediateScreen \
    testStartFailureKeepsPickerRecoverable
do
    rg -q "${test_name}" WellSpentWatchTests WellSpentWatchUITests \
        || fail "missing regression ${test_name}"
done

if rg -n '(print\(|debugPrint\(|os_log\(|Logger\()' \
    WellSpentWatch/Features/Timer \
    WellSpentWatch/App/WellSpentWatchRuntime.swift
then
    fail "Start path contains an unreviewed logging path"
fi

echo "Watch Start passed: immediate boundary, atomic persistence, local success feedback, offline outbox, failure recovery, and rapid-tap safety are regression-covered."
