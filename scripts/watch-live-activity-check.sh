#!/bin/bash
set -euo pipefail
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
cd "${repository_root}"
fail() { echo "Watch Live Activity check failed: $1" >&2; exit 1; }

readonly lifecycle=WellSpentApp/Integrations/LiveActivity/LiveActivityLifecycle.swift
readonly intent=WellSpentShared/LiveActivity/StopWellSpentTimerIntent.swift
readonly presentation=WellSpentShared/LiveActivity/WellSpentActivityPresentation.swift
readonly app_entry=WellSpentApp/App/WellSpentApp.swift
readonly watch_runtime=WellSpentWatch/App/WellSpentWatchRuntime.swift
readonly watch_state=WellSpentWatchStore/WatchWidgetState.swift
rg -q 'setDesiredState' "${lifecycle}" || fail 'synchronous canonical publication missing'
rg -q 'captured == generation' "${lifecycle}" || fail 'generation fence missing'
rg -q 'drainTask' "${lifecycle}" || fail 'serialized driver drain missing'
rg -q 'canRequestActivity' "${lifecycle}" || fail 'foreground creation gate missing'
rg -q 'expectedRevision' "${intent}" || fail 'revision-bound Stop missing'
rg -q 'supportedModes.*background' "${intent}" || fail 'Stop intent must execute without foregrounding iPhone'
rg -q 'openAppWhenRun.*false' "${intent}" || fail 'Stop intent still requires foreground iPhone launch'
rg -q 'WellSpentLiveActivityHandoffDispatcher\.reconcile' "${app_entry}" || fail 'early app intent bridge registration missing'
if rg -n 'Activity<|\.end\(|\.update\(|Activity.request' "${intent}"; then
    fail 'Stop intent writes ActivityKit before canonical persistence'
fi
if rg -n 'TimelineView|Timer.scheduledTimer' WellSpentShared/LiveActivity/WellSpentActivityPresentation.swift WellSpentWidgets; then
    fail 'widget presentation acquired an extension timer loop'
fi
rg -q 'WellSpentLiveActivityHourglass' "${presentation}" || fail 'custom Watch mirror mark missing'
rg -q 'Link\(destination: WellSpentDeepLink\.watchStopURL' "${presentation}" || fail 'Watch mirror Stop link missing'
rg -q 'state\.stopAccessibilityLabel' "${presentation}" || fail 'Watch mirror Stop accessibility missing'
rg -q 'WatchLiveActivityAction' "${watch_state}" || fail 'Watch Stop link parser missing'
rg -q 'performLiveActivityAction' "${watch_runtime}" || fail 'Watch Stop link command bridge missing'
if rg -q 'iPhone copy' "${presentation}"; then
    fail 'obsolete iPhone copy label remains visible'
fi
rg -q 'WKSupportsLiveActivityLaunchAttributeTypes' project.yml || fail 'Watch mirror launch configuration missing'
for test_source in LiveActivityLifecycleTests LiveActivitySerializationTests LiveActivityPresentationTests; do
    [[ -s "WellSpentTests/LiveActivity/${test_source}.swift" ]] || fail 'regression suite missing'
done
if [[ -n "${LIVE_ACTIVITY_WIDGET_BUNDLE:-}" ]]; then
    command -v jq >/dev/null || fail 'jq is required for generated metadata validation'
    metadata="${LIVE_ACTIVITY_WIDGET_BUNDLE}/Metadata.appintents/extract.actionsdata"
    [[ -f "${metadata}" ]] || fail 'generated Live Activity App Intent metadata missing'
    jq -e '
        .actions.StopWellSpentTimerIntent as $action |
        $action.openAppWhenRun == false and $action.supportedModes == 1 and
        $action.authenticationPolicy == 2 and $action.isAuthPolExplicit == true and
        $action.isDiscoverable == false and
        [$action.parameters[].name] == ["activityID", "expectedRevision"]
    ' "${metadata}" >/dev/null || fail 'Stop intent lost background/authentication/revision metadata'
    echo "Live Activity structural and generated intent metadata checks passed."
else
    echo "Live Activity structural checks passed; set LIVE_ACTIVITY_WIDGET_BUNDLE to validate generated intent metadata."
fi
