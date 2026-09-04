#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentXcodeGenDrift.XXXXXX")"
readonly temporary_root

cleanup() {
    case "${temporary_root}" in
        "${TMPDIR:-/tmp}"/WellSpentXcodeGenDrift.*)
            rm -rf -- "${temporary_root}"
            ;;
        *)
            echo "Refusing to remove unexpected temporary path: ${temporary_root}" >&2
            ;;
    esac
}
trap cleanup EXIT

for command in git rsync xcodegen shasum; do
    command -v "${command}" >/dev/null || {
        echo "Generated-project drift check failed: missing ${command}." >&2
        exit 1
    }
done

git -C "${repository_root}" ls-files --cached --others --exclude-standard -z \
    | rsync -a --from0 --files-from=- "${repository_root}/" "${temporary_root}/"

xcodegen generate --spec "${temporary_root}/project.yml" \
    --project "${temporary_root}" --project-root "${temporary_root}" --quiet

portable_manifest() {
    local project="$1"
    (
        cd "${project}"
        find . -type f \( \
            -path './project.pbxproj' -o \
            -path './project.xcworkspace/contents.xcworkspacedata' -o \
            -path './xcshareddata/xcschemes/*.xcscheme' \
        \) -print0 \
            | LC_ALL=C sort -z \
            | xargs -0 shasum -a 256
    )
}

portable_manifest "${repository_root}/WellSpent.xcodeproj" > "${temporary_root}/checked-in.sha256"
portable_manifest "${temporary_root}/WellSpent.xcodeproj" > "${temporary_root}/generated.sha256"

if ! cmp -s "${temporary_root}/checked-in.sha256" "${temporary_root}/generated.sha256"; then
    diff -u "${temporary_root}/checked-in.sha256" "${temporary_root}/generated.sha256" >&2 || true
    echo 'Generated-project drift check failed: run xcodegen generate --spec project.yml and retain the generated project/schemes.' >&2
    exit 1
fi

echo 'Generated Xcode project and shared schemes match project.yml.'
