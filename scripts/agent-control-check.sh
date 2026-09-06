#!/bin/bash
set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly task_directory="${1:-${repository_root}/AgentControl/tasks}"
readonly evidence_directory="${2:-${repository_root}/AgentControl/evidence}"
readonly gate_file="${repository_root}/AgentControl/control/gates.json"
readonly resource_file="${repository_root}/AgentControl/control/resources.json"
readonly schema_directory="${repository_root}/AgentControl/schema"
fail() { echo "Agent control validation failed: $1" >&2; exit 1; }
verify_commit_tree() {
    local commit="$1" expected_tree="$2" label="$3" actual_tree
    git -C "${repository_root}" cat-file -e "${commit}^{commit}" 2>/dev/null \
        || fail "missing Git commit for ${label}: ${commit}"
    actual_tree="$(git -C "${repository_root}" rev-parse --verify "${commit}^{tree}")" \
        || fail "cannot resolve Git tree for ${label}: ${commit}"
    [[ "${actual_tree}" == "${expected_tree}" ]] \
        || fail "Git tree mismatch for ${label}: expected ${expected_tree}, got ${actual_tree}"
}

for dependency in jq git; do
    command -v "${dependency}" >/dev/null || fail "missing dependency: ${dependency}"
done
for required in "${gate_file}" "${resource_file}" \
    "${schema_directory}/task-v1.jq" "${schema_directory}/evidence-v1.jq"; do
    [[ -f "${required}" && ! -L "${required}" ]] || fail "missing or unsafe control file: ${required}"
done
for directory in "${task_directory}" "${evidence_directory}"; do
    [[ -d "${directory}" && ! -L "${directory}" ]] || fail "missing or unsafe record directory: ${directory}"
    [[ -z "$(find "${directory}" -type l -print -quit)" ]] || fail "record directories cannot contain symlinks"
    [[ -z "$(find "${directory}" -type f ! -name '*.json' -print -quit)" ]] \
        || fail "record directories may contain only JSON files"
done

jq -e --slurpfile resources "${resource_file}" '
  .schemaVersion == 1
  and (.gates | type == "array" and length > 0)
  and (([.gates[].id] | unique | length) == (.gates | length))
  and all(.gates[];
    (type == "object")
    and ((keys_unsorted - ["id", "description", "tier", "evidenceClass", "argv", "arguments", "resources"]) | length == 0)
    and (["id", "description", "tier", "evidenceClass", "argv", "arguments", "resources"] - keys_unsorted | length == 0)
    and (.id | type == "string" and test("^[a-z][a-z0-9-]+$"))
    and (.description | type == "string" and length > 0)
    and (.tier | IN("focused", "impacted", "full"))
    and (.evidenceClass | IN("source", "unit", "ui-simulator", "physical-device", "signed-package", "external-service", "human-approval"))
    and (.argv | type == "array" and all(.[]; type == "string" and length > 0))
    and ((.id == "owner-attestation" and (.argv | length) == 0) or (.id != "owner-attestation" and (.argv | length) > 0))
    and (.arguments | type == "array" and all(.[]; type == "string" and length > 0) and ((unique | length) == length))
    and (.resources | type == "array" and all(.[]; type == "string") and ((unique | length) == length))
    and all(.resources[]; . as $id | [$resources[0].resources[].id] | index($id) != null)
  )
' "${gate_file}" >/dev/null || fail 'invalid gate registry'

jq -e '
  .schemaVersion == 1
  and (.resources | type == "array" and length > 0)
  and (([.resources[].id] | unique | length) == (.resources | length))
  and all(.resources[];
    (type == "object")
    and ((keys_unsorted - ["id", "mode", "description", "paths"]) | length == 0)
    and (["id", "mode", "description", "paths"] - keys_unsorted | length == 0)
    and (.id | type == "string" and test("^[a-z][a-z0-9-]+$"))
    and (.mode == "exclusive")
    and (.description | type == "string" and length > 0)
    and (.paths | type == "array" and all(.[];
      type == "string" and length > 0 and (startswith("/") | not)
      and (test("(^|/)\\.\\.(/|$)") | not)))
  )
