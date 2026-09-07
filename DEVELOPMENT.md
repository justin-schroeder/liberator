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

Install an Apple Developer ID Application certificate with its private key in Keychain. Store notarization credentials using `xcrun notarytool store-credentials`. Do not put passwords or API private keys in this repository.

```sh
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID1234)'
export DEVELOPER_TEAM_ID='TEAMID1234'
export NOTARY_KEYCHAIN_PROFILE='liberator-notary'
./release.sh
```

The script builds a universal app, signs the helper and host with hardened runtime, runs local core tests, notarizes and staples the app, verifies Gatekeeper acceptance, creates a DMG, and signs/notarizes/staples the DMG. It does not upload or publish the release to any website.

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
