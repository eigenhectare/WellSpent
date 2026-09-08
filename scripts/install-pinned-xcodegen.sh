#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly destination_root="${1:?destination root required}"
source "${script_directory}/xcodegen-toolchain.sh"

for command in curl unzip shasum install; do
    command -v "${command}" >/dev/null || {
        echo "Missing XcodeGen installer prerequisite: ${command}" >&2
        exit 1
    }
done
configured_version="$(configured_xcodegen_version "${repository_root}/project.yml")"
[[ "${configured_version}" == "${XCODEGEN_VERSION}" ]] || {
    echo "XcodeGen toolchain mismatch: project.yml requires ${configured_version:-an unspecified version}; pinned toolchain is ${XCODEGEN_VERSION}." >&2
    exit 1
}

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentXcodeGen.XXXXXX")"
readonly temporary_root
cleanup() {
    case "${temporary_root}" in
        "${TMPDIR:-/tmp}"/WellSpentXcodeGen.*) rm -rf -- "${temporary_root}" ;;
        *) echo "Refusing to remove unexpected temporary path: ${temporary_root}" >&2 ;;
    esac
}
trap cleanup EXIT

archive_path="${temporary_root}/xcodegen.zip"
curl --fail --location --retry 3 --silent --show-error --output "${archive_path}" "${XCODEGEN_ARCHIVE_URL}"
actual_digest="$(shasum -a 256 "${archive_path}" | awk '{ print $1 }')"
[[ "${actual_digest}" == "${XCODEGEN_ARCHIVE_SHA256}" ]] || {
    echo "XcodeGen archive digest mismatch." >&2
    exit 1
}
unzip -q "${archive_path}" -d "${temporary_root}/unpacked"
readonly downloaded_binary="${temporary_root}/unpacked/xcodegen/bin/xcodegen"
[[ -x "${downloaded_binary}" ]] || {
    echo "Pinned XcodeGen archive did not contain its executable." >&2
    exit 1
}
downloaded_version="$("${downloaded_binary}" --version | awk '/^Version: / { print $2; exit }')"
[[ "${downloaded_version}" == "${XCODEGEN_VERSION}" ]] || {
    echo "Pinned XcodeGen archive reported ${downloaded_version:-an unavailable version}." >&2
    exit 1
}
mkdir -p "${destination_root}/bin" "${destination_root}/share/xcodegen"
install -m 755 "${downloaded_binary}" "${destination_root}/bin/xcodegen"
cp -R "${temporary_root}/unpacked/xcodegen/share/xcodegen/." "${destination_root}/share/xcodegen/"
printf 'Installed XcodeGen %s at %s\n' "${XCODEGEN_VERSION}" "${destination_root}/bin/xcodegen"
