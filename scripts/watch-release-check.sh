#!/bin/bash
set -euo pipefail

# Read-only inspection: never builds, signs, changes versions, exports or uploads.
# A passed package/archive inspection is NOT release approval.
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly mode="${1:?usage: watch-release-check.sh unsigned-device-app|signed-archive INPUT NEW_REPORT_DIRECTORY}"
readonly input="${2:?input required}"
report="${3:?new report directory required}"
fail() { echo "Watch release inspection failed: $1" >&2; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$2"; }
[[ ! -e "${report}" ]] || fail 'report directory already exists; preserve earlier evidence'

case "${mode}" in
    unsigned-device-app)
        [[ "${input}" == *.app && -d "${input}" ]] || fail 'device app bundle required'
        phone_app="${input}"
        ;;
    signed-archive)
        [[ "${input}" == *.xcarchive && -d "${input}" ]] || fail 'an actual .xcarchive directory is required'
        [[ "$(plist ApplicationProperties:ApplicationPath "${input}/Info.plist")" == 'Applications/WellSpent.app' ]] \
            || fail 'archive application path does not match the joint product'
        phone_app="${input}/Products/Applications/WellSpent.app"
        ;;
    *) fail 'unknown mode; unsigned and signed evidence must be explicit' ;;
esac
[[ -d "${phone_app}" ]] || fail 'missing iPhone application'
phone_app="$(cd "${phone_app}" && pwd -P)"
[[ -z "$(find "${phone_app}" -type l -print -quit)" ]] || fail 'unexpected symlink in product tree'
report_parent="$(cd "$(dirname "${report}")" && pwd -P)" || fail 'report parent must already exist'
report="${report_parent}/$(basename "${report}")"
case "${report}/" in "${phone_app}/"*) fail 'report must be outside the inspected product' ;; esac
if [[ "${mode}" == signed-archive ]]; then
    archive_root="$(cd "${input}" && pwd -P)"
    case "${report}/" in "${archive_root}/"*) fail 'report must be outside the inspected archive' ;; esac
fi
mkdir -p "${report}"
readonly phone_app report

