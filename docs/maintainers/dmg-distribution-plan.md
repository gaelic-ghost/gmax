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

Check the local signing identity with:

```sh
security find-identity -v -p codesigning
```

The output must include a `Developer ID Application` identity for team
`BC73766F69`. An `Apple Development` identity can build and run the app locally,
but it cannot export the direct-distribution app used for the public DMG.
The local packaging script defaults to
`Developer ID Application: Gale Williams (BC73766F69)`. Override that only when
the repo's signing owner changes:

```sh
GMAX_DEVELOPER_ID_APPLICATION_IDENTITY="Developer ID Application: Example (TEAMID)" \
  scripts/package-notarized-dmg.sh --version v0.1.6
```

Create the notary profile locally with:

```sh
xcrun notarytool store-credentials gmax-notary \
  --apple-id <apple-id> \
  --team-id BC73766F69 \
  --password <app-specific-password>
```

Verify the local profile before spending time on archive/export work:

```sh
xcrun notarytool history --keychain-profile gmax-notary
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
2. archive with `MARKETING_VERSION` set from the release tag, so the exported
   app's `CFBundleShortVersionString` matches the DMG release version without
   direct project-file edits
3. `xcodebuild -exportArchive` with
   `scripts/export-options-developer-id.plist`
4. verify the exported app's `CFBundleShortVersionString`
5. `scripts/package-dmg.sh --app-path <exported app>`
6. sign the DMG with the Developer ID Application identity
7. `xcrun notarytool submit --keychain-profile gmax-notary --wait`
8. `xcrun stapler staple`
9. `xcrun stapler validate`
10. `spctl --assess --type open --context context:primary-signature`
11. `shasum -a 256`
12. optional `gh release upload --clobber`

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
REPO_MAINTENANCE_SKIP_VERSION_BUMP=true
REPO_MAINTENANCE_PACKAGE_LOCAL_DMG=true
```

`REPO_MAINTENANCE_SKIP_VERSION_BUMP=true` is intentional for this Xcode project:
the release artifact version is injected at archive time from the release tag
and verified from the exported app's `Info.plist`, rather than editing
`gmax.xcodeproj/project.pbxproj` directly during release.

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
8. verify that `HEAD` still matches the release tag
9. preflight the local Developer ID signing identity and notary profile
10. package, notarize, staple, and verify the local DMG assets from the tagged
   release candidate
11. merge the PR
12. fast-forward local `main`
13. create the GitHub release object
14. upload the local DMG assets

The DMG packaging step runs only after CI and the review-comment gate pass, but
before the branch is merged, so the signed artifact is built from the exact
commit named by the release tag. The upload step runs only after the reviewed
PR is merged and the GitHub release object exists. Both steps run on the local
machine, using the local keychain and local notary profile. CI does not receive
signing credentials.

The release script also retries briefly when GitHub has created the pull
request but has not yet reported any check runs. That keeps a healthy release
from stopping just because the CI provider is a few seconds behind the PR.

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
