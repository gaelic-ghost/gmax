/*

This note defines the first code pass for the workspace focus redesign in gmax.

It turns the earlier architectural notes into a bounded implementation plan that
is intentionally small enough to execute safely, while still moving the focus
model onto native SwiftUI ownership.

The main constraint for this first pass is to keep sidebar workspace selection
native-list-driven if that remains feasible, and to avoid widening the refactor
into a full window-restoration or terminal transport rewrite.

*/

# Workspace Focus First Pass Plan

> Status
> Historical implementation-pass record. Do not use this as the current source
> of truth for focus behavior or remaining work.
>
> Use these notes instead:
> - [`workspace-focus-target-plan.md`](./workspace-focus-target-plan.md) for
>   current decisions
> - [`workspace-focus-implementation-boundary.md`](./workspace-focus-implementation-boundary.md)
>   for ownership boundaries
> - [`workspace-window-scene-command-focus-map.md`](./workspace-window-scene-command-focus-map.md)
>   for current implementation shape
> - [`framework-command-audit.md`](./framework-command-audit.md) for current
>   gaps and risks

## Purpose

This note defines the first implementation pass for moving `gmax` away from its
current custom pane-focus system.

This pass is not the whole redesign. It is the first safe structural move.

The structural first pass has now landed. Keep this note as the record of what
that pass was supposed to do, what it was allowed to defer, and what the next
pass now needs to pick up.

Use this together with:

- [`workspace-focus-implementation-boundary.md`](./workspace-focus-implementation-boundary.md)
- [`workspace-focus-target-plan.md`](./workspace-focus-target-plan.md)
- [`workspace-focus-removal-and-redesign-notes.md`](./workspace-focus-removal-and-redesign-notes.md)
- [`swiftterm-surface-investigation.md`](./swiftterm-surface-investigation.md)

## First-Pass Goal

The goal of the first pass is:

- keep sidebar selection native and list-driven
- introduce a real scene-owned workspace focus model
- move pane-local command publication onto native focus placement
- reduce the amount of custom model-owned runtime focus behavior
- avoid forcing a larger SwiftTerm transport rewrite yet

This pass should create the new backbone without trying to finish every focus,
responder, persistence, and modal question at once.

## Current Status

The structural goals of this pass are now in place:

- the scene owns `WorkspaceFocusTarget` and scene-local `@FocusState`
- pane-local command publication follows native pane focus
- the sidebar remains native-list-driven
- the inspector participates as a real native focus region
- live pane focus is no longer owned by `Workspace.focusedPaneID`

That means the first pass should now be treated as complete enough to hand off
to a next design pass, not as an open implementation plan that still needs its
backbone work done.

## Explicit First-Pass Decisions

### 1. Keep sidebar selection native-list-driven

For this pass, do not invent a custom `@FocusState` target for every workspace
row.

The sidebar should continue using the standard SwiftUI shape it already has:

- `List(selection:)`
- `ForEach`
- `NavigationLink(value:)`

That means the first focus graph should treat the sidebar as a focus region, not
as a custom row-by-row focus engine.

If later work reveals that row-level focus identity is truly needed for command
behavior beyond ordinary list selection, that can be introduced in a later pass.

### 2. Make pane identity the first custom focus target

The first explicit custom focus identity we should add is the pane.

That means the first concrete `WorkspaceFocusTarget` should likely start as:

- `sidebar`
- `pane(PaneID)`
- `inspector`

This is small enough to reason about and matches the current command needs.

### 3. Keep prompt-versus-scrollback inside the terminal surface

Do not split prompt and scrollback into separate scene-level focus targets in
this design.

Treat them as terminal-native interaction states that still live inside the same
pane command target.

This is no longer an open design question for `gmax`. SwiftTerm owns that
internal distinction, and `gmax` should let SwiftTerm handle it without adding a
parallel scene-focus or command-target model on top.

### 4. Keep modals scene-owned in this pass

Do not move rename, delete, or saved-library presentation downward in the tree
yet.

That ownership question is important, but it is not the first blocking step for
native pane focus.

## Scope Of The First Pass

### In scope

- add a scene-owned workspace focus type
- add scene-owned `@FocusState`
- bind pane containers to native focus
- publish pane-local command values from native focus truth
- keep scene-wide command values on the scene root
- reduce or remove the dependency on `Workspace.focusedPaneID` as the live
  runtime source of truth
- narrow the responder bridge where it directly depends on model-owned focus

### Out of scope

- redesigning the library persistence model
- fully reworking per-window open-workspace persistence
- rewriting SwiftTerm process transport around `TerminalView`
- splitting prompt and scrollback into separate scene focus targets
- redesigning modal ownership
- implementing the final terminal subclass strategy unless a tiny subclass
  becomes unavoidable during this pass

## Proposed Type Shape

The first pass should introduce a scene-owned focus type, likely near the
workspace scene layer.

Example shape:

```swift
enum WorkspaceFocusTarget: Hashable {
	case sidebar
	case pane(PaneID)
	case inspector
}
```

This should be owned by the scene, likely in or near
`WorkspaceWindowSceneView`, and driven by:

