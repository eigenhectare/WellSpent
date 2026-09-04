#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

cd "${repository_root}"

production_paths=(
    WellSpentApp
    WellSpentShared
    WellSpentWidgets
    WellSpentWatch
    WellSpentWatchContracts
    WellSpentWatchIntents
    WellSpentWatchStore
    WellSpentWatchWidgets
)
if [[ -n "${PRIVACY_AUDIT_EXTRA_SOURCE_PATH:-}" ]]; then
    production_paths+=("${PRIVACY_AUDIT_EXTRA_SOURCE_PATH}")
fi
readonly -a production_paths
readonly privacy_manifests=(
    WellSpentApp/Resources/PrivacyInfo.xcprivacy
    WellSpentWidgets/PrivacyInfo.xcprivacy
    WellSpentWatch/Resources/PrivacyInfo.xcprivacy
    WellSpentWatchWidgets/PrivacyInfo.xcprivacy
)
readonly entitlements_files=(
    WellSpentApp/Resources/WellSpent.entitlements
    WellSpentWidgets/WellSpentWidgets.entitlements
    WellSpentWatch/Resources/WellSpentWatch.entitlements
    WellSpentWatchWidgets/WellSpentWatchWidgets.entitlements
)

search_swift_sources() {
    local pattern="$1"
    shift

    find "$@" -type f -name '*.swift' -exec grep -nEH -- "${pattern}" {} +
}

# Local Watch goal alerts are opt-in and do not register with APNs. Keep all
# UserNotifications access confined to the audited adapter; other targets still
# cannot quietly acquire notification APIs under this exception.
if search_swift_sources '(import UserNotifications|UNUserNotificationCenter)' "${production_paths[@]}" \
    | grep -v '^WellSpentWatch/Features/Goals/WatchGoalSystemNotifications.swift:'
then
    echo "Privacy audit failed: notification API found outside the local Watch goal adapter." >&2
    exit 1
fi

if search_swift_sources \
    '(^import (HealthKit|WorkoutKit)$|HKHealthStore|HKWorkoutSession|HKWorkoutBuilder|WKExtendedRuntimeSession)' \
    "${production_paths[@]}"
then
    echo "Privacy audit failed: fitness or extended-runtime API found." >&2
    exit 1
fi

if search_swift_sources \
    '(^|[^[:alnum:]_])(print|debugPrint|NSLog|os_log)[[:space:]]*\(|Logger[[:space:]]*\(' \
    "${production_paths[@]}"
then
    echo "Privacy audit failed: production logging call found." >&2
    exit 1
fi

if search_swift_sources \
    '(^import (Network|CFNetwork|WebKit|CloudKit|MetricKit|AdSupport|AppTrackingTransparency|AuthenticationServices|StoreKit)$|URLSession|NSURLSession|NSURLConnection|HTTPURLResponse|NW(Connection|PathMonitor|Listener|Browser)|(^|[^[:alnum:]_])(socket|connect|send|recv|getaddrinfo)[[:space:]]*\(|WKWebView|ASWebAuthenticationSession|registerForRemoteNotifications|push(TokenUpdates|ToStartToken)|pushType:[[:space:]]*\.(token|channel)|CKContainer|cloudKitDatabase:[[:space:]]*\.(automatic|private|public)|Analytics|Crashlytics|Sentry|Firebase|Telemetry|AppCenter|Datadog|NewRelic|Bugsnag|Instabug|Amplitude|Mixpanel|PostHog|Snowplow)' \
    "${production_paths[@]}"
then
    echo "Privacy audit failed: unexpected network, tracking, or diagnostics API found." >&2
    exit 1
fi

if search_swift_sources \
    "(https?|wss?|ftp)://[^[:space:]\"']+" \
    "${production_paths[@]}"
then
    echo "Privacy audit failed: hard-coded remote URL found in production source." >&2
    exit 1
fi

if search_swift_sources \
    '(fatalError|preconditionFailure|assertionFailure)[[:space:]]*\([^)]*\\\(' \
    "${production_paths[@]}"
then
    echo "Privacy audit failed: interpolated production crash/assertion message found." >&2
    exit 1
fi

if grep -nEH \
    '(XCRemoteSwiftPackageReference|repositoryURL[[:space:]]*=|packageReferences[[:space:]]*=)' \
    WellSpent.xcodeproj/project.pbxproj project.yml
then
    echo "Privacy audit failed: remote package dependency found." >&2
    exit 1
fi

readonly dependency_manifests=(
    Package.swift
    Package.resolved
    Podfile
    Podfile.lock
    Cartfile
    Cartfile.resolved
)
for dependency_manifest in "${dependency_manifests[@]}"; do
    if [[ -e "${dependency_manifest}" ]]; then
        echo "Privacy audit failed: dependency manifest found: ${dependency_manifest}." >&2
        exit 1
    fi
