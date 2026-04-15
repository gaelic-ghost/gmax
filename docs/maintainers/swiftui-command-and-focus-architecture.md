# SwiftUI Command and Focus Architecture

## Purpose

This note captures the current preferred command, focus, selection, and close-behavior defaults for `gmax`.

Use it as a strong repo-local default, not as a substitute for current Apple documentation. If this note and the SwiftUI or AppKit docs appear to disagree, re-check the Apple docs first and update this note instead of treating it as infallible law.

The main lesson from earlier cleanup work is simple: `gmax` got into trouble when it duplicated built-in scene, focus, and window behavior with custom routing layers. The goal of this note is to preserve that lesson without overstating what SwiftUI guarantees.

## Research Workflow

Before relying on any rule in this note:

- Prefer the Xcode MCP `DocumentationSearch` tool for current SwiftUI and AppKit API lookup.
- Use Dash as a fallback or cross-check when local doc browsing is more convenient.
- On this machine, the most relevant installed Apple Dash docsets are the generic Swift API reference (`ntiaiyxj-swift`), Objective-C API reference (`ntiaiyxj-objc`), and offline macOS set (`jtswqsfb`).
- If neither local path answers the question clearly, use the official Apple documentation URLs linked at the end of this note.

## Current Default Model

- Put app-specific menu commands on the scene with `Scene.commands`.
- Prefer built-in command groups like `SidebarCommands`, `InspectorCommands`, and `ToolbarCommands` when they already match the product surface.
- Use `focusedSceneValue` or `focusedSceneObject` for command context that should remain available while the window scene is active.
- Use `focusedValue` or `focusedObject` for command context that should only exist while a specific view or subtree is focused.
- Use bindings, closures, and ordinary view state for normal parent-child coordination.
- Use environment values for downward configuration and built-in actions like `dismiss`, `dismissWindow`, `openWindow`, and `openSettings`.
- Use preferences only for child-to-container signals, especially layout or container-facing configuration.
- Keep ordinary window close behavior framework-owned unless there is a concrete product need and a documented framework gap.

## How To Choose The Right Channel

### Scene command surface

When a command belongs in the menu bar or keyboard-command surface for a window scene, define it on the scene through `Scene.commands`.

In `gmax`, that means [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneCommands.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneCommands.swift) is the normal home for workspace-window command definitions.

### Scene-wide command context

Use `focusedSceneValue` or `focusedSceneObject` when the command should stay available as long as the window scene is active, regardless of which child view currently has keyboard focus.

Good examples in `gmax`:

- the selected workspace for the active window
- scene-owned sheet or alert presentation actions
- scene-owned rename, delete, or reopen context

This follows Apple's documented distinction that scene-focused values remain visible regardless of where focus sits inside the active scene.

### Focused-view command context

Use `focusedValue` or `focusedObject` when the command should only be available while a specific view or its descendants are focused.

Good examples in `gmax`:

- split the focused pane
- close the focused pane
- relaunch the focused pane

If the pane is not the focused part of the scene, the command should normally disable rather than guessing a target through an app-global backchannel.

### Parent-child coordination

If the problem is just ordinary view composition, prefer bindings, closures, and direct state ownership over command infrastructure.

If the parent owns the presentation, selection, or mutation state already, the child should usually coordinate through that normal parent-child path instead of routing upward through a custom bus.

### Child-to-container signals

Use preferences only when a descendant needs to report information upward to a container that reconciles or acts on it.

This is the right tool for layout and container-facing metadata. It is not the default tool for command routing.

### Built-in environment actions

Before adding a custom command or action surface, check whether SwiftUI already provides the action through the environment:

- `dismiss`
- `dismissWindow`
- `openWindow`
- `openSettings`

If one of those already models the behavior, prefer it.

### AppKit escape hatch

If the job really belongs to the responder chain, menu validation, toolbar validation, or window-delegate lifecycle, AppKit may be the correct primitive.

That is still different from inventing a parallel in-house responder or command system. Use the native AppKit surface directly before creating a custom abstraction.

## Repo-Specific Defaults For `gmax`

These are preferences derived from current product shape, not universal SwiftUI laws:

- Per-window workspace selection should stay scene-local rather than app-global.
- Pane-targeted commands should prefer focused pane context over “current selection” guesses.
- `Close Window`, `Close Workspace`, and `Close Pane` are different actions and should stay distinct.
- A presented sheet or alert should normally dismiss through its presenter before any app-defined workspace mutation tries to happen underneath it.
- Custom routing or close infrastructure should stay narrow and local when it is truly needed.

## When Custom Infrastructure Is Acceptable

Custom command, focus, or close infrastructure is acceptable only when all of the following are true:

1. The relevant SwiftUI or AppKit behavior has been checked in current Apple docs.
2. The built-in surface leaves a concrete product gap in `gmax`.
3. The narrower options were considered first.
4. The custom path is documented as a local exception rather than a new general architecture.
5. Gale approves the tradeoff.

When that happens, the write-up should say:

- which Apple API was considered
- what it does according to the docs
- why it is insufficient here
- what near-term use case the custom path unlocks
- what maintenance cost we are accepting

## Practical Decision Checklist

Before adding new command, focus, selection, toolbar, sheet, inspector, or close behavior:

1. Is there already a built-in scene command or command group that fits?
2. Is the command scene-wide or focused-view-specific?
3. Is this just ordinary parent-child composition?
4. Is this a child-to-container signal?
5. Does the environment already provide the action?
6. Is this actually an AppKit job?
7. If none of the above fit cleanly, what exact framework gap remains?

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
