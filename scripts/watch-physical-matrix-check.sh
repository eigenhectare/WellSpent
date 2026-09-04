#!/bin/bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <candidate.json> <results-directory> <new-report-directory>" >&2
    exit 64
fi

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly required_cases="${script_directory}/watch-physical-required-cases.tsv"
readonly candidate_input="$1"
readonly results_input="$2"
report_directory="$3"
fail() { echo "Watch physical matrix check failed: $1" >&2; exit 1; }

[[ -f "${candidate_input}" && ! -L "${candidate_input}" ]] || fail 'regular candidate JSON required'
[[ -d "${results_input}" && ! -L "${results_input}" ]] || fail 'regular results directory required'
[[ -s "${required_cases}" ]] || fail 'required-case manifest missing'
[[ ! -e "${report_directory}" ]] || fail 'report directory already exists; preserve earlier evidence'

candidate="$(cd "$(dirname "${candidate_input}")" && pwd -P)/$(basename "${candidate_input}")"
results_directory="$(cd "${results_input}" && pwd -P)"
report_parent="$(cd "$(dirname "${report_directory}")" && pwd -P)" \
    || fail 'report parent must already exist'
report_directory="${report_parent}/$(basename "${report_directory}")"
readonly candidate results_directory report_directory

jq -e '
    .schemaVersion == 1
    and (.sourceCommit | type == "string" and test("^[0-9a-f]{40}$"))
    and (.version | type == "string" and test("^[0-9]+[.][0-9]+[.][0-9]+$"))
    and (.build | type == "string" and test("^[0-9]+$"))
    and (.productDigest | type == "string" and test("^[0-9a-f]{64}$"))
    and .workingTreeClean == true
    and (.installationChannel == "xcode-unified"
        or .installationChannel == "testflight"
        or .installationChannel == "app-store")
    and (.verifiedAt | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T"))
' "${candidate}" >/dev/null || fail 'candidate identity is incomplete or not a clean fixed source'

result_files=()
while IFS= read -r result; do
    result_files+=("${result}")
done < <(find "${results_directory}" -maxdepth 1 -type f -name '*.json' -print | LC_ALL=C sort)
[[ "${#result_files[@]}" -gt 0 ]] || fail 'no physical result JSON files found'

scratch_directory="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentPhysicalMatrix.XXXXXX")"
readonly scratch_directory
cleanup() {
    [[ -n "${scratch_directory}" && -d "${scratch_directory}" ]] || return
    rm -rf -- "${scratch_directory}"
}
trap cleanup EXIT
keys_file="${scratch_directory}/keys.txt"
readonly keys_file
: >"${keys_file}"

