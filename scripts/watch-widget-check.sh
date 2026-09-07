#!/bin/bash
set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
cd "${repository_root}"

fail() { echo "Watch widget structural check failed: $1" >&2; exit 1; }

for task_file in \
    WellSpentWatchStore/WatchWidgetState.swift \
    WellSpentWatchStore/WatchWidgetSnapshotReader.swift \
    WellSpentWatchWidgets/WellSpentWatchStatusView.swift \
    WellSpentWatchTests/WatchWidgetStateTests.swift \
    WellSpentWatchUITests/WatchWidgetUITests.swift
do
    [[ -f "${task_file}" ]] || fail "missing ${task_file}"
done

rg -q 'allowsSave: false' WellSpentWatchStore/WatchWidgetSnapshotReader.swift || fail "writer enabled in widget reader"
rg -q 'showProjectNamesOnSystemSurfaces == true' WellSpentWatchStore/WatchWidgetState.swift || fail "explicit privacy opt-in missing"
rg -q 'isLuminanceReduced' WellSpentWatchWidgets/WellSpentWatchStatusView.swift || fail "Always On fallback missing"
rg -q 'context.isPreview' WellSpentWatchWidgets/WellSpentWatchStatusWidget.swift || fail "gallery privacy missing"
rg -q 'WellSpentHourglassSilhouette' WellSpentWatchWidgets/WellSpentWatchStatusView.swift \
    || fail "custom hourglass mark missing"
rg -q 'WellSpentHourglassTrace' WellSpentWatchWidgets/WellSpentWatchStatusView.swift \
    || fail "running trace missing"
rg -q '\.linear\(duration: 2\)' WellSpentWatchWidgets/WellSpentWatchStatusView.swift \
    || fail "two-second trace animation missing"
rg -q '\.widgetAccentable\(\)' WellSpentWatchWidgets/WellSpentWatchStatusView.swift \
    || fail "Watch-face palette adaptation missing"
rg -q 'watch.complication.hourglass' WellSpentWatchWidgets/WellSpentWatchStatusView.swift \
    || fail "hourglass accessibility identity missing"
if rg -n '^[[:space:]]*(Text|Label)\(|timerInterval:|projectName' WellSpentWatchWidgets/WellSpentWatchStatusView.swift; then
    fail "complication contains visible words, numbers, or project identity"
fi
rg -q 'reloadTimelines\(ofKind: WatchWidgetState.kind\)' WellSpentWatch/App/WellSpentWatchRuntime.swift || fail "state-change reload missing"
rg -q 'wellspent-watch' WellSpentWatch/Resources/Info.plist || fail "Watch navigation scheme missing"

for family in accessoryCircular accessoryCorner accessoryInline accessoryRectangular; do
    rg -q "\.${family}" WellSpentWatchWidgets/WellSpentWatchStatusWidget.swift || fail "missing ${family}"
done

if rg -n '(Timer\.scheduledTimer|while true|Task\.sleep|performLocalCommand|ModelContext|ModelContainer)' WellSpentWatchWidgets; then
    fail "widget contains a writer or background tick loop"
fi

echo "Watch widget structural checks passed. Run WatchWidgetStateTests, WatchStoreTests, PhoneWatchSyncStoreTests and WatchWidgetUITests for behavioral evidence; physical WidgetKit remains a separate gate."
