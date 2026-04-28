# Security Audit: 2026-04-28

## Executive Summary

This audit covered the current `gmax` repository on the
`release/dmg-distribution` branch, with special attention to local DMG signing
and notarization, shell integration, browser panes, persistence, CI, and
committed repository material.

No committed secrets, Developer ID certificates, private keys, notarization
credentials, app-specific passwords, DMG assets, or build artifacts were found
in tracked source. The new local notarization direction is appropriate for this
repo because it keeps signing credentials on Gale's machine instead of exposing
them to GitHub-hosted CI.

The main remaining security risks are privacy and trust-boundary issues that
come from the product's core job: `gmax` runs an unsandboxed local terminal,
embeds a WebKit browser, and persists terminal/browser state for restoration.
Those features are useful, but they should be treated as sensitive surfaces.

## High Severity

### H1: Terminal transcripts and launch environments persist sensitive data in plaintext

Impact: a command that prints a token, secret, private URL, or other sensitive
value can be restored, indexed, and stored on disk in the workspace database.

Evidence:

- `TerminalPaneController.captureHistory()` captures terminal text from host
  output, terminal buffer data, or selected terminal text:
  `gmax/Terminal/Panes/TerminalPaneController.swift:101-137`
- Captured transcript text is capped to 250,000 characters, but not redacted:
  `gmax/Terminal/Panes/TerminalPaneController.swift:215-225`
- Workspace persistence stores the launch executable, arguments, full encoded
  launch environment, current directory, transcript, and preview text:
  `gmax/Persistence/Workspace/WorkspacePersistenceController.swift:835-849`
- The Core Data model includes plaintext `environmentData`, `transcript`, and
  `previewText` fields:
  `gmax/Persistence/Workspace/WorkspacePersistenceController+CoreData.swift:309-321`
- Search indexing includes full transcript text, making sensitive terminal
  output searchable and duplicated into `searchText`:
  `gmax/Persistence/Workspace/WorkspacePersistenceController.swift:1202-1219`

Risk notes:

This is not a remote code execution issue, and it is partly expected for a
terminal-restoration app. The concern is that restoration currently treats all
terminal output and environment values as safe to persist.

Recommended follow-up:

- Add a user-facing setting that disables terminal transcript persistence.
- Consider making transcript persistence opt-in, or at least excluding
  transcript text from search indexing by default.
- Filter obvious secret-bearing environment keys before persistence, such as
  names containing `TOKEN`, `SECRET`, `PASSWORD`, `KEY`, `AUTH`, `CREDENTIAL`,
  and related variants.
- Document that workspace restoration stores terminal output and launch
  context locally.

## Medium Severity

### M1: Browser panes allow and restore `file:` URLs while JavaScript is enabled

Impact: a browser pane can load local files, and restored browser history can
reopen persisted `file:` URLs; combined with an unsandboxed app, this expands
the local data exposure surface.

Evidence:

- Browser URL normalization accepts `file` alongside `http`, `https`, and
  `about`:
  `gmax/Browser/Panes/BrowserPaneController.swift:32-35`
- The navigation delegate treats `file` as an internal scheme rather than
  opening it externally or blocking it:
  `gmax/Browser/Panes/BrowserPaneView+Coordinator.swift:188-194`
- The WebKit configuration uses the shared default website data store and
  enables page JavaScript:
  `gmax/Browser/WebKit/BrowserWebViewFactory.swift:54-64`
- Browser history persists visited URLs and titles:
  `gmax/Persistence/Workspace/WorkspacePersistenceController.swift:853-865`

Risk notes:

Loading local files may be useful during development, but the repo does not yet
document that `file:` is an intentional browser-pane capability. If it is not a
product requirement, it should be blocked before public DMG distribution. If it
is intentional, it needs a narrower policy and explicit docs.

Recommended follow-up:

- Decide whether browser panes should support `file:` URLs at all.
- If not required, remove `file` from allowed navigation schemes.
- If required, prefer explicit user-entered `file:` navigation only, avoid
  restoring arbitrary persisted `file:` history automatically, and document the
  local-file behavior.

### M2: The app is unsandboxed while embedding both terminal and browser capabilities

Impact: if WebKit content, shell integration, or future browser features are
compromised, the app process is not constrained by the App Sandbox.

Evidence:

- The app target has `ENABLE_APP_SANDBOX = NO` for Debug and Release:
  `gmax.xcodeproj/project.pbxproj:465`
  `gmax.xcodeproj/project.pbxproj:500`
