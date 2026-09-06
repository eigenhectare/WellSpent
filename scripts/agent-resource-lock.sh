#!/bin/bash
set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly resource_file="${repository_root}/AgentControl/control/resources.json"
readonly action="${1:?usage: agent-resource-lock.sh acquire|release|status [TASK_JSON]}"
readonly task_file="${2:-}"
fail() { echo "Agent resource lock failed: $1" >&2; exit 1; }

command -v jq >/dev/null || fail 'missing dependency: jq'
[[ -f "${resource_file}" && ! -L "${resource_file}" ]] || fail 'missing resource registry'

if [[ -n "${AGENT_RESOURCE_LOCK_ROOT:-}" ]]; then
    [[ "${AGENT_RESOURCE_LOCK_ROOT}" == /* \
        && "$(basename "${AGENT_RESOURCE_LOCK_ROOT}")" == ".agent-locks" ]] \
        || fail 'lock-root override must be an absolute .agent-locks directory'
    lock_root="${AGENT_RESOURCE_LOCK_ROOT}"
else
    git_common_directory="$(git -C "${repository_root}" rev-parse --git-common-dir)" \
        || fail 'cannot resolve Git common directory'
    if [[ "${git_common_directory}" != /* ]]; then
        git_common_directory="${repository_root}/${git_common_directory}"
    fi
    git_common_directory="$(cd "${git_common_directory}" && pwd -P)" \
        || fail 'cannot canonicalize Git common directory'
    lock_root="$(dirname "${git_common_directory}")/.agent-locks"
fi
readonly lock_root
[[ ! -L "${lock_root}" ]] || fail 'lock root cannot be a symlink'

if [[ "${action}" == "status" ]]; then
    [[ -z "${task_file}" ]] || fail 'status does not accept a task file'
    if [[ ! -d "${lock_root}" ]]; then
        printf '[]\n'
        exit 0
    fi
    status_files=()
    status_count=0
    while IFS= read -r owner_file; do
        status_files+=("${owner_file}")
        status_count=$((status_count + 1))
    done < <(find "${lock_root}" -mindepth 2 -maxdepth 2 -type f -name owner.json | LC_ALL=C sort)
    if [[ ${status_count} -eq 0 ]]; then printf '[]\n'
    else jq -s '.' "${status_files[@]}"; fi
    exit 0
fi

[[ "${action}" == "acquire" || "${action}" == "release" ]] \
    || fail 'action must be acquire, release, or status'
[[ -f "${task_file}" && ! -L "${task_file}" ]] || fail 'task file must be a regular JSON file'
task_id="$(jq -er '.taskId' "${task_file}")" || fail 'task has no taskId'
readonly task_id
[[ "${task_id}" =~ ^[A-Z][A-Z0-9]*(-[A-Z0-9]+)+$ ]] || fail 'taskId is invalid'
jq -e --slurpfile registry "${resource_file}" '
  .writeScope.resources as $resources
  | ($resources | type == "array" and all(.[]; type == "string"))
    and (($resources | unique | length) == ($resources | length))
    and ($resources == ($resources | sort))
    and all($resources[]; . as $id | [$registry[0].resources[].id] | index($id) != null)
' "${task_file}" >/dev/null || fail 'task resources are invalid, duplicated, unsorted, or unknown'

resources=()
resource_count=0
while IFS= read -r resource; do
    resources+=("${resource}")
    resource_count=$((resource_count + 1))
done < <(jq -r '.writeScope.resources[]' "${task_file}")

if [[ "${action}" == "acquire" ]]; then
    mkdir -p "${lock_root}"
    [[ -d "${lock_root}" && ! -L "${lock_root}" ]] || fail 'cannot create a safe lock root'
    acquired=()
    acquired_count=0
    rollback_acquired() {
        if [[ ${acquired_count} -gt 0 ]]; then
            for acquired_resource in "${acquired[@]}"; do
                rm -f "${lock_root}/${acquired_resource}.lock/owner.json"
                rmdir "${lock_root}/${acquired_resource}.lock" 2>/dev/null || true
            done
        fi
    }
    acquire_complete=0
    trap 'if [[ ${acquire_complete} -ne 1 ]]; then rollback_acquired; fi' EXIT
    if [[ ${resource_count} -gt 0 ]]; then
        for resource in "${resources[@]}"; do
            lock_directory="${lock_root}/${resource}.lock"
            if ! mkdir "${lock_directory}" 2>/dev/null; then
                owner="unknown"
                if [[ -f "${lock_directory}/owner.json" ]]; then
                    owner="$(jq -r '.taskId // "unknown"' "${lock_directory}/owner.json" 2>/dev/null || printf 'unknown')"
                fi
                fail "resource ${resource} is already locked by ${owner}"
            fi
            if ! jq -n --arg taskId "${task_id}" --arg resourceId "${resource}" \
                --arg acquiredAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --argjson processId "$$" \
                '{schemaVersion:1,taskId:$taskId,resourceId:$resourceId,
                  acquiredAt:$acquiredAt,processId:$processId}' \
                > "${lock_directory}/owner.json"; then
                rm -f "${lock_directory}/owner.json"
                rmdir "${lock_directory}" 2>/dev/null || true
                fail "cannot write owner record for ${resource}"
            fi
            acquired+=("${resource}")
            acquired_count=$((acquired_count + 1))
        done
    fi
    acquire_complete=1
    trap - EXIT
    echo "Agent resources acquired for ${task_id}: ${resource_count}"
    exit 0
fi

if [[ ${resource_count} -gt 0 ]]; then
    for resource in "${resources[@]}"; do
        lock_directory="${lock_root}/${resource}.lock"
        [[ -e "${lock_directory}" ]] || continue
        [[ -d "${lock_directory}" && ! -L "${lock_directory}" \
            && -f "${lock_directory}/owner.json" && ! -L "${lock_directory}/owner.json" ]] \
            || fail "unsafe or incomplete lock for ${resource}"
        owner="$(jq -er '.taskId' "${lock_directory}/owner.json")" \
            || fail "invalid owner record for ${resource}"
        [[ "${owner}" == "${task_id}" ]] \
            || fail "resource ${resource} is owned by ${owner}, not ${task_id}"
        rm -f "${lock_directory}/owner.json"
        rmdir "${lock_directory}" || fail "lock directory for ${resource} contains unexpected files"
    done
fi
echo "Agent resources released for ${task_id}: ${resource_count}"
