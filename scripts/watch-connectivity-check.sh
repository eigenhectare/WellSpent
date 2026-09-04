#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

fail() {
    echo "Watch connectivity check failed: $1" >&2
    exit 1
}

cd "${repository_root}"

readonly phone_coordinator="WellSpentApp/Integrations/WatchConnectivity/IPhoneWatchConnectivityCoordinator.swift"
readonly phone_store="WellSpentApp/Integrations/WatchConnectivity/PhoneWatchSyncStore.swift"
readonly watch_coordinator="WellSpentWatch/Connectivity/WatchConnectivityCoordinator.swift"
readonly watch_runtime="WellSpentWatch/App/WellSpentWatchRuntime.swift"
readonly transport_models="WellSpentWatchContracts/TransportModels.swift"

for path in \
    "${phone_coordinator}" \
    "${phone_store}" \
    "${watch_coordinator}" \
    "${watch_runtime}" \
    "${transport_models}" \
    WAT-10-WATCH-CONNECTIVITY.md
do
    [[ -f "${path}" ]] || fail "missing ${path}"
done

rg -q '^@preconcurrency import WatchConnectivity$' "${phone_coordinator}" \
    || fail "the iPhone production adapter does not import WatchConnectivity"
rg -q '^@preconcurrency import WatchConnectivity$' "${watch_coordinator}" \
    || fail "the Watch production adapter does not import WatchConnectivity"
rg -q 'sendMessage\(' "${phone_coordinator}" "${watch_coordinator}" \
    || fail "the reachable message fast path is missing"
rg -q 'transferUserInfo\(' "${phone_coordinator}" "${watch_coordinator}" \
    || fail "the durable user-info path is missing"
rg -q 'updateApplicationContext\(' "${phone_coordinator}" \
    || fail "the replaceable canonical snapshot path is missing"

rg -q 'PhoneMutationInboxRecord' WellSpentApp/Data/SwiftDataModels/WellSpentSchemaV4.swift \
    || fail "the durable iPhone mutation inbox is missing from schema v4"
rg -q 'PhoneAcknowledgementOutboxRecord' WellSpentApp/Data/SwiftDataModels/WellSpentSchemaV4.swift \
    || fail "the durable iPhone acknowledgement outbox is missing from schema v4"
rg -q 'fromVersion: WellSpentSchemaV3.self' WellSpentApp/Data/Migrations/WellSpentMigrationPlan.swift \
    || fail "the additive v3-to-v4 migration is missing"

rg -q 'setAfterInboxReceiptSavedForTesting' "${phone_store}" \
    || fail "the persist-before-apply failure boundary is not testable"
rg -q 'setBeforeSaveForTesting' "${phone_store}" \
    || fail "the atomic apply-and-ack save boundary is not testable"
rg -q 'processReceivedInbox' "${phone_store}" \
    || fail "the durable inbox restart path is missing"
rg -q 'WKWatchConnectivityRefreshBackgroundTask' "${watch_coordinator}" "${watch_runtime}" \
    || fail "Watch background delivery completion is not wired"

for test_name in \
    testDuplicateAndLostAcknowledgementApplyMutationExactlyOnce \
    testReceiveBeforeTerminationResumesWithoutDoubleApply \
    testDomainAndTerminalReceiptRollbackTogetherOnSaveFailure \
    testDelayedPredecessorUnblocksReorderedPause \
    testOfflineMutationStaysPendingWhileDurableTransferIsQueued \
    testSnapshotQueuesReceiptAndPreservesNewerPendingProjection \
    testV3StoreMigratesThroughV5WithoutChangingDomainData
do
    rg -q "${test_name}" WellSpentTests WellSpentWatchTests \
        || fail "missing regression ${test_name}"
done

if rg -n '(Spikes/WatchConnectivity|SpikeProtocol|SpikePersistence)' \
    WellSpentApp WellSpentWatch WellSpentWatchContracts WellSpentWatchStore
then
    fail "production transport references the disposable WC Probe"
fi

if rg -n '(print\(|debugPrint\(|os_log\(|Logger\()' \
    "${phone_coordinator}" "${phone_store}" "${watch_coordinator}"
then
    fail "production transport contains an unreviewed logging path"
fi

echo "Watch connectivity passed: production fast, durable, and snapshot lanes use durable journals with restart and exactly-once regressions."
