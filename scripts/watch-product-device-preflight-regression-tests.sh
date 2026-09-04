#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly filter="${script_directory}/watch-product-device-preflight-summary.jq"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentDevicePreflightTests.XXXXXX")"
readonly fixture_root
cleanup() {
    [[ -n "${fixture_root}" && -d "${fixture_root}" ]] || return
    rm -rf -- "${fixture_root}"
}
trap cleanup EXIT

write_details() {
    local output="$1" model="$2" platform="$3" os="$4" route="$5"
    local developer_mode="${6:-enabled}" paired="${7:-paired}" tunnel="${8:-connected}"
    jq -n --arg model "${model}" --arg platform "${platform}" --arg os "${os}" \
        --arg route "${route}" --arg developerMode "${developer_mode}" \
        --arg paired "${paired}" --arg tunnel "${tunnel}" '{
            result: {
                identifier: "SECRET_DEVICE_IDENTIFIER",
                hardwareProperties: {
                    marketingName: $model, platform: $platform,
                    serialNumber: "SECRET_SERIAL", udid: "SECRET_UDID"
                },
                deviceProperties: {
                    name: "SECRET_OWNER_NAME", osVersionNumber: $os,
                    bootState: "booted", developerModeStatus: $developerMode
                },
                connectionProperties: {
                    pairingState: $paired, transportType: $route,
                    tunnelState: $tunnel, tunnelIPAddress: "SECRET_TUNNEL"
                }
            }
        }' >"${output}"
}

write_app() {
    local output="$1" bundle="$2" installed="$3" version="${4:-}" build="${5:-}"
    jq -n --arg bundle "${bundle}" --argjson installed "${installed}" \
        --arg version "${version}" --arg build "${build}" '{
            result: {
                deviceIdentifier: "SECRET_DEVICE_IDENTIFIER",
                apps: if $installed then [{
                    bundleIdentifier: $bundle, version: $version,
                    bundleVersion: $build, url: "SECRET_INSTALL_PATH"
                }] else [] end
            }
        }' >"${output}"
}

write_details "${fixture_root}/phone-details.json" 'Fixture iPhone' iOS 26.6 wired
write_details "${fixture_root}/watch-details.json" 'Fixture Watch' watchOS 26.6 localNetwork
write_app "${fixture_root}/phone-apps.json" com.drewreilly.wellspent true 0.1.0 2
write_app "${fixture_root}/watch-apps.json" com.drewreilly.wellspent.watchkitapp true 0.1.0 2

render() {
    local output="$1" xcode_available="${2:-true}"
    jq -n \
        --arg observedAt '2026-09-03T00:00:00Z' \
        --arg expectedVersion 0.1.0 \
        --arg expectedBuild 2 \
        --arg phoneBundleID com.drewreilly.wellspent \
        --arg watchBundleID com.drewreilly.wellspent.watchkitapp \
        --argjson xcodeDestinationAvailable "${xcode_available}" \
        --slurpfile phoneDetails "${fixture_root}/phone-details.json" \
        --slurpfile watchDetails "${fixture_root}/watch-details.json" \
        --slurpfile phoneApps "${fixture_root}/phone-apps.json" \
        --slurpfile watchApps "${fixture_root}/watch-apps.json" \
        -f "${filter}" >"${output}"
}

render "${fixture_root}/ready.json"
jq -e '
    .result == "ready"
    and ([.checks[]] | all)
    and .reasonCodes == []
    and .rawIdentifiersRetained == false
    and .phone.app.version == "0.1.0"
    and .watch.app.build == "2"
' "${fixture_root}/ready.json" >/dev/null
if rg -q 'SECRET_|identifier|serial|udid|hostname|IPAddress' "${fixture_root}/ready.json"; then
    echo 'Preflight summary leaked a raw device field.' >&2
    exit 1
fi

write_app "${fixture_root}/watch-apps.json" com.drewreilly.wellspent.watchkitapp false
render "${fixture_root}/missing-watch.json"
jq -e '
    .result == "blocked"
    and .checks.physicalPairAvailable
    and .checks.phoneBundleInstalled
    and (.checks.watchBundleInstalled | not)
    and (.checks.candidateVersionsAligned | not)
    and .reasonCodes == ["watch_bundle_not_installed"]
' "${fixture_root}/missing-watch.json" >/dev/null

write_app "${fixture_root}/watch-apps.json" com.drewreilly.wellspent.watchkitapp true 0.1.1 3
render "${fixture_root}/wrong-version.json"
jq -e '
    .result == "blocked"
    and .checks.watchBundleInstalled
    and (.checks.candidateVersionsAligned | not)
    and .reasonCodes == ["candidate_versions_misaligned"]
' "${fixture_root}/wrong-version.json" >/dev/null

write_app "${fixture_root}/watch-apps.json" com.drewreilly.wellspent.watchkitapp true 0.1.0 2
write_details "${fixture_root}/phone-details.json" 'Fixture iPhone' iOS 26.6 localNetwork
render "${fixture_root}/not-wired.json"
jq -e '
    .result == "blocked"
    and (.checks.phoneUsesWiredRoute | not)
    and .reasonCodes == ["phone_not_wired"]
' "${fixture_root}/not-wired.json" >/dev/null

write_details "${fixture_root}/phone-details.json" 'Fixture iPhone' iOS 26.6 wired
render "${fixture_root}/missing-destination.json" false
jq -e '
    .result == "blocked"
    and (.checks.physicalPairAvailable | not)
    and .reasonCodes == ["physical_pair_unavailable"]
' "${fixture_root}/missing-destination.json" >/dev/null

echo 'Watch product device preflight sanitization and fail-closed regression checks passed.'
