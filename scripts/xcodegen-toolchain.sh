#!/bin/bash

# The generated project is checked in, so its generator is part of the source
# toolchain. Keep the release URL and digest together with the required version
# so a future XcodeGen upgrade is deliberate and reproducible.
readonly XCODEGEN_VERSION="2.45.4"
readonly XCODEGEN_ARCHIVE_URL="https://github.com/yonaskolb/XcodeGen/releases/download/2.45.4/xcodegen.zip"
readonly XCODEGEN_ARCHIVE_SHA256="090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef"

configured_xcodegen_version() {
    local project_spec="$1"
    awk -F ': *' '/^[[:space:]]*minimumXcodeGenVersion:[[:space:]]*/ { print $2; exit }' "${project_spec}"
}

verify_xcodegen_version() {
    local project_spec="$1"
    local configured_version installed_version
    configured_version="$(configured_xcodegen_version "${project_spec}")"
    [[ "${configured_version}" == "${XCODEGEN_VERSION}" ]] || {
        echo "XcodeGen toolchain mismatch: project.yml requires ${configured_version:-an unspecified version}; pinned toolchain is ${XCODEGEN_VERSION}." >&2
        return 1
    }
    installed_version="$("${XCODEGEN_BINARY:-xcodegen}" --version | awk '/^Version: / { print $2; exit }')"
    [[ "${installed_version}" == "${XCODEGEN_VERSION}" ]] || {
        echo "XcodeGen version mismatch: required ${XCODEGEN_VERSION}, found ${installed_version:-unavailable}. Run scripts/install-pinned-xcodegen.sh before generating the project." >&2
        return 1
    }
}
