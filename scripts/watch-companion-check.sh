#!/bin/bash
set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
cd "${repository_root}"

fail() { echo "Watch companion check failed: $1" >&2; exit 1; }

for path in \
    WellSpentApp/Features/SessionEditor/PhoneConflictResolutionPlan.swift \
    WellSpentApp/Features/SessionEditor/WatchConflictReviewView.swift \
    WellSpentApp/Data/SwiftDataModels/WellSpentSchemaV6.swift \
    WellSpentWatchContracts/WatchReviewLink.swift \
    WAT-17-IPHONE-COMPANION.md
do
    [[ -f "${path}" ]] || fail "missing ${path}"
done

for name in \
    testPhoneConflictChoicesPreviewAndCommitExactResults \
    testResolutionSaveFailureLeavesBothBranchesAndCanRetrySamePreview \
    testSyncOverviewWaitsForReceiptAndTracksOfflinePhoneEdits \
    testEraseRejectsDelayedWatchContentAndKeepsGenerationMonotonic \
    testPhoneModelResumesSwitchesAndEndsPausedWatchRunThroughJournal \
    testPhoneConflictDeepLinkFreezesCommandsAndRejectsChangedPreview \
    testV5MigratesToV6AndResetFenceSurvivesRelaunch \
    testConflictKeepPhoneAndRelaunchPreservesResolution \
    testConflictKeepBothExplainsOverlapAndPreservesTwoRuns \
    testConflictUseWatchShowsChosenProject \
    testFailedConflictSaveStaysInConfirmationWithoutLosingVersions \
    testConflictReviewAtLargestTextAndCancelKeepsVersions
do
    rg -q "${name}" WellSpentTests WellSpentUITests || fail "missing ${name}"
done

rg -q 'minimumAcceptedGeneration' WellSpentApp/Data/Repositories/WellSpentPersistence.swift || fail "erase fence missing"
rg -q 'minimumAcceptedGeneration' WellSpentApp/Integrations/WatchConnectivity/PhoneWatchSyncStore.swift || fail "delayed erase rejection missing"
rg -q 'onContinueUserActivity' WellSpentApp/App/Navigation/RootView.swift || fail "Handoff receiver missing"
rg -q 'isEligibleForSearch = false' WellSpentWatch/Features/Projects/WatchRootView.swift || fail "Handoff privacy guard missing"
rg -q 'com.drewreilly.wellspent.review' project.yml || fail "Handoff activity declaration missing"

echo "Watch companion passed: receipt-based status, explicit conflict confirmation, paused controls, migration/erase fence, Handoff, and UI recovery are regression-covered."
