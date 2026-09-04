#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly derived_data_root="${WATCH_FOUNDATION_DERIVED_DATA_ROOT:-${repository_root}/.derivedData/WatchFoundation}"
readonly supplied_phone_app="${WATCH_FOUNDATION_IPHONE_APP:-}"
readonly phone_bundle_id="com.drewreilly.wellspent"
readonly watch_bundle_id="${phone_bundle_id}.watchkitapp"
readonly watch_widget_bundle_id="${watch_bundle_id}.widgets"

fail() {
    echo "Watch foundation check failed: $1" >&2
    exit 1
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2"
}

build_watch() {
    local configuration="$1"
    local destination="$2"
    local destination_name="$3"

    xcodebuild \
        -project WellSpent.xcodeproj \
        -scheme WellSpentWatch \
        -configuration "${configuration}" \
        -destination "${destination}" \
        -derivedDataPath "${derived_data_root}/${destination_name}-${configuration}" \
        CODE_SIGNING_ALLOWED=NO \
        clean build
}

command -v xcodegen >/dev/null || fail "xcodegen is not installed"

cd "${repository_root}"
xcodegen generate --spec project.yml

for plist in \
    WellSpentWatch/Resources/Info.plist \
    WellSpentWatch/Resources/PrivacyInfo.xcprivacy \
    WellSpentWatch/Resources/WellSpentWatch.entitlements \
    WellSpentWatchWidgets/Info.plist \
    WellSpentWatchWidgets/PrivacyInfo.xcprivacy \
    WellSpentWatchWidgets/WellSpentWatchWidgets.entitlements
do
    plutil -lint "${plist}" >/dev/null
done

[[ "$(plist_value WKCompanionAppBundleIdentifier WellSpentWatch/Resources/Info.plist)" == "${phone_bundle_id}" ]] \
    || fail "the Watch companion bundle identifier is incorrect"
[[ "$(plist_value WKRunsIndependentlyOfCompanionApp WellSpentWatch/Resources/Info.plist)" == "false" ]] \
    || fail "the Watch app must be installed as an iPhone companion"

readonly watch_app_group="$(
    plist_value 'com.apple.security.application-groups:0' \
        WellSpentWatch/Resources/WellSpentWatch.entitlements
)"
readonly widget_app_group="$(
    plist_value 'com.apple.security.application-groups:0' \
        WellSpentWatchWidgets/WellSpentWatchWidgets.entitlements
)"
[[ "${watch_app_group}" == "group.com.drewreilly.wellspent.watch" ]] \
    || fail "the Watch app group is incorrect"
[[ "${watch_app_group}" == "${widget_app_group}" ]] \
    || fail "the Watch app and widget do not share the same local app group"

rg -q 'WellSpentWatch.app in Embed Watch Content.*RemoveHeadersOnCopy' \
    WellSpent.xcodeproj/project.pbxproj \
    || fail "the iPhone target does not embed the production Watch app"
rg -q -F 'dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";' WellSpent.xcodeproj/project.pbxproj \
    || fail "the generated project is missing the native Watch embed directory"

if [[ "${WATCH_FOUNDATION_VERIFY_ONLY:-0}" == 1 ]]; then
    [[ -n "${supplied_phone_app}" && -n "${WATCH_FOUNDATION_TEST_PRODUCTS:-}" ]] \
        || fail 'verification-only mode requires compiled phone and Watch test products'
    readonly watch_test_products="${WATCH_FOUNDATION_TEST_PRODUCTS}"
else
build_watch Debug 'generic/platform=watchOS Simulator' Simulator
build_watch Release 'generic/platform=watchOS Simulator' Simulator
build_watch Debug 'generic/platform=watchOS' Device
build_watch Release 'generic/platform=watchOS' Device

xcodebuild \
    -project WellSpent.xcodeproj \
    -scheme WellSpentWatch \
    -configuration Debug \
    -destination 'generic/platform=watchOS Simulator' \
    -derivedDataPath "${derived_data_root}/Test-Build" \
    CODE_SIGNING_ALLOWED=NO \
    build-for-testing

readonly watch_test_products="${derived_data_root}/Test-Build/Build/Products/Debug-watchsimulator"
fi
[[ -d "${watch_test_products}/WellSpentWatch.app/PlugIns/WellSpentWatchTests.xctest" ]] \
    || fail "the Watch unit-test bundle did not compile"
[[ -d "${watch_test_products}/WellSpentWatchUITests-Runner.app/PlugIns/WellSpentWatchUITests.xctest" ]] \
    || fail "the Watch UI-test bundle did not compile"

if [[ -n "${supplied_phone_app}" ]]; then
    readonly phone_app="${supplied_phone_app}"
else
    xcodebuild \
        -project WellSpent.xcodeproj \
        -scheme WellSpent \
        -configuration Release \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "${derived_data_root}/Phone-Release" \
        CODE_SIGNING_ALLOWED=NO \
        clean build
    readonly phone_app="${derived_data_root}/Phone-Release/Build/Products/Release-iphonesimulator/WellSpent.app"
fi

readonly embedded_watch_app="${phone_app}/Watch/WellSpentWatch.app"
readonly embedded_watch_widget="${embedded_watch_app}/PlugIns/WellSpentWatchWidgets.appex"
[[ -d "${embedded_watch_app}" ]] || fail "the built iPhone app does not contain WellSpentWatch.app"
[[ -d "${embedded_watch_widget}" ]] || fail "the Watch app does not contain WellSpentWatchWidgets.appex"
[[ "$(plist_value CFBundleIdentifier "${embedded_watch_app}/Info.plist")" == "${watch_bundle_id}" ]] \
    || fail "the embedded Watch app bundle identifier is incorrect"
[[ "$(plist_value CFBundleIdentifier "${embedded_watch_widget}/Info.plist")" == "${watch_widget_bundle_id}" ]] \
    || fail "the embedded Watch widget bundle identifier is incorrect"
[[ "$(plist_value WKCompanionAppBundleIdentifier "${embedded_watch_app}/Info.plist")" == "${phone_bundle_id}" ]] \
    || fail "the embedded Watch companion identifier is incorrect"

readonly phone_build="$(plist_value CFBundleVersion "${phone_app}/Info.plist")"
readonly watch_build="$(plist_value CFBundleVersion "${embedded_watch_app}/Info.plist")"
readonly watch_widget_build="$(plist_value CFBundleVersion "${embedded_watch_widget}/Info.plist")"
[[ "${phone_build}" == "${watch_build}" && "${watch_build}" == "${watch_widget_build}" ]] \
    || fail "the iPhone, Watch app, and Watch widget build versions differ"

for bundled_manifest in \
    "${embedded_watch_app}/PrivacyInfo.xcprivacy" \
    "${embedded_watch_widget}/PrivacyInfo.xcprivacy"
do
    [[ -f "${bundled_manifest}" ]] || fail "a Watch privacy manifest is missing from the built pair"
done

if [[ "${WATCH_FOUNDATION_VERIFY_ONLY:-0}" == 1 ]]; then
    echo "Watch foundation packaging and test bundles passed against supplied compiled products. Build evidence belongs to the calling CI stages."
else
    echo "Watch foundation passed: generated targets, test bundles, Debug/Release Simulator builds, unsigned device builds, and companion packaging are valid."
fi
