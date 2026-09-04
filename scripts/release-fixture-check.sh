#!/bin/bash
set -euo pipefail
readonly app_bundle="${1:?Release iPhone app bundle required}"
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -d "${app_bundle}" && "${app_bundle}" == *.app ]] || {
    echo 'Release fixture audit requires an existing app bundle.' >&2; exit 1;
}
for executable in WellSpent Watch/WellSpentWatch.app/WellSpentWatch \
    PlugIns/WellSpentWidgets.appex/WellSpentWidgets \
    Watch/WellSpentWatch.app/PlugIns/WellSpentWatchWidgets.appex/WellSpentWatchWidgets; do
    [[ -s "${app_bundle}/${executable}" ]] || {
        echo "Missing Release executable: ${executable}" >&2; exit 1;
    }
done
# Scan executable bytes, embedded frameworks and copied resources. Print only
# paths, never a matching value that might itself be confidential.
if rg --hidden --no-ignore -a -l -F -f "${script_directory}/release-fixture-markers.txt" "${app_bundle}"; then
    echo 'Debug/test fixture marker found in Release products.' >&2; exit 1
else
    status="$?"
    [[ "${status}" == 1 ]] || exit "${status}"
fi
if find "${app_bundle}" \( -name '*.xctest' -o -name '*UITests*' -o -name '*.store' -o -name '*.sqlite' \
    -o -name 'Fixtures' -o -name '*ConnectivitySpike*' \) -print | rg .; then
    echo 'Test bundle, fixture database, or connectivity spike embedded in Release.' >&2; exit 1
fi
echo 'Release fixture isolation passed for iPhone, Watch, extensions and resources.'