```swift
@FocusState private var focusedTarget: WorkspaceFocusTarget?
```

The important point is not the exact file placement. The important point is that
the focus graph becomes scene-owned SwiftUI state instead of model-owned
workspace state.

## Proposed View Ownership In The First Pass

### `WorkspaceWindowSceneView`

This view should own:

- `selectedWorkspaceID`
- scene-wide modal presentation state
- scene-wide rename/delete/library actions
- `focusedTarget`
- scene-wide `focusedSceneValue` and `focusedSceneObject` exports

This view should not continue delegating runtime pane-focus truth into the
workspace model.

### `SidebarPane`

This view should continue owning:

- native `List(selection:)`
- native `NavigationLink(value:)`
- row rendering and row context menus

It may gain a narrow hook to set `focusedTarget = .sidebar` if we need a
truthful scene-owned focus marker when the sidebar becomes the active region.

But it should not grow a custom row-focus engine in this pass.

### `ContentPane`

This view should become the main bridge between:

- scene-owned `focusedTarget`
- pane tree rendering
- pane-local focus binding

Instead of threading only `focusedPaneID`, this layer should start threading the
native focus binding shape needed by pane containers.

### `ContentPaneLeafView`

This view should become the first explicit pane-focus participant.

Its first-pass responsibilities should be:

- declare itself as focusable
- bind native focus for `.pane(pane.id)`
- publish pane-local `focusedValue` entries when its pane is the active focused
  pane
- keep the visual “focused” treatment derived from native focus, not just from
  model state

This is also where we should begin reducing mixed responsibilities, even if we
do not fully split the file yet.

### `TerminalPaneView` and bridge code

The bridge should stay focused on:

- hosting the terminal surface
- process lifecycle
- appearance
- transcript restore/capture

The first pass should narrow or remove the parts that assume model-owned focus is
the truth, especially repeated responder forcing.

## Concrete Changes To Make In This Pass

### 1. Introduce `WorkspaceFocusTarget`

Add the scene-owned focus-target type and store it in the workspace scene layer.

### 2. Add `@FocusState` to `WorkspaceWindowSceneView`

The workspace window scene should own:

- `@FocusState private var focusedTarget: WorkspaceFocusTarget?`

### 3. Bind pane containers to native focus

Pane views should bind with a shape like:

- `.focused($focusedTarget, equals: .pane(pane.id))`

The exact binding point may land in `ContentPaneLeafView` or a small new pane
container wrapper if that becomes clearer.

### 4. Re-anchor `closeFocusedPane`

`closeFocusedPane` should be exported when the pane is the focused pane in the
scene-owned native focus model, not when `Workspace.focusedPaneID` says so.

This is one of the most important proof points of the new model.

### 5. Keep selected workspace scene-wide

Continue publishing selected-workspace scene context from the scene root with
`focusedSceneValue`.

This lets scene-level rename/delete/library commands keep working without
pretending those are pane-local behaviors.

### 6. Remove `Workspace.focusedPaneID` from live focus ownership

The original first-pass goal was to stop treating `Workspace.focusedPaneID` as
the live runtime truth.

That cleanup is now stronger than originally scoped:

- live focus no longer comes from `Workspace.focusedPaneID`
- the model no longer persists pane focus as workspace state
- scene-owned native focus is now the authoritative runtime source of truth

### 7. Narrow responder forcing

Remove or reduce:

- update-loop `makeFirstResponder(...)`
- custom focus pushing from model-first paths

If the terminal still needs first-responder alignment after native pane focus is
introduced, request it at a real activation transition, not on every update.

## What Success Looks Like After This Pass

The first pass is successful if all of the following become true:

- the sidebar still drives workspace selection through native `List` behavior
- pane close command availability follows native pane focus instead of
  `Workspace.focusedPaneID`
- pane commands disable when focus is in the sidebar or inspector
- the scene still owns rename/delete/library actions cleanly
- the terminal host is no longer being force-synced from a model-owned focus
  boolean on every render update

That is now the state of the workspace focus backbone, even though some
terminal-side and window-restoration cleanup still remains for later passes.

## Likely Follow-Up Passes

If this pass succeeds, the next likely passes are:

### Follow-up pass 1: terminal-side narrowing

- decide whether a small `LocalProcessTerminalView` subclass is still needed
- remove remaining custom click or responder glue that SwiftTerm already covers

### Follow-up pass 2: scene-local window restoration

- decide how per-window open-workspace state should restore independently
- align scene-local open-workspace state with any persisted window-restore model
- keep saved workspace library state distinct from live window contents

### Follow-up pass 3: focus-region refinement

- decide whether sidebar region focus needs any more explicit treatment than the
  current native list binding
- decide whether inspector commands and traversal need additional polish beyond
  the current region-level focus participation

## Practical Implementation Order

The safest implementation order for the code pass is:

1. Add `WorkspaceFocusTarget` and scene-owned `@FocusState`.
2. Bind pane containers to native focus.
3. Switch pane-local command publication to native focus truth.
4. Remove update-loop responder forcing.
5. Evaluate what terminal-side glue remains necessary.

That order keeps the new source of truth in place before we start deleting old
behavior.