done

for entitlements_file in "${entitlements_files[@]}"; do
    plutil -lint "${entitlements_file}" >/dev/null
    if grep -nEH \
        '(aps-environment|com\.apple\.developer\.icloud|com\.apple\.developer\.associated-domains|com\.apple\.developer\.networking|com\.apple\.developer\.healthkit|com\.apple\.developer\.usernotifications)' \
        "${entitlements_file}"
    then
        echo "Privacy audit failed: unexpected cloud, network, or sensitive entitlement found." >&2
        exit 1
    fi
done

for privacy_manifest in "${privacy_manifests[@]}"; do
    plutil -lint "${privacy_manifest}" >/dev/null
    if [[ "$(plutil -extract NSPrivacyTracking raw -o - "${privacy_manifest}")" != "false" ]]; then
        echo "Privacy audit failed: tracking is enabled in ${privacy_manifest}." >&2
        exit 1
    fi
    if [[ "$(plutil -extract NSPrivacyCollectedDataTypes json -o - "${privacy_manifest}")" != "[]" ]]; then
        echo "Privacy audit failed: collected data is declared in ${privacy_manifest}." >&2
        exit 1
    fi
done

readonly app_bundle="${PRIVACY_AUDIT_APP_BUNDLE:-}"
if [[ -n "${app_bundle}" ]]; then
    if [[ ! -d "${app_bundle}" ]]; then
        echo "Privacy audit failed: Release app bundle not found at ${app_bundle}." >&2
        exit 1
    fi

    readonly app_binary="${app_bundle}/WellSpent"
    readonly widget_bundle="${app_bundle}/PlugIns/WellSpentWidgets.appex"
    readonly widget_binary="${widget_bundle}/WellSpentWidgets"
    readonly watch_bundle="${app_bundle}/Watch/WellSpentWatch.app"
    readonly watch_binary="${watch_bundle}/WellSpentWatch"
    readonly watch_widget_bundle="${watch_bundle}/PlugIns/WellSpentWatchWidgets.appex"
    readonly watch_widget_binary="${watch_widget_bundle}/WellSpentWatchWidgets"
    readonly binaries=(
        "${app_binary}"
        "${widget_binary}"
        "${watch_binary}"
        "${watch_widget_binary}"
    )

    for bundled_manifest in \
        "${app_bundle}/PrivacyInfo.xcprivacy" \
        "${widget_bundle}/PrivacyInfo.xcprivacy" \
        "${watch_bundle}/PrivacyInfo.xcprivacy" \
        "${watch_widget_bundle}/PrivacyInfo.xcprivacy"
    do
        if [[ ! -f "${bundled_manifest}" ]]; then
            echo "Privacy audit failed: bundled privacy manifest missing: ${bundled_manifest}." >&2
            exit 1
        fi
        plutil -lint "${bundled_manifest}" >/dev/null
    done

    if [[ -n "$(find "${app_bundle}" -path '*/Frameworks/*' -type f -print -quit)" ]]; then
        echo "Privacy audit failed: embedded runtime framework or library found." >&2
        exit 1
    fi

    for binary in "${binaries[@]}"; do
        if [[ ! -x "${binary}" ]]; then
            echo "Privacy audit failed: expected executable missing: ${binary}." >&2
            exit 1
        fi
        if otool -L "${binary}" | grep -nE \
            '/(CFNetwork|Network|WebKit|CloudKit|MetricKit|AdSupport|AuthenticationServices|StoreKit|HealthKit|WorkoutKit)\.framework/'
        then
            echo "Privacy audit failed: prohibited framework linked by ${binary}." >&2
            exit 1
        fi
        if nm -u "${binary}" | grep -nEi \
            '(URLSession|NSURLConnection|HTTPURLResponse|NWConnection|NWPathMonitor|CKContainer|WKWebView|registerForRemoteNotifications|pushTokenUpdates|pushToStartToken|Analytics|Crashlytics|Sentry|Firebase|HKHealthStore|HKWorkoutSession|HKWorkoutBuilder|WKExtendedRuntimeSession)'
        then
            echo "Privacy audit failed: prohibited egress symbol found in ${binary}." >&2
            exit 1
        fi
        if strings -a "${binary}" | grep -nEi \
            '((https?|wss?|ftp)://|([0-9]{1,3}\.){3}[0-9]{1,3})'
        then
            echo "Privacy audit failed: remote URL or IP literal found in ${binary}." >&2
            exit 1
        fi
    done
fi

echo "Privacy audit passed: source, capabilities, dependencies, manifests, and available Release binaries are local-only."
