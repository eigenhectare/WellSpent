#!/bin/bash
set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly default_repository_root="$(cd "${script_directory}/.." && pwd)"
repository_root="$(git -C "${AGENT_SCOPE_REPOSITORY_ROOT:-${default_repository_root}}" \
    rev-parse --show-toplevel)" || { echo 'Agent scope validation failed: invalid repository root' >&2; exit 1; }
readonly repository_root
readonly task_file="${1:?usage: agent-scope-check.sh TASK_JSON BASE_COMMIT HEAD_COMMIT}"
readonly base_input="${2:?base commit required}"
readonly head_input="${3:?head commit required}"
fail() { echo "Agent scope validation failed: $1" >&2; exit 1; }

[[ -f "${task_file}" && ! -L "${task_file}" ]] || fail 'task file must be a regular JSON file'
base_commit="$(git -C "${repository_root}" rev-parse --verify "${base_input}^{commit}")" || fail 'invalid base commit'
readonly base_commit
head_commit="$(git -C "${repository_root}" rev-parse --verify "${head_input}^{commit}")" || fail 'invalid head commit'
readonly head_commit
task_base="$(jq -er '.base.commit' "${task_file}")" || fail 'task has no base commit'
readonly task_base
[[ "${task_base}" == "${base_commit}" ]] || fail 'provided base does not match the task contract'
task_result="$(jq -r '.result.commit // empty' "${task_file}")" || fail 'cannot read task result commit'
readonly task_result
if [[ -n "${task_result}" && "${task_result}" != "${head_commit}" ]]; then
    fail 'provided head does not match the task result commit'
fi
git -C "${repository_root}" merge-base --is-ancestor "${base_commit}" "${head_commit}" \
    || fail 'task base is not an ancestor of head'

diff_file="$(mktemp "${TMPDIR:-/tmp}/WellSpentAgentScope.XXXXXX")" \
    || fail 'cannot create scope-check scratch file'
readonly diff_file
trap 'rm -f "${diff_file}"' EXIT
git -C "${repository_root}" diff --name-only --no-renames -z \
    "${base_commit}" "${head_commit}" > "${diff_file}" \
    || fail 'cannot calculate base-to-head diff'

while IFS= read -r -d '' changed_path; do
    [[ -n "${changed_path}" ]] || continue
    jq -e --arg path "${changed_path}" '
      any(.writeScope.paths[]; . as $prefix |
        ($path == $prefix) or ($path | startswith($prefix + "/")))
    ' "${task_file}" >/dev/null || fail "changed path is outside write scope: ${changed_path}"
done < "${diff_file}"

echo "Agent write scope passed for $(jq -r '.taskId' "${task_file}"): ${base_commit}...${head_commit}"
