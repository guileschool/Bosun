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

## In-app updates (0.8.13+)

The build downloads Sparkle 2.9.6 from its official release and verifies a pinned SHA-256 checksum before extracting it. The framework and its helpers are signed before the outer app. Third-party notices ship in the app resources.

The release script also signs the final stapled DMG and generates a signed `dist/appcast.xml`. The Ed25519 private key is held in the login keychain under account `com.jcutplus.bosun.sparkle`; `SPARKLE_KEY_ACCOUNT` can override the account only when its public key matches `SUPublicEDKey`. Preserve this private key securely across releases. Never commit or export it into the repository.

1. Increase both `CFBundleShortVersionString` and `CFBundleVersion` in Info.plist.
2. Update the user-facing release notes in scripts/make-appcast.py for that release.
3. Complete the signed/notarized release packaging above. Inspect the generated feed and verify its signature using Sparkle's `sign_update --account com.jcutplus.bosun.sparkle --verify dist/appcast.xml`.
4. Upload the DMG and checksum to the matching stable GitHub release. Check that its anonymous download works and the downloaded checksum matches.
5. Only after the assets are available, copy `dist/appcast.xml` to `docs/appcast.xml`, commit it, and push main. Do not reformat the signed feed afterward.
6. Verify that the public feed is reachable and signed. Test update detection, installation, relaunch, and the resulting app signature with an older updater-enabled installation. `--check-for-updates` starts an update-only session without starting voice recognition or registering a login item.
7. Confirm the installed version reports that it is up to date. Keep previous releases available.

Version 0.8.12 and earlier do not include an updater; users must replace that installation using a DMG once. Automatic checks are optional, and installation always needs user confirmation. The app requires signatures on both the update feed and archive and verifies the archive before extraction.

Official reference: https://sparkle-project.org/documentation/publishing/
