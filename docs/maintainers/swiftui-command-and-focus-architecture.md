# SwiftUI Command and Focus Architecture

## Purpose

This document is the mandatory architecture note for any SwiftUI work in `gmax`.

Read this before proposing, implementing, or refactoring any SwiftUI command, focus, menu, toolbar, sheet, inspector, selection, or close behavior in this repository.

This note exists because the project previously drifted into custom routing and selection infrastructure that duplicated framework behavior, broke standard macOS affordances, and created cross-window bugs that SwiftUI and AppKit already know how to avoid.

The standing rule is simple:

- use SwiftUI and AppKit built-ins first
- use the framework's documented channels before creating custom ones
- do not build private routing systems, backchannels, or command buses when the frameworks already provide the mechanism

## Non-Negotiable Rules

- Scene commands belong on scenes through `Scene.commands { ... }`.
- App-specific top-level menus belong in `CommandMenu`.
- Modifying built-in menu structure belongs in `CommandGroup`.
- Use built-in command groups like `SidebarCommands`, `InspectorCommands`, and `ToolbarCommands` whenever they already match the product surface.
- Keep the standard window-close command framework-owned. Do not replace or shadow the built-in `Close Window` command unless Apple documentation proves the built-in scene and focus model cannot meet the product requirement.
- Window-close behavior stays standard unless there is a documented framework gap.
- Presented views dismiss through the presenting context that owns them.
- A sheet should dismiss before window-close behavior runs.
- Scene-wide command context comes from `focusedSceneValue` or `focusedSceneObject`.
- View-local command context comes from `focusedValue` or `focusedObject`.
- Environment values flow down the hierarchy.
- Preferences flow up to container views.
- Bindings and closures are the normal parent/child coordination path.
- Global or app-wide backchannels for per-window selection or focus are disallowed.
- Before adding any custom routing layer, backchannel, coordinator, or command bus, exhaust the implicit behavior already provided by SwiftUI scenes, `focusedSceneValue`, `focusedValue`, and built-in scene command groups.
- Any custom override of SwiftUI or AppKit command, focus, selection, sheet, toolbar, or close behavior requires a documented framework gap and Gale's approval first.

## What SwiftUI Already Provides

### Scene Commands

SwiftUI's command system is scene-based.

Apple's `Scene.commands(content:)` attaches command sets to a scene. That means menu-bar commands and key commands are defined at the scene boundary, not deep inside arbitrary child views.

Relevant surfaces:

- `Scene.commands { ... }`
- `Commands`
- `CommandMenu`
- `CommandGroup`
- `CommandGroupPlacement`
- built-in command groups like `SidebarCommands`, `InspectorCommands`, `ToolbarCommands`

What this means for `gmax`:

- `WorkspaceWindowSceneCommands` is the right home for app-specific workspace-window commands.
- A pane view should not try to define scene menus directly.
- A child view can influence commands by publishing context upward through SwiftUI's documented focus channels, not by inventing a private router.

### Focused Values

SwiftUI gives us two different focused-value channels, and the difference matters.

`focusedSceneValue` is for context that should be visible to scene commands as long as the scene is the active scene, regardless of which subview inside the scene currently has focus.

Use this for scene-scoped state like:

- the selected workspace in the active window
- the active window's library-sheet presentation action
- the active window's rename or delete workflow state
- any other command context that should remain available while the scene is active

`focusedValue` is for context that should only exist when a specific view or one of its descendants has focus.

Use this for view-specific actions like:

- close the currently focused pane
- split the currently focused pane
- relaunch the currently focused terminal pane
- any command that should only enable while a pane view is actually the focused part of the scene

This is the key architectural distinction that must drive command design in `gmax`.

If a command is about the active window regardless of focused subview, use `focusedSceneValue`.

If a command is about the currently focused pane or control, use `focusedValue`.

Do not collapse those two roles into a single custom scene object or app-wide model backchannel.

### Environment

Environment values flow down the view hierarchy.

That is what the environment is for:

- configuration
- services
- actions or values a container intentionally gives its descendants
- framework state like `dismiss`, `openWindow`, `dismissWindow`, `scenePhase`, and so on

