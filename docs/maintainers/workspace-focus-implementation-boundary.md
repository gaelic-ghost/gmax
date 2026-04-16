/*

This note defines the implementation boundary for the next workspace-focus
redesign pass in gmax.

It records which documented SwiftUI focus and command behaviors we are relying
on, which responsibilities should move into native SwiftUI scene and view
focus, which responsibilities should stay with SwiftTerm, and which current
custom integration behaviors should be removed.

The goal is to make the next implementation pass intentionally layered instead
of continuing to blend scene state, pane focus, AppKit first responder, and
terminal interaction behavior into one custom path.

*/

# Workspace Focus Implementation Boundary

## Purpose

This note turns the focus redesign discussion into an implementation boundary we
can build against.

It answers four concrete questions:

- What should SwiftUI scene state own?
- What should SwiftUI view focus own?
- What should SwiftTerm continue owning unchanged?
- What current custom behaviors should we stop doing?

Use this together with:

- [`swiftui-command-and-focus-architecture.md`](./swiftui-command-and-focus-architecture.md)
- [`workspace-focus-removal-and-redesign-notes.md`](./workspace-focus-removal-and-redesign-notes.md)
- [`workspace-focus-target-plan.md`](./workspace-focus-target-plan.md)
- [`workspace-focus-first-pass-plan.md`](./workspace-focus-first-pass-plan.md)
- [`workspace-window-state-and-persistence-model.md`](./workspace-window-state-and-persistence-model.md)
- [`swiftterm-surface-investigation.md`](./swiftterm-surface-investigation.md)

## Documented Framework Behavior We Are Relying On

This boundary depends on a few documented Apple behaviors:

- `focusedSceneValue` is for values that should remain visible regardless of
  where focus is located in the active scene.
- `focusedValue` is for values that should only be visible when focus is inside
  a particular view or descendant subtree.
- `focusable(interactions: .activate)` is the documented way to make a custom
  macOS SwiftUI view behave like a button-like activatable focus surface.
- `focusSection()` guides directional and sequential movement among a cohort of
  focusable descendants.
- Menu and command availability should track the active scene and the focused
  hierarchy rather than an app-defined parallel command router.

These are the Apple docs this note depends on:

- `focusedValue(_:_:)`
  - <https://developer.apple.com/documentation/swiftui/view/focusedvalue(_:_:)-odf9>
- `focusedSceneValue(_:_:)`
  - <https://developer.apple.com/documentation/swiftui/view/focusedscenevalue(_:_:)-57boz>
- `focusable(_:interactions:)`
  - <https://developer.apple.com/documentation/swiftui/view/focusable(_:interactions:)>
- `focusSection()`
  - <https://developer.apple.com/documentation/swiftui/view/focussection()>
- `Building and customizing the menu bar with SwiftUI`
  - <https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui>

## Boundary Summary

The implementation boundary should be:

- the scene owns window-local selection, window-local open-workspace state,
  modal presentation state, and scene-wide command context
- the pane layer owns pane focus identity and pane-local command context
- SwiftTerm owns terminal-native input, selection, find, copy, and responder
  behavior
- the AppKit bridge only translates between native pane activation and the
  terminal view's responder surface where needed

That is the core split.

## What The Scene Should Own

The workspace window scene should own state that is true for the whole active
window, regardless of which child currently has focus.

That includes:

- selected workspace in the active window
- the list of workspaces currently open in that window
- per-window restore state
- scene-owned modal presentation state
- scene-owned rename and delete presentation state
- scene-wide command exports for things like:
  - open the saved workspace library
  - present rename for the selected workspace
  - present deletion for the selected workspace

This is the right home for `focusedSceneValue` and `focusedSceneObject`.

### Scene-owned focus state

The scene should also own the primary native focus model for workspace-level
targets.

The likely shape is:

- `@FocusState private var focusedTarget: WorkspaceFocusTarget?`

Where `WorkspaceFocusTarget` is something close to:

- `sidebar`
- `workspaceListing(WorkspaceID)` if row-level binding proves necessary
- `pane(PaneID)`
- `inspector`

The exact enum can still change, but the important point is that the scene owns
the focus graph, not the workspace model.

## What The Sidebar Should Own

The sidebar should own workspace selection and navigation for the leading column
of the `NavigationSplitView`.

The standard shape remains:

- `List(selection:)`
- `ForEach`
- `NavigationLink(value:)`

That means the sidebar should rely on native list selection and native sidebar
focus behavior rather than a custom sidebar focus engine.

The likely next cleanup here is mostly structural:

- split row rendering into a small `WorkspaceListingView`
- keep row layout, accessibility, and row affordances together
- keep selection owned by the enclosing list

The sidebar does not need to become a separate custom command router.

## What The Pane Layer Should Own

The pane layer should own the semantic concept of "which pane is the active pane
for pane commands."

That includes:

- pane-level focus identity
- pane-local command publication such as `closeFocusedPane`
- pane-level actions such as split, close, restart, and pane navigation

This should be modeled through native SwiftUI focus placement, not through a
runtime `Workspace.focusedPaneID` field acting as the source of truth.

### Pane command context

When a pane is the active focused pane, it should publish pane-local command
context through `focusedValue`.

