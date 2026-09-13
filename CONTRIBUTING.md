# Contributing

[한국어](docs/CONTRIBUTING.ko.md)

New contributors are welcome. You can help without writing code: report a reproducible bug, test commands on your Mac, or improve documentation and translations.

## Your first contribution

1. Check existing Issues and pull requests to avoid duplicate work. For a substantial feature, open an Issue to discuss the scope first. Small fixes can go directly to a pull request.
2. Fork the repository and create a branch for your change. No invitation or repository write access is needed.
3. Make a focused change. For code changes, run the checks below; for documentation, check links and keep English and Korean guidance aligned.
4. Open a pull request describing the problem, the change, and what you verified. The maintainer reviews changes before merging.

For voice-command reports, include macOS and Bosun versions, the target app, command mode, expected and actual behavior, and whether the issue occurs with short or long dictation. Share reproducible steps without private spoken content. Real microphone tests and automated checks are different evidence—say which you performed.

## Development checks

Build with Xcode Command Line Tools on macOS 14 or later. Run `zsh scripts/test.sh` before submitting changes.

Keep Accessibility matching strings separate from translated interface text. Preserve command safety checks, on-device recognition, and transcript deletion verification. Include a regression case when changing transcript handling. Update both language catalogs together.

Describe the user-visible problem, changed behavior, and validation in each pull request. Redact prompt contents, recognized speech, and personal paths from logs. Do not submit generated app bundles or DMGs as source.

## Documentation languages

The main README is English with a Korean link at the top. Keep installation, usage, and troubleshooting instructions equivalent in Korean and English. Update both when user-facing behavior changes. Internal developer documents may use the language best suited to their audience. Korean and English issues are welcome; do not promise real-time English support.
