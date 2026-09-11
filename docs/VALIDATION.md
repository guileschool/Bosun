# Validation status

Current release: **0.8.12**. Verified on 2026-09-12 (KST).

## Verified locally

- Apple Silicon macOS application builds successfully with a Developer ID signature.
- Command, text cleanup, cancellation, deletion restoration, and English button classification regressions pass.
- All 78 English/Korean localization entries match with valid format arguments.
- Packaged language resources and app icon checks pass.
- Apple notarization accepted the release DMG. Submission ID: `7652c6ea-daa0-49e4-9f75-490560e7f93d`.
- The DMG's notarization ticket is stapled and validates successfully.
- macOS Gatekeeper accepts the DMG as `Notarized Developer ID`.
- Disk image integrity verification passes; a SHA-256 checksum accompanies the release.

## Validation limits

- Full end-to-end spoken-command checks, including Record followed by Stop, Cancel, Send, and editing commands, are not complete.
- A previous direct command-line Record check encountered a button-focus confirmation failure; automated tests do not establish live behavior.
- Fresh installation, permission setup, and behavior on another Mac have not been verified.

Apple notarization and passing automated tests do not establish that all live voice commands work. Repository visibility is independent of release status.
