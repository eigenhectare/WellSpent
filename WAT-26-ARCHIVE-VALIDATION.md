# WAT-26 — Joint release-candidate validation

Status: In Progress. Inspection tooling and a clean-source-linked local
development-signed Release archive and Xcode aggregate privacy report have
passed the checks below. **No distribution-candidate privacy report, upload
validation, or candidate device smoke has passed this issue.** No version/build
was exported, uploaded or installed. App Store Connect confirmed on September
4, 2026 that build 3 is unused for marketing version 0.1.0, and the working
source now carries the approved candidate identity 0.1.0 (3). A clean source
commit and candidate-bound CI/archive evidence are still required.

## Read-only inspection workflow

```sh
bash scripts/watch-release-check.sh unsigned-device-app \
  /absolute/path/Release-iphoneos/WellSpent.app /absolute/path/new-report

bash scripts/watch-release-check.sh signed-archive \
  /absolute/path/WellSpent.xcarchive /absolute/path/new-archive-report
```

The report parent must exist. The destination must be new and outside the input
product/archive. Existing evidence is not overwritten. Both modes inspect the
four fixed product components: phone, phone widget, embedded Watch, Watch widget.

Checks include exact embedding, bundle/executable identifiers, version/build
alignment, dependent-companion relationship, extension points, device platform,
the supported 26.0 deployment baseline, Mach-O platform/SDK/slices, and compiled
app-icon metadata/assets. Each privacy manifest must match its source file;
source/binary privacy and Release-fixture isolation audits also run. A sorted
SHA-256 file inventory fingerprints the supplied product. Asset presence is
not a substitute for visual icon QA or App Store validation.

Signed-archive mode additionally verifies each code signature, certificate-backed
team identity and archive version metadata. It records signed entitlements and
compares app-owned capabilities with source; only enumerated signing-generated
keys are allowed. Embedded profile entitlements are extracted for reconciliation,
without retaining the profile's personal device list or certificate data. The
archive must contain exactly the four expected component dSYMs. For every phone,
Watch and widget Mach-O slice, the checker requires the dSYM architecture and
UUID set to match the product binary exactly and records only those identifiers.

Important limits:

- Every report sets `releaseApproved: false`. Unsigned mode sets every
  `signatureChecked` and `dSYMChecked` field false; a correctly shaped unsigned
  archive is rejected by signed mode.
- A development-signed Release archive can have `get-task-allow: true`; the
  checker records that, not TestFlight eligibility. Final export/re-signing,
  profile authorization/expiry, certificate trust, installation and upload
  validation must still be reconciled on the actual distribution candidate.
- File hashes identify the supplied binary, not its source provenance. A source
  commit/build receipt must link the exact candidate independently. A dirty
  checkout or temporary CI snapshot is not an approved release commit.
- The checker does not generate Xcode's aggregated privacy report or access
  App Store Connect. Those remain separate retained evidence.

