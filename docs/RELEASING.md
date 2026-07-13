# Releasing Wee Orchestrator for macOS

The macOS app uses Semantic Versioning: `MAJOR.MINOR.PATCH`.

- Increment **MAJOR** for incompatible user-facing or configuration changes.
- Increment **MINOR** for backward-compatible features.
- Increment **PATCH** for backward-compatible fixes.
- Increment `CURRENT_PROJECT_VERSION` for every published build. It is the
  macOS bundle build number; `MARKETING_VERSION` is the user-visible SemVer.

The authoritative macOS release is published in the
[Wee-Orchestrator API repository](https://github.com/leprachuan/Wee-Orchestrator/releases),
so the downloadable app and the compatible API contract appear together.

## Development and release policy

Development may happen on any branch, including `main`. Direct commits to
`main` are permitted; feature branches and pull requests are optional tools for
collaboration, not release gates. Branches are not user-facing distribution
channels: only a tested, versioned GitHub Release is an app build we give out.

## Release naming

- GitHub release tag: `macos-vMAJOR.MINOR.PATCH`
- Release title: `Wee Orchestrator for macOS vMAJOR.MINOR.PATCH`
- Asset: `WeeOrchestrator-macOS-vMAJOR.MINOR.PATCH.zip`
- Checksum asset: `WeeOrchestrator-macOS-vMAJOR.MINOR.PATCH.zip.sha256`

For example, the first SemVer release is `macos-v0.2.0` with the asset
`WeeOrchestrator-macOS-v0.2.0.zip`.

## Checklist

1. Select the exact tested, committed revision to release. Update
   `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project, and
   record user-visible changes in the release notes.
2. Build and test the app:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -project WeeOrchestrator.xcodeproj -scheme WeeOrchestrator \
     -configuration Release test CODE_SIGNING_ALLOWED=NO
   ```

3. Build a Release archive, sign the `.app`, verify its signature, then create
   a zip containing the app bundle. Publish it to the API repository with the
   tag and asset names above, **including the `.zip.sha256` checksum asset**.
   The in-app updater verifies this checksum before it installs an update.
4. Verify the GitHub release asset and the app's `CFBundleShortVersionString`
   and `CFBundleVersion` before announcing it.

Release artifacts must never contain API tokens, local shared keys, OpenRouter
keys, or bot credentials. Ad-hoc signed builds should disclose that macOS may
require an initial Open/allow action when the app is not notarized.
