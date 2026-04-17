# Workspace Focus Target Plan

## Purpose

This is the active planning note for workspace-window focus in `gmax`.

It records only the focus work that is still open. Already-landed structural
changes and earlier cleanup passes are intentionally omitted here.

Use this together with:

- [`workspace-focus-implementation-boundary.md`](./workspace-focus-implementation-boundary.md)
- [`workspace-window-scene-command-focus-map.md`](./workspace-window-scene-command-focus-map.md)
- [`framework-command-audit.md`](./framework-command-audit.md)
- [`swiftterm-surface-investigation.md`](./swiftterm-surface-investigation.md)

## Source Of Truth Split

Use the focus and command notes by role:

- `workspace-focus-target-plan.md`
  - active focus-plan work only
- `workspace-focus-implementation-boundary.md`
  - current ownership boundary
- `workspace-window-scene-command-focus-map.md`
  - current implementation map
- `framework-command-audit.md`
  - current risk and test-gap audit
- `swiftterm-surface-investigation.md`
  - current SwiftTerm ownership boundary

These notes are now archival only:

- `workspace-focus-first-pass-plan.md`
- `workspace-focus-removal-and-redesign-notes.md`
- `swiftui-terminal-shell-architecture.md`

## Settled Decisions

These are not open planning questions anymore:

- the workspace window owns a scene-local focus namespace
- the sidebar stays native and list-driven
- the inspector is a real focus region, but pane-oriented commands disable when
  focus leaves content and moves there
- SwiftTerm owns prompt input, scrollback selection, copy, find, and terminal
  responder behavior
- `gmax` does not model prompt versus scrollback as separate scene-level focus
  targets

`Command-W` is also settled:

- if a pane is the active focus target, `Command-W` closes that pane
- if the selected workspace is empty, `Command-W` closes that workspace
- if focus is in the sidebar on a workspace listing, `Command-W` closes that
  workspace
- if that empty workspace is the only workspace in the window, `Command-W`
  closes the window
- if focus is in the inspector, `Command-W` does nothing
- if a modal surface owned by the scene is frontmost, `Command-W` dismisses the
  modal before any workspace or window close fallback is considered

## Remaining Focus Work

### 1. Manual behavior verification

The structural cleanup is done, but the bridge-free focus surface still needs a
real behavior pass across:

- pane activation and typing
- sidebar-to-content transitions
- inspector focus behavior
- `Command-W` in every focus region
- frontmost-window routing when multiple workspace windows exist

### 2. Better command-surface coverage

The command behavior is more explicit than it used to be, but it still needs
broader automated coverage for:

- pane lifecycle commands
- multi-window command routing
- focus-dependent command enablement and disablement

### 3. Accessibility and keyboard audit

The focus architecture is no longer the blocker. The remaining work is the real
product audit:

- keyboard-only reachability
- Full Keyboard Access behavior
- VoiceOver behavior in the shell around SwiftTerm
- command discoverability and visible focus treatment

### 4. Naming and doc drift cleanup

Any remaining comments, identifiers, or docs that still describe the removed
focus bridge or store-owned pane focus as current behavior should be cleaned up
when encountered.

## Out Of Scope For This Plan

These are not active focus-plan items:

- reintroducing any SwiftTerm focus bridge or responder adapter
- reviving `Workspace.focusedPaneID` or store-owned pane focus state
- inventing a prompt-versus-scrollback focus model in `gmax`
- reopening the `Command-W` product decision
