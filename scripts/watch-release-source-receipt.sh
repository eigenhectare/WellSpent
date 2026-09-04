#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
report="${1:?usage: watch-release-source-receipt.sh NEW_REPORT_DIRECTORY}"
fail() { echo "Release source receipt failed: $1" >&2; exit 1; }

[[ ! -e "${report}" ]] || fail 'report directory already exists; preserve earlier evidence'
report_parent="$(cd "$(dirname "${report}")" && pwd -P)" || fail 'report parent must already exist'
report="${report_parent}/$(basename "${report}")"

[[ -z "$(git -C "${repository_root}" status --porcelain --untracked-files=all)" ]] \
    || fail 'source checkout is not clean'
readonly source_commit="$(git -C "${repository_root}" rev-parse --verify 'HEAD^{commit}')"
readonly source_tree="$(git -C "${repository_root}" rev-parse --verify 'HEAD^{tree}')"
[[ "${source_commit}" =~ ^[0-9a-f]{40}$ && "${source_tree}" =~ ^[0-9a-f]{40}$ ]] \
    || fail 'source commit/tree identity is invalid'

readonly marketing_version="$(awk '$1 == "MARKETING_VERSION:" { print $2 }' "${repository_root}/project.yml")"
readonly build_version="$(awk '$1 == "CURRENT_PROJECT_VERSION:" { print $2 }' "${repository_root}/project.yml")"
[[ "${marketing_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "${build_version}" =~ ^[0-9]+$ ]] \
    || fail 'source version/build values are invalid'

readonly source_paths=(
    Configurations
    WellSpentApp
    WellSpentShared
    WellSpentWidgets
    WellSpentWatch
    WellSpentWatchContracts
    WellSpentWatchIntents
    WellSpentWatchLocalization
    WellSpentWatchStore
    WellSpentWatchWidgets
    project.yml
)
for source_path in "${source_paths[@]}"; do
    [[ -e "${repository_root}/${source_path}" ]] || fail "missing source path: ${source_path}"
done

mkdir -p "${report}"
readonly report
git -C "${repository_root}" ls-files --cached -z -- "${source_paths[@]}" \
    | LC_ALL=C sort -z > "${report}/files.zlist"
[[ -s "${report}/files.zlist" ]] || fail 'production source manifest is empty'

file_count=0
while IFS= read -r -d '' relative_file; do
    artifact="${repository_root}/${relative_file}"
    [[ -f "${artifact}" && ! -L "${artifact}" ]] || fail "source manifest contains a non-regular file: ${relative_file}"
    shasum -a 256 "${artifact}" | awk -v relative="${relative_file}" '{ print $1 "  " relative }'
    file_count=$((file_count + 1))
done < "${report}/files.zlist" > "${report}/files.sha256"
rm "${report}/files.zlist"
[[ "${file_count}" -gt 0 ]] || fail 'production source manifest has no files'

readonly source_digest="$(shasum -a 256 "${report}/files.sha256" | awk '{print $1}')"
jq -n \
    --arg commit "${source_commit}" \
    --arg tree "${source_tree}" \
    --arg digest "${source_digest}" \
    --arg version "${marketing_version}" \
    --arg build "${build_version}" \
    --argjson fileCount "${file_count}" \
    '{
        schemaVersion: 1,
        sourceCommit: $commit,
        sourceTree: $tree,
        sourceClean: true,
        productionFileCount: $fileCount,
        productionSourceManifestSHA256: $digest,
        version: $version,
        build: $build
    }' > "${report}/summary.json"

echo "Clean release-source receipt passed. Evidence: ${report}/summary.json"
