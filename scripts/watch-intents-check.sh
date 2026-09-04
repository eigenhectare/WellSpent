#!/bin/bash
set -euo pipefail
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
cd "${repository_root}"
fail() { echo "Watch intents check failed: $1" >&2; exit 1; }

rg -q 'WatchSystemCommandBoundary' WellSpentWatch/App/WellSpentWatchRuntime.swift || fail 'app executor missing'
rg -q 'expectedContext' WellSpentWatch/Features/Timer/WatchSystemCommandBoundary.swift || fail 'stale-state guard missing'
rg -q 'performLocalCommand' WellSpentWatch/Features/Timer/WatchSystemCommandBoundary.swift || fail 'durable command boundary missing'
rg -q 'WellSpentWatchTimerControl\(\)' WellSpentWatchWidgets/WellSpentWatchWidgetBundle.swift || fail 'control registration missing'
rg -q 'readProjectChoices' WellSpentWatchIntents/WellSpentWatchIntents.swift || fail 'bounded project query missing'
if rg -n '(ModelContainer|ModelContext|performLocalCommand|openDefault\()' WellSpentWatchIntents WellSpentWatchWidgets; then
    fail 'an intent/extension bypasses the app-owned writer'
fi

if [[ -n "${WATCH_INTENTS_APP_BUNDLE:-}" ]]; then
    command -v jq >/dev/null || fail 'jq is required for generated metadata validation'
    readonly watch_app="${WATCH_INTENTS_APP_BUNDLE}"
    for bundle in "${watch_app}" "${watch_app}/PlugIns/WellSpentWatchWidgets.appex"; do
        metadata="${bundle}/Metadata.appintents/extract.actionsdata"
        [[ -f "${metadata}" ]] || fail 'generated App Intent metadata missing'
        jq -e '.actions | length == 7' "${metadata}" >/dev/null || fail 'unexpected executable/configuration intent set'
        for intent in StartWellSpentWatchTimerIntent PauseWellSpentWatchTimerIntent ResumeWellSpentWatchTimerIntent SwitchWellSpentWatchProjectIntent EndWellSpentWatchTimerIntent WellSpentWatchControlAction; do
            jq -e --arg intent "${intent}" '
                .actions[$intent] as $action |
                $action.openAppWhenRun == true and $action.supportedModes == 2 and
                $action.authenticationPolicy == 2 and $action.isAuthPolExplicit == true
            ' "${metadata}" >/dev/null || fail "${intent} lost explicit foreground/authentication policy"
        done
        jq -e '.entities.WellSpentWatchProjectEntity != null and .actions.WellSpentWatchFavoriteConfiguration != null' "${metadata}" >/dev/null || fail 'project entity or favorite configuration missing'
    done
    jq -e '.autoShortcuts | length == 5' "${watch_app}/Metadata.appintents/extract.actionsdata" >/dev/null || fail 'five app shortcuts missing'
    jq -e '.autoShortcuts | length == 0' "${watch_app}/PlugIns/WellSpentWatchWidgets.appex/Metadata.appintents/extract.actionsdata" >/dev/null || fail 'extension duplicates app shortcuts'
    echo 'Generated app and widget intent metadata passed: foreground, local authentication, project entity, favorite configuration, five app shortcuts.'
else
    echo 'Watch intent structural checks passed; set WATCH_INTENTS_APP_BUNDLE to validate compiled execution/authentication metadata.'
fi
