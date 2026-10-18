# GitHub macOS releases

GitHub releases use the `today-md-github` Xcode scheme. The existing `today-md` scheme builds the App Store edition and has no Sparkle dependency. Both targets use `Config/Version.xcconfig` for the public version and numeric build number.

The stable update feed is [`releases/latest/download/appcast.xml`](https://github.com/arthurliebhardt/today-md/releases/latest/download/appcast.xml). Each enclosure uses its immutable tagged release URL. Sparkle verifies the signed feed before reading it and verifies the Ed25519 archive signature before extraction. Release notes are embedded inside the signed feed, so the updater does not fetch a separate notes page.

Users of an older GitHub build without Sparkle must manually install the first updater-enabled release once. Subsequent GitHub releases update inside the app. The App Store edition continues to update through Apple.

## One-time setup

1. In Apple Developer Certificates, create a **Developer ID Application** certificate for the team that owns `com.today-md.app`. A development or Apple Distribution certificate cannot sign this release. Export that certificate and its private key from Keychain Access as a password-protected `.p12` file. Keep its backup in a password manager.
2. Create a team App Store Connect API key with access to notarization, download its `.p8` file, and record its Key ID and Issuer ID. This workflow uses API-key authentication with `notarytool`, not an Apple ID password. Keep the key backup in a password manager.
3. Download the official [Sparkle 2.10.0 release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0). Its `Sparkle-2.10.0.tar.xz` SHA-256 is `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`. Verify it before running its tools. Run `bin/generate_keys --account today-md` on a trusted Mac. It stores the signing key in Keychain and prints the public key. Export the private key with `bin/generate_keys --account today-md -x /absolute/private/path/sparkle-private-key.txt`, save it in a password manager, then remove the exported file after configuring GitHub. Never commit that key. Preserve this key across releases, since installed apps trust its public half.
4. In GitHub repository Settings, create an environment named **macos-release** restricted to release tags matching `v*`, and **macos-rehearsal** restricted to branches matching `codex/rehearse-macos-*`. A reviewer gate is optional. Put the secrets and variables below at repository level so both environments can use them, or configure the same values separately in both environments. Restrict release-tag creation and rehearsal-branch pushes to trusted maintainers. The workflow does not run for pull requests.

| GitHub setting | Value |
| --- | --- |
| Secret `MACOS_SIGNING_P12` | Base64 of the exported `.p12` bytes, as one line |
| Secret `MACOS_SIGNING_P12_PASSWORD` | The export password |
| Secret `ASC_KEY_ID` | App Store Connect API Key ID |
| Secret `ASC_ISSUER_ID` | App Store Connect API Issuer ID |
| Secret `ASC_PRIVATE_KEY_P8` | Raw multiline contents of the downloaded `.p8` file |
| Secret `SPARKLE_PRIVATE_KEY` | Exact base64 contents exported by Sparkle `generate_keys -x` |
| Variable `MACOS_TEAM_ID` | Apple Developer Team ID, for example the team shown in the certificate |
| Variable `SPARKLE_PUBLIC_ED_KEY` | Base64 public key printed by Sparkle `generate_keys` |

For `.p12` encoding, `base64 -i /absolute/private/path/DeveloperID.p12 | tr -d '\n'` produces the required value. Transfer it directly into the secret field without saving it in the repository. The `.p8` and Sparkle private-key secrets are **not** base64-encoded a second time. The workflow token needs repository Contents write permission to create releases; it does not need a personal access token.

The public key is injected into the signed app through the `SPARKLE_PUBLIC_ED_KEY` build setting. A release with a missing, malformed, or mismatched key fails verification. Local GitHub builds can pass that public build setting explicitly. Unsigned development builds with no configured key show updates as unavailable.

## Publish a version

1. Increase `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `apps/macos/Config/Version.xcconfig`. The public version must be a stable `X.Y.Z`; every release must increase the numeric build, including rebuilds. Both targets inherit these values.
2. Commit and merge the intended release source, then create and push its corresponding tag, for example `v1.8.1`. A tag must exactly match the public version in the archive. Do not move or reuse release tags.
3. The **Release macOS app** workflow archives a universal Apple silicon and Intel app, signs it and all nested Sparkle helpers, notarizes it with Apple, staples the ticket, and validates Gatekeeper acceptance. It produces a ZIP, dSYM ZIP, signed appcast, provenance metadata, and `SHA256SUMS`.
4. The workflow uploads the archives and metadata to a new draft release, uploads the feed last, downloads the draft assets, and verifies their checksums and Ed25519 signatures. It then publishes the complete draft as latest. Until this final promotion, the currently published update feed stays in place. Existing release assets are never overwritten.

For a signing rehearsal, run **Release macOS app** manually with an existing version tag and leave **Publish** unchecked. When the release environment is restricted to tags, dispatch the workflow from that same tag, for example `gh workflow run release-macos.yml --ref v1.8.1 -f tag=v1.8.1 -f publish=false`. It performs signing, notarization, appcast generation, and verification, then stores the result as a workflow artifact without creating a GitHub release. Notarization contacts Apple even during a rehearsal. A rehearsal requires the same signing configuration as a release. CI explicitly selects Xcode 26.3 on the `macos-15` runner because its default Xcode is older; local builds require Swift 6.2 or newer.

To test changes before this workflow is merged or registered on the default branch, push the intended commit to a branch named `codex/rehearse-macos-<name>`. That branch push runs the workflow from the exact triggering commit in the **macos-rehearsal** environment. The runner creates a local synthetic `v<MARKETING_VERSION>` tag at that commit for the existing packaging checks, then sets `RELEASE_TAG` for the build. It rejects an existing local version tag that points elsewhere, so increase the version first if its tag is already in use. The synthetic tag is never pushed. This flow performs real signing and Apple notarization and retains verified files as a workflow artifact, without creating a remote tag, draft release, published release, or changing the stable update feed.

The publication step requires the workflow ref to be a tag and either a version-tag push or a manual dispatch with **Publish** enabled. A rehearsal-branch push cannot publish. A manual request to publish from a branch is rejected explicitly; run that workflow from an existing version tag instead.

Published artifacts are immutable. If a run stops after creating its draft, inspect that draft and the failure before retrying. Either finish publication of those exact verified bytes or delete the unpublished draft and rebuild, depending on the failure. Never replace an asset from an already published release. GitHub's repository-level immutable-release setting can further enforce this policy. If a broken release was published, ship a corrected release with a higher build number rather than moving the stable feed backwards.

## Verification and local tooling

Run the release checks without credentials:

```bash
python3 -m unittest discover -s apps/macos/scripts/tests -v
bash -n apps/macos/scripts/release-macos.sh
bash -n apps/macos/scripts/publish-macos-release.sh
```

The macOS tests generate temporary in-memory signing keys, verify valid feed and archive signatures, and reject tampered feeds, tampered archives, wrong public keys, unsigned feeds, and mutable download URLs. They do not access Keychain or Apple services.

To verify a downloaded feed and archive independently with the public key:

```bash
SPARKLE_PUBLIC_ED_KEY='the public key shipped in the app' \
  bash apps/macos/scripts/verify-sparkle-release.sh \
  /absolute/path/appcast.xml /absolute/path/today-md-v1.8.1-macos.zip v1.8.1 32
```

The `.mac-release.env` manifest supports the installed `release-mac-app` skill's status and verification commands. CI uses the portable scripts in this repository and does not require the skill or a developer's filesystem. Local shared-helper checks default to the `today-md` Sparkle Keychain account; the portable CI script receives its signing inputs only through explicitly supplied environment variables. Never pass private keys on command-line arguments or enable shell tracing while signing.

The signing script creates a dedicated temporary keychain, imports only the CI certificate, checks signing access before building, preserves the prior keychain search list, and restores it while deleting temporary key material on exit. The Sparkle secret is passed to its signing tools through standard input. The signed-feed format has an embedded signature comment; no detached `.sig` asset is needed. Do not edit generated `appcast.xml` after signing.

Before announcing the first release, install an older updater-enabled GitHub build in Applications and test **Check for Updates…** through download, install, and relaunch. Confirm unsaved task edits, SQLite data, folder sync, and automatic-check preferences survive the upgrade. Also confirm an App Store archive has neither Sparkle nor updater controls. Automated release validation checks signatures and packaging; it does not exercise this live upgrade with production certificates.

References: [Sparkle publishing](https://sparkle-project.org/documentation/publishing/), [Sparkle sandboxing](https://sparkle-project.org/documentation/sandboxing/), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
