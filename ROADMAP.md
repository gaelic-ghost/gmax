# gmax Roadmap

## Table of Contents

- [Vision](#vision)
- [Product Principles](#product-principles)
- [Milestone Progress](#milestone-progress)
- [Milestone 1: Workspace and Pane Core](#milestone-1-workspace-and-pane-core)
- [Milestone 2: Terminal Product UX](#milestone-2-terminal-product-ux)
- [Milestone 3: Accessibility](#milestone-3-accessibility)
- [Milestone 4: Preferences and Customization](#milestone-4-preferences-and-customization)
- [Milestone 5: Persistence and Sync Follow-Through](#milestone-5-persistence-and-sync-follow-through)
- [Milestone 6: Quality and Release Readiness](#milestone-6-quality-and-release-readiness)
- [Milestone 7: Deeper Terminal Integrations / Remote / SSH / Etc.](#milestone-7-deeper-terminal-integrations--remote--ssh--etc)
- [Milestone 8: App Sandbox Compatibility](#milestone-8-app-sandbox-compatibility)
- [Milestone 9: iOS Remote and iPadOS App](#milestone-9-ios-remote-and-ipados-app)
- [Milestone 10: Chromium Browser Pane](#milestone-10-chromium-browser-pane)
- [Milestone 11: Custom Codex App-Server Pane](#milestone-11-custom-codex-app-server-pane)
- [Backlog Candidates](#backlog-candidates)
- [History](#history)

## Vision

- Build `gmax` into a native-feeling macOS terminal workspace app where multi-window scene behavior, pane composition, persistence, and keyboard-first control all feel coherent enough to ship as a real product instead of a promising shell prototype.

## Product Principles

- Keep scene, focus, menu, and window behavior grounded in documented SwiftUI and AppKit primitives instead of custom routing infrastructure.
- Treat workspace and pane state as durable product data, not temporary UI convenience state.
- Prefer keyboard-first and accessibility-aware product decisions over chrome-heavy terminal mimicry.
- Keep observability, persistence, and future integrations explicit enough that maintainers can debug real user state without turning the app into a server-style telemetry project.

## Milestone Progress

- Milestone 1: Workspace and Pane Core - In Progress
- Milestone 2: Terminal Product UX - Planned
- Milestone 3: Accessibility - In Progress
- Milestone 4: Preferences and Customization - In Progress
- Milestone 5: Persistence and Sync Follow-Through - In Progress
- Milestone 6: Quality and Release Readiness - In Progress
- Milestone 7: Deeper Terminal Integrations / Remote / SSH / Etc. - Planned
- Milestone 8: App Sandbox Compatibility - Planned
- Milestone 9: iOS Remote and iPadOS App - Planned
- Milestone 10: Chromium Browser Pane - Planned
- Milestone 11: Custom Codex App-Server Pane - Planned

## Milestone 1: Workspace and Pane Core

### Status

In Progress

### Scope

- [ ] Finish the remaining multi-window command and close-behavior edges so the already-shipped workspace shell behaves predictably across multiple scene instances.

### Tickets

- [ ] Tighten remaining command-routing edge cases that only show up in multi-window use.

### Exit Criteria

- [ ] Multi-window workspace, pane, and close commands consistently target the frontmost scene-local context without mutating a background window.

## Milestone 2: Terminal Product UX

### Status

Planned

### Scope

- [ ] Replace the early shell chrome with calmer, more intentional terminal product behavior without undoing the existing split-pane workspace model.

### Tickets

- [ ] Replace scaffold-style pane controls with intentional terminal-native chrome.
- [ ] Improve close, focus, and split animations so the shell feels calmer.
- [ ] Add configurable startup behavior for new panes and new workspaces.
- [ ] Add pane-local tabs and reserve `cmd-t` for `New Tab` once the tab model exists.

### Exit Criteria

- [ ] The pane shell feels intentional enough that the current workspace model reads as product UI rather than scaffolding.

## Milestone 3: Accessibility

### Status

In Progress

### Scope

- [ ] Make the current shell meaningfully keyboard-reachable and screen-reader-auditable, while keeping `gmax`-specific shell affordances separate from any upstream SwiftTerm accessibility fixes.

### Tickets

- [ ] Audit the SwiftUI shell for keyboard-only reachability.
- [ ] Improve pane focus visibility and command discoverability.
- [ ] Design a practical Voice Control and Full Keyboard Access story.
- [ ] Integrate SpeakSwiftly for in-process custom TTS and STT.
- [ ] Evaluate small fine-tunes of FunctionGemma and STT for Voice Commands.
- [ ] Validate current SwiftTerm accessibility behavior under VoiceOver and Full Keyboard Access outside `gmax`-specific pane chrome.
- [ ] Identify the smallest macOS accessibility gaps in SwiftTerm's `TerminalView` and `LocalProcessTerminalView`.
- [ ] Prototype upstream-safe AppKit accessibility improvements that do not depend on `gmax` pane metadata or app-specific actions.
- [ ] Only deepen the currently limited macOS accessibility-service implementation in SwiftTerm where the gap is real and reproducible.
- [ ] Split app-local accessibility affordances from package-level terminal accessibility fixes so upstream scope stays clean.
- [ ] Prepare an isolated patch series and reproduction notes suitable for a SwiftTerm upstream contribution.

### Exit Criteria

- [ ] The main shell is usable in a keyboard-only pass, the primary accessibility gaps are documented precisely, and any SwiftTerm upstream work is separated from app-local accessibility follow-through.

## Milestone 4: Preferences and Customization

### Status

In Progress

### Scope

- [ ] Extend the existing settings surface from the current terminal appearance and persistence controls into a broader but still grounded customization model.

### Tickets

- [ ] Add import for theme and appearance settings.
- [ ] Add font, spacing, and terminal presentation settings.
- [ ] Add toolbar "preset" buttons for saving workspace layouts as "favorites".
- [ ] Add initial set of configurable keyboard shortcuts.
- [ ] Add custom actions or command presets worth persisting.

### Exit Criteria

- [ ] Settings cover the first real set of appearance, workspace-behavior, and shortcut customizations without fragmenting the app's command vocabulary.

## Milestone 5: Persistence and Sync Follow-Through

### Status

In Progress

### Scope

- [ ] Build on the shipped Core Data-backed multi-window workspace model with better diagnostics, a unified library surface for workspace and window items, and a deliberate decision about what future sync is actually worth carrying.

### Tickets

- [x] Unify workspace identity so live and saved-library flows use one durable `WorkspaceID`.
- [x] Add durable Core Data-backed window records for selection, open state, and window recency.
- [x] Move recent workspace reopen behavior onto durable window membership plus workspace recency.
- [ ] Add configurable transcript retention limits for saved workspace history.
- [ ] Decide whether deeper terminal history restore should stop at richer normal-buffer scrollback or eventually grow full alternate-buffer and emulator-state replay.
- [ ] Add crash-safe and operator-friendly persistence diagnostics.
- [x] Introduce a unified library listing surface that can hold both saved workspaces and saved windows.
- [ ] Revisit browser history restore so back-forward reconstruction does not have to replay real page loads for every saved history entry.
- [ ] Add explicit saved-workspace revision history retention instead of replacing the current saved payload in place.
- [ ] Decide which settings and metadata are sync-worthy.
- [ ] Evaluate `NSPersistentCloudKitContainer` for future sync support.
- [ ] Keep sync design scoped to durable product value, not novelty.
- [ ] Refine reopened-workspace naming so duplicate live opens communicate provenance more gracefully.
- [ ] Decide whether reopened-workspace provenance belongs in the title, sidebar metadata, or a transient badge.

### Exit Criteria

- [ ] Persistence failures are diagnosable, the unified library direction is explicit, reopened workspaces communicate provenance clearly, and the roadmap has an explicit answer about whether sync belongs in the product.

## Milestone 6: Quality and Release Readiness

### Status

In Progress

### Scope

- [ ] Turn the current shell into a release-ready internal build with broader coverage, stronger operator-facing diagnostics, and one lightweight observability baseline.

### Tickets

- [ ] Add broader UI coverage for pane lifecycle flows and multi-window command interactions.
- [ ] Tighten operator-facing logs and error messages throughout the app.
- [ ] Choose a lightweight logging and diagnostics baseline that supports support-bundle export and future crash or hang reporting.
- [ ] Write onboarding and maintainer docs for release-oriented development.
- [ ] Add an `OSLogStore`-based recent-diagnostics export path suitable for future user-facing feedback bundles.
- [ ] Decide what support-bundle metadata should accompany exported logs, such as workspace summaries, pane state, persistence outcomes, or recent alerts.
- [ ] Evaluate `MetricKit` intake for crash and hang diagnostics once the ordinary logging baseline is stable.
- [ ] Revisit distributed tracing and `swift-otel` only when `gmax` has a concrete telemetry destination or cross-process workflow that needs correlation.
- [ ] Keep observability scope lightweight and product-driven instead of introducing server-style telemetry by default.

### Exit Criteria

- [ ] The repo has a clear release-oriented validation path, the shell has stronger command and pane coverage, and the diagnostics baseline is good enough for an internal `v0.1.0` release.

## Milestone 7: Deeper Terminal Integrations / Remote / SSH / Etc.

### Status

Planned

### Scope

- [ ] Define how local shell, headless execution, and remote sessions could share one durable session model without bloating the current local-shell app.

### Tickets

- [ ] Explore other SwiftTerm types, particularly `TerminalView`.
- [ ] Decide how local-shell, headless, and remote-session backends should share one durable session model.
- [ ] Add a headless terminal path for workflow command execution.
- [ ] Add a remote SSH session path with clear connection lifecycle and operator-facing state.
- [ ] Surface remote host, command, and connection metadata in the inspector.
- [ ] Evaluate transport and protocol primitives worth using for remote sessions.
- [ ] Add Ghostty.app pane option if and when Ghostty exposes a stable integration surface.

### Exit Criteria

- [ ] There is one explicit session model for local, headless, and remote work, and any remote path has a clear lifecycle and operator-facing state model.

## Milestone 8: App Sandbox Compatibility

### Status

Planned

### Scope

- [ ] Make the local-shell product story compatible with sandboxed distribution constraints without hiding the helper and IPC behavior behind vague abstractions.

### Tickets

- [ ] Move environment capture to a bundled XPC service or SMAppService helper.
- [ ] Audit local-shell launch assumptions against macOS App Sandbox constraints.
- [ ] Decide how shell launching, environment inheritance, and path resolution should behave in sandboxed builds.
- [ ] Add security-scoped or bookmark-backed file access where the product needs durable user-selected locations.
- [ ] Keep helper and IPC design explicit, minimal, and operator-friendly to debug.

### Exit Criteria

- [ ] Sandboxed builds have an explicit and documented answer for shell launch, environment capture, helper ownership, and any durable file-access needs.

## Milestone 9: iOS Remote and iPadOS App

### Status

Planned

### Scope

- [ ] Define a remote-companion product that reuses the workspace model where it composes cleanly, instead of assuming full desktop parity on touch-first platforms.

### Tickets

- [ ] Define the first remote-companion scope instead of assuming full desktop feature parity.
- [ ] Reuse the workspace and pane model where it composes cleanly across macOS and iPadOS.
- [ ] Design an iPad external-keyboard-first interaction model.
- [ ] Add a remote session browser with clear workspace and pane selection.
- [ ] Decide which inspector affordances belong on touch-first platforms.
- [ ] Evaluate whether iPhone should stay companion-only while iPad carries the fuller remote shell story.

### Exit Criteria

- [ ] The remote companion has a clearly bounded first product scope and an interaction model that fits keyboard-first iPad use without pretending it is the desktop app.

## Milestone 10: Chromium Browser Pane

### Status

Planned

### Scope

- [ ] Decide whether a browser pane has durable product value inside mixed terminal workspaces, then define the minimum pane model, persistence, and security boundaries needed to support it.

### Tickets

- [ ] Define the browser-pane use cases that justify embedding Chromium instead of bouncing out to the default browser.
- [ ] Add a browser pane model that can coexist with terminal panes in the same workspace tree.
- [ ] Decide how navigation state, history, and session isolation should persist.
- [ ] Add intentional controls and inspector metadata for browser panes.
- [ ] Define security boundaries for web content inside mixed terminal workspaces.

### Exit Criteria

- [ ] The project either has a justified browser-pane feature with explicit persistence and security boundaries or an explicit decision not to carry it forward.

## Milestone 11: Custom Codex App-Server Pane

### Status

Planned

### Scope

- [ ] Define whether a Codex pane belongs in `gmax`, and if so, keep its prompt, tool, and context model explicit enough that local and remote backends can evolve without rewriting the pane model.

### Tickets

- [ ] Define the first Codex-specific pane workflows worth building into `gmax`.
- [ ] Decide whether the pane is chat-first, tool-first, or workflow-first.
- [ ] Add a durable model for pane-scoped prompts, responses, and task context.
- [ ] Define how terminal panes and Codex panes should share or hand off context.
- [ ] Add operator-friendly visibility into tool execution, progress, and failure states.
- [ ] Keep the app-server integration explicit enough that local and remote Codex backends can evolve without rewriting the pane model.

### Exit Criteria

- [ ] The project has a clear answer about whether a Codex pane is real product direction, and any adopted pane model preserves explicit prompt, tool, and context ownership.

## Backlog Candidates

- [ ] Revisit a user-facing support-bundle export UI once Milestone 6 settles the diagnostics payload and operator workflow.
- [ ] Revisit full alternate-buffer and emulator-state restoration only if the current restored-history model still feels meaningfully insufficient for ordinary shell use.
- [ ] Revisit lower-side-effect browser history restoration if replaying saved URLs during restore proves too costly or noisy in practice.
- [ ] Revisit Ghostty integration only if a stable pane-hosting surface actually exists.
- [ ] Revisit pane-local tabs only after the current workspace, split, and close model feels settled enough to support another navigation layer cleanly.

## History

- 2026-04-22: Migrated `ROADMAP.md` to the canonical checklist structure used by the roadmap-maintenance workflow.
- 2026-04-22: Folded the former standalone accessibility-upstream and observability follow-through sections into Milestone 3 and Milestone 6 so the roadmap tracks one milestone status per product area.
- 2026-04-23: Shipped the `v0.0.7` command-and-sizing follow-through checkpoint with intentional keyboard shortcut alignment, configurable closed-item auto-save behavior, and less constrained default window sizing.
- 2026-04-23: Shipped the `v0.0.8` terminal-history follow-through checkpoint with ordinary shell scrollback restore on relaunch, viewport-timed restore startup, and a cleaner host-output-backed transcript capture path.
- 2026-04-24: Shipped the `v0.0.9` browser-pane follow-through checkpoint with persisted browser session metadata, lightweight back-forward history restore, browser creation and navigation commands, and the first omnibox overlay pass.
