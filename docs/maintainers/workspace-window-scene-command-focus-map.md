## Purpose

This note maps the current scene, focus, command, and dismissal architecture for the main workspace window in `gmax`.

Unlike [`swiftui-command-and-focus-architecture.md`](./swiftui-command-and-focus-architecture.md), which records the repo's preferred default model, this file is a current-state implementation map. Treat it as the authoritative description of what the code is doing today, including edges that may deserve redesign.

For the current findings and priority order on what looks strong versus risky, also read [`framework-command-audit.md`](./framework-command-audit.md).

## Double-Check Sources

This map was checked against the current app code and the Apple APIs the code is relying on.

Primary repo surfaces:

- [`gmax/gmaxApp.swift`](../../gmax/gmaxApp.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneView.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneCommands.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneCommands.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/SidebarPanel/SidebarPane.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/SidebarPanel/SidebarPane.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/DetailPanel/DetailPane.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/DetailPanel/DetailPane.swift)
- [`gmax/Views/Sheets/SavedWorkspaceLibrarySheet.swift`](../../gmax/Views/Sheets/SavedWorkspaceLibrarySheet.swift)
- [`gmax/Workspace/WorkspaceStore.swift`](../../gmax/Workspace/WorkspaceStore.swift)
- [`gmax/Workspace/WorkspaceStore+PaneActions.swift`](../../gmax/Workspace/WorkspaceStore+PaneActions.swift)
- [`gmax/Workspace/WorkspaceStore+WorkspaceActions.swift`](../../gmax/Workspace/WorkspaceStore+WorkspaceActions.swift)

Primary Apple references:

