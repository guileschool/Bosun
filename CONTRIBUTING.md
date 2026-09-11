# Contributing

Build with Xcode Command Line Tools on macOS 14 or later. Run `zsh scripts/test.sh` before submitting changes.

Keep Accessibility matching strings separate from translated interface text. Preserve command safety checks, on-device recognition, and transcript deletion verification. Include a regression case when changing transcript handling. Update both language catalogs together.

Describe the user-visible problem, changed behavior, and validation in each pull request. Redact prompt contents, recognized speech, and personal paths from logs. Do not submit generated app bundles or DMGs as source.

## Documentation languages

The main README is English with a Korean link at the top. Keep installation, usage, and troubleshooting instructions equivalent in Korean and English. Update both when user-facing behavior changes. Internal developer documents may use the language best suited to their audience. Korean and English issues are welcome; do not promise real-time English support.
