#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <xcode-export-directory> <new-sanitized-report-directory>" >&2
    exit 64
fi

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
export_directory="$1"
report_directory="$2"

fail() { echo "WellSpent distribution-export check failed: $1" >&2; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$2"; }

[[ -d "${export_directory}" ]] || fail 'Xcode export directory is missing'
export_directory="$(cd "${export_directory}" && pwd -P)"
readonly export_directory
[[ ! -e "${report_directory}" ]] || fail 'report directory already exists; preserve earlier evidence'
report_parent="$(cd "$(dirname "${report_directory}")" && pwd -P)" \
    || fail 'report parent must already exist'
report_directory="${report_parent}/$(basename "${report_directory}")"
readonly report_directory
case "${report_directory}/" in "${export_directory}/"*) fail 'report must be outside the export' ;; esac

readonly ipa="${export_directory}/WellSpent.ipa"
readonly export_options="${export_directory}/ExportOptions.plist"
readonly distribution_summary="${export_directory}/DistributionSummary.plist"
[[ -s "${ipa}" ]] || fail 'WellSpent.ipa is missing'
[[ -s "${export_options}" ]] || fail 'ExportOptions.plist is missing'
[[ -s "${distribution_summary}" ]] || fail 'DistributionSummary.plist is missing'
[[ "$(find "${export_directory}" -maxdepth 1 -type f -name '*.ipa' | wc -l | tr -d ' ')" == 1 ]] \
    || fail 'export must contain exactly one IPA'

[[ "$(plist method "${export_options}")" == app-store-connect ]] || fail 'wrong export method'
[[ "$(plist destination "${export_options}")" == export ]] || fail 'export destination is not local export'
[[ "$(plist manageAppVersionAndBuildNumber "${export_options}")" == false ]] \
    || fail 'Xcode changed the version or build number'
[[ "$(plist signingStyle "${export_options}")" == automatic ]] || fail 'unexpected signing style'
[[ "$(plist uploadSymbols "${export_options}")" == true ]] || fail 'symbols were excluded'

