# FND-05 continuous integration

## Pipeline contract

`scripts/ci.sh` is the single entry point used locally and by
`.github/workflows/ci.yml`. It performs these gates in order:

1. Strict Apple `swift-format` lint over every Swift source target.
2. Clean Debug app and embedded-extension build for the generic iOS Simulator.
3. Clean Release app and embedded-extension build for the generic iOS Simulator.
4. The complete unit-test target on the current Xcode simulator runtime.

The pipeline uses the checked-in Xcode project and Apple toolchain only. It does
not read signing certificates, provisioning profiles, API keys, repository
secrets, Calendar entitlements, or CloudKit credentials. Generic build steps
explicitly disable code signing; simulator tests use only Xcode's local
ad-hoc signing.

## Pull-request workflow

The GitHub Actions workflow runs for every pull request, pushes to `main`, and
manual dispatches. It grants read-only repository contents permission and tells
the checkout action not to persist its token. No write permission or secret is
configured.

The workflow targets the current macOS runner generation because the app's
current-iOS-only deployment target requires an Xcode 26 toolchain. The workflow
prints the selected Xcode, Swift, and SDK versions before running the pipeline,
so an image drift failure is diagnosable.

## Local commands

Run formatting validation only:

```sh
cd '/Users/dev/Documents/Billable Hours App'
scripts/lint.sh
```

Run the same build and unit-test gates as CI:

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/ci.sh
```

Override the simulator without editing the script:

```sh
CI_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
scripts/ci.sh
```

## Clean-checkout verification

Until this local repository has its first authorized commit, verification uses
an isolated temporary Git repository and clone containing the same files. This
proves the pipeline does not depend on ignored derived data, Xcode user state,
the source worktree's `.git` metadata, signing identities, or untracked local
configuration:

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CI_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
scripts/verify-clean-checkout.sh
```

The verifier creates and commits only inside a guarded temporary directory; it
does not commit or modify the source repository. A hosted GitHub Actions run
cannot exist until the user later authorizes a source commit and remote.
