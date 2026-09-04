def file_at($listing; $path):
    [
        $listing.result.files[]
        | select(.relativePath == $path and .resources.isDirectory == false)
    ]
    | if length == 1 then .[0] else null end;

def valid_size($file):
    $file != null
    and ($file.metadata.size | type) == "number"
    and $file.metadata.size >= 0
    and ($file.metadata.size | floor) == $file.metadata.size;

def backup_attribute_present($file):
    $file != null
    and (($file.metadata.extendedAttributes // {})
        | has("com.apple.metadata:com_apple_backup_excludeItem"));

def observation($file): {
    present: ($file != null),
    logicalBytes: (if valid_size($file) then $file.metadata.size else null end),
    backupExclusionAttributePresent: backup_attribute_present($file)
};

[
    "Library/Application Support/WellSpentWatchLocal.store",
    "Library/Application Support/WellSpentWatchLocal.store-shm",
    "Library/Application Support/WellSpentWatchLocal.store-wal"
] as $storePaths
| "Library/Application Support/WatchGoalAlerts/preferences.json" as $goalPath
| $watchDetails[0] as $details
| $watchApps[0] as $apps
| $groupFiles[0] as $group
| $appFiles[0] as $appData
| ($storePaths | map({path: ., file: file_at($group; .)})) as $stores
| file_at($appData; $goalPath) as $goal
| ([
    $group.result.files[]
    | select(.resources.isDirectory == false)
    | select(.relativePath as $path | ($storePaths | index($path)) == null)
] | length) as $unexpectedGroupFileCount
| ([
    $stores[].file,
    $goal
    | select(. != null and valid_size(.))
    | .metadata.size
] | add // 0) as $combinedBytes
| {
    schemaVersion: 1,
    observedAt: $observedAt,
    scope: "Read-only physical Watch metadata observation for WellSpent-owned durable files; not file-protection, backup/restore, energy, wakeup, network, or accepted-budget certification.",
    rawIdentifiersRetained: false,
    expectedCandidate: {version: $expectedVersion, build: $expectedBuild},
    watch: {
        alias: "watch-under-test",
        model: $details.result.hardwareProperties.marketingName,
        platform: $details.result.hardwareProperties.platform,
        osVersion: $details.result.deviceProperties.osVersionNumber,
        booted: ($details.result.deviceProperties.bootState == "booted"),
        developerMode: ($details.result.deviceProperties.developerModeStatus == "enabled"),
        paired: ($details.result.connectionProperties.pairingState == "paired"),
        tunnelConnected: ($details.result.connectionProperties.tunnelState == "connected"),
        app: {
            bundleID: $watchBundleID,
            installed: (($apps.result.apps | length) == 1),
            version: ($apps.result.apps[0].version // null),
            build: ($apps.result.apps[0].bundleVersion // null)
        }
    },
    storage: {
        storeFiles: ($stores | map({
            role: (if .path | endswith("-shm") then "sqlite-shm"
                elif .path | endswith("-wal") then "sqlite-wal"
                else "sqlite-store" end),
            observation: observation(.file)
        })),
        goalPreferences: observation($goal),
        unexpectedAppGroupFileCount: $unexpectedGroupFileCount,
        combinedWellSpentLogicalBytes: $combinedBytes,
        proposedOfflineHighWaterBytes: 8388608,
        underProposedOfflineHighWater: ($combinedBytes <= 8388608),
        fileProtectionInspection: "not-exposed-by-coredevice-file-listing"
    }
}
| .checks = {
    watchReady: (
        .watch.platform == "watchOS"
        and .watch.booted and .watch.developerMode
        and .watch.paired and .watch.tunnelConnected
    ),
    candidateAligned: (
        .watch.app.installed
        and .watch.app.version == $expectedVersion
        and .watch.app.build == $expectedBuild
    ),
    mainStorePresent: .storage.storeFiles[0].observation.present,
    knownFileSizesValid: (
        ([.storage.storeFiles[].observation | select(.present) | .logicalBytes] +
            [(.storage.goalPreferences | select(.present) | .logicalBytes)])
        | all(. != null)
    ),
    presentStoreFilesBackupExcluded: (
        [.storage.storeFiles[].observation | select(.present)
            | .backupExclusionAttributePresent]
        | length > 0 and all
    ),
    goalPreferencesPresent: .storage.goalPreferences.present,
    goalPreferencesBackupExcluded: (
        .storage.goalPreferences.present
        and .storage.goalPreferences.backupExclusionAttributePresent
    ),
    noUnexpectedAppGroupFiles: (.storage.unexpectedAppGroupFileCount == 0)
}
| .reasonCodes = [
    if .checks.watchReady then empty else "watch_unavailable" end,
    if .checks.candidateAligned then empty else "candidate_misaligned" end,
    if .checks.mainStorePresent then empty else "main_store_missing" end,
    if .checks.knownFileSizesValid then empty else "invalid_file_metadata" end,
    if .checks.presentStoreFilesBackupExcluded then empty else "store_backup_attribute_missing" end,
    if .checks.goalPreferencesPresent then empty else "goal_preferences_missing" end,
    if .checks.goalPreferencesBackupExcluded then empty else "goal_preferences_backup_attribute_missing" end,
    if .checks.noUnexpectedAppGroupFiles then empty else "unexpected_app_group_file" end
]
| .result = if ([.checks[]] | all) then "observed" else "blocked" end
