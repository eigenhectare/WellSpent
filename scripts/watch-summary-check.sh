#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

fail() {
    echo "Watch summary check failed: $1" >&2
    exit 1
}

cd "${repository_root}"

for path in \
    WellSpentWatch/Features/Timer/WatchTimerAnnotationBoundary.swift \
    WellSpentWatch/Features/Timer/WatchEndedTimerSummaryView.swift \
    WellSpentWatchTests/WatchTimerAnnotationBoundaryTests.swift \
    WAT-16-WATCH-END-SUMMARY.md
do
    [[ -f "${path}" ]] || fail "missing ${path}"
done

rg -q 'typealias Persist = \(TimerMutationAction, Date, String\)' \
    WellSpentWatch/Features/Timer/WatchTimerAnnotationBoundary.swift \
    || fail "annotation does not use one UI-independent persistence adapter"
rg -q '\.annotate\(' \
    WellSpentWatch/Features/Timer/WatchTimerAnnotationBoundary.swift \
    || fail "complete annotate action is missing"
rg -q 'performLocalCommand\(' WellSpentWatch/App/WellSpentWatchRuntime.swift \
    || fail "summary is not connected to the atomic Watch store"
rg -q 'TextField\("Optional note"' \
    WellSpentWatch/Features/Timer/WatchEndedTimerSummaryView.swift \
    || fail "standard watchOS text entry is missing"
rg -q 'WatchTimerMetrics.calculate' \
    WellSpentWatch/Features/Timer/WatchEndedTimerSummaryView.swift \
    || fail "summary is not derived from persisted segments"

for identifier in \
    watch.end-summary.billable \
    watch.end-summary.sync \
    watch.end-summary.note \
    watch.end-summary.tags \
    watch.end-summary.save \
    watch.end-summary.done
do
    rg -q "${identifier}" WellSpentWatch/Features/Timer/WatchEndedTimerSummaryView.swift \
        || fail "missing accessibility identifier ${identifier}"
done

for detail_identifier in paused started ended goal segments
do
    rg -q "identifier: \"${detail_identifier}\"" \
        WellSpentWatch/Features/Timer/WatchEndedTimerSummaryView.swift \
        || fail "missing summary detail identifier ${detail_identifier}"
done

for test_name in \
    saveNormalizesNoteSortsTagsAndCapturesOneBoundary \
    whitespaceOnlyNoteClearsTheSavedNote \
    noteOnlyEditPreservesAnAssignedHistoricalTag \
    invalidStateUnknownTagOversizedAndUnchangedDraftsNeverPersist \
    saveFailureRollsBackAnnotationAndOutboxTogether \
    testEndedRunAnnotationAndPendingOutboxSurviveContainerRecreation \
    testLateWatchAnnotationConflictsWithoutOverwritingPhoneEditAndRetryIsDuplicate \
    testEndedSummaryShowsExactOrderedBillingDetailsBeforeOptionalEdits \
    testSystemNoteEntryCancelAndDoneLeaveEndedRunSafe \
    testOfflineTagAnnotationPersistsBeforeSuccessAndShowsPendingState \
    testAnnotationFailureCanDiscardEditWithoutChangingEndedRun \
    testDoneRequiresConfirmationForAnUnsavedAnnotationDraft \
    testHistoricalTagLongContentAndSummaryRelaunchRemainUnderstandable
do
    rg -q "${test_name}" WellSpentWatchTests WellSpentWatchUITests WellSpentTests \
        || fail "missing regression ${test_name}"
done

if rg -n '(print\(|debugPrint\(|os_log\(|Logger\()' \
    WellSpentWatch/Features/Timer \
    WellSpentWatch/App/WellSpentWatchRuntime.swift
then
    fail "summary path contains an unreviewed logging path"
fi

echo "Watch summary passed: exact persisted metrics, optional system note entry, active/historical tags, atomic offline saves, retry, relaunch, and conflict safety are regression-covered."
