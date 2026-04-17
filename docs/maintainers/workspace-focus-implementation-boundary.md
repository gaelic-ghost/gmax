# Workspace Focus Implementation Boundary

## Purpose

This is the current ownership boundary for workspace-window focus in `gmax`.

Use this note for implementation decisions. Use
[`workspace-focus-target-plan.md`](./workspace-focus-target-plan.md) for the
remaining focus-plan work, and use
[`swiftterm-surface-investigation.md`](./swiftterm-surface-investigation.md)
for the terminal-side source of truth.

## Boundary Summary

The focus model is now intentionally split like this:

- the scene owns window-local selection, modal presentation state, and the
  workspace-window focus namespace
- pane containers own pane identity and pane-local command publication
- SwiftTerm owns terminal-native responder behavior, prompt input, scrollback
  selection, copy, and find
- AppKit interop stays narrow and should not reintroduce a custom terminal
  focus adapter

## Scene Responsibilities

The workspace window scene owns:

- selected workspace
- window-local sidebar and inspector visibility
- scene-local modal presentation state
- the scene-wide command context exported through focused scene values
- `@FocusState` for `WorkspaceFocusTarget`

The scene does not own terminal responder behavior, and it does not push focus
into SwiftTerm through a custom bridge.

## Pane Responsibilities

Pane containers own:

- pane focus identity
- pane-local command exports such as close, split, and navigation actions
- visual focus treatment for the active pane

Pane identity is a workspace-window concern. It is not stored as live runtime
state on the workspace model.

## SwiftTerm Responsibilities

SwiftTerm owns:

- prompt input
- scrollback selection
- copy and select all
- built-in find behavior
- terminal-native responder and mouse behavior

`gmax` treats the enclosing pane as the workspace-level command target. It does
not model prompt versus scrollback as separate scene-level focus targets.

## AppKit Interop Boundary

The AppKit boundary should stay limited to:

- hosting SwiftTerm inside SwiftUI
- session lifecycle and transcript wiring
- ordinary accessibility labeling for the enclosing pane surface

The AppKit boundary should not grow back into:

- a custom first-responder forcing path
- a replacement for SwiftUI scene focus
- a replacement for SwiftTerm's terminal interaction model

## Active Follow-Through

The remaining focus work at this boundary is:

- manual verification of pane activation and keyboard behavior now that the
  SwiftTerm bridge is gone
- automated coverage for focus-dependent command behavior, especially
  multi-window routing and pane lifecycle commands
- cleanup of any stale naming or comments that still describe the removed
  bridge or store-owned focus engine as current behavior