Environment is not a general-purpose event bus and is not a replacement for command routing.

Use environment when:

- a parent or scene is configuring descendants
- a built-in environment action like `dismiss` or `dismissWindow` already does the job
- a custom environment value makes a real descendant-facing dependency explicit

Do not use environment as a secret side channel to smuggle per-window selection state around the app.

### Preferences

Preferences flow up the view hierarchy to container views.

That is what preferences are for:

- child views reporting configuration needs upward
- container-level decisions driven by descendant state
- layout and presentation coordination where the container has to reconcile input from many descendants

Preferences are not a replacement for scene commands or responder-style command routing.

Use preferences when:

- descendants need to communicate layout or container-facing configuration upward
- a container view has to observe child-produced metadata

Do not use preferences to build a private global action or selection system.

### Bindings and Closures

Bindings and closures are the ordinary composable SwiftUI coordination tools.

They are usually the first choice when:

- a parent view owns state
- a child view edits or triggers changes to that state
- the communication stays within a normal parent/child boundary

This is the standard declarative composition path.

When a parent presents a sheet or alert, the child should not invent a route that bypasses the parent. The presenting parent already owns the state that controls presentation and dismissal.

## What AppKit Already Provides

AppKit already owns several jobs that `gmax` should not reimplement.

### Window Close Behavior

AppKit already has the real close-window behavior:

- `NSWindow.performClose(_:)`
- `NSWindow.close()`
- `NSWindowDelegate.windowShouldClose(_:)`

The standard close command belongs to the window system. If `gmax` wants ordinary macOS `Close Window` behavior on `⌘W`, that should remain the framework-owned path.

Do not route plain window close through:

- a scene model
- a workspace-selection object
- a fake close-command abstraction
- a custom app-global router

Only intercept close when there is a concrete framework gap and the override is narrowly scoped.

### Responder Chain and Validation

AppKit already provides:

- responder-chain action dispatch
- menu validation
- toolbar validation
- window-level action dispatch

If `gmax` ever needs true responder-style window validation beyond what SwiftUI commands can comfortably express, AppKit's responder and validation surfaces are the native escape hatch.

That still does not justify inventing a separate pseudo-responder architecture.

## Architecture Rules for `gmax`

### 1. Keep Window Close Separate from Workspace and Pane Commands

`Close Window` is not the same thing as `Close Workspace`.

`Close Window`:

- belongs to the standard window command surface
- should preserve normal macOS behavior
- should dismiss presented sheets before closing the window
- should not mutate workspace state directly

`Close Workspace`:

- is an app-specific shell action
- belongs in app-specific commands
- should stay distinct from `Close Window`

`Close Pane`:

- is not a window command
- is a pane-scoped app action
- should be enabled only when a pane view is actually the focused part of the scene
- should be driven from pane focus via `focusedValue`, not via app-global selection state

Do not blur these three layers together.

### 1A. Empty Workspaces Stay Local To The Content Pane

In `gmax`, a workspace is rendered in the content pane of the three-column `NavigationSplitView`.

That means the last-pane close path is:

- close the focused pane
- leave the selected workspace behind as an explicit empty workspace
- move focus to that empty-workspace content
- let the content-pane workspace branch publish app-specific close-workspace context through `focusedSceneValue`

Do not skip directly from "last pane closed" to "close the workspace" or "close the window."

Do not add a custom scene router just to decide what `⌘W` means for an empty selected workspace. Start with the content-pane branch, focused values, and the built-in close command path first.

### 2. Keep Scene Context Scene-Local

Scene-local state is real and legitimate. `gmax` does need some per-window state.

Examples:

- selected workspace ID for that window
- inspector visibility for that window
- sidebar visibility for that window
- sheet presentation state for that window

That state should stay scene-local and explicit.

What it must not become:

- a private command framework
- a global selection authority
- a fake responder chain
- a proxy for focused subview state when `focusedValue` is the right API

### 3. Do Not Rebuild Selection Systems

SwiftUI already knows how to model selection through:

- `List(selection:)`
- `NavigationSplitView`
- bindings
- scene-local state

An app-global selected-workspace model for a multi-window `WindowGroup` app is an architectural smell here.

