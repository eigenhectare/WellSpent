#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly validator="${script_directory}/watch-physical-matrix-check.sh"
readonly manifest="${script_directory}/watch-physical-required-cases.tsv"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentPhysicalMatrixTests.XXXXXX")"
readonly fixture_root
cleanup() {
    [[ -n "${fixture_root}" && -d "${fixture_root}" ]] || return
    rm -rf -- "${fixture_root}"
}
trap cleanup EXIT
mkdir -p "${fixture_root}/results/artifacts"

jq -n '{
    schemaVersion: 1,
    sourceCommit: "0123456789abcdef0123456789abcdef01234567",
    version: "0.1.0",
    build: "3",
    productDigest: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    workingTreeClean: true,
    installationChannel: "xcode-unified",
    verifiedAt: "2026-09-03T00:00:00Z"
}' >"${fixture_root}/candidate.json"

while IFS=$'\t' read -r case_id minimum_repetitions minimum_seconds _ _; do
    [[ -z "${case_id}" || "${case_id}" == \#* ]] && continue
    for repeat in $(seq 1 "${minimum_repetitions}"); do
        artifact="artifacts/${case_id}-${repeat}.txt"
        printf 'sanitized physical observation\n' >"${fixture_root}/results/${artifact}"
        observation_seconds="${minimum_seconds}"
        [[ "${observation_seconds}" -gt 0 ]] || observation_seconds=60
        jq -n \
            --arg caseID "${case_id}" \
            --argjson repeat "${repeat}" \
            --argjson observationSeconds "${observation_seconds}" \
            --arg artifact "${artifact}" \
            --slurpfile candidate "${fixture_root}/candidate.json" '{
                schemaVersion: 1,
                caseID: $caseID,
                repeat: $repeat,
                outcome: "passed",
                observedAt: "2026-09-03T01:00:00Z",
                candidate: ($candidate[0] | {
                    sourceCommit, version, build, productDigest, installationChannel
                }),
                environment: {
                    physical: true,
                    debuggerAttached: false,
                    versionsAligned: true,
                    counterpartRegistered: true,
                    phoneAlias: "phone-fixture",
                    phoneModel: "Fixture Phone",
                    phoneOS: "26.6",
                    watchAlias: "watch-fixture",
                    watchModel: "Fixture Watch",
                    watchOS: "26.6",
                    installMethod: "xcode-unified"
                },
                observationSeconds: $observationSeconds,
                initialState: "Sanitized synchronized fixture",
                actions: ["Executed the frozen case"],
                observations: ["Observed the required invariant"],
                privacyReviewed: true,
                artifacts: [$artifact],
                authorizationReference: "owner-approved-fixture",
                oldBuildReference: "oldest-build-fixture",
                invariants: {
                    durableSave: "passed",
                    countedIntervals: "passed",
                    idempotency: "passed",
                    divergenceSafety: "passed",
                    convergence: "passed",
                    privacy: "passed"
                }
            }' >"${fixture_root}/results/${case_id}-${repeat}.json"
    done
done <"${manifest}"

bash "${validator}" "${fixture_root}/candidate.json" "${fixture_root}/results" "${fixture_root}/valid-report"
jq -e '
    .matrixPassed == true
    and .resultCount == 55
    and .requiredMinimum == 55
    and .failed == 0
    and .inconclusive == 0
    and .notRun == 0
    and .releaseApproved == false
' "${fixture_root}/valid-report/summary.json" >/dev/null

expect_rejected() {
    local label="$1"
    if bash "${validator}" "${fixture_root}/candidate.json" "${fixture_root}/results" \
        "${fixture_root}/rejected-${label}" >"${fixture_root}/${label}.log" 2>&1; then
        echo "Physical matrix validator falsely accepted: ${label}" >&2
        exit 1
    fi
}

mutate_and_reject() {
    local label="$1" file="$2" mutation="$3"
    cp "${file}" "${fixture_root}/original.json"
    jq "${mutation}" "${file}" >"${fixture_root}/mutated.json"
    mv "${fixture_root}/mutated.json" "${file}"
    expect_rejected "${label}"
    mv "${fixture_root}/original.json" "${file}"
}

mutate_and_reject failed-outcome "${fixture_root}/results/RADIO-02-1.json" '.outcome = "failed"'
mutate_and_reject attached-debugger "${fixture_root}/results/LIFE-01-1.json" '.environment.debuggerAttached = true'
mutate_and_reject identifier-leak "${fixture_root}/results/SAVE-01-1.json" '.environment.serialNumber = "SECRET"'
mutate_and_reject uuid-value-leak "${fixture_root}/results/SAVE-01-1.json" '.observations = ["device 12345678-1234-1234-1234-123456789abc"]'
mutate_and_reject missing-authorization "${fixture_root}/results/INSTALL-01-1.json" '.authorizationReference = ""'
mutate_and_reject wrong-candidate "${fixture_root}/results/BOOT-01-1.json" '.candidate.build = "4"'
mutate_and_reject short-long-run "${fixture_root}/results/LONG-01-1.json" '.observationSeconds = 10799'
mutate_and_reject missing-artifact "${fixture_root}/results/CONFLICT-01-1.json" '.artifacts = ["artifacts/missing.txt"]'

cp "${fixture_root}/results/RADIO-03-1.json" "${fixture_root}/results/duplicate.json"
expect_rejected duplicate-result
rm "${fixture_root}/results/duplicate.json"

mv "${fixture_root}/results/LIFE-09-3.json" "${fixture_root}/missing-required.json"
expect_rejected missing-required
mv "${fixture_root}/missing-required.json" "${fixture_root}/results/LIFE-09-3.json"

echo 'Physical matrix completeness, candidate binding, authorization, privacy and failure guards passed.'
