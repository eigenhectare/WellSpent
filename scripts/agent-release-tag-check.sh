#!/bin/bash
set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly task_file="${1:?usage: agent-release-tag-check.sh TASK_JSON TAG_NAME}"
readonly tag_name="${2:?tag name required}"
fail() { echo "Release tag validation failed: $1" >&2; exit 1; }

command -v jq >/dev/null || fail 'missing dependency: jq'
[[ -f "${task_file}" && ! -L "${task_file}" ]] || fail 'task file must be a regular JSON file'
[[ "${tag_name}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-build\.[0-9]+$ ]] || fail 'invalid version/build tag name'

task_commit="$(jq -er '.result.commit' "${task_file}")" || fail 'task has no result commit'
readonly task_commit
tag_ref="refs/tags/${tag_name}"
readonly tag_ref
tag_type="$(git -C "${repository_root}" cat-file -t "${tag_ref}" 2>/dev/null)" || fail 'tag does not exist'
readonly tag_type
[[ "${tag_type}" == "tag" ]] || fail 'release tag must be annotated'
tag_object="$(git -C "${repository_root}" rev-parse --verify "${tag_ref}")" || fail 'cannot resolve tag object'
readonly tag_object
tag_commit="$(git -C "${repository_root}" rev-parse --verify "${tag_ref}^{}")" || fail 'cannot peel tag'
readonly tag_commit
[[ "${tag_commit}" == "${task_commit}" ]] || fail 'tag does not target the task result commit'
project_source="$(git -C "${repository_root}" show "${tag_commit}:project.yml")" \
    || fail 'tagged source has no project.yml'
readonly project_source
marketing_version="$(printf '%s\n' "${project_source}" | awk '$1 == "MARKETING_VERSION:" { print $2 }')"
readonly marketing_version
build_version="$(printf '%s\n' "${project_source}" | awk '$1 == "CURRENT_PROJECT_VERSION:" { print $2 }')"
readonly build_version
[[ "${marketing_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "${build_version}" =~ ^[0-9]+$ ]] \
    || fail 'tagged source has invalid version/build values'
[[ "${tag_name}" == "v${marketing_version}-build.${build_version}" ]] \
    || fail 'tag name does not match the tagged source version/build'

jq -n --arg tag "${tag_name}" --arg object "${tag_object}" --arg commit "${tag_commit}" \
    --arg version "${marketing_version}" --arg build "${build_version}" \
  '{schemaVersion: 1, tag: $tag, tagObject: $object, targetCommit: $commit,
    version: $version, build: $build, result: "passed"}'
