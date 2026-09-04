#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

fail() {
    echo "Watch project picker check failed: $1" >&2
    exit 1
}

cd "${repository_root}"

for path in \
    WellSpentWatch/Features/Projects/WatchProjectPickerModel.swift \
    WellSpentWatch/Features/Projects/WatchProjectPickerView.swift \
    WellSpentWatch/Features/Projects/WatchRootView.swift \
    WellSpentWatch/App/WatchUITestFixture.swift \
    WAT-12-PROJECT-PICKER.md
do
    [[ -f "${path}" ]] || fail "missing ${path}"
done

rg -q 'enum WatchStoreSchemaV2' WellSpentWatchStore/WatchStoreModels.swift \
    || fail "Watch-local schema V2 is missing"
rg -q 'RecentProjectRecord' WellSpentWatchStore/WatchStoreModels.swift \
    || fail "durable project recency is missing"
rg -q 'fromVersion: WatchStoreSchemaV1.self' WellSpentWatchStore/WatchStoreModels.swift \
    || fail "the additive V1-to-V2 migration is missing"
rg -q 'func recordProjectSelection\(' WellSpentWatchStore/WellSpentWatchStore.swift \
    || fail "the project-selection persistence boundary is missing"
rg -q 'pruneRecentProjects' WellSpentWatchStore/WellSpentWatchStore.swift \
    || fail "snapshot installation does not prune invalid recents"

for state_identifier in \
    finish-setup \
    no-projects \
    update-required \
    review-required
do
    rg -q "identifier: \"${state_identifier}\"" \
        WellSpentWatch/Features/Projects/WatchRootView.swift \
        || fail "missing ${state_identifier} recovery state"
done

for fixture in \
    archived \
    conflict \
    empty \
    longNames \
    offline \
    pending \
    populated \
    setup \
    unsupported
do
    rg -q "case ${fixture}" WellSpentWatch/App/WatchUITestFixture.swift \
        || fail "missing deterministic ${fixture} fixture"
done

for test_name in \
    testProjectSelectionRecencyIsDurableAndMostRecentFirst \
    testProjectTombstonePrunesRecencyAndPreventsResurrection \
    testV1StoreMigratesWithAnEmptyRecentProjectList \
    activeDestinationThenRecentsThenStableCatalogOrder \
    unknownAndDuplicateRecentIDsNeverDuplicateOrInventProjects \
    testPopulatedPickerImmediatelyStartsOpenTimer \
    testPresetGoalImmediatelyStartsTimer \
    testSetupAndEmptyCatalogHaveDifferentRecoveryCopy \
    testCachedProjectRemainsSelectableOfflineAndWhilePending \
    testConflictAndUpgradeAreBlockingStates \
    testLongDuplicateNamesAndMissingEmojiRender
do
    rg -q "${test_name}" WellSpentWatchTests WellSpentWatchUITests \
        || fail "missing regression ${test_name}"
done

if rg -n '(print\(|debugPrint\(|os_log\(|Logger\()' \
    WellSpentWatch/Features/Projects \
    WellSpentWatchStore/WellSpentWatchStore.swift
then
    fail "picker or recency path contains an unreviewed logging path"
fi

echo "Watch project picker passed: phone-authored catalog, local recency, tombstone pruning, immediate Start handoff, accessibility, and recovery states are regression-covered."
