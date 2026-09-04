#!/bin/bash
set -euo pipefail
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
cd "${repository_root}"
fail() { echo "Watch Live Activity check failed: $1" >&2; exit 1; }

readonly lifecycle=WellSpentApp/Integrations/LiveActivity/LiveActivityLifecycle.swift
readonly intent=WellSpentShared/LiveActivity/StopWellSpentTimerIntent.swift
rg -q 'setDesiredState' "${lifecycle}" || fail 'synchronous canonical publication missing'
rg -q 'captured == generation' "${lifecycle}" || fail 'generation fence missing'
rg -q 'drainTask' "${lifecycle}" || fail 'serialized driver drain missing'
rg -q 'canRequestActivity' "${lifecycle}" || fail 'foreground creation gate missing'
rg -q 'expectedRevision' "${intent}" || fail 'revision-bound Stop missing'
if rg -n 'Activity<|\.end\(|\.update\(|Activity.request' "${intent}"; then
    fail 'Stop intent writes ActivityKit before canonical persistence'
fi
if rg -n 'TimelineView|Timer.scheduledTimer' WellSpentShared/LiveActivity/WellSpentActivityPresentation.swift WellSpentWidgets; then
    fail 'widget presentation acquired an extension timer loop'
fi
rg -q 'WKSupportsLiveActivityLaunchAttributeTypes' project.yml || fail 'Watch mirror launch configuration missing'
for test_source in LiveActivityLifecycleTests LiveActivitySerializationTests LiveActivityPresentationTests; do
    [[ -s "WellSpentTests/LiveActivity/${test_source}.swift" ]] || fail 'regression suite missing'
done
echo "Live Activity structural checks passed. Unit/render/UI tests prove behavior; physical mirroring and lock-screen intent execution remain separate."
