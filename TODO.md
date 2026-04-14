# TODO

- [ ] Complete the manual keyboard-only, VoiceOver, and Full Keyboard Access audit across the sidebar, pane tree, inspector, saved-workspace library, and terminal host.
- [ ] Evaluate `LocalProcessTerminalView` accessibility behavior and document whether `SwiftTerm` needs a local extension path for VoiceOver and Full Keyboard Access.
- [ ] Choose the `v0.1.0` logging baseline and diagnostics export path described in `docs/maintainers/logging-and-telemetry-options.md`.
- [ ] Replace the temporary pane-header material chip with more intentional terminal-native pane chrome and stronger focus treatment.
- [ ] Add configurable startup behavior for new panes and new workspaces.
- [ ] Add configurable transcript retention limits for saved workspace history.
- [ ] Add persistence-layer tests for workspace restore, save-to-library, and reopen flows.
- [ ] Tighten operator-facing logs and error messages around persistence, restore, and shell relaunch failures.
- [ ] Walk the first internal-build release checklist for `v0.1.0`.
