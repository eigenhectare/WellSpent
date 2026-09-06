# Agent control records

`AGENTS.md` defines the operating policy. This directory holds the small,
machine-readable control plane used to enforce it:

- `control/gates.json` names approved verification commands and evidence classes.
- `control/resources.json` names exclusive integration, simulator, device,
  signing, versioning, and external-service resources.
- `schema/task-v1.jq` is the executable schema for task contracts.
- `schema/evidence-v1.jq` is the executable schema for append-only receipts.
- `tasks/<TASK-ID>.json` records outcomes, assignment, dependencies, explicit
  exclusions, write scope, evidence requirements, authority, blockers, and
  result identity.
- `evidence/<TASK-ID>/<RECEIPT-ID>.json` binds a result to an exact source,
  registered gate, producer role, claims, artifacts, limitations, and authority.

Run `scripts/agent-control-check.sh` before dispatch, handoff, integration, and
release. Run `scripts/agent-scope-check.sh TASK_JSON BASE_COMMIT HEAD_COMMIT`
before accepting a worker commit. The full CI gate also runs the validator and
its negative regression fixtures.

Acquire a task's exclusive resources with
`scripts/agent-resource-lock.sh acquire TASK_JSON`, release only that task's
leases with `scripts/agent-resource-lock.sh release TASK_JSON`, and inspect live
leases with `scripts/agent-resource-lock.sh status`. Linked worktrees resolve the
same ignored `.agent-locks/` directory through Git's common directory.

`publicReleaseApproved` is deliberately narrower than App Review approval. It
may be true only in an owner-produced, passed human-approval receipt. App Review
approval, storefront availability, and a public-binary smoke test remain
separate claims.

`source.clean` describes the candidate checkout observed by the recorded gate;
it does not describe whichever worktree later reads the receipt.

A `repository` locator is resolved at the receipt's `source.commit`, so its Git
object identity supplies immutability when `sha256` is null. CI artifacts always
carry a SHA-256; passed physical-device and signed-package evidence must retain
at least one artifact and digest.

Receipts are sanitized metadata, not a replacement for retained CI artifacts.
Never put credentials, signing identities, profiles, personal device IDs,
tester identities, or private session transcripts here.
