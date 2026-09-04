#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

fail() {
    echo "Watch reconciliation check failed: $1" >&2
    exit 1
}

cd "${repository_root}"

for path in \
    WellSpentApp/Data/SwiftDataModels/WellSpentSchemaV5.swift \
    WellSpentWatchContracts/ConflictBranchReconciliation.swift \
    WellSpentApp/Integrations/WatchConnectivity/PhoneWatchSyncStore.swift \
    WAT-11-RECONCILIATION.md
do
    [[ -f "${path}" ]] || fail "missing ${path}"
done

for model in \
    PhoneCanonicalSnapshotRecord \
    PhoneTimerConflictRecord \
    PhoneConflictMutationRecord \
    PhoneEntityTombstoneRecord
do
    rg -q "${model}" WellSpentApp/Data/SwiftDataModels/WellSpentSchemaV5.swift \
        || fail "schema V5 is missing ${model}"
done

rg -q 'fromVersion: WellSpentSchemaV4.self' \
    WellSpentApp/Data/Migrations/WellSpentMigrationPlan.swift \
    || fail "the additive V4-to-V5 migration is missing"
rg -q 'func resolveConflict\(' \
    WellSpentApp/Integrations/WatchConnectivity/PhoneWatchSyncStore.swift \
    || fail "the persist-first conflict resolution boundary is missing"
rg -q 'TimerConflictBranchReconstructor.validateResolution' \
    WellSpentApp/Integrations/WatchConnectivity/PhoneWatchSyncStore.swift \
    || fail "resolution does not validate the complete replacement ledger"
rg -q 'entityType == \.conflictResolution' \
    WellSpentWatchStore/WellSpentWatchStore.swift \
    || fail "the Watch cannot clear a resolved conflict tombstone"

for test_name in \
    testConcurrentStartPreservesCanonicalAndReconstructedWatchBranches \
    testKeepBothResolutionIsAuditableIdempotentAndPreservesExactTotals \
    testMergeResolutionSoftDeletesCanonicalUntilWatchCrossesTombstone \
    testSecondConflictRoundGetsNewIdentityAfterResolution \
    testOriginSequenceCollisionIsRetainedForReview \
    testArchivedProjectProducesTombstoneAndCannotReappearInSnapshot \
    testEveryTimerActionFromAStaleBaseRequiresReviewWithoutClockOrdering \
    testConflictBranchReconstructionPreservesEveryExactBoundary \
    testResolvedSnapshotClearsConflictFreezeAndAppliesTombstones \
    testV4StoreMigratesToV5WithoutChangingSyncJournal
do
    rg -q "${test_name}" WellSpentTests WellSpentWatchTests WellSpentWatchContractTests \
        || fail "missing regression ${test_name}"
done

if rg -n '(print\(|debugPrint\(|os_log\(|Logger\()' \
    WellSpentApp/Integrations/WatchConnectivity/PhoneWatchSyncStore.swift \
    WellSpentWatchContracts/ConflictBranchReconciliation.swift
then
    fail "reconciliation contains an unreviewed logging path"
fi

echo "Watch reconciliation passed: divergent branches, audited resolution, tombstones, and Watch unfreeze are durable and regression-covered."