for result in "${result_files[@]}"; do
    [[ ! -L "${result}" ]] || fail 'result JSON symlinks are not accepted'
    jq -e --slurpfile candidate "${candidate}" '
        .schemaVersion == 1
        and (.caseID | type == "string" and test("^[A-Z]+-[0-9]{2}$"))
        and (.repeat | type == "number" and . >= 1 and floor == .)
        and .outcome == "passed"
        and (.observedAt | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T"))
        and .candidate == ($candidate[0] | {
            sourceCommit, version, build, productDigest, installationChannel
        })
        and .environment.physical == true
        and .environment.debuggerAttached == false
        and .environment.versionsAligned == true
        and .environment.counterpartRegistered == true
        and (.environment.phoneAlias | type == "string" and length > 0)
        and (.environment.phoneModel | type == "string" and length > 0)
        and (.environment.phoneOS | type == "string" and length > 0)
        and (.environment.watchAlias | type == "string" and length > 0)
        and (.environment.watchModel | type == "string" and length > 0)
        and (.environment.watchOS | type == "string" and length > 0)
        and (.environment.installMethod == "xcode-unified"
            or .environment.installMethod == "testflight"
            or .environment.installMethod == "app-store")
        and .environment.installMethod == $candidate[0].installationChannel
        and (.observationSeconds | type == "number" and . >= 0)
        and (.initialState | type == "string" and length > 0)
        and (.actions | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
        and (.observations | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
        and .privacyReviewed == true
        and (.artifacts | type == "array" and length > 0 and all(.[];
            type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._/-]*$") and (contains("..") | not)))
        and .invariants == {
            durableSave: "passed",
            countedIntervals: "passed",
            idempotency: "passed",
            divergenceSafety: "passed",
            convergence: "passed",
            privacy: "passed"
        }
        and ([paths(scalars) | map(tostring) | join(".")
            | test("(serial|udid|ecid|account|hostname|ipaddress|deviceidentifier)"; "i")] | any | not)
        and ([.. | scalars | tostring
            | test("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")] | any | not)
    ' "${result}" >/dev/null || fail "invalid, failed, inconclusive, unsafe, or mismatched result: $(basename "${result}")"

    key="$(jq -r '[.caseID, (.repeat | tostring)] | @tsv' "${result}")"
    [[ -n "${key}" ]] || fail 'missing result key'
    printf '%s\n' "${key}" >>"${keys_file}"

    while IFS= read -r artifact; do
        [[ "${artifact}" != /* && "${artifact}" != *..* ]] || fail 'unsafe artifact path'
        artifact_path="${results_directory}/${artifact}"
        [[ -s "${artifact_path}" && ! -L "${artifact_path}" ]] \
            || fail "missing or empty sanitized artifact: ${artifact}"
        artifact_parent="$(cd "$(dirname "${artifact_path}")" && pwd -P)"
        case "${artifact_parent}/" in
            "${results_directory}/"*) ;;
            *) fail "artifact escapes the result directory: ${artifact}" ;;
        esac
    done < <(jq -r '.artifacts[]' "${result}")
done

[[ "$(LC_ALL=C sort "${keys_file}" | uniq -d | wc -l | tr -d ' ')" == 0 ]] \
    || fail 'duplicate case/repetition result'

expected_records=0
while IFS=$'\t' read -r case_id minimum_repetitions minimum_seconds requires_authorization requires_old_build; do
    [[ -z "${case_id}" || "${case_id}" == \#* ]] && continue
    [[ "${case_id}" =~ ^[A-Z]+-[0-9]{2}$ ]] || fail 'invalid required case ID'
    [[ "${minimum_repetitions}" =~ ^[1-9][0-9]*$ && "${minimum_seconds}" =~ ^[0-9]+$ ]] \
        || fail "invalid manifest counts for ${case_id}"
    expected_records=$((expected_records + minimum_repetitions))
    for repeat in $(seq 1 "${minimum_repetitions}"); do
        matches=()
        for candidate_result in "${result_files[@]}"; do
            if jq -e --arg caseID "${case_id}" --argjson repeat "${repeat}" \
                '.caseID == $caseID and .repeat == $repeat' "${candidate_result}" >/dev/null; then
                matches+=("${candidate_result}")
            fi
        done
        [[ "${#matches[@]}" == 1 ]] || fail "missing or ambiguous ${case_id} repetition ${repeat}"
        result="${matches[0]}"
        [[ "$(jq -r '.observationSeconds' "${result}")" -ge "${minimum_seconds}" ]] \
            || fail "${case_id} did not meet its observation duration"
        if [[ "${requires_authorization}" == true ]]; then
            jq -e '.authorizationReference | type == "string" and length > 0' "${result}" >/dev/null \
                || fail "${case_id} lacks destructive-action authorization"
        fi
        if [[ "${requires_old_build}" == true ]]; then
            jq -e '.oldBuildReference | type == "string" and length > 0' "${result}" >/dev/null \
                || fail "${case_id} lacks an oldest-build reference"
        fi
    done
done <"${required_cases}"

while IFS=$'\t' read -r observed_case _; do
    awk -F $'\t' -v expected="${observed_case}" '$1 == expected { found=1 } END { exit !found }' "${required_cases}" \
        || fail "unknown physical case: ${observed_case}"
done <"${keys_file}"

[[ "${#result_files[@]}" -ge "${expected_records}" ]] || fail 'insufficient physical result count'
mkdir -p "${report_directory}"
jq -n --slurpfile candidate "${candidate}" \
    --argjson resultCount "${#result_files[@]}" \
    --argjson requiredMinimum "${expected_records}" '{
        schemaVersion: 1,
        matrixPassed: true,
        scope: "Physical paired-device results only; Simulator and WC Probe evidence are excluded.",
        candidate: ($candidate[0] | {sourceCommit, version, build, productDigest, installationChannel}),
        resultCount: $resultCount,
        requiredMinimum: $requiredMinimum,
        failed: 0,
        inconclusive: 0,
        notRun: 0,
        releaseApproved: false,
        remaining: ["WAT-25 resource/privacy acceptance", "WAT-26 signed distribution candidate", "WAT-27 candidate assets", "WAT-28 beta/review/release"]
    }' >"${report_directory}/summary.json"
echo "Physical WAT-24 matrix passed for one fixed candidate. This is not release approval. Evidence: ${report_directory}/summary.json"
