# Workspace Focus Guide

## Purpose

This is the canonical maintainer note for workspace-window focus, command
context, selection, and close behavior in `gmax`.

It replaces the older split between:

- `workspace-focus-target-plan.md`
- `workspace-focus-implementation-boundary.md`
- `workspace-focus-first-pass-plan.md`
- `workspace-focus-removal-and-redesign-notes.md`
- `swiftui-command-and-focus-architecture.md`
- `workspace-window-scene-command-focus-map.md`

Use this note for:

- current default architecture guidance
- current ownership boundaries
- the current implementation map
- settled product decisions
- remaining follow-through work

Use it together with:

- [`framework-command-audit.md`](./framework-command-audit.md)
- [`swiftui-terminal-shell-architecture.md`](./swiftui-terminal-shell-architecture.md)

## How To Use This Note

Use the workspace-window notes by role:

- `workspace-focus-guide.md`
  - current defaults, current implementation map, ownership boundary, and open
    follow-through
- `framework-command-audit.md`
  - risk, awkward edges, and test-gap audit
- `swiftui-terminal-shell-architecture.md`
  - historical shell architecture plus the consolidated SwiftTerm-side ownership
    boundary

Historical shell-shape context still lives in
[`swiftui-terminal-shell-architecture.md`](./swiftui-terminal-shell-architecture.md),
but it is not the source of truth for current focus or command behavior.

## Status

The structural focus cleanup is complete.

What remains is not another architecture reset. The remaining work is product
verification, accessibility follow-through, naming cleanup, and stronger
multi-window regression coverage for behavior that is already intentional.

The current shipped shape is:

- pane leaves participate in scene focus with `.focusable(interactions: .edit)`
- `WorkspaceWindowSceneView` is the single runtime owner of pane focus
- pane split, close, and navigation commands are derived at the scene root
- pane close restores the latest surviving focused pane from scene-local
  history
- the app intentionally supports multiple workspace windows, each with its own
  `WorkspaceSceneIdentity`, scene-local UI restoration, and independent
  persisted live and recently closed workspace state

## Research Workflow

Before relying on any rule in this note:

- Prefer the Xcode MCP `DocumentationSearch` tool for current SwiftUI and
  AppKit API lookup.
- Use Dash as a fallback or cross-check when local doc browsing is more
  convenient.
- On this machine, the most relevant installed Apple Dash docsets are the
  generic Swift API reference (`ntiaiyxj-swift`), Objective-C API reference
  (`ntiaiyxj-objc`), and offline macOS set (`jtswqsfb`).
- If neither local path answers the question clearly, use the official Apple
  documentation URLs linked at the end of this note.

Use this note as a strong repo-local default, not as a substitute for current
Apple documentation. If this note and the SwiftUI or AppKit docs appear to
disagree, re-check the Apple docs first and update this note instead of
treating it as infallible law.

## Current Default Model

- Put app-specific menu commands on the scene with `Scene.commands`.
- Prefer built-in command groups like `SidebarCommands`,
  `InspectorCommands`, and `ToolbarCommands` when they already match the
  product surface.
- Use `focusedSceneValue` or `focusedSceneObject` for command context that
  should remain available while the window scene is active.
- Use `focusedValue` or `focusedObject` for command context that should only
  exist while a specific view or subtree is focused.
- Use bindings, closures, and ordinary view state for normal parent-child
  coordination.
- Use environment values for downward configuration and built-in actions like
  `dismiss`, `dismissWindow`, `openWindow`, and `openSettings`.
- Use preferences only for child-to-container signals, especially layout or
  container-facing configuration.
- Keep ordinary window close behavior framework-owned unless there is a
  concrete product need and a documented framework gap.

## Repo-Specific Defaults For `gmax`

These are preferences derived from current product shape, not universal SwiftUI
laws:

- per-window workspace selection should stay scene-local rather than app-global
- pane-targeted commands should prefer focused pane context over "current
  selection" guesses
- `Close Window`, `Close Workspace`, and `Close Pane` are different actions and
  should stay distinct
- a presented sheet or alert should normally dismiss through its presenter
  before any app-defined workspace mutation tries to happen underneath it
- custom routing or close infrastructure should stay narrow and local when it
  is truly needed

The main lesson from earlier cleanup work is simple: `gmax` got into trouble
when it duplicated built-in scene, focus, and window behavior with custom
routing layers. The goal of this note is to preserve that lesson without
overstating what SwiftUI guarantees.

## Current Product Decisions

These are not open planning questions anymore:

- the workspace window owns a scene-local focus namespace
- the scene owns window-local selection, sidebar and inspector visibility, and
  modal presentation state