- The same app embeds an interactive terminal launch environment:
  `gmax/Terminal/Launching/TerminalLaunchContextBuilder.swift:17-47`
- The same app embeds WebKit browser panes:
  `gmax/Browser/WebKit/BrowserWebViewFactory.swift:54-64`

Risk notes:

A terminal app may need to be unsandboxed to behave like a normal developer
tool. That can be a valid product decision. The security issue is that this
decision is not yet captured as an explicit threat-model exception, especially
now that browser panes and public DMG distribution are becoming real.

Recommended follow-up:

- Add a short maintainer threat model explaining why App Sandbox is disabled.
- Keep browser features conservative while unsandboxed.
- Revisit sandboxing if `gmax` later adds file import/export, credential
  migration, extension loading, or browser automation features.

### M3: Local notarized DMG packaging originally built from the post-merge checkout rather than the release tag

Impact: a GitHub release tag could point at one commit while the signed DMG
asset was built from another commit, weakening release provenance and making
future incident review harder.

Evidence before the fix:

- The release flow created the release object and then packaged local DMG
  assets after `fast_forward_base_branch`.
- The release tag is created before PR merge, so the post-merge checkout can be
  a merge commit rather than the tagged release-candidate commit.

Fix applied during this audit:

- `scripts/repo-maintenance/release.sh` now packages the DMG after CI and PR
  comment checks, before merging the PR.
- The packaging step verifies that `HEAD` exactly matches `$RELEASE_TAG` before
  signing and notarization.
- Upload still happens after merge and GitHub release creation.

Fixed in working tree:

- `scripts/repo-maintenance/release.sh:307-397`
- `docs/maintainers/dmg-distribution-plan.md:176-206`

## Low Severity

### L1: CI uses floating third-party action and latest Homebrew packages

Impact: CI behavior can drift when `actions/checkout@v4`, `swiftformat`, or
`swiftlint` changes upstream, which can weaken reproducibility and make release
failures harder to attribute.

Evidence:

- CI uses `actions/checkout@v4` instead of a pinned commit SHA:
  `.github/workflows/validate-repo-maintenance.yml:17`
- CI installs the latest `swiftformat` and `swiftlint` from Homebrew on each
  run:
  `.github/workflows/validate-repo-maintenance.yml:18-19`

Recommended follow-up:

- Pin GitHub Actions by commit SHA if the repo wants stronger supply-chain
  reproducibility.
- Consider installing known tool versions or documenting that CI intentionally
  tracks latest Homebrew formatter/linter packages.

### L2: Shell integration wrapper files are rewritten without explicit file mode checks

Impact: a local same-user process could tamper with generated shell integration
files in Application Support and affect future shell launches.

Evidence:

- Shell integration files are written under Application Support:
  `gmax/Terminal/Launching/ShellIntegrationSupport.swift:24-29`
- Writes create parent directories and use atomic data writes, but do not
  explicitly set restrictive permissions or reject symlinked destinations:
  `gmax/Terminal/Launching/ShellIntegrationSupport.swift:31-48`

Risk notes:

This is a local same-user tampering concern, not a cross-user vulnerability.
It is lower priority than transcript persistence and browser policy.

Recommended follow-up:

- Consider setting directory and file permissions for generated integration
  files.
- Consider refusing to overwrite symlinked integration destinations unless the
  symlink target is inside the expected wrapper directory.

## Positive Findings

- No tracked DMG, archive, certificate, private key, `.p12`, `.pem`, `.key`,
  `.mobileprovision`, or build artifact was found in `git ls-files`.
- GitHub Actions does not import signing credentials or notarization
  credentials.
- The DMG/notarization guidance correctly keeps Developer ID and notary
  credentials local for now.
- `package-notarized-dmg.sh` uses a local `notarytool` keychain profile rather
  than accepting Apple credentials as command-line arguments.
- `build/` is ignored, so generated DMGs and archives are not staged by normal
  source commits.

## Recommended Priority Order

1. Add a privacy control for terminal transcript persistence and redact obvious
   secret-bearing launch environment keys before storing session snapshots.
2. Decide whether `file:` browser navigation is an intentional product feature;
   block it if not.
3. Capture the unsandboxed terminal-plus-browser threat model in maintainer
   docs before the first public notarized DMG.
4. Pin or consciously document floating CI dependencies.
5. Harden shell integration wrapper file permissions if local tampering becomes
   part of the threat model.
