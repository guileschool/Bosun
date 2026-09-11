# Bosun

Start ChatGPT’s microphone with your voice. Dictate your message, then send it hands-free. Bosun is a free, MIT-licensed Mac menu bar app.

![Bosun demo: voice dictation, transcription, submission, and an English response](docs/media/voice-input-demo.gif)

Watch with sound on YouTube: [English demo](https://www.youtube.com/shorts/i1BzBHXi8xw) · [한국어 시연](https://www.youtube.com/shorts/g9woBt5dl44)

Say “Record, please”, dictate your message, then say “Send, please”. Silent demo; playback is accelerated and waiting time is shortened.

[Download Bosun for Mac](https://github.com/guileschool/Bosun/releases/latest) — Apple Silicon, macOS 14+. Developer ID signed and Apple-notarized.

[한국어](docs/README.ko.md) · [Install, use & troubleshooting](docs/USAGE.md) · [Architecture](docs/architecture.ko.md) · [Release guide](docs/RELEASING.md)

Bosun runs in the menu bar and controls dictation and text editing with spoken English commands. Command recognition runs on your Mac. Bosun does not save audio files.

## Status

Current release: **0.8.13**. Targets Apple Silicon and macOS 14 or later, with English recognition assets available on the device. Menus support English and Korean.

Automated checks pass. The release DMG is notarized, its ticket is stapled, and macOS Gatekeeper accepts it. Full spoken-command testing and installation on another Mac are not yet verified. See [validation status](docs/VALIDATION.md).

## Updates

Choose **Check for Updates…** from the Bosun menu to download and install a new version. Enable **Automatically Check for Updates** in Settings to receive update notifications. Installation requires your confirmation; Bosun then restarts.

**Using 0.8.12 or earlier?** Quit Bosun and replace it in Applications with the latest DMG once. In-app updates are available starting with 0.8.13.

## Commands

| Say | Action |
|---|---|
| Record | Start dictation |
| Stop | Stop dictation and keep the transcript |
| Cancel | Cancel dictation |
| Send | Stop dictation, remove the trailing command, and send |
| Break | Interrupt pending submission or stop response generation |
| Clear | Clear the input |
| Delete | Remove the last word |
| Undo | Restore the most recent Bosun Delete or Clear once, if the input is unchanged |
| Enter | Insert a line break |
| Space | Insert a space |
| Home | Move to the beginning of the input |
| End | Move to the end of the input |

Use phrase mode while dictating English: “record please”, “stop please”, or “send please”. Append “please” to any command in the table. Menu language and command mode are independent.

## Build and use

Install Xcode Command Line Tools. From this directory:

```sh
SIGN_IDENTITY=- zsh build.sh
zsh scripts/test.sh
```

Output: `build/Bosun.app`. This explicitly creates an ad-hoc signed local test build. It does not install or launch the app. Do not replace an existing Developer ID signed installation with an ad-hoc build; use the same Developer ID identity for updates to preserve permissions.

For a signed build, set `SIGN_IDENTITY` to your Developer ID Application identity. Without an explicit value, the build script attempts to reuse the installed app's signing identity and fails if none is available.

A distribution build is installed by dragging Bosun into Applications. Allow Microphone, Speech Recognition, and Accessibility, then use the menu bar to start listening. See [installation instructions](docs/INSTALL.txt).

## Source layout

- `Sources/`: Swift application, speech recognition, Accessibility control, and localization.
- `Resources/`: app icon and English/Korean strings.
- `Design/`: editable icon source material.
- `Tests/`: command regressions and bundle checks.
- `scripts/`: testing, localization checks, and DMG packaging.
- `.github/workflows/`: automated macOS build and checks.

## Privacy and licensing

Diagnostic logs can contain recognized speech and input text. Keep them out of the repository. ChatGPT's own dictation and processing are separate from Bosun's on-device command recognition. The opt-in `--probe` diagnostic uses the microphone for eight seconds when permission is already granted.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Licensed under the [MIT License](LICENSE). Copyright (c) 2026 JCUTPLUSSOFT.

## Questions

Korean and English questions and bug reports are welcome in repository Issues. See the [reporting checklist](docs/USAGE.md#questions-and-bug-reports). Real-time English support is not promised.

## Creator

Created by [guileschool](https://github.com/guileschool) · [CaptainMacBot (캡틴맥봇)](https://www.youtube.com/@captainmacbot).