- [`Scene.commands(content:)`](https://developer.apple.com/documentation/swiftui/scene/commands(content:))
- [`Commands`](https://developer.apple.com/documentation/swiftui/commands)
- [`CommandGroup`](https://developer.apple.com/documentation/swiftui/commandgroup)
- [`Building and customizing the menu bar with SwiftUI`](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui)
- [`focusedSceneValue(_:_:)`](https://developer.apple.com/documentation/swiftui/view/focusedscenevalue(_:_:))
- [`focusedValue(_:_:)`](https://developer.apple.com/documentation/swiftui/view/focusedvalue(_:_:))
- [`DismissAction`](https://developer.apple.com/documentation/swiftui/dismissaction)
- [`WindowGroup`](https://developer.apple.com/documentation/swiftui/windowgroup)
- [`Settings`](https://developer.apple.com/documentation/swiftui/settings)
- [`PreferenceKey`](https://developer.apple.com/documentation/swiftui/preferencekey)

The key Apple behavior to keep in mind while reading this map:

- Scene commands are attached at the scene layer and update against the active scene.
- `focusedSceneValue` publishes command context that stays visible while the scene is active.
- `focusedValue` publishes context that disappears when focus leaves that subtree.
- `dismiss()` dismisses the current presentation first. In a sheet, it dismisses the sheet; in a window hierarchy, it can dismiss the window.

## Top-Level Scene Structure

The app declares two scene surfaces in [`gmax/gmaxApp.swift`](../../gmax/gmaxApp.swift):

1. A `WindowGroup` with the identifier `"main-window"` whose root view is `WorkspaceWindowSceneView`.
2. A `Settings` scene whose root view is `SettingsUtilityWindow`.

The workspace window scene also attaches `WorkspaceWindowSceneCommands` through `.commands { ... }` directly on the `WindowGroup`.

That means the main command surface for the app is not global app state. It is the command set attached to the workspace window scene, evaluated against whichever window scene is currently active.

## Workspace Window Scene Ownership

`WorkspaceWindowSceneView` is the scene root for the main workspace window.

It owns:

- the per-window `WorkspaceStore`
- the selected workspace ID
- pending rename and deletion presentation state
- the saved-workspace-library sheet state
- split-view column visibility
- inspector visibility
- per-window scene restoration state through `@SceneStorage`

This is an important boundary: the scene root owns window-local selection and presentation state, while `WorkspaceStore` owns the workspace graph, pane graph, sessions, and persistence-facing mutations.

The scene root is therefore doing real scene coordination work. It is not just a `NavigationSplitView` wrapper.

## Current Scene Layout

Inside `WorkspaceWindowSceneView`, the main window surface is:

- `NavigationSplitView`
- sidebar: `SidebarPane`
- detail/content: `ContentPane`
- inspector: `DetailPane`

The scene root also presents:

- the saved workspace library as a sheet
- workspace deletion as an alert
- workspace rename as a sheet

Those presentation surfaces are scene-owned. They are not owned by the sidebar or pane subtree directly.

## Current Focus And Command Context Publication

The main scene publishes command context in two layers.

### Scene-wide publication from `WorkspaceWindowSceneView`

The scene root publishes:

- `.focusedSceneObject(workspaceStore)`
- `.focusedSceneValue(\.activeWorkspaceFocusTarget, focusedTarget)`
- `.focusedSceneValue(\.selectedWorkspaceSelection, $selectedWorkspaceID)`
- `.focusedSceneValue(\.openSavedWorkspaceLibrary, openSavedWorkspaceLibrary)`
- `.focusedSceneValue(\.presentWorkspaceRename, presentWorkspaceRename)`
- `.focusedSceneValue(\.presentWorkspaceDeletion, presentWorkspaceDeletion)`

Those values represent scene-scoped state and scene-scoped actions:

- which logical workspace focus target is active in this window
- which workspace is selected in this window
- how to open the saved workspace sheet in this window
- how to present rename and deletion flows in this window
- the store that backs this window

These values are available to scene commands while the window scene is active, regardless of whether focus is in the sidebar, content pane, or inspector.

### Focused-subtree publication from content views

The content subtree publishes narrower values:

- `ContentPaneLeafView` publishes `.focusedValue(\.closeFocusedPane, isFocused ? onClose : nil)` only for the focused pane leaf.

That creates a layered command context:

- scene-wide workspace selection and presentation actions come from the scene root
- pane-specific close behavior comes from the focused pane
- scene commands derive empty-workspace close behavior from the active focus target plus selected workspace state

This is one of the most important current design choices in the repo.

## Current `FocusedValues` Surface

`WorkspaceWindowSceneCommands.swift` extends `FocusedValues` with six entries:

- `activeWorkspaceFocusTarget`
- `selectedWorkspaceSelection`
- `openSavedWorkspaceLibrary`
- `presentWorkspaceRename`
- `presentWorkspaceDeletion`
- `closeFocusedPane`

The first five are effectively scene-scoped command dependencies.

The last one is a context-sensitive close action:

- close the currently focused pane if a pane subtree owns focus

The file currently mixes the `FocusedValues` key declarations and the command implementation in one place. That is workable, but it means this file is both the key registry and the concrete menu surface.

## Command Consumption Model

`WorkspaceWindowSceneCommands` consumes command context with:

- `@Environment(\.dismiss)`
- `@FocusedObject private var workspaceStore: WorkspaceStore?`
- `@FocusedValue(...)` for the six custom keys

The command set then derives a local view of the active scene:

- `activeWorkspaceFocusTarget`
- `workspaces`
- `selectedWorkspaceID`
- `selectedWorkspace`
- `canSplitFocusedPane`
- `canDeleteSelectedWorkspace`
- `canCycleWorkspaces`

In other words, the command layer is not dispatching into a separate command router. It reads focused scene state, derives availability, and then directly calls store mutations or scene-owned closures.

That is currently one of the cleaner parts of the architecture.

## Menu And Keyboard Surface

The command scene currently includes:

- `SidebarCommands()`
- `InspectorCommands()`
- `TextEditingCommands()`
- `TextFormattingCommands()`
- `ToolbarCommands()`

It also adds custom command groups and menus:

### File / new-item-adjacent commands

- `New Workspace` with `Shift-Command-N`
- `Open Workspace…` with `Command-O`

### Replaced save group

`CommandGroup(replacing: .saveItem)` currently provides:

- `Save Workspace` with `Command-S`
- a divider
- a context-sensitive `Command-W` action whose label and target change between:
  - `Close Pane`
  - `Close Workspace`
  - `Close Window`

That means the app is currently replacing the system save-item group in order to inject both custom save behavior and custom close behavior into the same replacement group.

That is a very important implementation detail, because it means the standard command placement is being customized more aggressively here than in the rest of the menu setup.

### `Workspace` command menu

The custom `Workspace` menu currently exposes:

- `Undo Close Workspace`
- `Rename Workspace`
- `Duplicate Workspace Layout`
- `Close Workspace to Library`
- `Close Workspace`
- `Delete Workspace`
- `Previous Workspace`
- `Next Workspace`

### `Pane` command menu

The custom `Pane` menu currently exposes:

- move focus left, right, up, down
- focus next pane
- focus previous pane
- `Split Right`
- `Split Down`

These commands mostly target `WorkspaceStore` directly, using the selected workspace binding and focused store object.

## Current Close And Dismissal Behavior

The app currently has three different close layers, and they are easy to confuse if they are not documented separately.

### 1. Sheet dismissal

`SavedWorkspaceLibrarySheet` uses `@Environment(\.dismiss)` and dismisses itself directly after opening a saved workspace or when the user presses Cancel.

The workspace rename sheet is scene-owned rather than self-dismissing. It dismisses by clearing `workspacePendingRenameID` through scene-owned closures.

The deletion confirmation alert dismisses by clearing `workspacePendingDeletionID`.

### 2. Pane close

When a pane leaf is focused, `ContentPaneLeafView` publishes `closeFocusedPane`.

When the command layer sees that focused value, `Command-W` becomes `Close Pane` and invokes the pane-close closure rather than dismissing the window.

### 3. Empty workspace close or window close

When there is no focused pane close action, the scene command layer resolves
close behavior from:

- `activeWorkspaceFocusTarget`
- the selected workspace
- whether the selected workspace is empty
- whether the current window contains only one workspace

That produces the recorded product behavior:

- `Command-W` closes the selected workspace when the active workspace is empty
- `Command-W` closes the selected workspace when the sidebar is the active focus target
- `Command-W` closes the window when the selected workspace is the only workspace in the window and it is empty
- `Command-W` does nothing when the inspector is the active focus target

This means `Command-W` is still a context-sensitive close action, but the
scene now resolves that behavior directly from scene focus and workspace state
instead of relying on a separate `closeEmptyWorkspace` publication path from
`ContentPane`.

That behavior is coherent, but it is also one of the highest-risk surfaces in the current architecture because it combines:

- scene focus
- content focus
- workspace emptiness
- window dismissal

into a single command slot.

## Parent-Child Coordination Model

The app mostly uses ordinary parent-child coordination for view composition:

- the scene root owns selected workspace and presentation state
- `SidebarPane` mutates selection through bindings and asks the scene root to present rename or delete flows through closures
- `ContentPane` receives the store and current selected workspace binding
- `DetailPane` reads the selected workspace and focused pane from the store

That part is relatively direct. There is no separate coordinator or app-defined command bus between the view tree and the store.

## Preference Usage

The only current preference-based upward signal in this surface is pane geometry.

`ContentPaneLeafView` publishes pane frame rectangles through `ContentPaneFramePreferenceKey`, and `ContentPane` consumes those values with `.onPreferenceChange(...)` to feed `WorkspaceStore.updatePaneFrames(...)`.

That use of `PreferenceKey` is aligned with SwiftUI's intended child-to-container signaling model. It is carrying layout metadata upward rather than trying to route commands upward.

## Settings Scene

The app's settings surface is currently separate from the workspace window scene.

`SettingsUtilityWindow` is rooted in the `Settings` scene and uses `@AppStorage` directly for:

- terminal appearance settings
- workspace restore-on-launch behavior
- recently closed workspace retention
- auto-save closed workspaces

That means settings are not currently routed through `WorkspaceStore`, focused values, or scene command infrastructure. They are ordinary settings-scene state backed by app storage.

## Current Architectural Strengths

The current implementation is strongest in these areas:

- scene-local state is mostly owned by the scene root instead of being pushed into app-global state
- menu commands are attached at the scene boundary rather than routed through a custom global command system
- pane-specific command behavior uses focused values instead of hidden global selection guesses
- child-to-container layout signaling uses `PreferenceKey` for geometry rather than command routing
- settings are isolated in a separate scene instead of being folded into the workspace window

## Current Friction Points And Likely Redesign Targets

These are the most important places that look brittle or confusing today.

### Context-sensitive `Command-W`

The app currently overloads one close shortcut across:

- close pane
- close empty workspace
- close window

That behavior is understandable once mapped, but it is not obvious from the implementation at a glance, and it combines multiple responsibility layers in a single command branch.

### Scene-storage keys still use old naming

`WorkspaceWindowSceneView` still stores per-window restoration under:

- `"mainShell.selectedWorkspaceID"`
- `"mainShell.isInspectorVisible"`
- `"mainShell.isSidebarVisible"`

Those keys still work, but they no longer match the current terminology and make the scene root look more transitional than it actually is.

### Scene command file owns both keys and commands

`WorkspaceWindowSceneCommands.swift` currently owns:

- the `FocusedValues` key declarations
- the command implementation

That is not automatically wrong, but it means one file is carrying both the command vocabulary definition and the concrete menu behavior.

### The command layer mixes direct store mutation and scene-owned closures

Some commands act by:

- mutating the store directly

Others act by:

- calling scene-owned closures published through focused scene values

That split matches current ownership boundaries, but it is worth keeping visible because any larger redesign should decide whether that split stays intentional or gets normalized further.

### The docs previously understated current implementation detail

The policy note was doing a reasonable job of describing preferred architecture, but it was not a detailed enough map of the current command surface to support a major redesign safely.

That is the gap this document is meant to close.

## Practical Redesign Questions

If this surface is reworked later, these are the questions to answer first:

1. Should `Command-W` remain context-sensitive across pane, workspace, and window layers, or should those surfaces be separated more explicitly?
2. Should the focused-value key declarations remain co-located with the command implementation, or move to a narrower command-context file?
3. Should more pane commands move to explicit focused pane actions, or is store-plus-selection the correct level for pane navigation commands?
4. Should scene restoration keys be renamed now that the shell vocabulary has been retired elsewhere?
5. Are rename and delete presentation closures the right scene-scoped command dependency surface, or should those flows be represented differently?

## Suggested Companion Reading

- Preferred defaults: [`swiftui-command-and-focus-architecture.md`](./swiftui-command-and-focus-architecture.md)
- Current workspace state model: [`../../gmax/Workspace/WorkspaceStore.swift`](../../gmax/Workspace/WorkspaceStore.swift)
- Current persistence behavior: [`../../gmax/Persistence/Workspace/WorkspacePersistenceController.swift`](../../gmax/Persistence/Workspace/WorkspacePersistenceController.swift)