- pane containers own pane identity and visual focus treatment
- the sidebar stays native and list-driven
- the inspector is a real focus region, but pane-oriented commands disable when
  focus leaves content and moves there
- SwiftTerm owns prompt input, scrollback selection, copy, find, and
  terminal-native responder behavior
- `gmax` does not model prompt versus scrollback as separate scene-level focus
  targets
- AppKit interop should stay narrow and should not reintroduce a custom
  terminal focus bridge or first-responder forcing path

`Command-W` is also settled:

- if a scene-owned modal surface is frontmost, `Command-W` dismisses that modal
  first
- if a pane is the active focus target, `Command-W` closes that pane
- if the selected workspace is empty, `Command-W` closes that workspace unless
  it is the only workspace in the window, in which case it closes the window
- if focus is in the sidebar on a workspace listing, `Command-W` closes that
  workspace unless that empty workspace is the only workspace in the window
- if focus is in the inspector, `Command-W` does nothing

Do not reopen that product decision casually during adjacent cleanup work.

## Ownership Boundary

### Scene responsibilities

The workspace window scene owns:

- selected workspace
- window-local sidebar and inspector visibility
- scene-local modal presentation state
- the scene-wide command context exported through focused scene values
- `@FocusState` for `WorkspaceFocusTarget`

The scene does not own terminal responder behavior, and it does not push focus
into SwiftTerm through a custom bridge.

### Pane responsibilities

Pane containers own:

- pane focus identity
- visual focus treatment for the active pane
- terminal hosting and pane-local accessibility surfaces

Pane identity is a workspace-window concern. It is not stored as live runtime
state on the workspace model.

Pane command behavior is still pane-targeted, but the command closures are now
published from the scene root based on the active pane focus target rather than
from each pane leaf through separate `focusedValue` writes.

### SwiftTerm responsibilities

SwiftTerm owns:

- prompt input
- scrollback selection
- copy and select all
- built-in find behavior
- terminal-native responder and mouse behavior

`gmax` treats the enclosing pane as the workspace-level command target. It does
not model prompt versus scrollback as separate scene-level focus targets.

### AppKit interop boundary

The AppKit boundary should stay limited to:

- hosting SwiftTerm inside SwiftUI
- session lifecycle and transcript wiring
- ordinary accessibility labeling for the enclosing pane surface

The AppKit boundary should not grow back into:

- a custom first-responder forcing path
- a replacement for SwiftUI scene focus
- a replacement for SwiftTerm's terminal interaction model

## Choosing The Right Channel

### Scene command surface

When a command belongs in the menu bar or keyboard-command surface for a window
scene, define it on the scene through `Scene.commands`.

