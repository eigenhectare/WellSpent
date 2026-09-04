#!/bin/bash
set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly evidence_root="${WATCH_RESOURCE_EVIDENCE_ROOT:-${repository_root}/.derivedData/WatchResources}"
readonly destination="${WATCH_RESOURCE_DESTINATION:-platform=watchOS Simulator,name=Apple Watch SE 3 (40mm),OS=26.5}"
readonly manifest="${script_directory}/watch-resource-tests.txt"

for command in xcodegen xcodebuild xcrun jq; do
    command -v "${command}" >/dev/null || { echo "Missing resource-test prerequisite: ${command}" >&2; exit 1; }
done
[[ "${destination}" == platform=watchOS\ Simulator,* ]] || {
    echo 'This accelerated harness accepts only an explicitly selected watchOS Simulator.' >&2
    exit 1
}
cd "${repository_root}"
mkdir -p "${evidence_root}"
readonly run_root="$(mktemp -d "${evidence_root}/run.XXXXXX")"
echo "Resource test evidence: ${run_root}"
echo 'Do not share this destination with another active simulator job.'
xcodegen generate --spec project.yml > "${run_root}/generate.log" 2>&1
selections=()
while IFS= read -r selected || [[ -n "${selected}" ]]; do
    [[ -z "${selected}" || "${selected}" == \#* ]] && continue
    [[ "${selected}" =~ ^WellSpentWatchTests/WatchResourceTests/test[A-Za-z0-9_]+$ ]] || exit 1
    selections+=("-only-testing:${selected}")
done < "${manifest}"
xcodebuild -project WellSpent.xcodeproj -scheme WellSpentWatch -configuration Debug \
    -destination "${destination}" -destination-timeout 60 \
    -derivedDataPath "${run_root}/DerivedData" -resultBundlePath "${run_root}/resources.xcresult" \
    -parallel-testing-enabled NO -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 90 -maximum-test-execution-time-allowance 120 \
    "${selections[@]}" test > "${run_root}/tests.log" 2>&1
bash "${script_directory}/watch-resource-report.sh" "${run_root}/resources.xcresult" "${run_root}/report"
echo 'Accelerated storage correctness passed. CPU and file-size observations are not physical energy/budget certification.'