readonly marketing_version="$(plist CFBundleShortVersionString "${phone_app}/Info.plist")"
readonly build_version="$(plist CFBundleVersion "${phone_app}/Info.plist")"
[[ "${marketing_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "${build_version}" =~ ^[0-9]+$ ]] \
    || fail 'unresolved or invalid version/build values'
readonly expected_team="$(awk '$1 == "DEVELOPMENT_TEAM:" { print $2 }' "${repository_root}/project.yml")"
[[ "${expected_team}" =~ ^[A-Z0-9]{10}$ ]] || fail 'ambiguous configured signing team'

components=(
    'phone|.|WellSpent|com.drewreilly.wellspent|iPhoneOS|IOS|WellSpentApp/Resources/PrivacyInfo.xcprivacy|WellSpentApp/Resources/WellSpent.entitlements|WellSpent.app.dSYM'
    'phone-widget|PlugIns/WellSpentWidgets.appex|WellSpentWidgets|com.drewreilly.wellspent.widgets|iPhoneOS|IOS|WellSpentWidgets/PrivacyInfo.xcprivacy|WellSpentWidgets/WellSpentWidgets.entitlements|WellSpentWidgets.appex.dSYM'
    'watch|Watch/WellSpentWatch.app|WellSpentWatch|com.drewreilly.wellspent.watchkitapp|WatchOS|WATCHOS|WellSpentWatch/Resources/PrivacyInfo.xcprivacy|WellSpentWatch/Resources/WellSpentWatch.entitlements|WellSpentWatch.app.dSYM'
    'watch-widget|Watch/WellSpentWatch.app/PlugIns/WellSpentWatchWidgets.appex|WellSpentWatchWidgets|com.drewreilly.wellspent.watchkitapp.widgets|WatchOS|WATCHOS|WellSpentWatchWidgets/PrivacyInfo.xcprivacy|WellSpentWatchWidgets/WellSpentWatchWidgets.entitlements|WellSpentWatchWidgets.appex.dSYM'
)
[[ "$(find "${phone_app}" -type d \( -name '*.app' -o -name '*.appex' \) | wc -l | tr -d ' ')" == 4 ]] \
    || fail 'unexpected or missing embedded app/extension'
if [[ "${mode}" == signed-archive ]]; then
    [[ -d "${input}/dSYMs" ]] || fail 'archive dSYMs directory is missing'
    [[ "$(find "${input}/dSYMs" -mindepth 1 -maxdepth 1 -type d -name '*.dSYM' | wc -l | tr -d ' ')" == 4 ]] \
        || fail 'archive must contain exactly four component dSYMs'
fi

for component in "${components[@]}"; do
    IFS='|' read -r label relative executable identifier platform macho_platform manifest entitlements dsym_name <<< "${component}"
    bundle="${phone_app}/${relative}"
    [[ -d "${bundle}" && -x "${bundle}/${executable}" ]] || fail "missing ${label} executable"
    plutil -lint "${bundle}/Info.plist" >/dev/null
    [[ "$(plist CFBundleIdentifier "${bundle}/Info.plist")" == "${identifier}" ]] || fail "${label} bundle identifier"
    [[ "$(plist CFBundleExecutable "${bundle}/Info.plist")" == "${executable}" ]] || fail "${label} executable name"
    [[ "$(plist CFBundleShortVersionString "${bundle}/Info.plist")" == "${marketing_version}" ]] || fail "${label} marketing version"
    [[ "$(plist CFBundleVersion "${bundle}/Info.plist")" == "${build_version}" ]] || fail "${label} build version"
    [[ "$(plist CFBundleSupportedPlatforms:0 "${bundle}/Info.plist")" == "${platform}" ]] || fail "${label} is not a device product"
    [[ "$(plist MinimumOSVersion "${bundle}/Info.plist")" == '26.0' ]] || fail "${label} deployment target differs from supported baseline"
    case "${label}" in
        *widget)
            [[ "$(plist NSExtension:NSExtensionPointIdentifier "${bundle}/Info.plist")" == 'com.apple.widgetkit-extension' ]] \
                || fail "${label} extension point"
            ;;
        *)
            [[ -s "${bundle}/Assets.car" ]] || fail "${label} compiled assets are absent"
            [[ "$(plist CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName "${bundle}/Info.plist")" == AppIcon ]] \
                || fail "${label} app icon metadata"
            ;;
    esac

    xcrun vtool -show-build "${bundle}/${executable}" > "${report}/${label}-macho.txt"
    [[ "$(awk '$1 == "platform" { print $2 }' "${report}/${label}-macho.txt" | sort -u)" == "${macho_platform}" ]] \
        || fail "${label} contains a wrong-platform Mach-O slice"
    awk '$1 == "sdk" { split($2, v, "."); if (v[1] < 26) bad=1; count++ }
        $1 == "minos" && $2 != "26.0" { bad=1 } END { exit (bad || !count) }' \
        "${report}/${label}-macho.txt" || fail "${label} SDK/deployment metadata"
    architectures="$(xcrun lipo -archs "${bundle}/${executable}")"
    for architecture in ${architectures}; do
        [[ "${architecture}" == arm64 || ( "${platform}" == WatchOS && "${architecture}" == arm64_32 ) ]] \
            || fail "${label} unexpected architecture"
    done
    [[ " ${architectures} " == *' arm64 '* ]] || fail "${label} is missing arm64"
    if [[ "${platform}" == WatchOS ]]; then
        [[ " ${architectures} " == *' arm64_32 '* ]] || fail "${label} is missing the supported arm64_32 slice"
    fi
    plutil -convert json -o - "${bundle}/PrivacyInfo.xcprivacy" | jq -S . > "${report}/${label}-privacy.json"
    plutil -convert json -o - "${repository_root}/${manifest}" | jq -S . > "${report}/${label}-expected-privacy.json"
    cmp -s "${report}/${label}-privacy.json" "${report}/${label}-expected-privacy.json" \
        || fail "${label} embedded privacy manifest differs from source"

    signature_checked=false
    symbols_checked=false
    if [[ "${mode}" == signed-archive ]]; then
        codesign --verify --strict --verbose=2 "${bundle}" > "${report}/${label}-signature-verification.log" 2>&1 \
            || fail "${label} signature is missing or invalid"
        codesign -d --verbose=4 "${bundle}" 2>&1 \
            | awk '/^(Identifier=|TeamIdentifier=|CDHash=|Signature=)/' > "${report}/${label}-signature.txt"
        rg -q -x "TeamIdentifier=${expected_team}" "${report}/${label}-signature.txt" \
            || fail "${label} has no matching certificate-backed signing team"
        codesign -d --entitlements :- "${bundle}" > "${report}/${label}-entitlements.plist" 2> "${report}/${label}-entitlements.log"
        plutil -convert json -o "${report}/${label}-entitlements.json" "${report}/${label}-entitlements.plist"
        plutil -convert json -o - "${repository_root}/${entitlements}" > "${report}/${label}-expected-entitlements.json"
        jq -e --arg team "${expected_team}" --arg bundle "${identifier}" \
            --slurpfile source "${report}/${label}-expected-entitlements.json" \
            -f "${script_directory}/watch-release-entitlements.jq" "${report}/${label}-entitlements.json" >/dev/null \
            || fail "${label} unexpected signed entitlement"
        [[ -s "${bundle}/embedded.mobileprovision" ]] || fail "${label} embedded provisioning profile is missing"
        # Preserve only entitlement data, not personal device lists/certificates.
        security cms -D -i "${bundle}/embedded.mobileprovision" \
            | plutil -extract Entitlements json -o - - > "${report}/${label}-profile-entitlements.json"
        dsym_binary="${input}/dSYMs/${dsym_name}/Contents/Resources/DWARF/${executable}"
        [[ -f "${dsym_binary}" ]] || fail "${label} dSYM binary is missing"
        binary_symbols="$({
            xcrun dwarfdump --uuid "${bundle}/${executable}" \
                | awk '/^UUID:/ { print toupper($2) " " $3 }' | LC_ALL=C sort
        })"
        dsym_symbols="$({
            xcrun dwarfdump --uuid "${dsym_binary}" \
                | awk '/^UUID:/ { print toupper($2) " " $3 }' | LC_ALL=C sort
        })"
        jq -n \
            --argjson binarySymbols "$(printf '%s\n' "${binary_symbols}" | jq -R -s 'split("\n") | map(select(length > 0))')" \
            --argjson dSYMIdentifiers "$(printf '%s\n' "${dsym_symbols}" | jq -R -s 'split("\n") | map(select(length > 0))')" \
            -f "${script_directory}/watch-release-symbols.jq" \
            > "${report}/${label}-symbols.json" \
            || fail "${label} dSYM architecture/UUID mismatch"
        signature_checked=true
        symbols_checked=true
    fi
    jq -n --arg label "${label}" --arg id "${identifier}" --arg arch "${architectures}" \
        --arg version "${marketing_version}" --arg build "${build_version}" \
        --argjson signed "${signature_checked}" --argjson symbols "${symbols_checked}" \
        '{component:$label,bundleID:$id,architectures:($arch|split(" ")),version:$version,build:$build,signatureChecked:$signed,dSYMChecked:$symbols}' \
        > "${report}/${label}-component.json"
