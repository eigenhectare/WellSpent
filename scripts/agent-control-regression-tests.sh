#!/bin/bash
set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentAgentControlTests.XXXXXX")"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
fixture_commit="$(git -C "${repository_root}" rev-parse --verify HEAD^{commit})" \
    || { echo 'Agent control regression failed: cannot resolve fixture commit' >&2; exit 1; }
readonly fixture_commit
fixture_tree="$(git -C "${repository_root}" rev-parse --verify HEAD^{tree})" \
    || { echo 'Agent control regression failed: cannot resolve fixture tree' >&2; exit 1; }
readonly fixture_tree
trap 'rm -rf "${fixture_root}"' EXIT
fail() { echo "Agent control regression failed: $1" >&2; exit 1; }
expect_rejected() {
    local label="$1" task_dir="$2" evidence_dir="$3"
    if bash "${script_directory}/agent-control-check.sh" "${task_dir}" "${evidence_dir}" \
        > "${fixture_root}/${label}.log" 2>&1; then
        sed -n '1,120p' "${fixture_root}/${label}.log" >&2
        fail "validator falsely accepted ${label}"
    fi
}

make_case() {
    local label="$1"
    mkdir -p "${fixture_root}/${label}/tasks" "${fixture_root}/${label}/evidence/TST-001"
    jq -n --arg commit "${fixture_commit}" --arg tree "${fixture_tree}" '{
      schemaVersion:1, taskId:"TST-001", title:"Validate agent contracts", type:"chore",
      status:"done", risk:"low", outcome:"The agent control validator rejects unsafe state.",
      assignment:{role:"implementer",id:"fixture-implementer"},
      base:{branch:"main",commit:$commit},
      dependsOn:[], scope:{included:["Agent contract validation"],excluded:[]},
      writeScope:{paths:["README.md"],resources:[]},
      acceptanceCriteria:[{id:"AC-1",statement:"The canonical validator passes the valid fixture."}],
      evidenceRequirements:[{id:"ER-1",criterionIds:["AC-1"],evidenceClass:"source",gateIds:["agent-control"],candidateBound:true}],
      authorityRequirements:["repository-write"], legacyRefs:[], blocker:null,
      result:{commit:$commit,tree:$tree}
    }' > "${fixture_root}/${label}/tasks/TST-001.json"
    jq -n --arg commit "${fixture_commit}" --arg tree "${fixture_tree}" '{
      schemaVersion:1, receiptId:"RCP-001", taskId:"TST-001", requirementId:"ER-1",
      evidenceClass:"source", result:"passed", producerRole:"verifier", producerId:"fixture-verifier",
      observedAt:"2026-09-05T20:00:00-04:00",
      source:{commit:$commit,tree:$tree,clean:true,version:null,build:null},
      gate:{id:"agent-control",exitCode:0}, claims:["The valid fixture passed."],
      artifacts:[{kind:"repository",locator:"README.md",sha256:null}], limitations:[],
      authorityReference:{
        kind:"user-message",reference:"Fixture repository-write authority",
        confirmedBy:"fixture owner",confirmedAt:"2026-09-05",authorityIds:["repository-write"]
      },
      publicReleaseApproved:false
    }' > "${fixture_root}/${label}/evidence/TST-001/RCP-001.json"
}

make_case valid
bash "${script_directory}/agent-control-check.sh" "${fixture_root}/valid/tasks" "${fixture_root}/valid/evidence" >/dev/null

make_case unsafe-path
jq '.writeScope.paths = ["../escape"]' "${fixture_root}/unsafe-path/tasks/TST-001.json" \
    > "${fixture_root}/unsafe-path/tasks/rejected.json"
mv "${fixture_root}/unsafe-path/tasks/rejected.json" "${fixture_root}/unsafe-path/tasks/TST-001.json"
expect_rejected unsafe-path "${fixture_root}/unsafe-path/tasks" "${fixture_root}/unsafe-path/evidence"

