#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

cd "${repository_root}"

readonly production_paths=(
    WellSpentApp
    WellSpentShared
    WellSpentWidgets
)

if rg -n \
    '(^|[^[:alnum:]_])(print|debugPrint|NSLog|os_log)[[:space:]]*\(|Logger[[:space:]]*\(' \
    "${production_paths[@]}"
then
    echo "Privacy audit failed: production logging call found." >&2
    exit 1
fi

if rg -n \
    '(^import (Network|AdSupport|AppTrackingTransparency)$|URLSession|Analytics|Crashlytics|Sentry)' \
    "${production_paths[@]}"
then
    echo "Privacy audit failed: unexpected network, tracking, or diagnostics API found." >&2
    exit 1
fi

echo "Privacy audit passed: no production logging, networking, tracking, or diagnostics APIs found."
