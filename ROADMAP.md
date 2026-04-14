# ROADMAP

## Product Direction

Build `gmax` into a finished macOS terminal workspace app:

- native-feeling shell structure
- strong keyboard workflow
- reliable workspace and pane persistence
- thoughtful inspector and workspace tooling
- real accessibility and product polish

## Current Baseline

- [x] Three-column `NavigationSplitView` shell
- [x] Workspace sidebar
- [x] Recursive split-pane model
- [x] SwiftTerm-backed local shell panes
- [x] Explicit workspace creation and standalone new-pane creation commands
- [x] Directional pane focus movement
- [x] Close semantics for panes, empty workspaces, and window fallback
- [x] Core Data persistence for workspaces and pane graph
- [x] Saved-workspace library with transcript-backed reopen
- [x] `WindowGroup`-based main shell with frontmost-window command routing
- [x] Per-scene restoration for selected workspace plus sidebar and inspector visibility
- [x] App settings window for terminal appearance
- [x] Unified logging baseline plus maintainer logging-validation guide
- [x] Domain-grouped unit-test surface for workspace lifecycle and persistence
- [x] Maintainer architecture note

## Milestone 1: Workspace and Pane Core

- [x] Add explicit workspace creation
- [x] Add workspace rename
- [x] Add workspace deletion from the UI
- [x] Add duplicate workspace or clone-layout behavior
- [x] Add new-pane creation commands beyond split-from-focus flow
- [x] Add pane restart / relaunch behavior after shell exit
- [x] Add better empty-workspace presentation and actions
- [x] Persist selected workspace and inspector visibility per scene

## Milestone 2: Terminal Product UX

- [ ] Replace scaffold-style pane controls with intentional terminal-native chrome
- [x] Add contextual pane actions in the inspector
- [x] Surface session title, cwd, process state, and exit state more clearly
- [ ] Improve close, focus, and split animations so the shell feels calmer
- [ ] Add configurable startup behavior for new panes and new workspaces
- [x] Add support for opening multiple windows cleanly
- [x] Add better handling for dead or exited shell sessions

## Milestone 3: Accessibility

- [ ] Audit the SwiftUI shell for keyboard-only reachability
- [ ] Improve pane focus visibility and command discoverability
- [ ] Evaluate SwiftTerm host accessibility gaps in the app context
- [x] Add app-level accessibility affordances around pane metadata and session state
- [ ] Design a practical Voice Control and Full Keyboard Access story
- [ ] Decide whether SwiftTerm should be extended locally for better accessibility support
- [ ] Integrate SpeakSwiftly for in-process custom TTS and STT
- [ ] Evaluate small fine-tunes of FunctionGemma and STT for Voice Commands

## Milestone 3A: SwiftTerm Accessibility Upstream Work

- [ ] Validate current SwiftTerm accessibility behavior under VoiceOver and Full Keyboard Access outside `gmax`-specific pane chrome
- [ ] Identify the smallest macOS accessibility gaps in SwiftTerm's `TerminalView` and `LocalProcessTerminalView`
- [ ] Prototype upstream-safe AppKit accessibility improvements that do not depend on `gmax` pane metadata or app-specific actions
- [ ] Replace or deepen the currently limited macOS accessibility-service implementation in SwiftTerm where the gap is real and reproducible
- [ ] Split app-local accessibility affordances from package-level terminal accessibility fixes so upstream scope stays clean
- [ ] Prepare an isolated patch series and reproduction notes suitable for a SwiftTerm upstream contribution

## Milestone 4: Preferences and Customization

- [x] Add app settings window
- [x] Expand theme and appearance controls
- [ ] Add import for theme and appearance settings
- [ ] Add font, spacing, and terminal presentation settings
- [ ] Add toolbar "preset" buttons for saving workspace layouts as "favorites"
- [ ] Add initial set of configurable keyboard shortcuts
- [ ] Add custom actions or command presets worth persisting
- [ ] Separate durable app settings from scene-local window state beyond the current restored selection and inspector visibility

## Milestone 5: Persistence and Sync Follow-Through

- [ ] Add migration-safe versioning around the Core Data model
- [x] Restore a more complete session and workspace state on launch
- [x] Add a separate saved-workspace snapshot library beside the live session store
- [x] Add explicit `Save Workspace` and `Close to Library` flows
- [x] Add `Auto-save closed workspaces` and apply it orthogonally to the recently closed stack
- [x] Add a searchable `Open Workspace...` saved-workspace index
- [x] Preserve transcript-backed pane scrollback in saved workspace snapshots
- [ ] Add configurable transcript retention limits for saved workspace history
- [ ] Add crash-safe and operator-friendly persistence diagnostics
- [x] Add initial failure-mode coverage for corrupted and partial workspace snapshots so restore degrades safely instead of unpredictably
- [ ] Decide which settings and metadata are sync-worthy
- [ ] Evaluate `NSPersistentCloudKitContainer` for future sync support
- [ ] Keep sync design scoped to durable product value, not novelty
- [ ] Refine reopened-workspace naming so duplicate live opens communicate provenance more gracefully
- [ ] Decide whether reopened-workspace provenance belongs in the title, sidebar metadata, or a transient badge

## Milestone 6: Quality and Release Readiness

