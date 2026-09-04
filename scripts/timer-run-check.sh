#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

fail() {
    echo "TimerRun check failed: $1" >&2
    exit 1
}

cd "${repository_root}"

rg -q 'Schema\(versionedSchema: WellSpentSchemaV6.self\)' \
    WellSpentApp/Data/Repositories/WellSpentPersistence.swift \
    || fail "the current persistence schema does not include the v3 TimerRun model"
for schema in WellSpentSchemaV1 WellSpentSchemaV2 WellSpentSchemaV3 WellSpentSchemaV4 WellSpentSchemaV5 WellSpentSchemaV6; do
    rg -q "${schema}.self" WellSpentApp/Data/Migrations/WellSpentMigrationPlan.swift \
        || fail "${schema} is missing from the sequential migration path"
done
rg -q 'MigrationStage.custom' \
    WellSpentApp/Data/Migrations/WellSpentMigrationPlan.swift \
    || fail "the deterministic v2-to-v3 custom migration is missing"
rg -q 'LegacyTimerRunIdentity.runID\(for: session.id\)' \
    WellSpentApp/Data/Migrations/WellSpentMigrationPlan.swift \
    || fail "legacy timed sessions do not derive stable run IDs"

rg -q 'private let timerCommands: TimerRunCommandService' \
    WellSpentApp/App/AppEnvironment/WellSpentAppModel.swift \
    || fail "the iPhone model does not use the TimerRun command boundary"
rg -q 'throw SessionCommandError.timerRunCommandRequired\(timerRunID\)' \
    WellSpentApp/Domain/Commands/SessionCommandService.swift \
    || fail "legacy session commands can mutate run-owned segments"
rg -q 'for: sessions,' WellSpentApp/App/AppEnvironment/WellSpentAppModel.swift \
    || fail "reports no longer use authoritative session segments"
rg -q 'let current = activeRun' \
    WellSpentApp/App/AppEnvironment/WellSpentAppModel.swift \
    || fail "Live Activity reconciliation does not derive its current run from canonical state"
rg -q 'active: current.map \{ projection\(for: \$0\) \}' \
    WellSpentApp/App/AppEnvironment/WellSpentAppModel.swift \
    || fail "Live Activity desired state does not project the current canonical run"

test -f WellSpentTests/Persistence/TimerRunMigrationTests.swift \
    || fail "TimerRun migration fixtures are missing"
test -f WellSpentTests/Timer/TimerRunCommandServiceTests.swift \
    || fail "TimerRun command tests are missing"
test -f WAT-08-IPHONE-TIMER-RUN.md \
    || fail "the WAT-08 implementation contract is missing"

echo "TimerRun passed: schema-v3 domain model, sequential migration, command boundary, segment reports, Live Activity projection, and regression fixtures are wired."
