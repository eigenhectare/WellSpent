#!/bin/bash
set -euo pipefail
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentReleaseGuards.XXXXXX")"
trap 'rm -rf -- "${fixture_root}"' EXIT

jq -n '{"com.apple.security.application-groups":["group.example.watch"]}' > "${fixture_root}/source.json"
jq -n '{
    "application-identifier":"PREFIX1234.com.example.watch",
    "com.apple.developer.team-identifier":"TEAM123456",
    "com.apple.security.application-groups":["group.example.watch"],
    "keychain-access-groups":["PREFIX1234.com.example.watch"],
    "get-task-allow":true
}' > "${fixture_root}/valid.json"
check_policy() {
    jq -e --arg team TEAM123456 --arg bundle com.example.watch --slurpfile source "${fixture_root}/source.json" \
        -f "${script_directory}/watch-release-entitlements.jq" "$1" >/dev/null
}
check_policy "${fixture_root}/valid.json"
# Archives can be development-signed before distribution re-signing. Preserve
# this observation; don't pretend it establishes TestFlight eligibility.
jq '.["get-task-allow"] = false | .["beta-reports-active"] = true' "${fixture_root}/valid.json" \
    > "${fixture_root}/distribution.json"
check_policy "${fixture_root}/distribution.json"
reject_policy() {
    jq "$1" "${fixture_root}/valid.json" > "${fixture_root}/invalid.json"
    if check_policy "${fixture_root}/invalid.json"; then echo "Entitlement guard accepted: $1" >&2; exit 1; fi
}
reject_policy '.["com.apple.developer.healthkit"] = true'
reject_policy '.["aps-environment"] = "production"'
reject_policy '.["com.apple.security.application-groups"] = ["group.foreign"]'
reject_policy 'del(.["com.apple.security.application-groups"])'
reject_policy '.["com.apple.developer.team-identifier"] = "OTHER12345"'
reject_policy '.["application-identifier"] = "PREFIX1234.*"'
reject_policy '.["application-identifier"] = ".com.example.watch"'
reject_policy '.["keychain-access-groups"] = ["PREFIX1234.com.other.app"]'
reject_policy '.["get-task-allow"] = "false"'
reject_policy '.["beta-reports-active"] = false'
echo 'Signed-entitlement policy passed valid development/distribution fixtures and 10 rejection guards.'

