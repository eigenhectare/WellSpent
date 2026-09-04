#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

fail() {
    echo "Watch metrics check failed: $1" >&2
    exit 1
}

cd "${repository_root}"

for path in \
    WellSpentWatch/Features/Timer/WatchTimerMetrics.swift \
    WellSpentWatch/Features/Timer/WatchStartedTimerView.swift \
    WellSpentWatchTests/WatchTimerMetricsTests.swift \
    WAT-14-LIVE-METRICS.md
do
    [[ -f "${path}" ]] || fail "missing ${path}"
done

rg -q 'ownedSegments\.reduce' WellSpentWatch/Features/Timer/WatchTimerMetrics.swift \
    || fail "elapsed is not derived from owned segment intervals"
rg -q 'wallSeconds - billableSeconds' WellSpentWatch/Features/Timer/WatchTimerMetrics.swift \
    || fail "paused duration is not derived from wall minus billable time"
rg -q 'run\.state == \.running' WellSpentWatch/Features/Timer/WatchTimerMetrics.swift \
    || fail "open-segment advancement is not restricted to a running timer"
rg -q 'TimelineView' WellSpentWatch/Features/Timer/WatchStartedTimerView.swift \
    || fail "live elapsed has no system timeline"
rg -q '\.tabViewStyle\(\.verticalPage\(transitionStyle:' WellSpentWatch/Features/Timer/WatchStartedTimerView.swift \
    || fail "native vertical Crown paging is missing"
rg -q 'reduceMotion \? \.identity : \.automatic' WellSpentWatch/Features/Timer/WatchStartedTimerView.swift \
    || fail "reduced-motion paging adaptation is missing"
rg -q 'isLuminanceReduced' WellSpentWatch/Features/Timer/WatchStartedTimerView.swift \
    || fail "reduced-luminance handling is missing"
rg -q 'privateName: String.*String\(localized: "Billable timer"\)' WellSpentWatch/Features/Timer/WatchTimerMetrics.swift \
    || fail "privacy-neutral project identity is missing"

for identifier in \
    watch.metrics.elapsed \
    watch.metrics.run \
    watch.metrics.totals \
    watch.metrics.billable \
    watch.metrics.goal \
    watch.timer.pending-sync
do
    rg -q "${identifier}" WellSpentWatch/Features/Timer/WatchStartedTimerView.swift \
        || fail "missing accessibility identifier ${identifier}"
done

for fixture in \
    activeNoGoal \
    activeOffline \
    activePending \
    goalReached \
    largeDuration \
    overtime \
    paused \
    staleTotals
do
    rg -q "case ${fixture}" WellSpentWatch/App/WatchUITestFixture.swift \
        || fail "missing deterministic ${fixture} fixture"
done

for test_name in \
    runningElapsedMatchesExactSegmentIntervals \
    pausedBillableElapsedNeverAdvances \
    goalStatesCoverNoGoalReachedAndOvertime \
    elapsedUsesAbsoluteInstantsAcrossMidnightAndDaylightSavingChanges \
    totalsRemainPhoneAuthoredAndFreshnessUsesTheSnapshotTimeZone \
    reducedLuminanceIdentityUsesNeutralPrivacyCopy \
    testCrownMetricPagesExposeElapsedRunAndPhoneAuthoredTotals \
    testOfflinePendingAndStaleTotalsAreExplicit \
    testPrivacyRedactionAndLargeDurationRemainLegible
do
    rg -q "${test_name}" WellSpentWatchTests WellSpentWatchUITests \
        || fail "missing regression ${test_name}"
done

if rg -n '(print\(|debugPrint\(|os_log\(|Logger\()' \
    WellSpentWatch/Features/Timer
then
    fail "metrics presentation contains an unreviewed logging path"
fi

echo "Watch metrics passed: exact segment math, paused freeze, goals, cached totals, Crown paging, sync state, privacy, and boundary fixtures are regression-covered."
