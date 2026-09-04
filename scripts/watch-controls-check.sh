#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

fail() {
    echo "Watch controls check failed: $1" >&2
    exit 1
}

cd "${repository_root}"

for path in \
    WellSpentWatch/Features/Timer/WatchTimerControlBoundary.swift \
    WellSpentWatch/Features/Timer/WatchTimerControlsView.swift \
    WellSpentWatch/Features/Timer/WatchEndedTimerSummaryView.swift \
    WellSpentWatchTests/WatchTimerControlBoundaryTests.swift \
    WAT-15-WATCH-CONTROLS.md
do
    [[ -f "${path}" ]] || fail "missing ${path}"
done

rg -q 'typealias Persist = \(TimerMutationAction, Date, String\)' \
    WellSpentWatch/Features/Timer/WatchTimerControlBoundary.swift \
    || fail "controls do not share one UI-independent persistence adapter"
rg -q '\.switch\(' WellSpentWatch/Features/Timer/WatchTimerControlBoundary.swift \
    || fail "atomic Switch action is missing"
rg -q 'performLocalCommand\(' WellSpentWatch/App/WellSpentWatchRuntime.swift \
    || fail "runtime is not connected to the atomic Watch store"
rg -q '\.tabViewStyle\(\.page\(indexDisplayMode: \.never\)\)' \
    WellSpentWatch/Features/Timer/WatchStartedTimerView.swift \
    || fail "horizontal metric/control navigation is missing"

for identifier in \
    watch.controls.end \
    watch.controls.pause \
    watch.controls.resume \
    watch.controls.new \
    watch.controls.busy \
    watch.switch.screen \
    watch.end-summary.screen
do
    rg -q "${identifier}" WellSpentWatch/Features/Timer \
        || fail "missing accessibility identifier ${identifier}"
done

for test_name in \
    pauseCapturesOneBoundaryAndARepeatedPauseCannotAppendMutation \
    resumeOpensExactlyOneNewSegmentWithoutCountingPausedGap \
    endClosesRunningSegmentButDoesNotChangePausedSegmentBoundary \
    switchEndsAndStartsAtOneExactBoundary \
    failedSwitchRollsBackOldRunSegmentAndOutboxTogether \
    testEndedRunAndItsPendingOutboxSurviveContainerRecreation \
    testHorizontalSwipeRevealsWorkoutStyleControlSurface \
    testPauseAndResumeExposeBusyStateAndPersistVisibleState \
    testEndRequiresConfirmationThenRoutesToPersistedSummary \
    testNewSwitchesProjectsAndFailureKeepsOriginalRun \
    testSwitchPickerHandlesOfflineSingleProjectAndArchivedDestination
do
    rg -q "${test_name}" WellSpentWatchTests WellSpentWatchUITests \
        || fail "missing regression ${test_name}"
done

if rg -n '(print\(|debugPrint\(|os_log\(|Logger\()' \
    WellSpentWatch/Features/Timer \
    WellSpentWatch/App/WellSpentWatchRuntime.swift
then
    fail "control path contains an unreviewed logging path"
fi

echo "Watch controls passed: exact atomic Pause/Resume/Switch/End boundaries, busy gating, confirmation, rollback, offline use, and summary handoff are regression-covered."
