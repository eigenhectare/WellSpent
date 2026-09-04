#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly filter="${script_directory}/watch-physical-storage-summary.jq"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentPhysicalStorageTests.XXXXXX")"
readonly fixture_root
cleanup() {
    [[ -n "${fixture_root}" && -d "${fixture_root}" ]] || return
    rm -rf -- "${fixture_root}"
}
trap cleanup EXIT

jq -n '{
    result: {
        identifier: "SECRET_DEVICE_IDENTIFIER",
        hardwareProperties: {
            marketingName: "Fixture Watch", platform: "watchOS",
            serialNumber: "SECRET_SERIAL", udid: "SECRET_UDID"
        },
        deviceProperties: {
            name: "SECRET_OWNER_NAME", osVersionNumber: "26.6",
            bootState: "booted", developerModeStatus: "enabled"
        },
        connectionProperties: {
            pairingState: "paired", tunnelState: "connected",
            tunnelIPAddress: "SECRET_TUNNEL"
        }
    }
}' >"${fixture_root}/details.json"

jq -n '{result: {deviceIdentifier: "SECRET_DEVICE_IDENTIFIER", apps: [{
    bundleIdentifier: "com.drewreilly.wellspent.watchkitapp",
    version: "0.1.0", bundleVersion: "2", url: "SECRET_INSTALL_PATH"
}]}}' >"${fixture_root}/apps.json"

write_group_files() {
    jq -n '{result: {deviceIdentifier: "SECRET_DEVICE_IDENTIFIER", files: [
        {relativePath: "Library/Application Support", resources: {isDirectory: true},
            metadata: {size: 0, extendedAttributes: {}}},
        {relativePath: "Library/Application Support/WellSpentWatchLocal.store",
            resources: {isDirectory: false}, metadata: {size: 100000,
            extendedAttributes: {"com.apple.metadata:com_apple_backup_excludeItem": "SECRET_FIXED_ATTRIBUTE"}}},
        {relativePath: "Library/Application Support/WellSpentWatchLocal.store-shm",
            resources: {isDirectory: false}, metadata: {size: 32000,
            extendedAttributes: {"com.apple.metadata:com_apple_backup_excludeItem": "SECRET_FIXED_ATTRIBUTE"}}},
        {relativePath: "Library/Application Support/WellSpentWatchLocal.store-wal",
            resources: {isDirectory: false}, metadata: {size: 300000,
            extendedAttributes: {"com.apple.metadata:com_apple_backup_excludeItem": "SECRET_FIXED_ATTRIBUTE"}}}
    ]}}' >"$1"
}

write_app_files() {
    jq -n '{result: {deviceIdentifier: "SECRET_DEVICE_IDENTIFIER", files: [
        {relativePath: "Library/Application Support/WatchGoalAlerts/preferences.json",
            resources: {isDirectory: false}, metadata: {size: 100,
            extendedAttributes: {"com.apple.metadata:com_apple_backup_excludeItem": "SECRET_FIXED_ATTRIBUTE"}}},
        {relativePath: "Library/Caches/system-owned", resources: {isDirectory: false},
            metadata: {size: 999999, extendedAttributes: {}}}
    ]}}' >"$1"
}

write_group_files "${fixture_root}/group.json"
write_app_files "${fixture_root}/app-files.json"

render() {
    jq -n \
        --arg observedAt '2026-09-03T00:00:00Z' \
        --arg expectedVersion 0.1.0 \
        --arg expectedBuild 2 \
        --arg watchBundleID com.drewreilly.wellspent.watchkitapp \
        --slurpfile watchDetails "${fixture_root}/details.json" \
        --slurpfile watchApps "${fixture_root}/apps.json" \
        --slurpfile groupFiles "${fixture_root}/group.json" \
        --slurpfile appFiles "${fixture_root}/app-files.json" \
        -f "${filter}" >"$1"
}

render "${fixture_root}/observed.json"
jq -e '
    .result == "observed"
    and ([.checks[]] | all)
    and .reasonCodes == []
    and .rawIdentifiersRetained == false
    and .storage.combinedWellSpentLogicalBytes == 432100
    and .storage.underProposedOfflineHighWater
    and .storage.fileProtectionInspection == "not-exposed-by-coredevice-file-listing"
    and ([.storage.storeFiles[].observation.backupExclusionAttributePresent] | all)
    and .storage.goalPreferences.backupExclusionAttributePresent
' "${fixture_root}/observed.json" >/dev/null
if rg -q 'SECRET_|serialNumber|udid|ownerName|tunnelIPAddress|INSTALL_PATH' \
    "${fixture_root}/observed.json"; then
    echo 'Physical storage summary leaked a raw device field or attribute value.' >&2
    exit 1
fi

expect_blocked() {
    local mutation="$1" reason="$2"
    jq "${mutation}" "${fixture_root}/group.json" >"${fixture_root}/group-mutated.json"
    mv "${fixture_root}/group-mutated.json" "${fixture_root}/group.json"
    render "${fixture_root}/blocked.json"
    jq -e --arg reason "${reason}" '
        .result == "blocked" and (.reasonCodes | index($reason)) != null
    ' "${fixture_root}/blocked.json" >/dev/null
    write_group_files "${fixture_root}/group.json"
}

expect_blocked '.result.files |= map(select(.relativePath != "Library/Application Support/WellSpentWatchLocal.store"))' \
    main_store_missing
expect_blocked '(.result.files[] | select(.relativePath == "Library/Application Support/WellSpentWatchLocal.store-wal") | .metadata.extendedAttributes) = {}' \
    store_backup_attribute_missing
expect_blocked '.result.files += [{relativePath: "Library/Application Support/unexpected.bin", resources: {isDirectory: false}, metadata: {size: 1, extendedAttributes: {}}}]' \
    unexpected_app_group_file
expect_blocked '(.result.files[] | select(.relativePath == "Library/Application Support/WellSpentWatchLocal.store") | .metadata.size) = -1' \
    invalid_file_metadata

jq '(.result.files[] | select(.relativePath == "Library/Application Support/WatchGoalAlerts/preferences.json") | .metadata.extendedAttributes) = {}' \
    "${fixture_root}/app-files.json" >"${fixture_root}/app-files-mutated.json"
mv "${fixture_root}/app-files-mutated.json" "${fixture_root}/app-files.json"
render "${fixture_root}/blocked.json"
jq -e '.result == "blocked" and (.reasonCodes | index("goal_preferences_backup_attribute_missing")) != null' \
    "${fixture_root}/blocked.json" >/dev/null

echo 'Physical Watch storage metadata sanitization and five fail-closed regression checks passed.'
