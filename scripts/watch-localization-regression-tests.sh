#!/bin/bash
set -euo pipefail
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly fixture_directory="$(mktemp -d "${TMPDIR:-/tmp}/wellspent-localization-audit.XXXXXX")"
readonly fixture="${fixture_directory}/Localizable.xcstrings"
readonly output="${fixture_directory}/check.log"
trap 'rm -f -- "${fixture}" "${output}"; rmdir -- "${fixture_directory}"' EXIT

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
echo 'Watch localization negative guards passed: missing keys, new/stale values, plurals, sample data and language.'