readonly expected_version="$(awk '$1 == "MARKETING_VERSION:" { print $2; exit }' "${repository_root}/project.yml")"
readonly expected_build="$(awk '$1 == "CURRENT_PROJECT_VERSION:" { print $2; exit }' "${repository_root}/project.yml")"
readonly expected_team="$(awk '$1 == "DEVELOPMENT_TEAM:" { print $2; exit }' "${repository_root}/project.yml")"
[[ "${expected_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'invalid configured marketing version'
[[ "${expected_build}" =~ ^[0-9]+$ ]] || fail 'invalid configured build version'
[[ "${expected_team}" =~ ^[A-Z0-9]{10}$ ]] || fail 'ambiguous configured signing team'

scratch_directory="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentDistributionExport.XXXXXX")"
readonly scratch_directory
cleanup() {
    [[ -n "${scratch_directory}" && -d "${scratch_directory}" ]] || return
    rm -rf -- "${scratch_directory}"
}
trap cleanup EXIT

unzip -q "${ipa}" -d "${scratch_directory}/unpacked"
readonly phone_app="${scratch_directory}/unpacked/Payload/WellSpent.app"
[[ -d "${phone_app}" ]] || fail 'IPA payload does not contain WellSpent.app'
[[ -z "$(find "${scratch_directory}/unpacked/Payload" -mindepth 1 -maxdepth 1 -type d ! -name WellSpent.app -print -quit)" ]] \
    || fail 'IPA contains an unexpected top-level application'
[[ -z "$(find "${phone_app}" -type l -print -quit)" ]] || fail 'IPA contains an unexpected symlink'

# Reuse the release-package checks for bundle topology, compiled metadata,
# privacy manifests, deployment targets, assets and fixture isolation. The
# outer checks below independently establish the distribution signatures.
bash "${script_directory}/watch-release-check.sh" unsigned-device-app \
    "${phone_app}" "${scratch_directory}/package-report" \
    >"${scratch_directory}/package-check.log" 2>&1
readonly product_manifest="$(jq -r '.productFileManifestSHA256' "${scratch_directory}/package-report/summary.json")"
[[ "${product_manifest}" =~ ^[0-9a-f]{64}$ ]] || fail 'invalid product manifest digest'

components=(
    'phone|.|WellSpent|com.drewreilly.wellspent|iPhoneOS|arm64|WellSpentApp/Resources/WellSpent.entitlements|WellSpent.ipa:0|WellSpent.app'
    'phone-widget|PlugIns/WellSpentWidgets.appex|WellSpentWidgets|com.drewreilly.wellspent.widgets|iPhoneOS|arm64|WellSpentWidgets/WellSpentWidgets.entitlements|WellSpent.ipa:0:embeddedBinaries:0|WellSpentWidgets.appex'
    'watch|Watch/WellSpentWatch.app|WellSpentWatch|com.drewreilly.wellspent.watchkitapp|WatchOS|arm64 arm64_32|WellSpentWatch/Resources/WellSpentWatch.entitlements|WellSpent.ipa:0:embeddedBinaries:1|WellSpentWatch.app'
    'watch-widget|Watch/WellSpentWatch.app/PlugIns/WellSpentWatchWidgets.appex|WellSpentWatchWidgets|com.drewreilly.wellspent.watchkitapp.widgets|WatchOS|arm64 arm64_32|WellSpentWatchWidgets/WellSpentWatchWidgets.entitlements|WellSpent.ipa:0:embeddedBinaries:1:embeddedBinaries:0|WellSpentWatchWidgets.appex'
)

component_reports=()
readonly observed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
for component in "${components[@]}"; do
    IFS='|' read -r label relative executable identifier platform expected_architectures source_entitlements summary_path summary_name <<< "${component}"
    bundle="${phone_app}/${relative}"
    [[ -d "${bundle}" && -x "${bundle}/${executable}" ]] || fail "missing ${label} executable"
    [[ "$(plist CFBundleIdentifier "${bundle}/Info.plist")" == "${identifier}" ]] || fail "${label} bundle identifier"
    [[ "$(plist CFBundleShortVersionString "${bundle}/Info.plist")" == "${expected_version}" ]] \
        || fail "${label} marketing version"
    [[ "$(plist CFBundleVersion "${bundle}/Info.plist")" == "${expected_build}" ]] || fail "${label} build version"
    [[ "$(plist CFBundleSupportedPlatforms:0 "${bundle}/Info.plist")" == "${platform}" ]] \
        || fail "${label} platform"

    observed_architectures="$(xcrun lipo -archs "${bundle}/${executable}" | tr ' ' '\n' | LC_ALL=C sort | xargs)"
    [[ "${observed_architectures}" == "${expected_architectures}" ]] || fail "${label} architectures"
    codesign --verify --strict "${bundle}" >/dev/null 2>&1 || fail "${label} signature is invalid or untrusted"

    signed_entitlements="${scratch_directory}/${label}-signed-entitlements.plist"
    signed_entitlements_json="${scratch_directory}/${label}-signed-entitlements.json"
    source_entitlements_json="${scratch_directory}/${label}-source-entitlements.json"
    codesign -d --entitlements :- "${bundle}" >"${signed_entitlements}" 2>/dev/null \
        || fail "${label} signed entitlements are unreadable"
    plutil -convert json -o "${signed_entitlements_json}" "${signed_entitlements}"
    plutil -convert json -o "${source_entitlements_json}" "${repository_root}/${source_entitlements}"
    jq -e --arg team "${expected_team}" --arg bundle "${identifier}" \
        --slurpfile source "${source_entitlements_json}" \
        -f "${script_directory}/watch-release-entitlements.jq" \
        "${signed_entitlements_json}" >/dev/null || fail "${label} unexpected signed entitlement"
    jq -e '.["get-task-allow"] == false and .["beta-reports-active"] == true' \
        "${signed_entitlements_json}" >/dev/null || fail "${label} is not App Store signed"

    profile="${scratch_directory}/${label}-profile.plist"
    profile_entitlements="${scratch_directory}/${label}-profile-entitlements.json"
    [[ -s "${bundle}/embedded.mobileprovision" ]] || fail "${label} profile is missing"
    security cms -D -i "${bundle}/embedded.mobileprovision" -o "${profile}" >/dev/null \
        || fail "${label} profile is unreadable"
    if plutil -extract ProvisionedDevices raw -o - "${profile}" >/dev/null 2>&1; then
        fail "${label} profile contains a development-device list"
    fi
    if plutil -extract ProvisionsAllDevices raw -o - "${profile}" >/dev/null 2>&1; then
        fail "${label} profile is an enterprise profile"
    fi
    profile_expiration="$(plutil -extract ExpirationDate raw -o - "${profile}")"
    [[ "${profile_expiration}" > "${observed_at}" ]] || fail "${label} profile has expired"
    plutil -extract Entitlements json -o "${profile_entitlements}" "${profile}"
    jq -e --arg team "${expected_team}" --arg bundle "${identifier}" \
        --slurpfile signed "${signed_entitlements_json}" '
        .["application-identifier"] == ($team + "." + $bundle)
        and .["com.apple.developer.team-identifier"] == $team
        and .["get-task-allow"] == false
        and .["beta-reports-active"] == true
        and .["com.apple.security.application-groups"] == $signed[0]["com.apple.security.application-groups"]
        ' "${profile_entitlements}" >/dev/null || fail "${label} profile does not authorize signed entitlements"

    [[ "$(plist "${summary_path}:name" "${distribution_summary}")" == "${summary_name}" ]] \
        || fail "${label} distribution-summary name"
    [[ "$(plist "${summary_path}:buildNumber" "${distribution_summary}")" == "${expected_build}" ]] \
        || fail "${label} distribution-summary build"
    [[ "$(plist "${summary_path}:versionNumber" "${distribution_summary}")" == "${expected_version}" ]] \
        || fail "${label} distribution-summary version"
    [[ "$(plist "${summary_path}:symbols" "${distribution_summary}")" == true ]] \
        || fail "${label} distribution-summary symbols"
    [[ "$(plist "${summary_path}:certificate:type" "${distribution_summary}")" == 'Cloud Managed Apple Distribution' ]] \
        || fail "${label} distribution certificate type"

    component_report="${scratch_directory}/${label}-component.json"
    jq -n \
        --arg component "${label}" \
        --arg bundleID "${identifier}" \
        --arg architectures "${observed_architectures}" \
        --arg version "${expected_version}" \
        --arg build "${expected_build}" \
        --arg profileExpiresAt "${profile_expiration}" \
        '{
            component:$component,
            bundleID:$bundleID,
            architectures:($architectures | split(" ")),
            version:$version,
            build:$build,
            signatureChecked:true,
            entitlementsChecked:true,
            profileChecked:true,
            profileExpiresAt:$profileExpiresAt,
            developmentDeviceListPresent:false,
            symbolsIncluded:true
        }' >"${component_report}"
    component_reports+=("${component_report}")