In `gmax`, that means
[`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneCommands.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneCommands.swift)
is the normal home for workspace-window command definitions.

### Scene-wide command context

Use `focusedSceneValue` or `focusedSceneObject` when the command should stay
available as long as the window scene is active, regardless of which child view
currently has keyboard focus.

Good examples in `gmax`:

- the selected workspace for the active window
- scene-owned sheet or alert presentation actions
- scene-owned rename, delete, or reopen context

### Focused-view command context

Use `focusedValue` or `focusedObject` when the command should only be available
while a specific view or its descendants are focused.

In `gmax`, this is still the right tool for genuinely subtree-local context.
But after the pane-focus cleanup, pane split, close, and directional navigation
are no longer exported from each `ContentPaneLeafView`. Those command closures
are now scene-owned and derived from `focusedTarget` at the scene root so the
window has a single writer for pane command context.

If the pane is not the focused part of the scene, the command should normally
disable rather than guessing a target through an app-global backchannel.

### Parent-child coordination

If the problem is just ordinary view composition, prefer bindings, closures,
and direct state ownership over command infrastructure.

### Child-to-container signals

Use preferences only when a descendant needs to report information upward to a
container that reconciles or acts on it.

This is the right tool for layout and container-facing metadata. It is not the
default tool for command routing.

### Built-in environment actions

Before adding a custom command or action surface, check whether SwiftUI already
provides the action through the environment:

- `dismiss`
- `dismissWindow`
- `openWindow`
- `openSettings`

If one of those already models the behavior, prefer it.

### AppKit escape hatch

If the job really belongs to the responder chain, menu validation, toolbar
validation, or window-delegate lifecycle, AppKit may be the correct primitive.

That is still different from inventing a parallel in-house responder or command
system. Use the native AppKit surface directly before creating a custom
abstraction.

## Current Implementation Map

This section is the current-state implementation map for the main workspace
window. Treat it as the authoritative description of what the code is doing
today, including edges that may deserve redesign.

### Top-level scene structure

The app declares two scene surfaces in
[`gmax/gmaxApp.swift`](../../gmax/gmaxApp.swift):

1. A `WindowGroup` with the identifier `"main-window"` whose root view is
   `WorkspaceWindowSceneView`.
2. A `Settings` scene whose root view is `SettingsUtilityWindow`.

The workspace window scene attaches `WorkspaceWindowSceneCommands` directly on
the `WindowGroup`.

That means the main command surface for the app is not global app state. It is
the command set attached to the workspace window scene, evaluated against
whichever window scene is currently active.

### Workspace window scene ownership today

`WorkspaceWindowSceneView` owns:

- the per-window `WorkspaceStore`
- the selected workspace ID
- pending rename and deletion presentation state
- the saved-workspace-library sheet state
- split-view column visibility
- inspector visibility
- per-window scene restoration state through `@SceneStorage`

This is an important boundary: the scene root owns window-local selection and
presentation state, while `WorkspaceStore` owns the workspace graph, pane
graph, sessions, and persistence-facing mutations.

### Current scene layout

Inside `WorkspaceWindowSceneView`, the main window surface is:

- `NavigationSplitView`
- sidebar: `SidebarPane`
- detail/content: `ContentPane`
- inspector: `DetailPane`

The scene root also presents:

- the saved workspace library as a sheet
- workspace deletion as an alert
- workspace rename as a sheet

Those presentation surfaces are scene-owned. They are not owned by the sidebar
or pane subtree directly.

### Current focus and command-context publication

The main scene publishes command context in two layers.

Scene-wide publication from `WorkspaceWindowSceneView`:

- `.focusedSceneObject(workspaceStore)`
- `.focusedSceneValue(\.activeWorkspaceFocusTarget, focusedTarget)`
- `.focusedSceneValue(\.selectedWorkspaceSelection, $selectedWorkspaceID)`
- `.focusedSceneValue(\.dismissPresentedWorkspaceModal,
  dismissPresentedWorkspaceModal)`
- `.focusedSceneValue(\.openLibrary, openLibrary)`
- `.focusedSceneValue(\.presentWorkspaceRename, presentWorkspaceRename)`
- `.focusedSceneValue(\.presentWorkspaceDeletion, presentWorkspaceDeletion)`
- `.focusedSceneValue(\.moveFocusedPaneFocus, moveFocusedPaneFocusAction)`
- `.focusedSceneValue(\.splitFocusedPane, splitFocusedPaneAction)`
- `.focusedSceneValue(\.closeFocusedPane, closeFocusedPaneAction)`

Those values represent scene-scoped state and scene-scoped actions:

- which logical workspace focus target is active in this window
- which workspace is selected in this window
- how to dismiss the frontmost scene-owned modal in this window
- how to open the library sheet in this window
- how to present rename and deletion flows in this window
- how to move, split, or close the currently focused pane in this window
- the store that backs this window

Focused-subtree publication from content views is now minimal:

- `ContentPaneLeafView` participates in scene focus with `.focusable` and
  `.focused(...)`
- pane leaves publish pane geometry upward through `PreferenceKey`
- pane leaves no longer publish split, close, or navigation closures through
  `focusedValue`

That creates a simpler command context:

- scene-wide workspace selection, pane actions, and presentation actions come
  from the scene root
- pane leaves participate in the focus system, but they are not additional
  command-context writers
- scene commands derive empty-workspace and pane close behavior from the active
  focus target plus selected workspace state

### Current `FocusedValues` surface

`WorkspaceWindowSceneCommands.swift` extends `FocusedValues` with entries for:

- `activeWorkspaceFocusTarget`
- `selectedWorkspaceSelection`
- `dismissPresentedWorkspaceModal`
- `openLibrary`
- `presentWorkspaceRename`
- `presentWorkspaceDeletion`
- `moveFocusedPaneFocus`
- `splitFocusedPane`
- `closeFocusedPane`

The file currently mixes the focused-value key declarations and the command
implementation in one place. That is workable, but it means one file owns both
the command-context contract and the concrete menu surface.

### Command consumption model

`WorkspaceWindowSceneCommands` consumes command context with:

- `@Environment(\.dismiss)`
- `@FocusedObject private var workspaceStore: WorkspaceStore?`
- `@FocusedValue(...)` for the custom keys

The command layer reads focused scene state, derives availability, and then
directly calls store mutations or scene-owned closures. It is not dispatching
into a separate command router.

### Menu and keyboard surface

The command scene currently includes:

- `SidebarCommands()`
- `InspectorCommands()`
- `TextEditingCommands()`
- `TextFormattingCommands()`
- `ToolbarCommands()`

It also adds:

- `New gmax Window` through the `WindowGroup` scene title
- `New Workspace` with `Shift-Command-N`
- `Open Library…` with `Command-O`
- `Save Workspace` with `Command-S`
- a context-sensitive `Command-W` slot
- `Close Window` with `Option-Command-W`
- `Undo Close Window` with `Shift-Option-Command-W`
- a custom `Workspace` menu
- a custom `Pane` menu

The `Workspace` menu currently exposes:

- `Close Window`
- `Undo Close Window`
- `Undo Close Workspace`
- `Rename Workspace`
- `Duplicate Workspace Layout`
- `Close Workspace to Library`
- `Close Workspace`
- `Delete Workspace`
- `Previous Workspace`
- `Next Workspace`

The `Pane` menu currently exposes:

- move focus left, right, up, down
- focus next pane
- focus previous pane
- `Split Right`
- `Split Down`

### Current close and dismissal behavior

The app currently has three different close layers.

Sheet dismissal:

- `LibrarySheet` uses `@Environment(\.dismiss)` to close itself
  and `@Environment(\.openWindow)` to reopen saved window items through the
  same `WorkspaceSceneIdentity`-driven `WindowGroup` path
- the workspace rename sheet is scene-owned and dismisses by clearing
  `workspacePendingRenameID`
- the deletion confirmation alert dismisses by clearing
  `workspacePendingDeletionID`

Pane close:

- when the active focus target is a pane, the scene root publishes
  `closeFocusedPane`
- `Command-W` becomes `Close Pane`
- after pane removal, the scene restores pane focus from the latest surviving
  entry in `paneFocusHistory`

Window reactivation:

- when a workspace window becomes active again, the scene root watches the
  window-level `appearsActive` environment value instead of relying on the
  coarser scene phase
- if no modal is frontmost, the scene restores pane focus from the most recent
  surviving entry in `paneFocusHistory`
- if the same pane is already the remembered focus target, the scene briefly
  clears and reapplies that focus so the pane actually becomes first responder
  again

Empty workspace close or window close:

- if a scene-owned modal is frontmost, the command layer consults
  `dismissPresentedWorkspaceModal` first and uses `Close` to dismiss that modal
- when there is no focused pane close action, the scene command layer resolves
  close behavior from `activeWorkspaceFocusTarget`, the selected workspace,
  whether the selected workspace is empty, and whether the current window
  contains only one workspace

Dedicated window close and reopen:

- `Close Window` is an explicit scene command separate from the adaptive
  `Command-W` slot
- `WorkspaceWindowSceneView` publishes the active
  `WorkspaceSceneIdentity` as scene command context
- when a window disappears, the scene routes that identity through
  `WorkspaceWindowRestorationController`, which updates the durable
  `WorkspaceWindowEntity` record in Core Data
- `Undo Close Window` pops the newest closed identity and reopens it with
  `openWindow(value:)`
- because reopen uses the same `WorkspaceSceneIdentity`, the window restores
  the same per-window live workspaces, durable recently closed workspace
  history, and
  scene-local UI state instead of creating a fresh unrelated window identity

### Parent-child coordination model

The app mostly uses ordinary parent-child coordination for view composition:

- the scene root owns selected workspace and presentation state
- `SidebarPane` mutates selection through bindings and asks the scene root to
  present rename or delete flows through closures
- `ContentPane` receives the store and current selected workspace binding
- `DetailPane` reads the selected workspace and focused pane from the store

There is no separate coordinator or app-defined command bus between the view
tree and the store.

### Preference usage

The only current preference-based upward signal in this surface is pane
geometry.

`ContentPaneLeafView` publishes pane frame rectangles through
`ContentPaneFramePreferenceKey`, and `ContentPane` forwards those values upward
so the scene root can maintain pane-geometry state for directional focus.

That use of `PreferenceKey` is aligned with SwiftUI's intended
child-to-container signaling model. It is carrying layout metadata upward
rather than trying to route commands upward.

### Settings scene

`SettingsUtilityWindow` is rooted in the `Settings` scene and uses
`@AppStorage` directly for:

- terminal appearance settings
- workspace restore-on-launch behavior
- recently closed workspace retention
- auto-save closed workspaces

Settings are not currently routed through `WorkspaceStore`, focused values, or
scene command infrastructure.

## What Is Working Well

The current implementation is strongest in these areas:

- scene-local state is mostly owned by the scene root instead of app-global
  state
- menu commands are attached at the scene boundary rather than routed through a
  custom global command system
- pane-specific command behavior is derived from the scene-owned focus target
  instead of hidden global selection guesses or per-pane command writers
- child-to-container layout signaling uses `PreferenceKey` for geometry rather
  than command routing
- settings are isolated in a separate scene instead of being folded into the
  workspace window

## Historical Cleanup That Already Landed

These are complete and should stay complete:

- runtime pane focus no longer lives on `Workspace` or `WorkspaceStore`
- store-owned pane focus history and pane-frame ownership were removed
- pane and inspector tap handlers no longer manually shove scene focus around
- the SwiftTerm-specific focus bridge and custom first-responder adapter were
  removed

Do not reintroduce:

- `Workspace.focusedPaneID` as runtime focus truth
- a store-owned pane focus engine
- a SwiftTerm focus bridge or responder adapter
- a prompt-versus-scrollback focus model inside `gmax`

## Remaining Follow-Through

The remaining work is ordinary product follow-through, not another structural
focus redesign.

### 1. Manual behavior verification

The bridge-free focus surface still needs a real behavior pass across:

- pane activation and typing
- sidebar-to-content transitions
- inspector focus behavior
- `Command-W` in every focus region
- focus restoration when switching between windows and then returning to a
  previously active pane

That work is regression coverage for an intentional multi-window product model.
It is not a question of whether the app should support multiple independent
workspace windows in the first place.

### 2. Better command-surface coverage

The command behavior is clearer than it used to be, but it still needs broader
automated coverage for:

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

## Practical Decision Checklist

Before adding new command, focus, selection, toolbar, sheet, inspector, or
close behavior:

1. Is there already a built-in scene command or command group that fits?
2. Is the command scene-wide or focused-view-specific?
3. Is this just ordinary parent-child composition?
4. Is this a child-to-container signal?
5. Does the environment already provide the action?
6. Is this actually an AppKit job?
7. If none of the above fit cleanly, what exact framework gap remains?

## When Custom Infrastructure Is Acceptable

Custom command, focus, or close infrastructure is acceptable only when all of
the following are true:

1. The relevant SwiftUI or AppKit behavior has been checked in current Apple
   docs.
2. The built-in surface leaves a concrete product gap in `gmax`.
3. The narrower options were considered first.
4. The custom path is documented as a local exception rather than a new general
   architecture.
5. Gale approves the tradeoff.

When that happens, the write-up should say:

- which Apple API was considered
- what it does according to the docs
- why it is insufficient here
- what near-term use case the custom path unlocks
- what maintenance cost we are accepting

## Out Of Scope

These are not active focus-plan items:

- reintroducing any SwiftTerm focus bridge or responder adapter
- reviving `Workspace.focusedPaneID` or store-owned pane focus state
- inventing a prompt-versus-scrollback focus model in `gmax`
- reopening the `Command-W` product decision

## Apple References

- `Scene.commands(content:)`
  - <https://developer.apple.com/documentation/swiftui/scene/commands(content:)>
- `Commands`
  - <https://developer.apple.com/documentation/swiftui/commands>
- `CommandMenu`
  - <https://developer.apple.com/documentation/swiftui/commandmenu>
- `CommandGroup`
  - <https://developer.apple.com/documentation/swiftui/commandgroup>
- `Building and customizing the menu bar with SwiftUI`
  - <https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui>
- `focusedSceneValue`
  - <https://developer.apple.com/documentation/swiftui/view/focusedscenevalue(_:_:)-57boz>
- `focusedSceneObject`
  - <https://developer.apple.com/documentation/swiftui/view/focusedsceneobject(_:)-8ovym>
- `focusedValue`
  - <https://developer.apple.com/documentation/swiftui/view/focusedvalue(_:_:)-odf9>
- `FocusedValue`
  - <https://developer.apple.com/documentation/swiftui/focusedvalue>
- `EnvironmentValues`
  - <https://developer.apple.com/documentation/swiftui/environmentvalues>
- `PreferenceKey`
  - <https://developer.apple.com/documentation/swiftui/preferencekey>
- `DismissAction`
  - <https://developer.apple.com/documentation/swiftui/dismissaction>
- `OpenWindowAction`
  - <https://developer.apple.com/documentation/swiftui/openwindowaction>
- `OpenSettingsAction`
  - <https://developer.apple.com/documentation/swiftui/opensettingsaction>
- `NSWindow.performClose(_:)`
  - <https://developer.apple.com/documentation/appkit/nswindow/1419524-performclose>
- `NSWindowDelegate.windowShouldClose(_:)`
  - <https://developer.apple.com/documentation/appkit/nswindowdelegate/windowshouldclose(_)>
