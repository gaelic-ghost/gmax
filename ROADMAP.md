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
- [x] Directional pane focus movement
- [x] Close semantics for panes, empty workspaces, and window fallback
- [x] Core Data persistence for workspaces and pane graph
- [x] Maintainer architecture note

## Milestone 1: Workspace And Pane Core

- [ ] Add explicit workspace creation
- [ ] Add workspace rename
- [ ] Add workspace deletion from the UI
- [ ] Add duplicate workspace or clone-layout behavior
- [ ] Add new-pane creation commands beyond split-from-focus flow
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

## Milestone 4: Preferences And Customization

- [ ] Add app settings window
- [ ] Add theme and appearance controls
- [ ] Add font, spacing, and terminal presentation settings
- [ ] Add configurable keyboard shortcuts where practical
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

## Near-Term Recommended Order

- [ ] Workspace creation, rename, and deletion
- [ ] Empty-workspace and inspector polish
- [ ] Persistence follow-through for scene-local restore
- [ ] Accessibility pass on the current shell
- [ ] Settings foundation