done

readonly watch_plist="${phone_app}/Watch/WellSpentWatch.app/Info.plist"
[[ "$(plist WKCompanionAppBundleIdentifier "${watch_plist}")" == 'com.drewreilly.wellspent' ]] || fail 'Watch companion relationship'
[[ "$(plist WKRunsIndependentlyOfCompanionApp "${watch_plist}")" == false ]] || fail 'Watch must remain a dependent companion'
[[ "$(plist WKApplication "${watch_plist}")" == true ]] || fail 'modern Watch app declaration is absent'
if plist WKWatchOnly "${watch_plist}" >/dev/null 2>&1; then fail 'unexpected watch-only declaration'; fi

if [[ "${mode}" == signed-archive ]]; then
    [[ "$(plist ApplicationProperties:CFBundleIdentifier "${input}/Info.plist")" == 'com.drewreilly.wellspent' ]] \
        || fail 'archive bundle metadata'
    [[ "$(plist ApplicationProperties:CFBundleShortVersionString "${input}/Info.plist")" == "${marketing_version}" ]] \
        || fail 'archive marketing-version metadata'
    [[ "$(plist ApplicationProperties:CFBundleVersion "${input}/Info.plist")" == "${build_version}" ]] \
        || fail 'archive build-version metadata'
fi
PRIVACY_AUDIT_APP_BUNDLE="${phone_app}" bash "${script_directory}/privacy-audit.sh" > "${report}/privacy-audit.log" 2>&1
bash "${script_directory}/release-fixture-check.sh" "${phone_app}" > "${report}/fixture-audit.log" 2>&1
(cd "${phone_app}" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256) > "${report}/product-files.sha256"
product_digest="$(shasum -a 256 "${report}/product-files.sha256" | awk '{print $1}')"
jq -s --arg mode "${mode}" --arg digest "${product_digest}" '{
    schemaVersion:1, mode:$mode, productFileManifestSHA256:$digest,
    inspection:"passed", releaseApproved:false,
    remaining:["signed export/profile authorization reconciliation", "Xcode privacy report", "upload validation",
        "candidate source provenance", "physical install/upgrade/smoke", "release authorization"],
    components:.
}' "${report}/phone-component.json" "${report}/phone-widget-component.json" \
    "${report}/watch-component.json" "${report}/watch-widget-component.json" > "${report}/summary.json"
echo "Watch ${mode} inspection passed. This is not upload validation or release approval. Evidence: ${report}"
