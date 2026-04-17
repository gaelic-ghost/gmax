# Workspace Focus Removal and Redesign Notes

## Purpose

This note maps the current custom workspace-pane focus machinery in `gmax`,
marks the parts that should be removed or replaced, and outlines the remaining
SwiftUI-native cleanup after the first structural pass landed.

Use this alongside:

- [`swiftui-command-and-focus-architecture.md`](./swiftui-command-and-focus-architecture.md) for the preferred default model
- [`workspace-window-scene-command-focus-map.md`](./workspace-window-scene-command-focus-map.md) for the current command and focused-value flow
- [`framework-command-audit.md`](./framework-command-audit.md) for the broader redesign gaps and priorities
- [`workspace-focus-target-plan.md`](./workspace-focus-target-plan.md) for the current logical focus targets and the next design pass
- [`workspace-focus-implementation-boundary.md`](./workspace-focus-implementation-boundary.md) for the current implementation ownership split we want to move toward

## Current Custom Focus Surface

The pane focus system used to be primarily driven by `WorkspaceStore` state and
then mirrored into SwiftUI and AppKit. The first cleanup pass has already
removed the store-owned runtime focus engine, and the remaining cleanup is now
mostly about narrowing terminal-bridge behavior and clarifying scene-local
window restoration.

That scene-local restoration foundation is now in place too:

- each `WindowGroup` scene restores through a lightweight `WorkspaceSceneIdentity`
- live workspace state restores from `.live` placements
- recent-close state restores from `.recent` placements

The remaining focus work is therefore mostly about bridge narrowing, native
focus movement, and command behavior at region boundaries.

The main custom pieces were:

- `Workspace.focusedPaneID` in [`gmax/Workspace/WorkspaceLayout.swift`](../../gmax/Workspace/WorkspaceLayout.swift)
  - Removed in the first cleanup pass.
  - Live pane focus and persisted pane focus no longer live in the workspace
    model.
- `WorkspaceStore.focusPane`, `movePaneFocus`, `recordPaneFocus`, `paneFocusHistoryByWorkspace`, `paneFramesByWorkspace`, and `updatePaneFrames`
  - Removed in the first cleanup pass.
  - Live pane focus and directional pane navigation are now scene-local concerns in [`WorkspaceWindowSceneView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneView.swift), not store-owned runtime state.
- `ContentPaneFramePreferenceKey` and `.onPreferenceChange(...)` in [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift)
  - Descendants still report pane frames upward, but that geometry now feeds scene-local pane navigation instead of model-owned navigation state.
- `isFocused` plumbing through [`ContentPane.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift), [`ContentPaneLeafView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift), and [`TerminalPaneView.swift`](../../gmax/Terminal/Panes/TerminalPaneView.swift)
  - Partially redesigned.
  - Pane views now bind against scene-owned `@FocusState`, but the terminal bridge still consumes a derived `isFocused` flag while the SwiftTerm/AppKit boundary is being narrowed.
- pane-activation callbacks from [`ContentPaneLeafView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift) into [`TerminalPaneView.swift`](../../gmax/Terminal/Panes/TerminalPaneView.swift) and [`TerminalPaneHostView.swift`](../../gmax/Terminal/Panes/TerminalPaneHostView.swift)
  - Pointer and accessibility interactions still explicitly push focus back into the scene-owned focus state.
- `window?.makeFirstResponder(...)` calls in [`TerminalPaneView+Coordinator.swift`](../../gmax/Terminal/Panes/TerminalPaneView+Coordinator.swift)
  - The AppKit bridge still force-aligns the terminal view's first responder with pane focus transitions.

## Removal Or Replacement Map

The goal here is not “delete focus.” The goal is to stop owning custom focus state where SwiftUI or AppKit already has a native concept for it.

### Remove or redesign first

- `Workspace.focusedPaneID`
  - Removed in the first cleanup pass.
  - The next pass should not reintroduce it as either live focus truth or
    workspace persistence metadata unless a concrete restoration requirement
    proves that necessary.
- `WorkspaceStore.focusPane(...)`
  - Removed in the first cleanup pass.
  - Focus is no longer pushed into the store from arbitrary click handlers.
- `movePaneFocus(...)`
  - Removed from the store in the first cleanup pass.
  - The command intent remains, but the implementation now targets scene-local SwiftUI focus movement plus scene-local geometry ranking.
- `paneFocusHistoryByWorkspace`
  - Removed in the first cleanup pass.
- `paneFramesByWorkspace`, `updatePaneFrames(...)`, and directional geometry ranking
  - Store-owned frame storage and frame updates are removed.
  - Directional geometry ranking still exists, but now lives alongside scene-local focus state rather than inside `WorkspaceStore`.
- wrapper-owned pane activation callbacks and `.onTapGesture { focusedTarget = ... }`
  - Marked for narrowing rather than preserving as the default focus path.
  - Native focus movement should do as much of this work as SwiftUI will allow cleanly.
- Forced first-responder synchronization in `TerminalPaneView+Coordinator.update(...)`
  - Marked for redesign.
  - Some AppKit responder alignment will probably remain for the embedded terminal, but it should follow native focus transitions instead of model-owned “isFocused” state.

### Keep, but re-anchor on native focus

- `.focusable(interactions: .activate)` in [`ContentPaneLeafView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift)
  - Keep as the declaration that pane surfaces participate in focus.
  - Re-anchor its behavior on SwiftUI focus state rather than `Workspace.focusedPaneID`.
- `.focusedValue(\.closeFocusedPane, ...)`
  - Keep the concept.
  - Re-anchor publication on native focus truth instead of a model-derived `isFocused` flag.
- `.focusedSceneValue(...)` from [`WorkspaceWindowSceneView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneView.swift) and [`ContentPane.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift)
  - Keep.
  - These are scene-context exports, not the custom focus problem.
- `.focusSection()` in [`ContentPane.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift)
  - Keep and evaluate more intentionally.
  - This is already a SwiftUI-native focus-shaping primitive.

