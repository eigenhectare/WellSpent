#!/bin/bash
set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
cd "${repository_root}"
readonly catalog="${WATCH_LOCALIZATION_CATALOG:-WellSpentWatchLocalization/Localizable.xcstrings}"
readonly shortcuts="WellSpentWatch/Resources/AppShortcuts.xcstrings"

fail() { echo "Watch localization check failed: $1" >&2; exit 1; }

# This guard validates resources, not source completeness or rendered layout.
# Run the locale/plural unit cases and expanded-English UI suite as well.
jq -e '
    .sourceLanguage == "en" and .version == "1.0" and
    (.strings | length > 200) and
    (.strings | all(
        .extractionState != "stale" and
        (.localizations | keys == ["en"]) and
        ([.localizations.en | .. | objects | select(has("stringUnit")) | .stringUnit] |
            length > 0 and all(.state == "translated" and (.value | type == "string")))
    ))
' "${catalog}" >/dev/null || fail 'catalog needs complete English values without stale entries'

jq -e '
    .strings as $strings |
    ["Running", "Paused", "Couldn’t pause", "Couldn’t save changes", "Run saved",
     "Time Goal", "Time goal reached", "Pause Timer", "Project, %@"] |
    all(. as $key | $strings[$key].localizations.en.stringUnit.value == $key)
' "${catalog}" >/dev/null || fail 'a critical presentation boundary is missing'

jq -e '
    .strings["Pending sync, %lld items. Cached projects remain available."].localizations.en.variations.plural |
    .one.stringUnit.value == "Pending sync, %lld item. Cached projects remain available." and
    .other.stringUnit.value == "Pending sync, %lld items. Cached projects remain available."
' "${catalog}" >/dev/null || fail 'pending sync needs singular and plural forms'

if rg -q -F -e 'Toggle test privacy' -e 'Client Launch' -e 'Admin & Operations' -e 'Reviewed research findings' "${catalog}"; then
    fail 'test-only or sample private content was copied into the shipping catalog'
fi

jq -e '.sourceLanguage == "en" and (.strings | length == 5) and
    (.strings | keys | all(contains("${applicationName}")))' "${shortcuts}" >/dev/null \
    || fail 'the five Siri phrases must retain the application-name substitution'

# Optional parity against a completed Release build, never Debug extraction.
# Supply the Release-watchsimulator or Release-watchos intermediate directory.
if [[ "$#" -gt 0 ]]; then
    readonly release_data="$1"
    [[ -d "${release_data}" && "${release_data}" == */Release-watch* ]] \
        || fail 'extraction evidence must be a completed Watch Release intermediate directory'
    extraction_files=()
    while IFS= read -r -d '' path; do extraction_files+=("${path}"); done < <(
        rg --files -0 "${release_data}/WellSpentWatch.build" "${release_data}/WellSpentWatchWidgets.build" -g '*.stringsdata'
    )
    [[ "${#extraction_files[@]}" -gt 10 ]] || fail 'missing Release string extraction'
    jq -s -e --slurpfile catalog "${catalog}" --slurpfile shortcuts "${shortcuts}" '
        ([.[].tables.Localizable[]?.key] | unique) as $local |
        ([.[].tables.AppShortcuts[]?.key] | unique) as $phrases |
        ($local | length > 200) and ($phrases | length == 5) and
        ($local - ($catalog[0].strings | keys) | length == 0) and
        ($phrases - ($shortcuts[0].strings | keys) | length == 0)
    ' "${extraction_files[@]}" >/dev/null || fail 'shipping source contains keys absent from the catalogs'
fi

echo 'Watch localization resources passed: English values, critical keys, plurals, Siri substitutions and fixture isolation.'
