LIBERATOR

Move Liberator to Applications. macOS 14 or later is required.

1. Click Scan.
2. Uncheck apps or files you want to keep quarantined.
3. Click Liberate.

The receipt shows files scanned, apps scanned, and selected files. App rows group their flagged contents. Unchecking an app leaves all of those files quarantined. Quarantine is a downloaded-file security flag, not a malware diagnosis: clean only items you trust.

Scans cover your home folder (including hidden files), /Applications, /System/Applications, /opt/homebrew, and /usr/local where present. Other users' home folders and other volumes are not included automatically. Unreadable or incomplete scans are reported. A stopped scan shows partial results. Very large results are limited to 100,000 quarantine records per root per pass; rescan after cleaning a limited pass.

If macOS denies access, Liberator offers the relevant permission step when needed. Root-owned items require the signed release's administrator helper and normal macOS authorization. App Management and Full Disk Access remain separate macOS protections.

Cleanup preserves file contents, signatures, provenance, ACLs, and unrelated metadata. Undo restores exact original quarantine bytes if the file is unchanged and no replacement quarantine attribute exists. An undo receipt is saved before changes in ~/Library/Application Support/Liberator/Undo. The Undo action appears after cleanup.

All scanning and history are local. There are no accounts, analytics, or remote uploads.

A local preview is ad-hoc signed and cannot install the administrator helper. It is not a notarized public release.
