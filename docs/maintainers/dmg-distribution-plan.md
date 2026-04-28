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

A DMG that users can download is easy. A DMG that opens without scary
Gatekeeper friction requires Apple distribution signing and notarization.

Apple's documented direct-distribution path is:

1. Archive the macOS app.
2. Export a distribution-signed app with Developer ID signing.
3. Notarize the distributed software with Apple's notary service.
4. Staple the notarization ticket.
5. Package and publish the final artifact.

The current project is close on project settings but not distribution-ready
by itself:

- Hardened Runtime is enabled for `gmax`.
- The Release build currently signs with `Apple Development: Gale Williams`,
  not a `Developer ID Application` certificate.
- The generated Release entitlements include `com.apple.security.get-task-allow`
  in the local probe, which Apple documents as unsuitable for notarized
  distribution.

That means a GitHub-hosted DMG can exist before notarization, but it should be
treated as a developer/test artifact rather than the public installer.

## Recommended Shape

### Phase 1: Local DMG Packaging

Use `scripts/package-dmg.sh` to create a repeatable local DMG from a Release
build:

```sh
scripts/package-dmg.sh --version v0.1.6
```

The script builds `gmax.app`, stages it beside an `/Applications` symlink, and
creates:

- `build/distribution/Gmax-v0.1.6.dmg`
- `build/distribution/Gmax-v0.1.6.dmg.sha256`

This is useful immediately for manual testing and for proving the artifact
shape before CI gets secrets.

### Phase 2: Release Asset Upload

Once the artifact is trusted, attach it to a GitHub release with:

```sh
gh release upload v0.1.6 build/distribution/Gmax-v0.1.6.dmg build/distribution/Gmax-v0.1.6.dmg.sha256
```

This can be folded into the repo release script after the signing story is
settled.

### Phase 3: CI Signing And Notarization

For a fully automated GitHub-hosted release, CI needs:

- Developer ID Application certificate exported as a protected secret.
- Certificate password stored as a protected secret.
- Temporary keychain setup in the workflow.
- Apple notary credentials stored as protected secrets.
- `xcodebuild archive` / `xcodebuild -exportArchive` or an equivalent
  Developer ID signing path.
- `xcrun notarytool submit --wait`.
- `xcrun stapler staple` for the notarized artifact.
- DMG packaging and `gh release upload`.

This is feasible on GitHub Free for this public repo, but certificate and
notary credentials are the high-risk part. Keep them scoped to release-only
workflows and protected repository environments before enabling automatic
publishing.

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