make_case unknown-gate
jq '.evidenceRequirements[0].gateIds = ["missing-gate"]' "${fixture_root}/unknown-gate/tasks/TST-001.json" \
    > "${fixture_root}/unknown-gate/tasks/rejected.json"
mv "${fixture_root}/unknown-gate/tasks/rejected.json" "${fixture_root}/unknown-gate/tasks/TST-001.json"
expect_rejected unknown-gate "${fixture_root}/unknown-gate/tasks" "${fixture_root}/unknown-gate/evidence"

make_case missing-gate-resource
jq '.evidenceRequirements[0].gateIds = ["release-source-receipt"]' \
    "${fixture_root}/missing-gate-resource/tasks/TST-001.json" \
    > "${fixture_root}/missing-gate-resource/tasks/rejected.json"
mv "${fixture_root}/missing-gate-resource/tasks/rejected.json" \
    "${fixture_root}/missing-gate-resource/tasks/TST-001.json"
jq '.gate.id = "release-source-receipt"' \
    "${fixture_root}/missing-gate-resource/evidence/TST-001/RCP-001.json" \
    > "${fixture_root}/missing-gate-resource/evidence/TST-001/rejected.json"
mv "${fixture_root}/missing-gate-resource/evidence/TST-001/rejected.json" \
    "${fixture_root}/missing-gate-resource/evidence/TST-001/RCP-001.json"
expect_rejected missing-gate-resource "${fixture_root}/missing-gate-resource/tasks" \
    "${fixture_root}/missing-gate-resource/evidence"

make_case missing-protected-resource
jq '.writeScope.paths = ["project.yml"]' \
    "${fixture_root}/missing-protected-resource/tasks/TST-001.json" \
    > "${fixture_root}/missing-protected-resource/tasks/rejected.json"
mv "${fixture_root}/missing-protected-resource/tasks/rejected.json" \
    "${fixture_root}/missing-protected-resource/tasks/TST-001.json"
expect_rejected missing-protected-resource "${fixture_root}/missing-protected-resource/tasks" \
    "${fixture_root}/missing-protected-resource/evidence"

make_case missing-evidence
rm "${fixture_root}/missing-evidence/evidence/TST-001/RCP-001.json"
expect_rejected missing-evidence "${fixture_root}/missing-evidence/tasks" "${fixture_root}/missing-evidence/evidence"

make_case fabricated-git-identity
jq '.result = {
      commit:"ffffffffffffffffffffffffffffffffffffffff",
      tree:"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    }' "${fixture_root}/fabricated-git-identity/tasks/TST-001.json" \
    > "${fixture_root}/fabricated-git-identity/tasks/rejected.json"
mv "${fixture_root}/fabricated-git-identity/tasks/rejected.json" \
    "${fixture_root}/fabricated-git-identity/tasks/TST-001.json"
jq '.source = {
      commit:"ffffffffffffffffffffffffffffffffffffffff",
      tree:"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      clean:true,version:null,build:null
    }' "${fixture_root}/fabricated-git-identity/evidence/TST-001/RCP-001.json" \
    > "${fixture_root}/fabricated-git-identity/evidence/TST-001/rejected.json"
mv "${fixture_root}/fabricated-git-identity/evidence/TST-001/rejected.json" \
    "${fixture_root}/fabricated-git-identity/evidence/TST-001/RCP-001.json"
expect_rejected fabricated-git-identity "${fixture_root}/fabricated-git-identity/tasks" \
    "${fixture_root}/fabricated-git-identity/evidence"

make_case missing-authority-evidence
jq '.authorityRequirements = ["app-store-submit", "repository-write"]' \
    "${fixture_root}/missing-authority-evidence/tasks/TST-001.json" \
    > "${fixture_root}/missing-authority-evidence/tasks/rejected.json"
mv "${fixture_root}/missing-authority-evidence/tasks/rejected.json" \
    "${fixture_root}/missing-authority-evidence/tasks/TST-001.json"
expect_rejected missing-authority-evidence "${fixture_root}/missing-authority-evidence/tasks" \
    "${fixture_root}/missing-authority-evidence/evidence"

