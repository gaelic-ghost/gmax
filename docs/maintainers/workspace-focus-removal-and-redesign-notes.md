# Workspace Focus Removal and Redesign Notes

## Purpose

This note maps the current custom workspace-pane focus machinery in `gmax`, marks the parts that should be removed or replaced, and outlines a more SwiftUI-native focus model to discuss before implementation.

Use this alongside:

- [`swiftui-command-and-focus-architecture.md`](./swiftui-command-and-focus-architecture.md) for the preferred default model
- [`workspace-window-scene-command-focus-map.md`](./workspace-window-scene-command-focus-map.md) for the current command and focused-value flow
- [`framework-command-audit.md`](./framework-command-audit.md) for the broader redesign gaps and priorities

## Current Custom Focus Surface

The current pane focus system is not primarily driven by SwiftUI focus placement. It is driven by `WorkspaceStore` state and then mirrored into SwiftUI and AppKit.

The main custom pieces are:

- `Workspace.focusedPaneID` in [`gmax/Workspace/WorkspaceLayout.swift`](../../gmax/Workspace/WorkspaceLayout.swift)
  - The model stores which pane is considered focused.
  - This focus state is persisted and restored through workspace persistence.
- `WorkspaceStore.focusPane`, `movePaneFocus`, `recordPaneFocus`, and related helpers in [`gmax/Workspace/WorkspaceStore+PaneActions.swift`](../../gmax/Workspace/WorkspaceStore+PaneActions.swift)
  - Clicks, splits, closes, relaunches, and directional navigation all mutate model focus directly.
- `paneFocusHistoryByWorkspace` in [`gmax/Workspace/WorkspaceStore.swift`](../../gmax/Workspace/WorkspaceStore.swift)
  - The model keeps its own fallback history for which pane should become focused next.
- `paneFramesByWorkspace` and `updatePaneFrames` in [`gmax/Workspace/WorkspaceStore.swift`](../../gmax/Workspace/WorkspaceStore.swift) and [`gmax/Workspace/WorkspaceStore+PaneActions.swift`](../../gmax/Workspace/WorkspaceStore+PaneActions.swift)
  - Pane geometry is captured and stored so directional focus can be resolved manually.
- `ContentPaneFramePreferenceKey` and `.onPreferenceChange(...)` in [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift)
  - Descendants report pane frames upward so the model can compute directional pane focus.
- `isFocused` plumbing through [`ContentPane.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift), [`ContentPaneLeafView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift), and [`TerminalPaneView.swift`](../../gmax/Terminal/Panes/TerminalPaneView.swift)
  - The view tree receives model-derived focus rather than determining focus natively.
- `onFocus` closures from [`ContentPaneLeafView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift) into [`TerminalPaneView+Coordinator.swift`](../../gmax/Terminal/Panes/TerminalPaneView+Coordinator.swift)
  - Pointer and accessibility interactions explicitly push focus back into the model.
- `window?.makeFirstResponder(...)` calls in [`TerminalPaneView+Coordinator.swift`](../../gmax/Terminal/Panes/TerminalPaneView+Coordinator.swift)
  - The AppKit bridge force-aligns the terminal view's first responder with model focus.

## Removal Or Replacement Map

The goal here is not “delete focus.” The goal is to stop owning custom focus state where SwiftUI or AppKit already has a native concept for it.

### Remove or redesign first

- `Workspace.focusedPaneID`
  - Marked for removal as the primary live focus source of truth.
  - It may survive only as a persistence or restoration hint if product requirements justify it, but it should stop being the authoritative runtime focus state.
- `WorkspaceStore.focusPane(...)`
  - Marked for removal as a general focus-entry API.
  - Focus should not normally be pushed into the model from arbitrary click handlers.
- `movePaneFocus(...)`
  - Marked for redesign.
  - The command intent likely remains, but the implementation should target SwiftUI/AppKit focus movement rather than a geometry-driven model field.
- `paneFocusHistoryByWorkspace`
  - Marked for removal unless a concrete product behavior still needs history-aware fallback beyond framework focus restoration.
- `paneFramesByWorkspace`, `updatePaneFrames(...)`, and directional geometry ranking
  - Marked for removal if pane-to-pane navigation can be expressed through native focus movement or a simpler explicit focus graph.
- `onFocus` closure chains and `.onTapGesture(perform: onFocus)`
  - Marked for removal as the normal way panes become focused.
  - Native focus movement should do this work.
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
- explicit “move focus left/right/up/down” commands mutate `focusedTarget` or call a narrow responder/focus coordinator, rather than mutating `Workspace.focusedPaneID`

That would let the model stop pretending to be the live keyboard focus engine.

## Responsibilities In The Better Model

If `gmax` moves toward native SwiftUI focus:

- the scene owns the focus namespace and focus state
- views declare whether they are focusable and what they export when focused
- AppKit bridge code only translates native focus into terminal first responder where needed
- the model owns workspace structure and selection, not transient keyboard focus

That reduces custom coordination, but it does not remove responsibility. The app would still need to steward:

- how pane focus is restored after splits and closes
- what region should receive focus when a workspace becomes empty
- whether sidebar, content, and inspector participate in one shared graph or partially isolated focus regions
- how command enablement behaves when focus sits in the sidebar, in a pane terminal, or in inspector content

## Open Design Questions

- Should the app persist the last focused pane for workspace restoration, or should that become best-effort only?
- Should pane-to-pane directional movement stay spatial, or become a simpler next/previous graph with optional spatial refinement later?
- Should the inspector ever become a command target for pane-oriented commands, or should those commands disable whenever focus leaves content?
- Does the embedded terminal need a dedicated AppKit focus adapter object, or can the pane wrapper own that translation directly?
- Should pane focus and workspace selection always move together, or can they diverge temporarily?

## Recommended Next Step

Before implementation, define one explicit target model for these three example slices:

1. user clicks a pane terminal
2. user presses `Command-W` with focus in a pane terminal
3. user invokes a pane-navigation command while the sidebar or inspector has focus

If the target model is crisp for those three flows, the rest of the cleanup should become much easier to stage safely.
