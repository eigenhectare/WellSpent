#!/bin/bash
set -euo pipefail
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly fixture_directory="$(mktemp -d "${TMPDIR:-/tmp}/wellspent-localization-audit.XXXXXX")"
readonly fixture="${fixture_directory}/Localizable.xcstrings"
readonly output="${fixture_directory}/check.log"
cleanup() {
    case "${fixture_directory}" in
        "${TMPDIR:-/tmp}"/wellspent-localization-audit.*) rm -rf -- "${fixture_directory}" ;;
        *) echo "Refusing to remove unexpected temporary path: ${fixture_directory}" >&2 ;;
    esac
}
trap cleanup EXIT

bash "${script_directory}/watch-localization-check.sh"
reject() {
    local transformation="$1" expected="$2"
    # Mechanically derive corrupt resource fixtures from the real catalog.
    jq "${transformation}" "${repository_root}/WellSpentWatchLocalization/Localizable.xcstrings" > "${fixture}"
    if WATCH_LOCALIZATION_CATALOG="${fixture}" bash "${script_directory}/watch-localization-check.sh" > "${output}" 2>&1; then
        echo 'Localization regression guard accepted corrupt catalog.' >&2; exit 1
    fi
    rg -q -F "${expected}" "${output}" || { echo 'Localization guard failed for the wrong reason.' >&2; exit 1; }
}
reject 'del(.strings.Running)' 'critical presentation boundary'
reject '.strings.Running.localizations.en.stringUnit.state = "new"' 'complete English values'
reject '.strings.Running.extractionState = "stale"' 'without stale entries'
reject '.strings["Pending sync, %lld items. Cached projects remain available."].localizations.en.variations.plural.one.stringUnit.value = "Wrong plural"' 'singular and plural forms'
reject '.strings.Running.localizations.en.stringUnit.value = "Client Launch"' 'critical presentation boundary'
reject '.strings["Track billable time from your wrist."].localizations.en.stringUnit.value = "Client Launch"' 'sample private content'
reject '.sourceLanguage = "fr"' 'complete English values'

readonly release_fixture="${fixture_directory}/Release-watchsimulator"
mkdir -p "${release_fixture}/WellSpentWatch.build" "${release_fixture}/WellSpentWatchWidgets.build"
jq -n \
    --slurpfile catalog "${repository_root}/WellSpentWatchLocalization/Localizable.xcstrings" \
    --slurpfile shortcuts "${repository_root}/WellSpentWatch/Resources/AppShortcuts.xcstrings" '
    {
        tables: {
            Localizable: ((($catalog[0].strings | keys) + ["Missing CI diagnostic key"]) | map({key: .})),
            AppShortcuts: (($shortcuts[0].strings | keys) | map({key: .}))
        }
    }
' > "${release_fixture}/WellSpentWatch.build/diagnostic.stringsdata"
for index in 1 2 3 4 5 6 7 8 9 10; do
    printf '%s\n' '{}' > "${release_fixture}/WellSpentWatchWidgets.build/empty-${index}.stringsdata"
done
if bash "${script_directory}/watch-localization-check.sh" "${release_fixture}" > "${output}" 2>&1; then
    echo 'Localization parity guard accepted a missing extracted key.' >&2; exit 1
fi
rg -q -F 'Localizable.xcstrings: Missing CI diagnostic key' "${output}" \
    || { echo 'Localization parity guard did not identify the missing key.' >&2; exit 1; }
echo 'Watch localization negative guards passed: missing keys, new/stale values, plurals, sample data and language.'