make_case wrong-class
jq '.evidenceClass = "unit"' "${fixture_root}/wrong-class/evidence/TST-001/RCP-001.json" \
    > "${fixture_root}/wrong-class/evidence/TST-001/rejected.json"
mv "${fixture_root}/wrong-class/evidence/TST-001/rejected.json" \
    "${fixture_root}/wrong-class/evidence/TST-001/RCP-001.json"
expect_rejected wrong-class "${fixture_root}/wrong-class/tasks" "${fixture_root}/wrong-class/evidence"

make_case self-verification
jq '.producerId = "fixture-implementer"' \
    "${fixture_root}/self-verification/evidence/TST-001/RCP-001.json" \
    > "${fixture_root}/self-verification/evidence/TST-001/rejected.json"
mv "${fixture_root}/self-verification/evidence/TST-001/rejected.json" \
    "${fixture_root}/self-verification/evidence/TST-001/RCP-001.json"
expect_rejected self-verification "${fixture_root}/self-verification/tasks" \
    "${fixture_root}/self-verification/evidence"

make_case mismatched-gate-class
jq '.evidenceRequirements[0].evidenceClass = "unit"' \
    "${fixture_root}/mismatched-gate-class/tasks/TST-001.json" \
    > "${fixture_root}/mismatched-gate-class/tasks/rejected.json"
mv "${fixture_root}/mismatched-gate-class/tasks/rejected.json" \
    "${fixture_root}/mismatched-gate-class/tasks/TST-001.json"
jq '.evidenceClass = "unit"' \
    "${fixture_root}/mismatched-gate-class/evidence/TST-001/RCP-001.json" \
    > "${fixture_root}/mismatched-gate-class/evidence/TST-001/rejected.json"
mv "${fixture_root}/mismatched-gate-class/evidence/TST-001/rejected.json" \
    "${fixture_root}/mismatched-gate-class/evidence/TST-001/RCP-001.json"
expect_rejected mismatched-gate-class "${fixture_root}/mismatched-gate-class/tasks" \
    "${fixture_root}/mismatched-gate-class/evidence"

make_case passed-without-exit
jq '.gate.exitCode = null' "${fixture_root}/passed-without-exit/evidence/TST-001/RCP-001.json" \
    > "${fixture_root}/passed-without-exit/evidence/TST-001/rejected.json"
mv "${fixture_root}/passed-without-exit/evidence/TST-001/rejected.json" \
    "${fixture_root}/passed-without-exit/evidence/TST-001/RCP-001.json"
expect_rejected passed-without-exit "${fixture_root}/passed-without-exit/tasks" \
    "${fixture_root}/passed-without-exit/evidence"

make_case false-release-approval
jq '.publicReleaseApproved = true' "${fixture_root}/false-release-approval/evidence/TST-001/RCP-001.json" \
    > "${fixture_root}/false-release-approval/evidence/TST-001/rejected.json"
mv "${fixture_root}/false-release-approval/evidence/TST-001/rejected.json" \
    "${fixture_root}/false-release-approval/evidence/TST-001/RCP-001.json"
expect_rejected false-release-approval "${fixture_root}/false-release-approval/tasks" \
    "${fixture_root}/false-release-approval/evidence"

make_case public-release-without-authority
jq '.evidenceRequirements[0].evidenceClass = "human-approval"
    | .evidenceRequirements[0].gateIds = ["owner-attestation"]' \
    "${fixture_root}/public-release-without-authority/tasks/TST-001.json" \
    > "${fixture_root}/public-release-without-authority/tasks/rejected.json"
mv "${fixture_root}/public-release-without-authority/tasks/rejected.json" \
    "${fixture_root}/public-release-without-authority/tasks/TST-001.json"
jq '.evidenceClass = "human-approval"
    | .producerRole = "owner"
    | .producerId = "fixture-owner"
    | .gate = {id:"owner-attestation",exitCode:null}
    | .authorityReference = {
        kind:"user-message",reference:"Fixture authority",confirmedBy:"fixture owner",confirmedAt:"2026-09-05",
        authorityIds:["repository-write"]
      }
    | .publicReleaseApproved = true' \
    "${fixture_root}/public-release-without-authority/evidence/TST-001/RCP-001.json" \
    > "${fixture_root}/public-release-without-authority/evidence/TST-001/rejected.json"
