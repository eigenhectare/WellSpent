# WAT-06 — Production Watch Target Foundation

Status: Complete  
Linear: `IDK-367`  
Plan: [APPLE-WATCH-PLAN.md](APPLE-WATCH-PLAN.md)

## Outcome

`project.yml` generates the production paired-app structure:

- `WellSpent` embeds `WellSpentWatch.app` in its native `Watch/` directory.
- `WellSpentWatch` embeds `WellSpentWatchWidgets.appex` in `PlugIns/`.
- `WellSpentWatchTests` and `WellSpentWatchUITests` are shared-scheme targets.
- The Watch app and widget share only the Watch-local
  `group.com.drewreilly.wellspent.watch` App Group.
- Watch sources, entitlements, manifests, and built binaries are included in
  formatting and privacy audits.

The first production Watch screen is intentionally the pre-sync
**Finish setup on iPhone** state. Project data, persisted commands, and
Watch Connectivity enter through WAT-07 through WAT-10.

## Reproducible gates

Run the standalone foundation gate:

```sh
xcodegen generate --spec project.yml
scripts/watch-foundation-check.sh
```

It validates both Watch test bundles, Debug and Release watchOS Simulator
builds, unsigned Debug and Release watchOS device-SDK builds, bundle IDs,
shared versions, local App Group configuration, privacy manifests, and the
iPhone → Watch → widget package.

`scripts/ci.sh` runs the same gate plus the Watch unit tests and all existing
iPhone unit tests. The checked-in CI workflow supplies current iPhone and Watch
Simulator destinations.

## Acceptance evidence

Verified locally on 2026-09-01 with Xcode 26.6 / SDK 26.5:

- full `scripts/ci.sh`: pass;
- iPhone tests: 103 passed, 0 failed;
- Watch unit tests: 1 passed, 0 failed;
- Watch UI launch smoke: 1 passed, 0 failed;
- unsigned Release iOS archive: pass;
- archive layout:
  `WellSpent.app/Watch/WellSpentWatch.app/PlugIns/WellSpentWatchWidgets.appex`;
- archive source/binary privacy audit: pass.

Signing identities, provisioning profiles, device identifiers, archive output,
and derived data remain local and ignored. Signed archive validation remains
owned by WAT-26.
