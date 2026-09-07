# Privacy

Liberator operates locally. It has no analytics, accounts, remote scanner, updater, or network client. External documentation links open only when selected.

Scans inspect paths, filesystem identity and extended attributes. They do not read file contents. Optional code-signature checks necessarily inspect app signatures and code. The optional benchmark invokes the installed Rust compiler to generate and run tiny local programs in a temporary folder; it does not download a compiler.

Undo records contain file paths, original quarantine attribute bytes, filesystem identity, timestamps and outcomes. They are stored in the current user's `~/Library/Application Support/Liberator/Undo`, with directory permissions 0700 and file permissions 0600. The operating system's normal backup policy may back up these records. Reports are saved only at an explicitly chosen path and contain paths and counts, not attribute values.

An administrator password is handled by macOS Authorization Services, never by a Liberator text field. It is never stored by the app. Helper authorization is destroyed when the operation finishes.

Users control App Management, Developer Tools, Full Disk Access and helper approval in System Settings. Liberator cannot override those protections. Remove the helper before deleting the app; remove its local undo folder separately if you no longer want that history.
