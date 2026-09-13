# Validation status

Current release: **0.8.14**. Verified on 2026-09-13 (KST).

## Verified locally

- Developer ID signed Apple Silicon build and strict nested signature verification pass.
- Command, cleanup, cancellation, deletion restoration, and English button regressions pass.
- All 80 bilingual localization entries and packaged resources pass checks.
- Apple notarization accepted the DMG: `6c6c56b8-ca82-4808-b24c-aa5272752587`.
- Stapled ticket validation, Gatekeeper assessment, disk image integrity and SHA-256 checks pass.
- Sparkle signatures on the final DMG and update feed verify successfully.
- Previous 0.8.13 verification: a separate updater-enabled fixture with an older build number detected, downloaded and installed the final DMG from a loopback test server, then relaunched. Its resulting version was 813 and executable SHA-256 matched the release build; Gatekeeper accepted the updated app.
- The release notes display an English heading and three short bullets in the actual update window.
- The fixture is a synthetic older build. Original 0.8.12 installations have no updater and need a one-time manual DMG replacement.

- The owner confirmed successful long-dictation sending with the timeout fix before the 0.8.14 version bump.
- New deterministic tests exercise delayed stop transitions, delayed final transcription, short-input latency, extended recording waits, and Break cancellation.

## Validation limits

- Full end-to-end spoken-command checks, including Record followed by Stop, Cancel, Send, and editing commands, are not complete.
- A previous direct command-line Record check encountered a button-focus confirmation failure; automated tests do not establish live behavior.
- Fresh installation, permission setup, and behavior on another Mac have not been verified.

Apple notarization and passing automated tests do not establish that all live voice commands work. Repository visibility is independent of release status.