mv "${fixture_root}/public-release-without-authority/evidence/TST-001/rejected.json" \
    "${fixture_root}/public-release-without-authority/evidence/TST-001/RCP-001.json"
expect_rejected public-release-without-authority \
    "${fixture_root}/public-release-without-authority/tasks" \
    "${fixture_root}/public-release-without-authority/evidence"

make_case high-assurance-without-artifact
jq '.writeScope.resources = ["signing-archive", "version-build"]
    | .evidenceRequirements[0].evidenceClass = "signed-package"
    | .evidenceRequirements[0].gateIds = ["signed-archive-inspection"]' \
    "${fixture_root}/high-assurance-without-artifact/tasks/TST-001.json" \
    > "${fixture_root}/high-assurance-without-artifact/tasks/rejected.json"
mv "${fixture_root}/high-assurance-without-artifact/tasks/rejected.json" \
    "${fixture_root}/high-assurance-without-artifact/tasks/TST-001.json"
jq '.evidenceClass = "signed-package"
    | .gate.id = "signed-archive-inspection"
    | .artifacts = []' \
    "${fixture_root}/high-assurance-without-artifact/evidence/TST-001/RCP-001.json" \
    > "${fixture_root}/high-assurance-without-artifact/evidence/TST-001/rejected.json"
mv "${fixture_root}/high-assurance-without-artifact/evidence/TST-001/rejected.json" \
    "${fixture_root}/high-assurance-without-artifact/evidence/TST-001/RCP-001.json"
expect_rejected high-assurance-without-artifact \
    "${fixture_root}/high-assurance-without-artifact/tasks" \
    "${fixture_root}/high-assurance-without-artifact/evidence"

make_case blocked-without-resume
jq '.status = "blocked" | .result = null' "${fixture_root}/blocked-without-resume/tasks/TST-001.json" \
    > "${fixture_root}/blocked-without-resume/tasks/rejected.json"
mv "${fixture_root}/blocked-without-resume/tasks/rejected.json" \
    "${fixture_root}/blocked-without-resume/tasks/TST-001.json"
expect_rejected blocked-without-resume "${fixture_root}/blocked-without-resume/tasks" \
    "${fixture_root}/blocked-without-resume/evidence"

make_case cycle
rm "${fixture_root}/cycle/evidence/TST-001/RCP-001.json"
jq '.status = "backlog" | .result = null | .dependsOn = ["TST-002"]' \
    "${fixture_root}/cycle/tasks/TST-001.json" > "${fixture_root}/cycle/tasks/first.json"
mv "${fixture_root}/cycle/tasks/first.json" "${fixture_root}/cycle/tasks/TST-001.json"
jq '.taskId = "TST-002" | .title = "Second cyclic task" | .dependsOn = ["TST-001"]' \
    "${fixture_root}/cycle/tasks/TST-001.json" > "${fixture_root}/cycle/tasks/TST-002.json"
expect_rejected cycle "${fixture_root}/cycle/tasks" "${fixture_root}/cycle/evidence"

mkdir -p "${fixture_root}/malformed/tasks" "${fixture_root}/malformed/evidence"
printf '{not-json\n' > "${fixture_root}/malformed/tasks/TST-001.json"
expect_rejected malformed "${fixture_root}/malformed/tasks" "${fixture_root}/malformed/evidence"

readonly scope_repository="${fixture_root}/scope-repository"
mkdir -p "${scope_repository}"
git -C "${scope_repository}" init -q
printf 'base\n' > "${scope_repository}/base.txt"
git -C "${scope_repository}" add base.txt
git -C "${scope_repository}" -c user.name='Agent Contract Fixture' \
    -c user.email='fixture.invalid@example.com' -c commit.gpgSign=false \
    commit -q -m 'base fixture'
