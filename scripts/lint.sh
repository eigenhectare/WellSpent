#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

cd "${repository_root}"

xcrun swift-format lint \
    --configuration .swift-format \
    --recursive \
    --parallel \
    --strict \
    --no-color-diagnostics \
    WellSpentApp \
    WellSpentShared \
    WellSpentWidgets \
    WellSpentTests \
    WellSpentUITests
