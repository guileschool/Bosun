# Using Bosun

[한국어](USAGE.ko.md) · [Overview](../README.md)

## Requirements and installation

Use an Apple Silicon Mac running macOS 14 or later. On-device English speech recognition must be available. Download the signed and Apple-notarized DMG from [release 0.8.13](https://github.com/guileschool/Bosun/releases/latest). Access requires permission while the repository is private.

Open the DMG, drag Bosun into Applications, and launch it there. Bosun appears in the menu bar. Grant Microphone, Speech Recognition, and Accessibility permissions in System Settings → Privacy & Security. Use the same Developer ID signed app for updates to preserve existing permissions.

For a local source build, follow the build instructions in the overview. An ad-hoc test build is not a replacement for a signed installed app.

## Updates

Choose **Check for Updates…** from the Bosun menu to download and install a new version. Enable **Automatically Check for Updates** in Settings to receive update notifications. Installation requires your confirmation; Bosun then restarts.

**Using 0.8.12 or earlier?** Quit Bosun and replace it in Applications with the latest DMG once. In-app updates are available starting with 0.8.13.

## First use

1. Open the target ChatGPT desktop input window.
2. Open Bosun in the menu bar and start listening.
3. Choose phrase mode for English dictation. The menu language is independent of command mode.
4. Say “Record, please”, speak a short sentence, then say “Stop, please”. Verify that recording stops and your text remains in the input.
5. Check the text before choosing to send it. “Send, please” sends the input after finishing dictation and cleaning the trailing command.

Use “Cancel, please” to discard dictation. “Break, please” interrupts pending submission or response generation; it does not recall a message already sent. Other commands are listed in the overview. “Undo” restores only the most recent Bosun Delete or Clear once, while the same input remains unchanged.

## Troubleshooting

| Symptom | Check |
|---|---|
| No command is detected | Confirm listening is on, microphone permission is allowed, and the selected mode matches your phrase. |
| The command is detected but nothing happens | Confirm Accessibility permission and that the intended target input window is available. |
| Recording does not stop | Use the target app's own stop control, then check Bosun's diagnostic menu and report the failure. |
| The transcript is not sent | Review the input and error state before retrying; confirm it was not already sent. |
| Undo has no effect | It only restores Bosun's last Delete or Clear in the unchanged input. |
| Problems after an update | Check permissions and confirm the app is installed in Applications with the expected signing identity. |

Hold Option when opening Bosun's menu to reveal diagnostics. Reports can contain recognized words or input text. Share only a minimal redacted example. Target-app UI changes can affect automation. See [current validation limits](VALIDATION.md).

## Questions and bug reports

Use this repository's Issues when available. Korean and English reports are welcome; real-time English support is not promised. Include the Bosun version, macOS version, target app name/version and interface language, command mode, exact command, expected result, and actual result. Do not include credentials or personal transcripts.

No subscription, channel follow, or purchase is required to use Bosun.