Examples:

- `closeFocusedPane`
- potentially future pane-local split or relaunch actions

When focus leaves content and moves to the sidebar or inspector, those pane
commands should naturally become unavailable.

That matches Gale's current design decision.

## What SwiftTerm Should Own

SwiftTerm should continue owning terminal-native behavior.

That includes:

- prompt input
- scrollback selection
- copy and select-all availability
- built-in find behavior
- mouse selection
- terminal-specific responder behavior
- terminal-side search and selection policy

At the current stage of the project, prompt-versus-scrollback should remain a
terminal interaction distinction, not a separate scene-level command target
model.

The pane remains the semantic command target, while the SwiftTerm view remains
the concrete text and responder surface inside that pane.

## What The AppKit Bridge Should Own

The AppKit bridge should be narrow.

It should own:

- hosting the SwiftTerm view inside SwiftUI
- process/session lifecycle wiring
- transcript restore and capture
- narrow translation from pane activation into terminal first responder, if
  SwiftTerm still needs that help

It should not own:

- the global focus model for panes
- command routing policy
- a replacement for SwiftUI focus
- a replacement for SwiftTerm's internal mouse or selection behavior

## Current Behaviors We Should Explicitly Stop Doing

These are the behaviors this redesign should remove or phase out:

### 1. Stop using `Workspace.focusedPaneID` as live runtime focus truth

If the app still needs last-focused-pane information for restore, that can
survive as persistence or restoration data. But it should stop being the live
keyboard-focus engine.

### 2. Stop forcing terminal first responder from every `updateNSView`

Forcing `makeFirstResponder(...)` on every update when `isFocused` is true makes
AppKit responder state follow a model boolean.

The better path is:

- pane becomes active through native SwiftUI focus or an explicit activation
  transition
- terminal first responder is requested only at that transition boundary if
  needed

That is a much narrower responsibility.

### 3. Stop replacing SwiftTerm mouse behavior casually

SwiftTerm already owns selection and mouse interaction behavior inside the
terminal surface.

So we should stop defaulting to:

- removing existing click recognizers
- installing our own recognizer as the primary control path

unless we can name a concrete SwiftTerm gap we must fill.

### 4. Stop using pane geometry as the general focus engine

The current geometry preference and directional ranking system is a custom focus
engine.

Some directional navigation policy may remain, but it should no longer require
the workspace model to ingest pane frames and compute focus as its primary
runtime truth.

## Legitimate Extension Seams

These are the seams that still look legitimate after the redesign:

### 1. Subclass `LocalProcessTerminalView` if terminal-side hooks are needed

This is currently the best terminal extension seam because it follows
SwiftTerm's own guidance.

Use this when we need terminal-specific behavior that belongs close to the
terminal surface.

### 2. Keep `NSViewRepresentable` for hosting and lifecycle

This remains the right bridge for:

- embedding the AppKit terminal view
- syncing appearance
- process lifecycle wiring
- transcript persistence

### 3. Publish scene-wide values from the scene root

Use `focusedSceneValue` and `focusedSceneObject` for active-window state and
scene-owned actions.

### 4. Publish pane-local values from the pane root

Use `focusedValue` from the pane container when pane-local commands should only
exist while the pane is active.

## Provisional Implementation Shape

The most likely implementation direction is:

1. Keep window-local workspace state at the scene layer.
2. Introduce a native scene-owned `@FocusState` for workspace-level targets.
3. Bind pane containers to that focus state with stable pane identities.
4. Derive pane command publication from native focus placement.
5. Narrow the terminal bridge so it reacts to activation transitions instead of
   owning focus truth.
6. Only subclass `LocalProcessTerminalView` if a real terminal-side hook is
   still missing.

## Recommended Cleanup Order

The safest order looks like this:

### Phase 1: define the scene-owned focus graph

- add `WorkspaceFocusTarget`
- add scene-owned `@FocusState`
- stop treating `Workspace.focusedPaneID` as the live runtime truth

### Phase 2: re-anchor pane command publication

- make pane containers the source of pane-local `focusedValue` exports
- let pane commands disable naturally when focus is not in content

### Phase 3: narrow the SwiftTerm bridge

- remove update-loop responder forcing
- remove custom click behavior unless a concrete gap remains
- move terminal-specific hooks into a narrower terminal-side seam

### Phase 4: revisit persistence

- decide whether last-focused-pane survives only as restore metadata
- align per-window restore data with the scene-local open-workspace model

## Practical Litmus Test

After the redesign, this should be true:

- if the sidebar is focused, sidebar commands work and pane commands do not
- if a pane is focused, pane commands work
- if the terminal inside that pane needs text input, SwiftTerm owns that input
  behavior
- if a modal is presented, the scene root still owns that presentation flow
- if the terminal view needs extra behavior, the first question is "can
  SwiftTerm already do this?" and the second is "does this belong in a terminal
  subclass?" rather than "should we build a new workspace-side routing layer?"

## Current Recommendation

The next implementation pass should treat this as the rule:

- SwiftUI owns workspace-level focus and command targeting.
- SwiftTerm owns terminal-native interaction behavior.
- The bridge between them should stay narrow, explicit, and local.

That is the durable building-block change we should optimize for.