## Views That Already Carry Native Focus Well

These surfaces likely do not need new custom focus work:

- `SidebarPane`
  - The `List(selection:)` and `NavigationLink(value:)` stack already has strong native selection and focus behavior.
- `SavedWorkspaceLibrarySheet`
  - Sheet controls and lists already participate in native focus handling.
- `WorkspaceRenameSheet`
  - Text field and buttons should use ordinary SwiftUI focus and first responder behavior.
- `DetailPane`
  - Static inspector content and text selection mostly rely on built-in focus and responder behavior already.

## Views That Are Strong Candidates To Participate In A Native Focus Model

These are the surfaces worth discussing as explicit focus participants:

- Pane leaf root in [`ContentPaneLeafView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift)
  - Best candidate for pane-level focus identity.
  - This is the visible pane surface the user conceptually focuses.
- Embedded terminal host in [`Terminal/Panes`](../../gmax/Terminal/Panes)
  - Likely needs AppKit responder ownership for text input.
  - This should probably be the actual editing target when a pane is focused.
- Sidebar workspace list
  - Already native, but it is part of the scene’s overall focus graph and should be treated as a first-class focus region in design discussions.
- Inspector / detail pane
  - Likely a focus region rather than a custom focus target.
- Empty workspace content
  - Probably does not need custom focus identity beyond its button, but it is part of the fallback navigation path when no pane exists.

## Better SwiftUI-Based Focus Shape

The likely better direction is to separate three concepts that are currently blended together:

- scene selection
  - Which workspace is selected in the window
- native input focus
  - Which concrete control or pane surface currently owns keyboard focus
- command context
  - What commands should be enabled or routed based on the active scene and active focused subtree

### Proposed model

- Keep `selectedWorkspaceID` scene-local in `WorkspaceWindowSceneView`.
- Introduce a real SwiftUI focus model at the scene level, likely with `@FocusState`.
- Give pane leaves stable focus identities, for example `WorkspaceFocusTarget.pane(PaneID)`.
- Let pane views bind themselves to that focus state with `.focused(...)` instead of reporting focus into the model.
- Let pane-local command exports like `closeFocusedPane` derive from native focus placement.
- Let AppKit terminal first responder follow the pane’s native focus transition, rather than model focus trying to drive AppKit first responder directly.

### Likely shape

One plausible direction is:

- `@FocusState private var focusedTarget: WorkspaceFocusTarget?` owned by `WorkspaceWindowSceneView`
- pane leafs bind with `.focused($focusedTarget, equals: .pane(pane.id))`
- scene-level commands read command context from `focusedValue` and `focusedSceneValue`
- explicit “move focus left/right/up/down” commands mutate scene-local `focusedTarget`, rather than mutating `Workspace.focusedPaneID`

That would let the model stop pretending to be the live keyboard focus engine.

## Responsibilities In The Better Model

If `gmax` moves toward native SwiftUI focus:

- the scene owns the focus namespace and focus state
- views declare whether they are focusable and what they export when focused
- AppKit bridge code only translates native focus into terminal first responder where needed
- the model owns workspace structure and selection, not transient keyboard focus

That reduces custom coordination, but it does not remove responsibility. The
app still needs to steward:

- how pane focus is restored after splits and closes
- what region should receive focus when a workspace becomes empty
- how command enablement behaves when focus sits in the sidebar, in a pane terminal, or in inspector content

## Recorded Design Decisions

- The inspector is a real focus region, but pane-oriented commands disable when
  focus leaves content and moves there.
- The embedded terminal should not regain a broad AppKit focus adapter layer.
  The remaining bridge should stay narrow and only translate native responder
  behavior where SwiftTerm still needs help.
- Per-window open-workspace state and recent-close state restore independently
  through the scene-scoped payload-plus-placement persistence model rather than
  through app-global live window state.
- Pane focus and workspace selection stay aligned at the workspace-window
  level. Changing the selected workspace resets pane focus into that window's
  active workspace context rather than letting pane focus drift across
  workspaces.

Prompt-versus-scrollback is intentionally no longer an open question here.
SwiftTerm owns that internal terminal interaction behavior, and `gmax` should
keep treating the enclosing pane as the workspace-level focus and command
target.

The SwiftTerm-side ownership question is also much narrower now than it was in
earlier planning. [`swiftterm-surface-investigation.md`](./swiftterm-surface-investigation.md)
should be treated as the current source of truth for what SwiftTerm already
handles cleanly on its own and which remaining behaviors are still wrapper-side
glue in `gmax`.

Pane navigation policy is also no longer an open question here.
The intended behavior remains:

- spatial pane navigation
- next/previous pane traversal alongside spatial movement

The remaining work there is implementation narrowing toward more native focus
movement over time, not semantic redesign.

## Recommended Next Step

Before the next implementation pass, keep implementation work aligned to this
already-decided target model for these three example slices:

1. user clicks a pane terminal
2. user presses `Command-W` with focus in a pane terminal
3. user invokes a pane-navigation command while the sidebar or inspector has focus

The close-command portion of that target model is already settled:

- `Command-W` closes an actively focused pane
- if the actively selected workspace has no panes, `Command-W` closes that
  workspace
- if focus is in the sidebar and a workspace listing is focused, `Command-W`
  closes that workspace
- if focus is on the only workspace in a window and that workspace has no
  panes, `Command-W` closes the window
- if focus is in the inspector, `Command-W` does nothing

The remaining work is to make the implementation express those rules more
directly, not to reopen the decision itself.
