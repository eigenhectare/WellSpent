# WAT-23–28 owner decisions

This sheet records the remaining decisions that engineering evidence cannot make
on the owner's behalf. It grants nothing by existing in the repository. Record
an explicit dated approval or replacement value before crossing each boundary.

## 1. Resource budget — WAT-25

Recommendation: accept the complete proposed gate in
`WAT-25-RESOURCE-PRIVACY-AUDIT.md` under “Proposed physical resource budget.”
It makes correctness and privacy absolute gates, gives storage roughly 2×
headroom over the largest accelerated sample, and treats the first physical
battery/CPU/wakeup baseline as a reason to revise the budget before—not after—a
candidate verdict when platform measurement floors make a value infeasible.

Owner record:

- Decision: approved — accept the complete proposed WAT-25 resource and
  privacy gate as recommended.
- Decided by/date: Drew Reilly, September 4, 2026.
- Notes: Correctness and privacy remain absolute gates. The first physical
  battery/CPU/wakeup baseline may revise infeasible numeric limits before a
  candidate verdict.

## 2. Release-candidate identity — WAT-26

Repository evidence shows all four configured product components at marketing
version `0.1.0`, build `2`. Commit history says build 2 was prepared for App
Store review, but the repository has no release tag or authoritative App Store
Connect/TestFlight history. Therefore it cannot prove which build number is
available externally.

Recommendation: keep marketing version `0.1.0` and increment the shared build to
`3` **only if App Store Connect confirms build 3 is unused for 0.1.0**. Otherwise
use the next unused integer. After that choice, create one clean source commit,
rerun full CI, and bind every physical, archive, asset and beta result to that
same commit/version/build. Do not reuse the build number for different bytes.

Owner record:

- Current public/TestFlight state checked in App Store Connect: authenticated
  September 4, 2026. The authoritative TestFlight build list for WellSpent
  `0.1.0` contains builds `1` and `2` only; build `2` remains in **Waiting for
  Review** on its current submission.
- Approved marketing version: `0.1.0`.
- Approved next unused build number: `3`; App Store Connect confirmed it is
  unused for `0.1.0` on September 4, 2026.
- Approved source checkpoint/commit creation: approved after the build-number
  check, with all release evidence bound to that exact source/version/build.
- Decided by/date: Drew Reilly, September 4, 2026.

## 3. Physical-test authority — WAT-23–25

These scopes are deliberately separate.

### Nondestructive test session

Requires the owner present with the Watch worn/unlocked when requested. It may
change accessibility settings, radio availability and app lifecycle, create
fictitious local records, reboot the test devices, and run multi-hour battery,
storage, widget, notification and convergence observations. It does not
uninstall an app, erase a store, unpair devices, restore a backup, replace a
Watch, or inspect personal content.

- Authorization: approved for the recommended nondestructive session.
- Approved devices/date window: current supported WellSpent test devices;
  owner presence, Watch-worn/unlocked state, and availability remain execution
  prerequisites when a case requires them. No expiration date was specified.
- Decided by/date: Drew Reilly, September 4, 2026.

### Destructive retention session

Separately covers Watch-app reinstall, phone-app reinstall, unpair/re-pair,
backup/restore and replacement-Watch behavior. Before approval, inventory any
unsynchronized records, use a dedicated fictitious data set, record the selected
backup/restore path and confirm which real device data may be lost. An ordinary
nondestructive-test approval does not authorize this scope.

- Authorization: pending.
- Approved individual cases: pending.
- Data inventory/recovery plan: pending.

The September 4 approval of the recommendation is not interpreted as approval
for this separately gated destructive scope.

### Oldest-build upgrade

Requires the actual oldest supported binary/source and a populated fictitious
store. Do not substitute a newly built compatibility fixture for the real old
build.

- Old build reference: pending.
- Authorization: pending.

The September 4 approval of the recommendation is not interpreted as supplying
the missing real oldest build or authorizing a substitute compatibility fixture.

## 4. External distribution authority — WAT-26–28

Each step remains independently gated: distribution signing/export; App Store
upload validation; TestFlight upload; internal tester selection/invitations;
external beta submission/cohort; App Review submission; and final manual public
release. Approval of an earlier step never implies approval of a later one.

- Distribution archive/export: approved for this and future WellSpent versions.
- Upload validation: approved for this and future WellSpent versions.
- TestFlight upload: approved when used as part of the App Store submission
  workflow for this and future WellSpent versions.
- Internal testers/invitations: pending; not inferred from App Store submission
  authority because it communicates with specifically selected people.
- External beta: pending; not inferred from App Store submission authority.
- App Review submission: explicitly approved for this and future WellSpent
  versions, on the owner's behalf.
- Manual public release: explicitly approved for this and future WellSpent
  versions after the exact approved build and storefront configuration are
  verified.
- Decided by/date: Drew Reilly, September 4, 2026.
- Scope note: this is durable authority for the Apple-facing steps needed to
  submit and publish WellSpent. It does not waive factual preflight checks,
  Apple authentication, legally required agreements, or separately gated
  tester invitations and external-beta enrollment.

## Recorded reply and remaining owner decisions

On September 4, 2026, Drew Reilly approved recommendations 1–3 and explicitly
authorized the full App Store submission and manual public-release workflow for
this and future WellSpent versions on the owner's behalf.

The approvals are sufficient to continue the nondestructive validation and
Apple-facing release-preparation phase. These items remain deliberately open:

1. Supply the actual oldest supported build and separately authorize its upgrade
   test if that acceptance case is still required.
2. Approve named destructive-retention cases only after the data inventory and
   recovery plan are available.
3. Approve internal tester invitations or an external beta cohort before either
   is used.
