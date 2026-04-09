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
- [x] App settings window for terminal appearance
- [x] Maintainer architecture note

## Milestone 1: Workspace And Pane Core

- [x] Add explicit workspace creation
- [ ] Add workspace rename
- [ ] Add workspace deletion from the UI
- [ ] Add duplicate workspace or clone-layout behavior
- [x] Add new-pane creation commands beyond split-from-focus flow
- [ ] Add pane restart / relaunch behavior after shell exit
- [ ] Add better empty-workspace presentation and actions
- [ ] Persist selected workspace and inspector visibility per scene

## Milestone 2: Terminal Product UX

- [ ] Replace scaffold-style pane controls with intentional terminal-native chrome
- [ ] Add contextual pane actions in the inspector
- [ ] Surface session title, cwd, process state, and exit state more clearly
- [ ] Improve close, focus, and split animations so the shell feels calmer
- [ ] Add configurable startup behavior for new panes and new workspaces
- [ ] Add support for opening multiple windows cleanly
- [ ] Add better handling for dead or exited shell sessions

## Milestone 3: Accessibility

- [ ] Audit the SwiftUI shell for keyboard-only reachability
- [ ] Improve pane focus visibility and command discoverability
- [ ] Evaluate SwiftTerm host accessibility gaps in the app context
- [ ] Add app-level accessibility affordances around pane metadata and session state
- [ ] Design a practical Voice Control and Full Keyboard Access story
- [ ] Decide whether SwiftTerm should be extended locally for better accessibility support
- [ ] Integrate SpeakSwiftly for in-process custom TTS and STT
- [ ] Evaluate small fine-tunes of FunctionGemma and STT for Voice Commands

## Milestone 4: Preferences And Customization

- [x] Add app settings window
- [ ] Expand theme and appearance controls
- [ ] Add import for theme and appearance settings
- [ ] Add font, spacing, and terminal presentation settings
- [ ] Add toolbar "preset" buttons for saving workspace layouts as "favorites"
- [ ] Add initial set of configurable keyboard shortcuts
- [ ] Add custom actions or command presets worth persisting
- [ ] Separate durable app settings from scene-local window state

## Milestone 5: Persistence And Sync Follow-Through

- [ ] Add migration-safe versioning around the Core Data model
- [ ] Restore a more complete session and workspace state on launch
- [ ] Add crash-safe and operator-friendly persistence diagnostics
- [ ] Decide which settings and metadata are sync-worthy
- [ ] Evaluate `NSPersistentCloudKitContainer` for future sync support
- [ ] Keep sync design scoped to durable product value, not novelty

## Milestone 6: Quality And Release Readiness

- [ ] Add meaningful unit coverage for pane-tree mutations
- [ ] Add persistence-layer tests for load and save behavior
- [ ] Add UI coverage for workspace and pane lifecycle flows
- [ ] Tighten operator-facing logs and error messages throughout the app
- [ ] Write onboarding and maintainer docs for release-oriented development
- [ ] Prepare a release checklist for first usable internal builds

## Milestone 7: Deeper Terminal Integrations/Remote/SSH/Etc

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

- [ ] Workspace creation, rename, and deletion
- [ ] Empty-workspace and inspector polish
- [ ] Persistence follow-through for scene-local restore
- [ ] Accessibility pass on the current shell
- [ ] Settings foundation
