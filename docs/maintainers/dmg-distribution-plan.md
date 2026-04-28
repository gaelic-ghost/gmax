# DMG Distribution Plan

## Current Answer

Yes, `gmax` can publish a downloadable DMG through GitHub Releases.

The repository is public, so standard GitHub-hosted Actions runners do not
consume the private-repository free-plan minute quota. GitHub Releases also
support binary assets directly: a release can have up to 1000 assets, each
asset must be under 2 GiB, and GitHub does not set a total release size or
bandwidth quota for those release assets.

The current local Release build is small:

- `gmax.app`: about 8.3 MB
- compressed DMG probe: about 2.5 MB

So GitHub storage and asset-size limits are not the blocker.

## Apple Distribution Requirement

A DMG that users can download is easy. A DMG that opens without Gatekeeper
friction requires Apple distribution signing and notarization.

Apple's documented direct-distribution path is:

1. Archive the macOS app.
2. Export a distribution-signed app with Developer ID signing.
3. Package the exported app into the final distributable format.
4. Notarize the distributed software with Apple's notary service.
5. Staple the notarization ticket.
6. Publish the final artifact.

For `gmax`, the final distributable format is a compressed UDIF DMG containing
`Gmax.app` and an `/Applications` symlink.

## Credential And Fork Safety Model

`gmax` must not store Developer ID certificates, private keys, notary
credentials, app-specific passwords, App Store Connect API keys, exported
keychains, or base64-encoded credential blobs in the repository.

The local release path uses credentials already installed on Gale's Mac:

- a Developer ID Application certificate in the login keychain, available to
  Xcode's archive export workflow
- a local `notarytool` keychain profile named `gmax-notary`

Create the notary profile locally with:

```sh
xcrun notarytool store-credentials gmax-notary \
  --apple-id <apple-id> \
  --team-id BC73766F69 \
  --password <app-specific-password>
```

This keeps signing and notarization local. Forks of the public repository can
run the open-source build and packaging scripts, but they cannot sign as Gale
unless they separately possess Gale's private Developer ID signing key and
notary credentials.

If CI signing is added later, it must be protected as release infrastructure,
not ordinary CI:

- use a protected GitHub Environment such as `release-signing`
- expose signing secrets only to trusted tag or release workflows
- do not expose signing secrets to `pull_request` workflows
- do not use `pull_request_target` for workflows that run repository scripts
  while holding signing secrets
- require a human environment approval before any job imports a Developer ID
  certificate or accesses notary credentials
- never run unreviewed contributor-controlled code in a job that has signing
  secrets

GitHub-hosted signing is feasible, but it is intentionally not the first
implementation for this project.

## Current Project Audit

The current project is close on build settings but is not distribution-ready
through a normal Release build alone:

- Hardened Runtime is enabled for `gmax`.
- The target has `SKIP_INSTALL=NO`, so `xcodebuild archive` can produce an
  installable app archive.
- The bundle identifier is `com.galewilliams.gmax`.
- The development team is `BC73766F69`.
- The normal Release build signs with `Apple Development: Gale Williams`, not
  a `Developer ID Application` certificate.
- The local build probe included `com.apple.security.get-task-allow`, which is
  unsuitable for notarized distribution when set to `true`.
- No GitHub workflow currently imports signing credentials or performs
  notarization.
- The repo-maintenance release script creates and publishes GitHub release
  objects, but previously did not package or attach DMG assets.

That means the compliant path is: archive/export specifically for Developer ID,
then package and notarize that exported app. Do not treat a normal local
Release build as the public distribution app.

## Local DMG Packaging

Use `scripts/package-dmg.sh` when only the DMG container shape needs to be
tested:

```sh
scripts/package-dmg.sh --version v0.1.6
```

The script builds `gmax.app`, stages it beside an `/Applications` symlink, and
creates:

- `build/distribution/Gmax-v0.1.6.dmg`
- `build/distribution/Gmax-v0.1.6.dmg.sha256`

For distribution, prefer the notarized script below because it archives and
exports a Developer ID signed app before packaging.

## Local Notarized Release DMG

Use `scripts/package-notarized-dmg.sh` for the public downloadable artifact:

```sh
scripts/package-notarized-dmg.sh --version v0.1.6 --upload-release v0.1.6
```

The script performs the full local path:

1. `xcodebuild archive`
2. `xcodebuild -exportArchive` with
   `scripts/export-options-developer-id.plist`
3. `scripts/package-dmg.sh --app-path <exported app>`
4. `xcrun notarytool submit --keychain-profile gmax-notary --wait`
5. `xcrun stapler staple`
6. `xcrun stapler validate`
7. `spctl --assess --type open`
8. `shasum -a 256`
9. optional `gh release upload --clobber`

The generated files are:

- `build/distribution/Gmax-v0.1.6.dmg`
- `build/distribution/Gmax-v0.1.6.dmg.sha256`
- `build/distribution/Gmax-v0.1.6.xcarchive`
- `build/distribution/export-v0.1.6/`

`build/` is ignored by git, so release artifacts stay out of source control.

If notarization credentials are not available yet, use `--skip-notarize` only
for local packaging validation. Do not upload a skipped-notarization artifact
as the public release DMG.

## Existing Release Flow Integration

The standard release script packages, notarizes, staples, verifies, and uploads
the local DMG by default because `scripts/repo-maintenance/config/release.env`
sets:

```sh
REPO_MAINTENANCE_PACKAGE_LOCAL_DMG=true
```

Use the normal release command when a public release should include the signed
and notarized DMG assets:

```sh
scripts/repo-maintenance/release.sh --mode standard --version v0.1.6
```

The explicit `--package-local-dmg` flag is still supported when a caller wants
to override a temporary environment default. Use `--skip-local-dmg` only for an
intentional release that should create the tag and GitHub release object without
uploading DMG assets.

The release flow remains review-first:

1. validate
2. bump versions
3. tag the release candidate
4. push the branch and tag
5. open or update the release PR
6. wait for CI
7. stop on unresolved comments unless explicitly acknowledged
8. merge the PR
9. fast-forward local `main`
10. create the GitHub release object
11. package, notarize, staple, verify, and upload the local DMG assets

The DMG step runs only after the reviewed code is merged and the GitHub release
object exists. It runs on the local machine, using the local keychain and local
notary profile. CI does not receive signing credentials.

If `--skip-gh-release` is used while local DMG packaging is enabled, the release
script stops because there is no GitHub release object to receive the DMG
assets. Pair `--skip-gh-release` with `--skip-local-dmg`, or package manually
with `scripts/package-notarized-dmg.sh` if an offline artifact is needed.

## Validation Notes

Local probe commands run during this investigation:

```sh
xcodebuild -project gmax.xcodeproj -scheme gmax -configuration Release -derivedDataPath /private/tmp/gmax-dmg-probe-derived build
codesign --display --verbose=4 /private/tmp/gmax-dmg-probe-derived/Build/Products/Release/gmax.app
hdiutil create -volname Gmax -srcfolder /private/tmp/gmax-dmg-probe-stage -ov -format UDZO /private/tmp/Gmax-probe.dmg
hdiutil imageinfo /private/tmp/Gmax-probe.dmg
```

The first sandboxed `hdiutil create` attempt failed with `Device not
configured`. Running `hdiutil` outside the sandbox succeeded, so DMG creation
needs access to macOS disk-image services.
