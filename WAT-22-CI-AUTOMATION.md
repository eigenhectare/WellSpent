# WAT-22 — Reproducible Watch and iPhone CI

Status: complete for the WAT-22 implementation checkpoint. The full local
clean-checkout CI passed on September 2, 2026. No physical transport or remote
GitHub execution is claimed; the workflow is prepared but was not pushed/run.

Verified temporary source snapshot: `8b8b631b70ca020c3d3534b92b065b971a71baf8`.
This is a disposable snapshot commit, not a commit in the working repository.
The subsequent WAT-23 accessibility work has its own verification ledger.

## Gate design

`scripts/ci.sh` records a unique run directory, per-stage logs, elapsed times,
explicit `.xcresult` bundles, and machine-readable executed-test summaries.
Its stage runner fails at the first unsuccessful command, including failures
inside a multi-command function. Negative regression checks exercise this rule.

The bounded default gate runs:

1. Toolchain inventory, XcodeGen, strict formatting, privacy and source wiring.
2. Four clean joint builds: Debug/Release for Simulator and unsigned device SDKs.
   Each builds the iPhone app, embedded Watch app and both widget extensions.
3. Shared golden contracts on iOS, all Watch unit tests (including the same
   golden sources), and all iPhone unit tests.
4. Built-product embedding, versions, privacy, generated intent metadata and
   Release fixture isolation checks.
5. Focused Watch and iPhone UI manifests, including real process termination
   and disk-backed recovery. `CI_FULL_UI=1` expands to both complete UI targets.

Runtime Simulator tests use normal local Simulator signing so App Groups work.
Unsigned compilation is tested separately; unsigned runtime tests are not a
substitute for entitled execution. No distribution credentials are needed.
The workflow explicitly installs XcodeGen/ripgrep and selects Xcode 26.6 with
iOS/watchOS 26.5 destinations; local destinations can be overridden by UDID.

## Assertions that prevent false green results

`ci-check-results.sh` reads the actual result bundle, not success-looking log
text. It requires a passed result, no failures, no skipped/expected failures,
equal passed/total counts, minimum suite counts and every named critical/UI
test. JSON validation has negative tests for empty/partial/skipped results and
missing required tests. Critical manifests cover migration identity, exact
segment totals, atomic rollback, duplicate/lost acknowledgement handling,
corrupt journal quarantine, erase fences, stale projections and privacy.

`release-fixture-check.sh` scans all files inside the joint Release bundle,
including embedded frameworks/resources. It rejects DEBUG fixture names,
launch switches, fault hooks, the unique restart canary, test bundles and
embedded fixture databases. Synthetic positive/negative packages test the
scanner itself. Existing privacy checks independently inspect source and
compiled network/capability surfaces.

## Process-termination evidence

Each restart case uses a fresh UUID-named store under a DEBUG-only directory
in its app's private container. It never resets or reads the live App Group
store. Seeding refuses to overwrite an existing file; recovery refuses to
create a missing one. Production persistence, journal and reconciliation code
are used. A small DEBUG-only checkpoint view exposes stored identity/counts;
XCTest calls `terminate()`, verifies the process is not running, and relaunches
twice without reseeding.

- Watch local commit before transport: exact run/segment, one outbox item,
  next sequence, revision, mutation identity, digest and envelope bytes survive.
- Watch delivery-attempt checkpoint before acknowledgement: all the above plus
  durable attempt count survive. This is adapter-boundary evidence, not radio
  delivery evidence.
- iPhone saved inbox receipt before canonical application: recovery through the
  production coordinator applies it once, then duplicate delivery and another
  restart retain one run/segment and one terminal acknowledgement.
- iPhone commit before acknowledgement delivery: duplicate delivery after two
  restarts preserves the exact original acknowledgement bytes and revision.

The existing unit suites inject pre-save failures to verify rollback within
transactions. The new UI cases cover process loss at committed boundaries.
They do not claim that XCTest terminates halfway through SQLite's own write.

UI/model fixtures use disconnected injected transport. Watch fixtures do not
activate WCSession; iPhone UI fixture catalogs cannot be published to a paired
device. Fixtures and persistence fault hooks are conditional on DEBUG.

## Running and retaining evidence

```sh
KEEP_CLEAN_CHECKOUT=1 bash scripts/verify-clean-checkout.sh
```

The clean-checkout script copies Git-known tracked/untracked source, excludes
ignored local credentials/products, creates a disposable local snapshot
repository, clones it, and runs the exact CI script there. It never commits or
pushes the working repository. KEEP preserves the temporary workspace and all
results for inspection; the evidence root is printed at the start.