Apple documents signature/profile inspection and the role of generated
entitlements in [TN2415](https://developer.apple.com/library/archive/technotes/tn2415/_index.html).
For a final export, retain and reconcile `DistributionSummary.plist`, export
options and packaging logs described in [Archive export files](https://help.apple.com/xcode/mac/current/en.lproj/deva1f2ab5a2.html).
The current SDK floor was checked against Apple's [submission requirements](https://developer.apple.com/app-store/submitting/)
on September 3, 2026; recheck before upload.

## Verified tooling evidence

Unsigned combined device product:
`.derivedData/WAT23-Device-Release/Build/Products/Release-iphoneos/WellSpent.app`.
Inspection report: `.derivedData/WAT26-UnsignedDeviceInspection1/summary.json`;
log: `/tmp/wat26-unsigned-device-inspection1.log`.
The four components agree on 0.1.0 (2); phone binaries contain arm64, Watch
binaries contain arm64_32 and arm64, and all use SDK 26.5/deployment target 26.0.
Product file-manifest SHA-256:
`9e11d1ada9c83c8ac5ebcc616f94f5af2826b60b7014ce4e54a5f4d5dac33971`.

The exact unsigned Release-Device product from the subsequently passed clean CI
was also inspected successfully. Report:
`.derivedData/WAT26-CICandidateUnsignedInspection/summary.json`; log
`/tmp/wat26-ci-candidate-inspection.log`. File-manifest SHA-256:
`6a1b9e599d99a2523c2ee32773235da9759f8e9a45385cfd1b6ac642448f6586`.
It retains the same versions/architectures/SDK; all signatures remain explicitly
unchecked in this unsigned mode. See WAT-23's final checkpoint for its exact
temporary source snapshot and retained CI product path.

`scripts/watch-release-guard-tests.sh` passes valid development/distribution
entitlement fixtures and ten rejection cases. With the compiled device app as
its argument, it copies the product into a disposable directory and passes a
positive inspection plus twelve targeted rejection cases: wrong version, ID,
deployment, platform, independent install, privacy, extra extension, wrong
Mach-O platform, missing architecture, missing assets, missing archive dSYMs,
and an unsigned archive with the expected dSYM layout.
Logs: `/tmp/wat26-release-guards.log` and the canonical-path-hardening rerun
`/tmp/wat26-release-guards-final.log`. Original products are not modified.

`scripts/watch-release-symbol-regression-tests.sh` separately proves the exact
UUID/architecture-set rule with phone and universal Watch positive fixtures. It
rejects missing, extra, stale-UUID, wrong-architecture, duplicate and malformed
identifier sets. The symbol and package guards are both CI source gates.

September 3 CI integration: `scripts/ci.sh` now runs entitlement-policy guards
in source gates, then inspects its own freshly built unsigned Release-Device
product and exercises all eleven invalid-package fixtures in `release-products`.
The per-run report lives in `release-package-inspection`; it still explicitly
records `releaseApproved: false` and unchecked signatures. These calls passed
in `WellSpentCleanCheckout.SWLC0U/DerivedData/run.n4GbYz` before that run was
intentionally interrupted for WAT-23's later screenshot-confirmed cache-layout
correction. The replacement full final-source pipeline subsequently passed all
13 stages and 374 tests in `WellSpentCleanCheckout.BB9IUG/DerivedData/run.h0nZNi`.
Its `release-package-inspection` report and `logs/release-products.log` verify
the integrated package/negative checks. The earlier 358-test run did not contain
these newly added CI calls. All package reports remain unsigned evidence only.

The new help/control checkpoint's joint device Release build passed a separate
inspection: `.derivedData/WAT26-HelpControlUnsignedInspection/summary.json`,
log `/tmp/wat26-help-control-inspection.log`, product file-manifest SHA-256
`270b0277e6076c0d7d432141a6678b4af576d9d9e8e67f7728e6b20c753f20ff`.
Its 0.1.0 (2) versions, four components, architectures, SDK/deployment, manifests
and fixture isolation passed; signatures remain unchecked. Entitlement and
package guards also passed again against the retained earlier CI device product
in `/tmp/wat26-ci-package-guards.log`.

The earlier fixture-only signed-archive limitation was resolved by the local
development archive checkpoint below. It does not resolve the distribution gate.

## Genuine local development archive — September 3

`xcodebuild archive` succeeded using the project's existing automatic signing
configuration, without provisioning-update flags or portal/account changes:

- Archive was created at `.derivedData/WAT26-LocalSignedProbe1.xcarchive` on
  `2026-09-03T14:49:15Z`; the raw archive and build log were later deleted
  because they exposed personal signing identifiers.
- Actual Apple Development signing; Release configuration, 0.1.0 (2).
- `signed-archive` inspection passed for all four components, including actual
  code signatures, signed/profile entitlements, embedding, architectures, SDK,
  deployment, resources, privacy manifests and fixture isolation. The raw
  inspection report was later deleted; the nonidentifying verdict, digests and
  profile dates remain in this record.
- Product file-inventory SHA-256:
  `ba63b8700f79fecb3e22fd88f6d4f9248cfff30d6f74a847a10bd6e30883fe54`.
- Production source/resource/configuration digest:
  `cebfb83e7986310342cdca126eceeafa6510ed2591854fd95a765991e2f0c85c`.
  This is the current dirty-worktree checkpoint, not an approved release commit.
- All six binary architecture/UUID pairs match their archived dSYMs. Four
  embedded profile expiration dates are in the future at inspection: phone
  `2027-08-31T13:13:35Z`, phone widget `2027-08-31T13:13:34Z`, Watch
  `2027-09-02T02:03:12Z`, Watch widget `2027-09-02T02:03:11Z`.
  No device lists or certificate data were copied into this record.

This verifies the checker against a genuine signed positive case. Expiration
dates alone do not prove certificate trust/revocation or distribution eligibility.
The archive is an engineering probe; it has not been exported, installed,
uploaded, or designated the release candidate. The report correctly retains
`releaseApproved: false`; final candidate versioning, clean source/CI, privacy
report, distribution signing/export/upload validation and physical gates remain.

### Later sanitized-widget archive — authorized reinspection passed

The widget's generic-content redaction fix changes the source digest to
`e0629625d4ef5d2e02032c9146b82ce84c8c9ed97a6f655107058b6b11ff0168`.
Its Release Simulator build and a fresh development archive both succeeded:

- `.derivedData/WAT23-WidgetPrivacy-ReleaseSimulator`; log
  `/tmp/wat23-widget-privacy-release-simulator.log`.
- `.derivedData/WAT26-LocalSignedProbe2.xcarchive` at the time of validation.

Both products pass privacy and Release-fixture isolation checks, and the
Simulator product passes localization resource parity. Versions remain 0.1.0 (2).
This was not an upload candidate. The raw archive and signing log were later
deleted after sanitized current-source evidence superseded them.

The earlier restricted read-only inspection could not establish signature trust:
`CSSMERR_TP_NOT_TRUSTED` for the phone binary. The identical restricted context
also failed on the unchanged Probe1 product that had passed normally. That
failed result was preserved until the unrestricted retry established the cause,
then its raw account-bearing report/log was deleted. It was never overwritten
or reclassified as a pass.

The requested normal authorized reinspection subsequently passed for all four
components. The product manifest SHA-256 is
`53c38636525f51dcf541e0da045bfb70a78a0f11eaa3e13d96ae9daf2fcf37e9`.
All signatures were checked, all six binary architecture/UUID pairs match their
archived dSYMs, and the four embedded profiles carry the same future expiration
dates recorded above. The report correctly remains `releaseApproved: false`:
this is development-signed engineering evidence, not a distribution export,
upload candidate, device install or release authorization.

### Integrated dSYM enforcement — September 3

The signed-archive checker now performs the dSYM comparison itself rather than
depending on a separately prepared observation. Reinspection of the unchanged
development archive passed with all four `signatureChecked` and `dSYMChecked`
fields true. Its product file-manifest SHA-256 remains
`53c38636525f51dcf541e0da045bfb70a78a0f11eaa3e13d96ae9daf2fcf37e9`,
and its per-component reports matched the exact six binary/dSYM architecture
and UUID pairs. The raw report was later deleted as described below; its verdict
remained `releaseApproved: false`.

The Probe2 archive and its raw inspection directories were later deleted
because signed entitlements exposed the developer-team account identifier.
Their historical verdict and product digest remain here; the sanitized
current-source record below is the retained positive evidence.

The unsigned-device path was rerun through the enhanced checker at
`.derivedData/WAT26-UnsignedDeviceInspection2/summary.json`. All four components
passed the package checks while correctly retaining `signatureChecked: false`
and `dSYMChecked: false`; unsigned inspection cannot substitute for the signed
archive gate. Both products predate the later physical-reset source correction,
so neither is the final source-linked release candidate.

### Clean source/product provenance — September 3

`scripts/watch-release-source-receipt.sh` now fails on a dirty checkout and
records a clean commit/tree, version/build, file count and a deterministic,
path-ordered production source/resource/configuration manifest. Ignored host
files such as `.DS_Store`, tests, documents, scripts and generated products are
excluded. A clean fixture passed and an untracked dirty marker was rejected.
`scripts/xcodegen-drift-check.sh` also requires the checked-in portable Xcode
project and all shared schemes to match a fresh isolated generation from
`project.yml`; the current project passes.

CI runs the source receipt after all source gates, then writes
`source-product-provenance.json` only when its version/build matches every
component in that run's inspected device product. The final clean run retained
both records under
`WellSpentCleanCheckout.xArrZO/DerivedData/run.Q3i2uP/`. Its synthetic source
commit is `26e977e184d5651b56efbd960a02680a6a564f8e`, the 142-file production
source-manifest SHA-256 is
`59e8d569f95ba1b92eba486e51cc69b760c00005cc3cad3b2f5aae37d9face75`,
and its unsigned product-manifest SHA-256 is
`794a6fbc92d14a7016143ca4ea19744a939a00f31f48e579d096a645c41dca14`.
All 13 stages and 381 tests passed, including the two physical-reset regressions.
The receipt is reproducibility evidence, but the temporary synthetic commit is
not an owner-approved source commit and the unsigned product is not a candidate.

A later clean checkout, after the WAT-25 runtime-sampler and WAT-27 icon-evidence
integration, also passed all 13 stages and the same 381-test split from synthetic
snapshot `1e929e74935550b891cf99dbe2348e99e03b8c49`; retained evidence:
`WellSpentCleanCheckout.5Aqsso/DerivedData/run.HOdM21`. Its production source
manifest is unchanged at
`59e8d569f95ba1b92eba486e51cc69b760c00005cc3cad3b2f5aae37d9face75`, its
synthetic tree is `1c99388f2dd9be466c0e997dd260b512a155eeec`, and its same-run unsigned
product manifest is
`4af63ecdaf63d455edfb8abb0dc0131038071935538f8dfb401315d5a0191775`.
This is the current CI receipt; it does not convert the earlier development
archive into a distribution candidate.

### Clean-source development archive — September 4

The unchanged clean snapshot above was also archived with the project's existing
automatic development signing configuration. Before archiving, its Git status
was empty. The enhanced signed-archive inspection passed all four embedded
components at 0.1.0 (2): every signature was verified and each phone, Watch and
widget Mach-O UUID/architecture set matched its exact dSYM.

The identifier-free evidence is retained at
`.derivedData/WAT26-CurrentSourceSignedProbe1-Sanitized/`:

- `summary.json` records `inspection: passed`, four signature/dSYM checks and
  `releaseApproved: false`.
- `source-product-provenance.json` links synthetic source commit
  `26e977e184d5651b56efbd960a02680a6a564f8e`, tree
  `79026cf165cd204ddd9224b9c8093ba29afc6f82`, the 142-file production-source
  manifest `59e8d569f95ba1b92eba486e51cc69b760c00005cc3cad3b2f5aae37d9face75`,
  and product manifest
  `7c237f880228697e063cd9bdd0f2412968e31fd5b7e5475a037efbbe0560fcf6`.
- Per-component package and dSYM records remain available without signing-team,
  profile, certificate, device or account identifiers.

The raw development archive and unsanitized inspection report were deleted
after validation because they embedded personal signing/account information.
They are reproducible from the clean snapshot. This proves the current release
shape and inspection path against genuine signatures, but it remains a local
development build: it was not exported with a distribution profile, installed,
uploaded, processed or designated as the release candidate.

### Xcode aggregate privacy report — September 4

Xcode 26.6 Organizer generated its native privacy report from a second temporary
development archive of the same unchanged clean snapshot. The identifier-free
PDF and a machine-readable receipt are retained at
`.derivedData/WAT26-PrivacyReportProbe1-Sanitized/`.

The one-page PDF was rendered at 150 dpi and visually inspected. It is blank,
with no truncated or hidden text. This is consistent with the report's
nutrition-label scope: all four source and archived `PrivacyInfo.xcprivacy`
files match byte-for-byte and declare no tracking, tracking domains or collected
data categories. The phone and phone-widget manifests separately declare only
the UserDefaults required-reason category (`1C8F.1` and, for the phone, `CA92.1`);
the Watch manifests declare no required-reason categories. No third-party runtime
framework or dynamic library was present in the archived product.

`privacy-report-receipt.json` records the clean source commit/tree, all four
manifest hashes, the 807-byte one-page PDF hash
`c82934ce6bec4a08151be0efeb680c16231e5105f4fb15f557e9ea303283db3b`,
the blank-page interpretation and `releaseApproved: false`. The PDF and receipt
contain no signing-team, certificate, profile, device or account identifier.
The raw privacy-report archive was deleted after verification. Repeat this exact
workflow against the approved distribution candidate and reconcile its output
with the final App Store Connect privacy answers before closing WAT-26.

## Candidate record and closure checklist

### Approved build-3 candidate checkpoint — September 4

The owner-approved source checkpoint is commit
`8ead2308259fa030abdd0d81ef3ba9ab0199c7b9`, tree
`91fba2b65df906240ded78df5313fc99c8dae968`, at version 0.1.0 (3).
The clean source receipt is retained at
`.derivedData/WAT26-Build3SourceReceipt1/summary.json`; its 142-file production
manifest is
`a008d2d0cbfbed0f06e8a85d50cc19777a9c8fa96c98dc64dab355c4f81d2bca`.

The exact checkpoint passed all 13 CI stages and 381 tests with no failures,
skips or expected failures. Same-run provenance is retained at
`.derivedData/CI/run.RGIiBQ/source-product-provenance.json`; its unsigned product
manifest is
`9b166d718be8af5c2b707c85397e9d927236cf32d319c3d3c4f104a3cc52dd28`.

The joint archive `.derivedData/WAT26-Build3Candidate1.xcarchive` was created at
2026-09-04T11:48:13Z. Strict inspection passed all four 0.1.0 (3) components:
each signature and exact architecture/UUID dSYM pairing was checked, the iPhone
products contain arm64, and the Watch products contain arm64_32 and arm64. The
archive product manifest is
`41871fef8b96022660696c0f8a51f9045a48d9c21b5565ef3df1d2e20eb51322`;
identifier-free evidence is retained at
`.derivedData/WAT26-Build3ArchiveInspection1/summary.json` and
`.derivedData/WAT26-Build3Candidate1-Sanitized/summary.json`.

Command-line App Store export stopped without changing the archive because this
shell has no Xcode Apple account, Apple Distribution certificate, or App Store
profiles for the Watch products. The next safe step is the authenticated Xcode
Accounts/Organizer workflow on an unlocked Mac, using this existing archive and
without rebuilding. Export, the candidate privacy report, upload validation,
processing, candidate installation and remaining physical gates are still open.

For the eventual candidate, record actual values rather than pre-filling passes:

- [x] Approved source commit, clean tree and full CI evidence, including the
  final WAT-23 changes. Remaining WAT-24/25 physical gates are tracked separately.
- [x] Current external build history identified in authenticated App Store
  Connect on September 4, 2026: version 0.1.0 contains builds 1 and 2 only;
  build 2 is attached to the current Waiting for Review submission. The owner
  approved 0.1.0 (3), and the shared working-source build number was incremented
  once for this upload.
- [x] Signed joint archive path/date, all four IDs/versions, signatures,
  product/dSYM UUIDs and SHA-256 inventories retained in sanitized evidence.
- [ ] Export the unchanged archive and reconcile distribution signatures,
  entitlements, profiles, validity, architectures and deployment support.
- [ ] Generate Xcode's privacy report; match required-reason APIs, manifests,
  optional local notifications and App Store privacy answers to this candidate.
- [ ] Inspect real compiled icons/assets and final screenshot/copy set (WAT-27).
- [ ] Authorized dedicated-pair clean install and oldest-supported upgrade from
  the archived/exported candidate. Record exact phone/Watch versions and aliases.
- [ ] Execute Start/Pause/Resume/Switch/End, detached offline acknowledgement,
  history/reports, complications/controls, optional goal alert and authorized
  erase scenarios. Preserve failures and do not erase personal stores.
- [ ] Retain successful upload validation and the exact processed build identity.
  Upload, tester invitations, submission and public release require their own
  explicit authorization; this checklist does not grant it.

Keep WAT-26 In Progress until its complete acceptance criteria are verified.
