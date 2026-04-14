# TODO

- [ ] Complete the manual keyboard-only, VoiceOver, and Full Keyboard Access audit across the sidebar, pane tree, inspector, saved-workspace library, and terminal host.
- [ ] Evaluate `LocalProcessTerminalView` accessibility behavior and document whether `SwiftTerm` needs a local extension path for VoiceOver and Full Keyboard Access.
- [ ] Use `docs/maintainers/logging-validation-guide.md` during the first manual `v0.1.0` validation pass and capture any missing or confusing diagnostics wording that still needs cleanup.
- [ ] Replace the temporary pane-header material chip with more intentional terminal-native pane chrome and stronger focus treatment.
- [ ] Add configurable startup behavior for new panes and new workspaces.
- [ ] Add configurable transcript retention limits for saved workspace history.
- [ ] Add broader save and restore coverage for stale or more deeply corrupted persisted layouts beyond the current missing-session and corrupted-pane-tree cases.
- [ ] Add broader UI coverage for pane lifecycle flows and multi-window command routing beyond the current sidebar and saved-workspace suites.
- [ ] Tighten operator-facing logs and error messages around persistence, restore, and shell relaunch failures.
- [ ] Keep resiliency and recovery behavior explicit during feature work, especially where persistence, restore, and pane lifecycle flows can fail partially.
- [ ] Walk the first internal-build release checklist for `v0.1.0`.
