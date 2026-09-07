# Development

A native macOS utility for finding and clearing quarantine metadata. SwiftUI UI, direct Darwin metadata access, and a constrained SMAppService administrator helper. No external dependencies, telemetry, or accounts.

## Build

Requires macOS 14+ and Apple Command Line Tools with a Swift compiler supporting the installed SDK. Tested with Swift 6.3.3 in Swift 5 language mode and macOS 26.6.2.

```sh
./build.sh local       # Apple Silicon development build
./build.sh universal   # Apple Silicon + Intel development build
./test.sh
open build/Liberator.app
```

The locally signed app scans and cleans user-owned files and apps with macOS permissions. Root functionality deliberately remains disabled without a configured Developer ID release identity.

## Public release

Push a stable version tag to publish a signed, notarized universal DMG automatically:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The tag supplies the app version; the Actions run number supplies its build number. The workflow runs tests, signs the helper and app with hardened runtime, notarizes and staples the app, builds and signs the DMG, notarizes and staples it, and checks signatures and Gatekeeper acceptance before publishing a GitHub Release with generated notes and a SHA-256 checksum. A failed build or notarization never publishes an unsigned fallback. Only stable `vMAJOR.MINOR.PATCH` tags are supported.

The README button always points to the latest release's `Liberator.dmg`. It becomes usable after the first successful release. Download both assets and run `shasum -a 256 -c Liberator.dmg.sha256` to verify the download.

### One-time repository secrets

In [Actions secrets](https://github.com/justin-schroeder/liberator/settings/secrets/actions), add:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 of an exported Developer ID Application certificate **and its private key**, in password-protected `.p12` format |
| `DEVELOPER_ID_P12_PASSWORD` | Export password for that `.p12` |
| `DEVELOPER_ID_APPLICATION` | Exact signing identity, `Developer ID Application: Name (TEAMID1234)` |
| `DEVELOPER_TEAM_ID` | Matching ten-character Apple team ID |
| `NOTARY_APPLE_ID` | Apple Developer account email |
| `NOTARY_APP_PASSWORD` | Apple app-specific password for notarization, not your account password |

Upload the certificate without printing its contents:

```sh
base64 < /secure/path/DeveloperID.p12 | gh secret set DEVELOPER_ID_P12_BASE64
```

Use `gh secret set NAME` to enter other values interactively. Never commit signing material or put credentials in a tag, issue, or workflow file. The hosted runner imports the certificate into a temporary keychain, validates notarization credentials, and deletes the keychain on success or failure. GitHub also discards the hosted runner after the job. Only trusted maintainers should be allowed to push release tags or change workflows.

For a local signed build, install the matching certificate/private key in Keychain, store a `notarytool` profile, and run:

```sh
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID1234)'
export DEVELOPER_TEAM_ID='TEAMID1234'
export NOTARY_KEYCHAIN_PROFILE='liberator-notary'
RELEASE_VERSION=0.1.0 ./release.sh
```

The local script produces `build/Liberator.dmg`; GitHub publication happens only in the tag workflow. If publication fails after draft creation, delete that unpublished draft before rerunning the failed job; published releases are never overwritten automatically.

References: [GitHub certificate setup](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications), [Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Before public shipping, complete the signed-helper integration matrix in `SECURITY.md` on both Apple Silicon and Intel, and on the minimum supported macOS release. Local tests cannot stand in for notarization or administrator-service testing. Branding and the bundle identifiers are working release identifiers and should be finalized before users install the app, because changing them affects saved macOS permissions.

## Behavior

The app has one screen: Scan, a checkbox list, a receipt with file/app totals, and Liberate. Findings are selected by default. Applications group their flagged contents; ordinary files are individually selectable. Unchecking an item preserves its quarantine. Undo appears after cleanup.

During scanning, a vintage radar scope fills most of the fixed window. Actual quarantine findings arrive at scattered bearings and move inward beneath a rotating sweep. Up to 300 contacts are retained, while readable filename callouts avoid each other and rotate with the sweep. Contacts fade with an eight-second half-life and disappear as they reach the center exclusion zone, no later than 32 seconds after arrival. The full checkbox list and receipt return when scanning finishes or stops. Progress is batched to roughly ten updates per second and animation is limited to twenty frames per second; Reduce Motion disables the sweep and inward movement.

Scans include the current user's home directory, /Applications, /System/Applications, /opt/homebrew and /usr/local where present. The scanner reads quarantine metadata only, including hidden files. System app findings are view-only. Partial scans, record limits and unreadable entries are reported accurately.

The interface has no sidebar, settings screen, development-tool setup, or benchmarks. Access prompts appear only when an operation needs them. Cleanup saves original metadata first and preserves all other attributes and file contents. See DISTRIBUTION.md for user instructions.

## Layout

- `Sources/Core.swift`: scanner, identity records, descriptor-based metadata operations.
- `Sources/Model.swift`: scans, review, local undo journals and permission workflows.
- `Sources/App.swift`: native user interface.
- `Sources/Privilege.swift`, `Sources/Helper.swift`: authorization and constrained XPC service.
- `Sources/Benchmark.swift`: optional local Rust launch measurement.
- `Tests/CoreTests.swift`: metadata round trips and filesystem boundary tests.
- `Resources`: app metadata, helper service configuration, generated aircraft artwork and icon packaging.

See `DISTRIBUTION.md` for end-user instructions, `PRIVACY.md` for data handling, and `SECURITY.md` for privilege boundaries and remaining release verification.

## Background

- [Faster Rust builds on Mac — Nicholas Nethercote](https://nnethercote.github.io/2025/09/04/faster-rust-builds-on-mac.html)
- [Nextest macOS guidance](https://nexte.st/docs/installation/macos/)
- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple ExecutionPolicy](https://developer.apple.com/documentation/executionpolicy)

### Large scans and interrupted operations

Counts include every inspected entry, while reviewable quarantine records are capped at 100,000 per root to bound memory. A limited result is explicitly marked; clear one pass and rescan for remaining flags. No unrecorded file is mutated.

An initial undo journal is saved before any cleanup. If the app is interrupted before outcomes are saved, the saved JSON receipt can be used to recover an interrupted operation; the source model includes a recovery operation. It attempts to restore only recorded original quarantine bytes, only if the attribute is now absent and file identity still matches. Existing/replaced attributes and changed files are refused. Ordinary undo restores only recorded successful removals; it does not re-quarantine files reported as already clear.
