#!/bin/bash
set -euo pipefail
readonly result_bundle="${1:?result bundle required}"
readonly minimum="${2:?minimum executed test count required}"
readonly expected_file="${3:-}"
readonly summary_file="${result_bundle}.summary.json"
readonly tests_file="${result_bundle}.tests.json"
xcrun xcresulttool get test-results summary --path "${result_bundle}" > "${summary_file}"
xcrun xcresulttool get test-results tests --path "${result_bundle}" > "${tests_file}"
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${script_directory}/ci-check-results-json.sh" "${summary_file}" "${tests_file}" "${minimum}" "${expected_file}"
