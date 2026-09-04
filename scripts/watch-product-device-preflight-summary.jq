def device($details; $alias): {
    alias: $alias,
    model: $details.result.hardwareProperties.marketingName,
    platform: $details.result.hardwareProperties.platform,
    osVersion: $details.result.deviceProperties.osVersionNumber,
    booted: ($details.result.deviceProperties.bootState == "booted"),
    developerMode: ($details.result.deviceProperties.developerModeStatus == "enabled"),
    paired: ($details.result.connectionProperties.pairingState == "paired"),
    route: $details.result.connectionProperties.transportType,
    tunnelConnected: ($details.result.connectionProperties.tunnelState == "connected")
};

def app($apps; $bundle): {
    bundleID: $bundle,
    installed: (($apps.result.apps | length) == 1),
    version: ($apps.result.apps[0].version // null),
    build: ($apps.result.apps[0].bundleVersion // null)
};

(device($phoneDetails[0]; "phone-under-test")) as $phone |
(device($watchDetails[0]; "watch-under-test")) as $watch |
(app($phoneApps[0]; $phoneBundleID)) as $phoneApp |
(app($watchApps[0]; $watchBundleID)) as $watchApp |
{
    schemaVersion: 1,
    observedAt: $observedAt,
    scope: "Read-only WellSpent product installation prerequisite; not transport, flow, accessibility, energy, or release evidence.",
    rawIdentifiersRetained: false,
    expectedCandidate: {version: $expectedVersion, build: $expectedBuild},
    phone: ($phone + {app: $phoneApp}),
    watch: ($watch + {app: $watchApp, xcodeDestinationAvailable: $xcodeDestinationAvailable})
}
| .checks = {
    physicalPairAvailable: (
        .phone.platform == "iOS" and .watch.platform == "watchOS"
        and .phone.booted and .watch.booted
        and .phone.developerMode and .watch.developerMode
        and .phone.paired and .watch.paired
        and .phone.tunnelConnected and .watch.tunnelConnected
        and .watch.xcodeDestinationAvailable
    ),
    phoneUsesWiredRoute: (.phone.route == "wired"),
    phoneBundleInstalled: .phone.app.installed,
    watchBundleInstalled: .watch.app.installed,
    candidateVersionsAligned: (
        .phone.app.installed and .watch.app.installed
        and .phone.app.version == $expectedVersion and .watch.app.version == $expectedVersion
        and .phone.app.build == $expectedBuild and .watch.app.build == $expectedBuild
    )
}
| .reasonCodes = [
    if .checks.physicalPairAvailable then empty else "physical_pair_unavailable" end,
    if .checks.phoneUsesWiredRoute then empty else "phone_not_wired" end,
    if .checks.phoneBundleInstalled then empty else "phone_bundle_not_installed" end,
    if .checks.watchBundleInstalled then empty else "watch_bundle_not_installed" end,
    if (.checks.phoneBundleInstalled and .checks.watchBundleInstalled and .checks.candidateVersionsAligned)
        then empty
        elif (.checks.phoneBundleInstalled and .checks.watchBundleInstalled)
        then "candidate_versions_misaligned"
        else empty
    end
]
| .result = if ([.checks[]] | all) then "ready" else "blocked" end
