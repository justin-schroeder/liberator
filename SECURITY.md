# Security design and release verification

## Boundaries

The GUI runs as the logged-in user, outside App Sandbox because arbitrary user-approved filesystem scans and app maintenance require broad local access. Scanning is read-only. Cleanup targets only `com.apple.quarantine`. Provenance and all other attributes are preserved. No system-wide protection toggle or TCC database write exists.

The administrator daemon is registered through SMAppService only in a Developer ID build. macOS requires notarization and administrator approval for this launch daemon. The local build fails closed and cannot install or run it as root. Installation is optional; the normal app does not run as root.

The NSXPC listener accepts only connections with the configured team identifier and exact GUI signing identifier using Foundation's native code-signing requirement enforcement. The client similarly pins the helper identity. Effective UID must identify a regular local user. Each request also supplies an Authorization Services external form that must possess `system.privilege.admin`; the helper cannot present its own authorization UI. Client authorization is invalidated at operation end.

Requests are bounded to 8 MB and 1,000 file operations. The GUI sends batches of 500. Root paths are limited to `/Applications` and the requesting UID's home directory from the password database. No supplied username, executable, shell command, arbitrary xattr name, chmod/chown request, or destination path is accepted.

All path components are opened through directory descriptors with `O_NOFOLLOW`; the target is held open for validation and mutation. File type, device/inode, size, modification time, hard-link count and existing quarantine bytes are verified. Symlinks, changed targets, multiple hardlinks, traversal components and out-of-scope paths are refused. The same descriptor is used for the mutation. Restoration uses create-only semantics and cannot overwrite a newer attribute.

A journal of original values is persisted before cleanup. Results are written when the operation completes. As with other filesystem tools, OS crashes can interrupt bookkeeping; use the recovery guidance for an incomplete record and rescan before retrying. Concurrent external edits can cause individual files to be skipped. Root operations do not bypass TCC or SIP.

## Tests already automated

`./test.sh` exercises scanning, cancellation, exact quarantine removal/restoration, unchanged file contents, scope boundaries, changed file identity, changed attribute bytes, hardlinks, symlink targets, symlink ancestors, symlinked roots, serialization and the disabled local helper.

## Required before public release

No notarized identity was available on the development machine, so these integration checks must be run on the signed release:

- Install from notarized DMG; confirm Gatekeeper acceptance and universal architecture.
- Grant/revoke App Management and Developer Tools; verify the app handles relaunch requirements and denied files accurately.
- Register, approve, connect to, unregister and update the SMAppService daemon.
- Verify same-team/wrong-bundle, wrong-team, unsigned, unauthenticated and non-admin callers are refused; test revoked/expired authorization.
- Remove and restore quarantine on root-owned fixtures inside a dedicated `/Applications` test bundle. Confirm no other metadata changes.
- Exercise disconnects/timeouts during multi-batch operations and interrupted-journal recovery.
- Verify paths outside the permitted roots, traversal, symlink swaps, inode replacements and hardlinks are rejected by the running root service.
- Test both architectures and macOS 14 and the latest supported release.
- Review accessibility, multi-monitor behavior, large scans and cancellation with millions of entries.

This is an implementation and local verification record, not a claim that the unsigned preview has passed the signed-helper release matrix.

Interrupted records remain in the local undo journal. The model supports recovery, but the simplified interface does not yet expose a recovery action. Recovery is a user-requested attempt to restore original bytes to unchanged files with an absent attribute; it does not infer that every planned operation completed. Normal undo considers only successful removals. Review records are capped at 100,000 per root; counts remain complete and additional passes require a rescan.

## Known scanning limitation

A macOS metadata read can block inside the operating system, including during scans of the home directory. Cancellation is cooperative and takes effect when that call returns; the radar stays responsive while waiting. A process-isolated scanner with bounded read timeouts is not implemented yet.
