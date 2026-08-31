#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentCleanCheckout.XXXXXX")"
readonly source_repository="${temporary_root}/source"
readonly clean_clone="${temporary_root}/clone"

cleanup() {
    if [[ "${KEEP_CLEAN_CHECKOUT:-0}" == "1" ]]; then
        echo "Preserved clean-checkout workspace at: ${temporary_root}" >&2
        return
    fi

    case "${temporary_root}" in
        "${TMPDIR:-/tmp}"/WellSpentCleanCheckout.*)
            rm -rf -- "${temporary_root}"
            ;;
        *)
            echo "Refusing to remove unexpected temporary path: ${temporary_root}" >&2
            ;;
    esac
}
trap cleanup EXIT

mkdir -p "${source_repository}"
rsync -a \
    --exclude '.git/' \
    --exclude '.derivedData/' \
    --exclude 'DerivedData/' \
    --exclude 'xcuserdata/' \
    "${repository_root}/" \
    "${source_repository}/"

git -C "${source_repository}" init --quiet
git -C "${source_repository}" add --all
git -C "${source_repository}" \
    -c user.name='WellSpent CI Verification' \
    -c user.email='ci-verification@example.invalid' \
    commit --quiet --message='Temporary clean-checkout verification'
git clone --quiet "${source_repository}" "${clean_clone}"

CI_DERIVED_DATA_ROOT="${temporary_root}/DerivedData" \
    "${clean_clone}/scripts/ci.sh"