Per-window selection is scene-local.

Per-focused-view context is focus-local.

Do not recreate those roles as app-global state.

### 4. Pane Commands Must Come from Focused Pane Context

If a command is about the currently focused pane, the pane view should publish that capability through `focusedValue`.

Examples of pane-scoped actions that should use focused values:

- close focused pane
- split focused pane
- relaunch focused pane
- copy pane-local metadata if that ever becomes a command

The scene command surface can then read those actions through `@FocusedValue` and enable or disable menu items accordingly.

That is the documented SwiftUI model.

Do not substitute:

- a selected workspace lookup
- a model-global `focusedPane`
- a scene object that guesses which pane should receive the action

### 5. Presented Views Dismiss Themselves Through Their Presenter

If a sheet is on screen, the first close action should be the sheet's dismissal, not some custom command path that tunnels past the presentation.

Use:

- the presenter's `isPresented` binding
- `@Environment(\.dismiss)` inside the presented view when appropriate

Do not:

- manually reroute close commands through unrelated scene state first
- close workspace state underneath a presented sheet
- create app-global close infrastructure to compensate for a sheet that should already be dismissible

## Standard Decision Tree

Before adding any new SwiftUI command, focus, selection, toolbar, sheet, or close behavior, answer these questions in order.

### Step 1. Is there already a built-in SwiftUI scene command or command group?

Check:

- `SidebarCommands`
- `InspectorCommands`
- `ToolbarCommands`
- standard `CommandGroupPlacement` insertion or replacement points

If yes, start there.

### Step 2. Is this command scene-wide or focused-view-specific?

If scene-wide:

- use `focusedSceneValue` or `focusedSceneObject`

If focused-view-specific:

- use `focusedValue` or `focusedObject`

Do not mix the two casually.

### Step 3. Is this normal parent/child composition instead of command routing?

If yes:

- use bindings, closures, and ordinary SwiftUI state ownership

Do not promote it into command infrastructure without a reason.

### Step 4. Is this a child-to-container configuration signal?

If yes:

- use preferences

### Step 5. Does the environment already provide the action or value?

Check built-ins like:

- `dismiss`
- `dismissWindow`
- `openWindow`
- `openSettings`

If yes, use them.

### Step 6. Is this actually an AppKit job?

If it belongs to:

- responder chain
- menu validation
- toolbar validation
- window delegate lifecycle
- window-level close semantics

then AppKit may be the correct primitive.

Use AppKit directly before inventing a SwiftUI-only imitation.

## Forbidden Patterns

The following patterns are disallowed in this repository unless this document is explicitly updated with a concrete framework gap and Gale approves the change first.

- app-global selected-workspace state for a multi-window shell app
- app-global focused-pane state used as a command backchannel
- custom scene objects that act like controller frameworks or command buses
- hand-built pseudo-responder chains
- custom close-command pipelines for ordinary sheets and ordinary windows
- fake routing layers that mirror SwiftUI focus or selection behavior
- custom event handling meant to replace documented SwiftUI or AppKit command APIs

## Required Pre-Work for Future SwiftUI Changes

Before doing SwiftUI architecture work in `gmax`:

1. Read this document.
2. Read the relevant Apple documentation for the specific APIs being used.
3. State which built-in SwiftUI or AppKit behavior you are relying on.
4. If you believe a custom layer is required, document:
   - which built-in API was considered
   - why it is insufficient
   - what concrete product need is blocked
   - what maintenance cost the custom path adds
5. Get Gale's approval before implementing that custom layer.

If those steps are not complete, do not build the custom path.

## References

- Apple, `Scene.commands(content:)`
- Apple, `CommandMenu`
- Apple, `CommandGroup`
- Apple, `CommandGroupPlacement`
- Apple, `focusedSceneValue`
- Apple, `focusedValue`
- Apple, `EnvironmentValues`
- Apple, `Preferences`
- Apple, `WindowGroup`
- Apple, `DismissAction`
- Apple, `DismissWindowAction`
- Apple, `NSWindow.performClose(_:)`
- Apple, `NSWindowDelegate.windowShouldClose(_:)`