Watch XCTest can verify app-owned views and persistence. It cannot establish
physical Watch Connectivity delivery, battery cost, haptic quality, actual Siri
or Action button routing, lock-screen authentication, or multi-hour system
scheduling. Those retain their own physical acceptance rows in
`WAT-05-ACCEPTANCE-MATRIX.md` and WAT-24; no simulator pass closes them.

## Current diagnostic record

- Both Watch process-restart cases passed on the 46mm Simulator in
  `.derivedData/WAT22-Watch-Restart.xcresult` (25.7s).
- Both iPhone process-restart cases passed on iPhone 17 Pro Max in
  `.derivedData/WAT22-Phone-Restart3.xcresult` (25.6s).
- First iPhone compile found a fixture clock isolation error; corrected before
  runtime tests. A subsequent receipt test caught normal SwiftUI StateObject
  bootstrap adding tags to the checkpoint store and correctly causing a stale
  base conflict. The unused normal app model now has a separate in-memory
  container; fault recovery continues to use its unchanged on-disk store.
- Result checking accepts the retained 161-case iPhone and 109-case Watch
  WAT-21 bundles, including each critical named case. Negative checks pass.
- First clean-checkout run stopped at a stale WAT-08 source assertion expecting
  the pre-WAT-21 projection expression. The assertion now checks canonical
  current-run selection and desired-state projection. No behavioral assertion
  or stale-conflict rule was weakened.
- Full clean-checkout verification subsequently passed all 13 stages in about
  11 minutes. Evidence is retained under
  `/var/folders/g6/h9knh2zj6sj218p24n0d0p6m0000gn/T/WellSpentCleanCheckout.vAbEbv/DerivedData/run.QaR940`.
  `stages.tsv` records each stage. `results/` contains the five explicit result
  bundles, summaries and complete test trees. `/tmp/wat22-clean-checkout2.log`
  contains the outer execution record.
- Verified executed counts: 19 shared contract tests on iOS, 109 Watch unit
  tests, 161 iPhone unit tests, 16 Watch UI tests and 17 iPhone UI tests. Every
  named critical/selected test passed; zero failures, skipped tests or expected
  failures. These counts include the four process-termination scenarios.
- Both clean Debug/Release joint Simulator builds and unsigned device-SDK
  builds passed. Embedding, versions, generated metadata, both Release privacy
  scans and both Release fixture scans passed. The watchOS device-family
  conditional also removed the earlier shared-target warning.
- The CI/checker/restart-fixture files were compared with the verified clean
  clone after execution and matched. Changes begun afterward for WAT-23 do not
  retroactively belong to this CI checkpoint.

## Later release-provenance hardening — September 3

WAT-26 follow-up exposed two clean-checkout blind spots and converted both into
fail-fast CI gates. The App Store, beta, privacy, support and accessibility
drafts were still covered by the repository-wide Markdown ignore rule, so the
snapshot copier omitted them even though `watch-release-copy-check.sh` required
them. `.gitignore` now explicitly includes all five release documents. The
first diagnostic clean run correctly stopped at that missing-input condition in
`WellSpentCleanCheckout.56jMJt/DerivedData/run.eUbI44`; it is not a pass.

The next complete run passed but post-run status showed that `xcodegen generate`
had changed three shared Watch schemes. The generated project and schemes were
refreshed, and `scripts/xcodegen-drift-check.sh` now regenerates an isolated
copy and requires its portable project files to match `project.yml` exactly.
`scripts/watch-release-source-receipt.sh` separately requires a clean checkout
and records the commit, tree, version/build and a path-ordered SHA-256 manifest
of the 142 production source/resource/configuration files. Release-product CI
then binds that receipt to the inspected unsigned product digest; the result
still records `releaseApproved: false`.

The final current-source pipeline passed all 13 stages from synthetic snapshot
`26e977e184d5651b56efbd960a02680a6a564f8e`. Retained root:
`/var/folders/g6/h9knh2zj6sj218p24n0d0p6m0000gn/T/WellSpentCleanCheckout.xArrZO`;
evidence `DerivedData/run.Q3i2uP`. Exact result summaries verify **381 passed**,
zero failed/skipped/expected failures: 19 shared contracts, 123 Watch units,
163 phone units, 59 Watch UI and 17 phone UI. All four joint build variants,
source gates and Release-product inspection passed in 2,000 stage-seconds.
The clean source receipt records production manifest SHA-256
`59e8d569f95ba1b92eba486e51cc69b760c00005cc3cad3b2f5aae37d9face75`;
the same-run unsigned product manifest is
`794a6fbc92d14a7016143ca4ea19744a939a00f31f48e579d096a645c41dca14`.
The synthetic snapshot commit proves a reproducible clean checkout, not owner
approval of a final release commit.
