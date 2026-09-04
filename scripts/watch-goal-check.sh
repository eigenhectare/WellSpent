#!/bin/bash
set -euo pipefail
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
cd "${repository_root}"
fail() { echo "Watch goal check failed: $1" >&2; exit 1; }

rg -q 'wellspent.duration-goal' WellSpentWatch/Features/Goals/WatchGoalAlertPlan.swift || fail 'stable single request ID missing'
rg -q 'WatchWidgetState.make' WellSpentWatch/Features/Goals/WatchGoalAlertPlan.swift || fail 'counted-segment projection missing'
rg -q 'pendingGoal\(\)' WellSpentWatch/Features/Goals/WatchGoalAlertCoordinator.swift || fail 'restart reconciliation missing'
rg -q 'beforeBackgroundTaskCompletion' WellSpentWatch/App/WellSpentWatchRuntime.swift || fail 'finite WC projection completion missing'
rg -q 'completeFileProtectionUntilFirstUserAuthentication' WellSpentWatch/Features/Goals/WatchGoalPreferences.swift || fail 'preference protection missing'
rg -q 'isExcludedFromBackup = true' WellSpentWatch/Features/Goals/WatchGoalPreferences.swift || fail 'preference backup exclusion missing'
rg -q 'performLocalCommand' WellSpentWatch/Features/Goals/WatchTimerGoalBoundary.swift || fail 'goal edits bypass durable commands'
if rg -n '(Timer\.scheduledTimer|HKWorkout|WKExtendedRuntimeSession|registerForRemoteNotifications|UserDefaults)' WellSpentWatch/Features/Goals; then
    fail 'goal alerts gained a timer loop, unrelated runtime, remote registration, or unprotected preferences'
fi
for test_source in WellSpentWatchTests/WatchGoalAlertTests.swift WellSpentWatchUITests/WatchGoalUITests.swift; do
    [[ -s "${test_source}" ]] || fail 'goal regression suite missing'
done
echo "Watch goal structural checks passed. WatchGoalAlertTests and WatchGoalUITests prove behavior; physical long-goal delivery remains separate."