' "${resource_file}" >/dev/null || fail 'invalid resource registry'

readonly temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentAgentControl.XXXXXX")"
trap 'rm -rf "${temporary_root}"' EXIT

task_files=()
task_file_count=0
while IFS= read -r path; do
    task_files+=("${path}")
    task_file_count=$((task_file_count + 1))
done < <(find "${task_directory}" -type f -name '*.json' | LC_ALL=C sort)
evidence_files=()
evidence_file_count=0
while IFS= read -r path; do
    evidence_files+=("${path}")
    evidence_file_count=$((evidence_file_count + 1))
done < <(find "${evidence_directory}" -type f -name '*.json' | LC_ALL=C sort)

if [[ ${task_file_count} -eq 0 ]]; then printf '[]\n' > "${temporary_root}/tasks.json"
else jq -s '.' "${task_files[@]}" > "${temporary_root}/tasks.json" || fail 'task JSON parse failure'; fi
if [[ ${evidence_file_count} -eq 0 ]]; then printf '[]\n' > "${temporary_root}/evidence.json"
else jq -s '.' "${evidence_files[@]}" > "${temporary_root}/evidence.json" || fail 'evidence JSON parse failure'; fi

if [[ ${task_file_count} -gt 0 ]]; then
    for task_file in "${task_files[@]}"; do
        task_id="$(jq -er '.taskId' "${task_file}")" || fail "missing taskId: ${task_file}"
        [[ "$(basename "${task_file}" .json)" == "${task_id}" ]] || fail "task filename must equal taskId: ${task_file}"
        jq -e -L "${schema_directory}" --slurpfile gates "${gate_file}" --slurpfile resources "${resource_file}" '
          include "task-v1";
          valid_task($gates[0].gates; $resources[0].resources)
        ' "${task_file}" >/dev/null || fail "task schema rejected: ${task_file}"
        base_commit="$(jq -er '.base.commit' "${task_file}")"
        git -C "${repository_root}" cat-file -e "${base_commit}^{commit}" 2>/dev/null \
            || fail "missing task base commit: ${task_id} ${base_commit}"
        result_commit="$(jq -r '.result.commit // empty' "${task_file}")"
        if [[ -n "${result_commit}" ]]; then
            result_tree="$(jq -er '.result.tree' "${task_file}")"
            verify_commit_tree "${result_commit}" "${result_tree}" "task ${task_id} result"
            git -C "${repository_root}" merge-base --is-ancestor "${base_commit}" "${result_commit}" \
                || fail "task base is not an ancestor of its result: ${task_id}"
        fi
        if [[ "$(jq -r '.status' "${task_file}")" == "done" ]]; then
            git -C "${repository_root}" merge-base --is-ancestor "${result_commit}" HEAD \
                || fail "done task result is not integrated into HEAD: ${task_id}"
        fi
    done
fi

if [[ ${evidence_file_count} -gt 0 ]]; then
    for evidence_file in "${evidence_files[@]}"; do
        receipt_id="$(jq -er '.receiptId' "${evidence_file}")" || fail "missing receiptId: ${evidence_file}"
        task_id="$(jq -er '.taskId' "${evidence_file}")" || fail "missing evidence taskId: ${evidence_file}"
        [[ "$(basename "${evidence_file}" .json)" == "${receipt_id}" ]] || fail "evidence filename must equal receiptId: ${evidence_file}"
        [[ "$(basename "$(dirname "${evidence_file}")")" == "${task_id}" ]] || fail "evidence parent must equal taskId: ${evidence_file}"
        jq -e -L "${schema_directory}" --slurpfile gates "${gate_file}" '
          include "evidence-v1";
          valid_evidence([$gates[0].gates[].id])
        ' "${evidence_file}" >/dev/null || fail "evidence schema rejected: ${evidence_file}"
        source_commit="$(jq -er '.source.commit' "${evidence_file}")"
        source_tree="$(jq -er '.source.tree' "${evidence_file}")"
        verify_commit_tree "${source_commit}" "${source_tree}" "evidence ${receipt_id} source"
        if [[ "$(jq -r '.result == "passed" and .gate.id == "release-tag-binding"' "${evidence_file}")" == "true" ]]; then
            tag_ref="$(jq -er '[.artifacts[] | select(.kind == "repository" and (.locator | startswith("refs/tags/"))) | .locator][0]' "${evidence_file}")" \
                || fail "passed release-tag receipt has no repository tag ref: ${receipt_id}"
            bash "${script_directory}/agent-release-tag-check.sh" \
                "${task_directory}/${task_id}.json" "${tag_ref#refs/tags/}" >/dev/null \
                || fail "release tag no longer matches its task: ${receipt_id}"
        fi
    done