done

readonly ipa_digest="$(shasum -a 256 "${ipa}" | awk '{print $1}')"
[[ "${ipa_digest}" =~ ^[0-9a-f]{64}$ ]] || fail 'invalid IPA digest'

mkdir -p "${report_directory}"
jq -s \
    --arg observedAt "${observed_at}" \
    --arg version "${expected_version}" \
    --arg build "${expected_build}" \
    --arg ipaSHA256 "${ipa_digest}" \
    --arg productFileManifestSHA256 "${product_manifest}" \
    '{
        schemaVersion:1,
        observedAt:$observedAt,
        rawIdentifiersRetained:false,
        inspection:"passed",
        releaseApproved:false,
        candidate:{version:$version,build:$build},
        export:{
            method:"app-store-connect",
            destination:"export",
            manageAppVersionAndBuildNumber:false,
            signingStyle:"automatic",
            certificateType:"Cloud Managed Apple Distribution",
            symbolsIncluded:true,
            ipaSHA256:$ipaSHA256,
            productFileManifestSHA256:$productFileManifestSHA256
        },
        components:.,
        remaining:[
            "candidate physical install and smoke",
            "final candidate screenshot and processed-icon review",
            "App Review submission",
            "manual public release"
        ]
    }' "${component_reports[@]}" >"${report_directory}/summary.json"

echo "WellSpent distribution export passed. No upload or device state changed. Sanitized evidence: ${report_directory}/summary.json"