- [x] Add meaningful unit coverage for pane-tree mutations
- [x] Add persistence-layer tests for load and save behavior
- [ ] Add persistence-layer tests for corruption, partial snapshots, and graceful restore failure handling
- [x] Add UI coverage for saved-workspace library and workspace-sidebar lifecycle flows
- [ ] Add broader UI coverage for pane lifecycle flows and multi-window command interactions
- [ ] Tighten operator-facing logs and error messages throughout the app
- [ ] Choose a lightweight logging and diagnostics baseline that supports support-bundle export and future crash or hang reporting
- [ ] Write onboarding and maintainer docs for release-oriented development
- [x] Prepare a release checklist for first usable internal builds

## Milestone 6A: Observability And Diagnostics Follow-Through

- [x] Land the initial Apple `Logger` subsystem and category taxonomy across app, workspace, pane, persistence, and diagnostics surfaces
- [x] Standardize operator-facing log message shape so restore, reopen, and relaunch failures are immediately understandable in Console
- [x] Add a maintainer logging-validation note that documents Console filters, `/usr/bin/log` commands, and expected noise during UI and launch-performance tests
- [ ] Add an `OSLogStore`-based recent-diagnostics export path suitable for future user-facing feedback bundles
- [ ] Decide what support-bundle metadata should accompany exported logs, such as workspace summaries, pane state, persistence outcomes, or recent alerts
- [ ] Evaluate `MetricKit` intake for crash and hang diagnostics once the ordinary logging baseline is stable
- [ ] Revisit distributed tracing and `swift-otel` only when `gmax` has a concrete telemetry destination or cross-process workflow that needs correlation
- [ ] Keep observability scope lightweight and product-driven instead of introducing server-style telemetry by default

## Milestone 7: Deeper Terminal Integrations / Remote / SSH / Etc.

- [ ] Explore other SwiftTerm types, particularly `TerminalView`
- [ ] Decide how local-shell, headless, and remote-session backends should share one durable session model
- [ ] Add a headless terminal path for workflow command execution
- [ ] Add a remote SSH session path with clear connection lifecycle and operator-facing state
- [ ] Surface remote host, command, and connection metadata in the inspector
- [ ] Evaluate transport and protocol primitives worth using for remote sessions
- [ ] Add Ghostty.app pane option if and when Ghostty exposes a stable integration surface

## Milestone 8: App Sandbox Compatibility

- [ ] Move environment capture to a bundled XPC service or SMAppService helper
- [ ] Audit local-shell launch assumptions against macOS App Sandbox constraints
- [ ] Decide how shell launching, environment inheritance, and path resolution should behave in sandboxed builds
- [ ] Add security-scoped or bookmark-backed file access where the product needs durable user-selected locations
- [ ] Keep helper and IPC design explicit, minimal, and operator-friendly to debug

## Milestone 9: iOS Remote and iPadOS App

- [ ] Define the first remote-companion scope instead of assuming full desktop feature parity
- [ ] Reuse the workspace and pane model where it composes cleanly across macOS and iPadOS
- [ ] Design an iPad external-keyboard-first interaction model
- [ ] Add a remote session browser with clear workspace and pane selection
- [ ] Decide which inspector affordances belong on touch-first platforms
- [ ] Evaluate whether iPhone should stay companion-only while iPad carries the fuller remote shell story

## Milestone 10: Chromium Browser Pane

- [ ] Define the browser-pane use cases that justify embedding Chromium instead of bouncing out to the default browser
- [ ] Add a browser pane model that can coexist with terminal panes in the same workspace tree
- [ ] Decide how navigation state, history, and session isolation should persist
- [ ] Add intentional controls and inspector metadata for browser panes
- [ ] Define security boundaries for web content inside mixed terminal workspaces

## Milestone 11: Custom Codex App-Server Pane

- [ ] Define the first Codex-specific pane workflows worth building into `gmax`
- [ ] Decide whether the pane is chat-first, tool-first, or workflow-first
- [ ] Add a durable model for pane-scoped prompts, responses, and task context
- [ ] Define how terminal panes and Codex panes should share or hand off context
- [ ] Add operator-friendly visibility into tool execution, progress, and failure states
- [ ] Keep the app-server integration explicit enough that local and remote Codex backends can evolve without rewriting the pane model

## Near-Term Recommended Order

- [x] Workspace creation, rename, and deletion
- [x] Empty-workspace and inspector polish
- [x] Saved-workspace library foundation and transcript-backed restore
- [ ] Accessibility pass on the current shell
- [x] Settings foundation
- [ ] Saved-workspace library polish and reopen semantics
- [ ] Keyboard-shortcut and command discoverability pass
- [ ] Release-readiness pass on logs, errors, and first-run workflow

## Reference Docs

- [docs/maintainers/accessibility-and-keyboard-plan.md](docs/maintainers/accessibility-and-keyboard-plan.md)
- [docs/maintainers/logging-and-telemetry-options.md](docs/maintainers/logging-and-telemetry-options.md)
- [docs/maintainers/swiftui-terminal-shell-architecture.md](docs/maintainers/swiftui-terminal-shell-architecture.md)
- [docs/maintainers/v0.1.0-release-checklist.md](docs/maintainers/v0.1.0-release-checklist.md)