fi

jq -ne --slurpfile tasks "${temporary_root}/tasks.json" --slurpfile evidence "${temporary_root}/evidence.json" '
  ($tasks[0]) as $taskList | ($evidence[0]) as $evidenceList |
  def task($id): [$taskList[] | select(.taskId == $id)][0];
  def requirement($taskId; $requirementId):
    [task($taskId).evidenceRequirements[] | select(.id == $requirementId)][0];
  def cyclic($id; $path):
    if ($path | index($id)) != null then true
    elif task($id) == null then false
    else any(task($id).dependsOn[]; cyclic(.; $path + [$id]))
    end;

  ([ $taskList[].taskId ] | unique | length) == ($taskList | length)
  and ([ $evidenceList[].receiptId ] | unique | length) == ($evidenceList | length)
  and all($taskList[]; . as $task |
    all($task.dependsOn[]; . as $dependency | [$taskList[].taskId] | index($dependency) != null)
    and (if ($task.status | IN("ready", "in_progress", "in_review", "done")) then
           all($task.dependsOn[]; task(.).status == "done")
         else true end)
  )
  and all($taskList[].taskId; cyclic(.; []) | not)
  and all($evidenceList[]; . as $receipt |
    ([ $taskList[] | select(.taskId == $receipt.taskId) ] | length) == 1
    and ([ task($receipt.taskId).evidenceRequirements[] | select(.id == $receipt.requirementId) ] | length) == 1
    and ($receipt.evidenceClass == requirement($receipt.taskId; $receipt.requirementId).evidenceClass)
    and (requirement($receipt.taskId; $receipt.requirementId).gateIds | index($receipt.gate.id) != null)
    and (if $receipt.result == "passed" then $receipt.producerRole != "implementer" else true end)
    and (if $receipt.result == "passed" and requirement($receipt.taskId; $receipt.requirementId).candidateBound then
           $receipt.source.commit == task($receipt.taskId).result.commit
           and $receipt.source.tree == task($receipt.taskId).result.tree
         else true end)
    and (if ($receipt.evidenceClass | IN("physical-device", "signed-package", "external-service", "human-approval"))
            and $receipt.result == "passed" then
           all($receipt.artifacts[]; .kind != "local-diagnostic")
         else true end)
    and (if $receipt.publicReleaseApproved then
           (task($receipt.taskId).authorityRequirements | index("public-release")) != null
           and ($receipt.authorityReference.authorityIds | index("public-release")) != null
         else true end)
  )
  and all($taskList[]; . as $task |
    if $task.status == "done" then
      all($task.acceptanceCriteria[].id; . as $criterion |
        any($task.evidenceRequirements[]; .criterionIds | index($criterion) != null))
      and all($task.evidenceRequirements[]; . as $requirement |
        any($evidenceList[];
          .taskId == $task.taskId and .requirementId == $requirement.id and .result == "passed")
        and (if $requirement.evidenceClass == "human-approval" then true
             else any($evidenceList[];
               .taskId == $task.taskId
               and .requirementId == $requirement.id
               and .result == "passed"
               and .producerRole == "verifier"
               and ($task.assignment == null or .producerId != $task.assignment.id))
             end))
      and all($task.authorityRequirements[]; . as $authority |
        any($evidenceList[];
          .taskId == $task.taskId
          and .result == "passed"
          and .authorityReference != null
          and (.authorityReference.authorityIds | index($authority)) != null))
    else true end
  )
' >/dev/null || fail 'cross-record dependency or evidence validation failed'

echo "Agent control validation passed: ${task_file_count} task(s), ${evidence_file_count} evidence receipt(s)."