scope_base="$(git -C "${scope_repository}" rev-parse --verify HEAD^{commit})" \
    || fail 'cannot resolve scope-test base'
readonly scope_base
printf 'allowed\n' > "${scope_repository}/allowed.txt"
git -C "${scope_repository}" add allowed.txt
git -C "${scope_repository}" -c user.name='Agent Contract Fixture' \
    -c user.email='fixture.invalid@example.com' -c commit.gpgSign=false \
    commit -q -m 'scoped fixture'
scope_head="$(git -C "${scope_repository}" rev-parse --verify HEAD^{commit})" \
    || fail 'cannot resolve scope-test head'
readonly scope_head
jq -n --arg base "${scope_base}" --arg head "${scope_head}" \
    '{taskId:"TST-SCOPE",base:{commit:$base},result:{commit:$head},writeScope:{paths:["allowed.txt"]}}' \
    > "${fixture_root}/scope-valid.json"
AGENT_SCOPE_REPOSITORY_ROOT="${scope_repository}" \
    bash "${script_directory}/agent-scope-check.sh" "${fixture_root}/scope-valid.json" \
    "${scope_base}" "${scope_head}" >/dev/null
jq '.writeScope.paths = ["path-that-cannot-match"]' "${fixture_root}/scope-valid.json" \
    > "${fixture_root}/scope-invalid.json"
if AGENT_SCOPE_REPOSITORY_ROOT="${scope_repository}" \
    bash "${script_directory}/agent-scope-check.sh" "${fixture_root}/scope-invalid.json" \
    "${scope_base}" "${scope_head}" > "${fixture_root}/scope-invalid.log" 2>&1; then
    sed -n '1,120p' "${fixture_root}/scope-invalid.log" >&2
    fail 'scope validator falsely accepted an out-of-scope diff'
fi

readonly lock_root="${fixture_root}/locks/.agent-locks"
mkdir -p "$(dirname "${lock_root}")"
jq -n '{taskId:"TST-LOCK-A",writeScope:{resources:["ios-simulator"]}}' \
    > "${fixture_root}/lock-a.json"
jq -n '{taskId:"TST-LOCK-B",writeScope:{resources:["ios-simulator"]}}' \
    > "${fixture_root}/lock-b.json"
AGENT_RESOURCE_LOCK_ROOT="${lock_root}" \
    bash "${script_directory}/agent-resource-lock.sh" acquire "${fixture_root}/lock-a.json" >/dev/null
if AGENT_RESOURCE_LOCK_ROOT="${lock_root}" \
    bash "${script_directory}/agent-resource-lock.sh" acquire "${fixture_root}/lock-b.json" \
    > "${fixture_root}/lock-conflict.log" 2>&1; then
    sed -n '1,120p' "${fixture_root}/lock-conflict.log" >&2
    fail 'resource lock admitted two owners'
fi
AGENT_RESOURCE_LOCK_ROOT="${lock_root}" \
    bash "${script_directory}/agent-resource-lock.sh" status \
    | jq -e 'length == 1 and .[0].taskId == "TST-LOCK-A"' >/dev/null \
    || fail 'resource lock status lost its owner'
AGENT_RESOURCE_LOCK_ROOT="${lock_root}" \
    bash "${script_directory}/agent-resource-lock.sh" release "${fixture_root}/lock-a.json" >/dev/null
AGENT_RESOURCE_LOCK_ROOT="${lock_root}" \
    bash "${script_directory}/agent-resource-lock.sh" acquire "${fixture_root}/lock-b.json" >/dev/null
AGENT_RESOURCE_LOCK_ROOT="${lock_root}" \
    bash "${script_directory}/agent-resource-lock.sh" release "${fixture_root}/lock-b.json" >/dev/null
AGENT_RESOURCE_LOCK_ROOT="${lock_root}" \
    bash "${script_directory}/agent-resource-lock.sh" status \
    | jq -e 'length == 0' >/dev/null || fail 'resource locks were not released'

echo 'Agent control positive fixture and negative dependency, scope, evidence and authority checks passed.'
