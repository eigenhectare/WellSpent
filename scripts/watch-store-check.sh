#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

fail() {
    echo "Watch store check failed: $1" >&2
    exit 1
}

cd "${repository_root}"
command -v xcodegen >/dev/null || fail "xcodegen is not installed"
xcodegen generate --spec project.yml

rg -q 'WellSpentWatchStore' WellSpent.xcodeproj/project.pbxproj \
    || fail "the generated project is missing the Watch store target"
rg -q 'import WellSpentWatchStore' WellSpentWatch/App/WellSpentWatchRuntime.swift \
    || fail "the production Watch runtime does not open the Watch store"
rg -q 'import WellSpentWatchStore' WellSpentWatchWidgets/WellSpentWatchStatusWidget.swift \
    || fail "the Watch widget does not use the shared read-only projection"

if rg -n \
    '(^import SwiftData$|ModelContext|ModelContainer|performLocalCommand|receiveAcknowledgement|installSnapshotData|eraseAll)' \
    WellSpentWatchWidgets
then
    fail "the Watch widget references a persistence writer API"
fi

readonly unexpected_imports="$({
    rg -n '^import ' WellSpentWatchStore || true
} | rg -v '^.*:import (Foundation|SwiftData|WellSpentWatchContracts)$' || true)"
[[ -z "${unexpected_imports}" ]] \
    || fail "the Watch store imports an API outside its persistence boundary"

rg -q 'completeUntilFirstUserAuthentication' WellSpentWatchStore/WatchStorePersistence.swift \
    || fail "the store is missing watch-compatible file protection"
rg -q 'isExcludedFromBackup = true' WellSpentWatchStore/WatchStorePersistence.swift \
    || fail "the store is not excluded from backup"
rg -q 'allowsSave: false' WellSpentWatchStore/WatchWidgetSnapshotReader.swift \
    || fail "the production widget reader is not configured read-only"

echo "Watch store passed: private SwiftData writer, independent outbox rows, protected App Group storage, and read-only widget projection are wired."
