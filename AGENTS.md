# WellSpent agent operating contract

This file is the compact control plane for AI-assisted work in this repository.
It applies to the entire repository. Keep it short enough to load for every task;
put task-specific facts in `AgentControl/tasks/` and append-only results in
`AgentControl/evidence/`.

The rules below are required operating policy. The validators enforce record
shape, dependency/evidence integrity, Git identity, protected-resource
declarations, and write scope; the coordinator and integrator enforce role,
worktree, and live-lease behavior that cannot be inferred from committed files.

## Purpose and precedence

- Follow the user's current request and explicit authority first, then this file,
  then the active task contract, then legacy planning prose.
- `AgentControl/tasks/*.json` is the operational source of truth for new work.
  `AgentControl/evidence/**/*.json` is the durable, sanitized evidence record.
- `PROJECT_PLAN.md` and WAT documents remain historical context. The evidence
  boundaries in `WAT-05-ACCEPTANCE-MATRIX.md` and human authority boundaries in
  `WAT-OWNER-DECISIONS.md` remain authoritative until explicitly superseded.
- Do not silently resolve conflicting instructions. Record the conflict and ask
  the coordinator or owner when it changes scope, evidence, or authority.

## Starting a task

- Planning, status inspection, and read-only audits may proceed without a task
  file. Repository writes require a ready task contract unless the user directly
  authorizes a small, bounded change in the current conversation.
- Before writing, read the task's outcome, exclusions, exact base commit,
  dependencies, write scope, resource locks, acceptance criteria, evidence
  requirements, and authority requirements.
- Start only when all dependencies are `done`, the base commit still applies,
  required authority is present, and every exclusive resource can be acquired.
- Tasks reference gate IDs from `AgentControl/control/gates.json`; task JSON never
  carries executable shell text.

## Agent roles

- **Coordinator:** decomposes work, owns task status and dependency changes,
  assigns non-overlapping scopes, manages resource locks, and is the only agent
  that synchronizes external issue trackers.
- **Implementer:** changes only the declared scope and returns one reviewable
  commit. It may run focused checks but does not independently approve its work.
- **Verifier:** starts from the task contract and resulting diff, tries to
  disprove each acceptance claim, and writes only a unique evidence receipt.
  A verifier does not repair the same result while acting as verifier.
- **Integrator:** owns target-branch mutation, shared-file conflict resolution,
  generated-project reconciliation, and integration gates.
- **Release steward:** owns version/build allocation, frozen-candidate receipts,
  archive and Store workflow. It records human/external authority but never
  invents it.
- High-risk architecture or platform work requires a fresh verifier acting as an
  architecture critic before implementation tasks are dispatched.

## Task lifecycle and blockers

- Valid states are `backlog`, `ready`, `in_progress`, `in_review`, `blocked`,
  `done`, and `cancelled`.
- Only the coordinator changes state. A worker hands back facts and evidence;
  it does not declare its own task done.
- A blocked task records blocker kind, owner, reference, and an observable
  `resumeEvent`. Suspend it until that event occurs. Do not spend turns polling
  unchanged hardware, authentication, review, or human state.
- When assumptions, scope, or architecture change, update the durable task graph
  before dispatching dependent work.

## Worktrees and parallel execution

- Use one short-lived branch and linked worktree per bounded implementation task.
- Delegate independent, bounded tasks when parallel work saves time or improves
  review. Do not dispatch tasks with dependency or path overlap.
- A task contract is immutable after dispatch except for coordinator-managed
  status, blocker, and result fields. Revise and redispatch if its write scope
  or acceptance/evidence contract must expand.
- Never let two workers edit the same path prefix concurrently. Shared hotspots
  belong to the integrator.
- Each worker returns one commit plus a handoff containing changed files, checks,
  evidence paths, decisions, limitations, blockers, and newly unblocked work.

## Write scopes and shared-resource locks

- Compare `git diff --name-only <base>...HEAD` with `writeScope.paths` before
  handoff. `scripts/agent-scope-check.sh` is the canonical check.
- Resource IDs and protected paths live in `AgentControl/control/resources.json`.
- Acquire all required exclusive locks in lexical order before dispatch and
  release them after handoff. Runtime leases live in `/.agent-locks/` resolved
  from the Git common directory so linked worktrees coordinate.
- Use `scripts/agent-resource-lock.sh acquire TASK_JSON` and
  `scripts/agent-resource-lock.sh release TASK_JSON`; inspect active leases with
  `scripts/agent-resource-lock.sh status`.
- Workers never force-release another task's lease. Escalate a suspected stale
  lock to the coordinator.

## Verification tiers

- **Focused:** cheapest gate that exercises the changed behavior; run during
  implementation.
- **Impacted:** relevant structural checks, unit/UI suites, migrations, contracts,
  privacy, or generated-project checks; run by the verifier.
- **Full:** `scripts/ci.sh`; run at integration/release boundaries or when risk
  justifies it, not repeatedly after unrelated documentation-only changes.
- Simulator, physical-device, signed-package, external-service, and human-
  approval evidence are distinct and cannot substitute for one another.

## Evidence and handoffs

- Evidence receipts are append-only JSON under
  `AgentControl/evidence/<TASK-ID>/`. Never overwrite a prior attempt.
- Bind passed evidence to the exact task requirement, commit/tree, registered
  gate, producer role, result, claims, artifact locators/digests, and limitations.
- Raw logs, archives, profiles, screenshots, and `.xcresult` bundles remain in
  CI artifacts or ignored local storage. Commit only sanitized metadata and
  digests. Never record credentials, personal device IDs, tester identities, or
  private project/session content.
- `local-diagnostic` artifacts cannot close physical, signed-package, external-
  service, or human-approval requirements.

## Human and external authority

- Obtain and cite explicit authority before destructive device actions, personal
  data changes, tester invitations, external beta enrollment, signing/upload,
  public messages, App Store submission, or public release.
- Missing hardware, authentication, agreement state, or owner action is
  `blocked` or `not_run`, never `passed`.
- Batch device/authentication steps into one checklist. State the purpose, exact
  action, expected observable result, and what each step unblocks.
- Verify that a requested reminder or monitor was actually created before saying
  it is scheduled.

## Repository invariants

- `project.yml` is the source of truth for project structure. Regenerate the
  checked-in Xcode project and pass `scripts/xcodegen-drift-check.sh` after edits.
- Preserve local-first privacy, persist-first command handling, idempotence,
  migration continuity, exact time accounting, and non-overlapping sessions.
- Do not modify signing identity, bundle IDs, version/build values, privacy
  declarations, shared wire contracts, or SwiftData schemas incidentally.
- Preserve unrelated user changes. Never rewrite release history or evidence to
  make a later result appear to have been observed earlier.

## Release handling

- Release work uses a frozen worktree and an exact commit/tree/source receipt.
- Keep engineering validation, App Review approval, public release, and public-
  binary smoke as separate states.
- Tags bind the exact binary source commit, not a later documentation commit.
  Never move or replace a published release tag.
- Historical archive/export hashes remain bound to the commit that produced
  them. Record unavailable exact-candidate values as unavailable; do not borrow
  hashes from a byte-equivalent but differently identified build.
- Only the release steward mutates version/build, signing/archive state, or App
  Store state, and only within explicit owner authority.

## Definition of done

A task is done only when all acceptance criteria have passed evidence of the
required class, independent verification is recorded, the result commit is
integrated, required authority is cited, and the final tree is clean. Report the
result commit, gates run, evidence paths, residual risks, and next ready tasks.