[[ $# -gt 0 ]] || exit 0
readonly original_app="$(cd "$1" && pwd)"
readonly copied_app="${fixture_root}/WellSpent.app"
ditto "${original_app}" "${copied_app}"
bash "${script_directory}/watch-release-check.sh" unsigned-device-app "${copied_app}" "${fixture_root}/valid-report" \
    > "${fixture_root}/valid.log" 2>&1
jq -e '.inspection == "passed" and .releaseApproved == false and all(.components[]; .signatureChecked == false)' \
    "${fixture_root}/valid-report/summary.json" >/dev/null
jq -e 'all(.components[]; .dSYMChecked == false)' \
    "${fixture_root}/valid-report/summary.json" >/dev/null

reject_package() {
    local label="$1" reason="$2" mode="${3:-unsigned-device-app}" target="${4:-${copied_app}}"
    if bash "${script_directory}/watch-release-check.sh" "${mode}" "${target}" "${fixture_root}/report-${label}" \
        > "${fixture_root}/${label}.log" 2>&1; then
        echo "Package guard accepted invalid fixture: ${label}" >&2; exit 1
    fi
    rg -q -F "${reason}" "${fixture_root}/${label}.log" || {
        echo "Package fixture failed for an unexpected reason: ${label}" >&2
        sed -n '1,20p' "${fixture_root}/${label}.log" >&2
        exit 1
    }
}
readonly watch_relative='Watch/WellSpentWatch.app'
readonly widget_relative="${watch_relative}/PlugIns/WellSpentWatchWidgets.appex"

plutil -replace CFBundleVersion -string 999 "${copied_app}/${widget_relative}/Info.plist"
reject_package version 'watch-widget build version'
cp "${original_app}/${widget_relative}/Info.plist" "${copied_app}/${widget_relative}/Info.plist"
plutil -replace CFBundleIdentifier -string com.example.foreign "${copied_app}/${watch_relative}/Info.plist"
reject_package identifier 'watch bundle identifier'
cp "${original_app}/${watch_relative}/Info.plist" "${copied_app}/${watch_relative}/Info.plist"
plutil -replace MinimumOSVersion -string 25.0 "${copied_app}/${watch_relative}/Info.plist"
reject_package deployment 'watch deployment target'
cp "${original_app}/${watch_relative}/Info.plist" "${copied_app}/${watch_relative}/Info.plist"
plutil -replace CFBundleSupportedPlatforms.0 -string WatchSimulator "${copied_app}/${watch_relative}/Info.plist"
reject_package simulator 'watch is not a device product'
cp "${original_app}/${watch_relative}/Info.plist" "${copied_app}/${watch_relative}/Info.plist"
plutil -replace WKRunsIndependentlyOfCompanionApp -bool true "${copied_app}/${watch_relative}/Info.plist"
reject_package independent 'Watch must remain a dependent companion'
cp "${original_app}/${watch_relative}/Info.plist" "${copied_app}/${watch_relative}/Info.plist"
plutil -replace NSPrivacyTracking -bool true "${copied_app}/${watch_relative}/PrivacyInfo.xcprivacy"
reject_package privacy 'watch embedded privacy manifest differs from source'
cp "${original_app}/${watch_relative}/PrivacyInfo.xcprivacy" "${copied_app}/${watch_relative}/PrivacyInfo.xcprivacy"
mkdir "${copied_app}/PlugIns/Unexpected.appex"
reject_package extra-extension 'unexpected or missing embedded app/extension'
rmdir "${copied_app}/PlugIns/Unexpected.appex"
cp "${original_app}/WellSpent" "${copied_app}/${watch_relative}/WellSpentWatch"
reject_package macho-platform 'watch contains a wrong-platform Mach-O slice'
cp "${original_app}/${watch_relative}/WellSpentWatch" "${copied_app}/${watch_relative}/WellSpentWatch"
xcrun lipo -thin arm64_32 "${original_app}/${watch_relative}/WellSpentWatch" -output "${copied_app}/${watch_relative}/WellSpentWatch"
chmod u+x "${copied_app}/${watch_relative}/WellSpentWatch"
reject_package architecture 'watch is missing arm64'
cp "${original_app}/${watch_relative}/WellSpentWatch" "${copied_app}/${watch_relative}/WellSpentWatch"
mv "${copied_app}/${watch_relative}/Assets.car" "${fixture_root}/held-assets.car"
reject_package assets 'watch compiled assets are absent'
mv "${fixture_root}/held-assets.car" "${copied_app}/${watch_relative}/Assets.car"

# A correctly shaped directory wrapping an unsigned real product must still
# fail signed mode. A passing negative test is not a signed archive pass.
readonly fake_archive="${fixture_root}/UnsignedFixture.xcarchive"
mkdir -p "${fake_archive}/Products/Applications"
ditto "${copied_app}" "${fake_archive}/Products/Applications/WellSpent.app"
jq -n '{ApplicationProperties:{ApplicationPath:"Applications/WellSpent.app"}}' \
    | plutil -convert xml1 -o "${fake_archive}/Info.plist" -
reject_package missing-dsyms 'archive dSYMs directory is missing' signed-archive "${fake_archive}"
mkdir -p \
    "${fake_archive}/dSYMs/WellSpent.app.dSYM" \
    "${fake_archive}/dSYMs/WellSpentWidgets.appex.dSYM" \
    "${fake_archive}/dSYMs/WellSpentWatch.app.dSYM" \
    "${fake_archive}/dSYMs/WellSpentWatchWidgets.appex.dSYM"
reject_package unsigned-archive 'phone signature is missing or invalid' signed-archive "${fake_archive}"
echo 'Device-package positive fixture and 12 targeted invalid-package guards passed; signed-candidate validation remains unrun.'
