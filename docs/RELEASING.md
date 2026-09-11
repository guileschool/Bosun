# Release guide

## Local preview

Run `SIGN_IDENTITY=- zsh build.sh` and `zsh scripts/test.sh`.
To create an ad-hoc signed, unnotarized DMG, run `zsh scripts/package-dmg.sh --preview`.
The package contains Bosun, an Applications shortcut, and bilingual installation instructions.

Generated apps, DMGs, logs, credentials, and build caches are excluded from source control.

## Public distribution

1. Keep the MIT LICENSE file and its copyright notice in the published source.
2. Review all tracked files and any repository history for personal or confidential data.
3. Complete all checks listed in docs/VALIDATION.md, including all current spoken commands and English/Korean target-app behavior.
4. Set `SIGN_IDENTITY` to a Developer ID Application identity and `NOTARY_PROFILE` to an existing notarytool keychain profile. Never commit credentials or signing keys.
5. Run `zsh scripts/package-dmg.sh --release`. The script signs, notarizes, staples, verifies, and writes a SHA-256 checksum.
6. Verify installation and operation of the packaged app on another Mac.
7. Attach the verified DMG and checksum to a GitHub release after the owner approves publication.

The bundle identifier is `com.jcutplus.bosun`. Preserve it and the signing identity for installed updates. The default build targets Apple Silicon. Intel builds are not a verified support claim.

This identifier replaces the local development identity. Existing development installations may require permission approval again, reconfiguration of preferences, and re-registration of the login item. Validate those transitions before replacing a development installation. Do not assume the old permissions or preferences migrate automatically.
