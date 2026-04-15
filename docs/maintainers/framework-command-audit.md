# SwiftUI and AppKit Command Audit

## Purpose

This note is the reset point for `gmax` command, selection, window, sheet, toolbar, and inspector behavior.

The rule going forward is simple:

- use built-in SwiftUI behavior when SwiftUI already models the job cleanly
- use built-in AppKit behavior when the job belongs to the responder chain, menu validation, window lifecycle, or window delegate model
- only keep custom infrastructure when the built-in surfaces leave a real product gap

This document is intentionally specific. It lists the relevant Apple surfaces, what they already provide, where the repo currently shadows them, and what should be kept, collapsed into the framework, or removed.

## Scope

This audit covers the current main-shell architecture in:

- `gmax/gmaxApp.swift`
- `gmax/App/MainShellCommands.swift`
- `gmax/App/gmaxApp+Actions.swift`
- `gmax/App/WindowSceneInterop.swift`
- `gmax/Views/Scenes/MainShellSceneView.swift`
- `gmax/Models/ShellModel.swift`
- `gmax/Models/ShellModel+WorkspaceManagement.swift`
- `gmax/Models/ShellModel+PaneManagement.swift`

## Apple Built-In Inventory

### 1. Scene-local selection and restoration

SwiftUI already provides built-in scene-scoped state and selection coordination:

- `NavigationSplitView`
  - Apple says selections in leading columns control presentations in later columns.
  - Programmatic changes to the bound selection update both the list appearance and the detail presentation.
- `List(selection:)`
  - SwiftUI already models selected rows and coordinates that with split-view navigation.
- `@SceneStorage`
  - Apple describes this as lightweight state scoped to a scene.
  - Each scene has its own scene storage.
  - Apple explicitly says to use scene storage with the data model, not as a replacement for the data model.
- `WindowGroup(..., for:content:)`
  - SwiftUI can present value-based windows.
  - SwiftUI automatically persists and restores the presented value binding as part of state restoration.
- `restorationBehavior(_:)`
  - SwiftUI already owns whether scene instances restore at launch.

What this means for `gmax`:

- per-window selected workspace is a normal scene-local concern
- per-window inspector visibility is a normal scene-local concern
- per-window sidebar visibility is a normal scene-local concern
- app-global workspace selection is not a requirement imposed by SwiftUI

### 2. Scene-local command routing

SwiftUI already provides built-in scene-aware command context:

- `commands(content:)`
  - scenes can attach commands directly
- `CommandMenu`
  - top-level app-specific menus
- `CommandGroup`
  - inserts, replaces, or augments standard menu groups
- `focusedSceneValue(_:_:)`
  - Apple explicitly recommends this when commands should depend on the active scene, regardless of which focused subview is active
- `focusedValue(_:_:)`
  - Apple explicitly recommends this when commands should only depend on focus within a specific part of a scene
- `focusedSceneObject(_:)`
  - built-in scene-scoped observable-object publication for command consumers
- `@FocusedValue`
  - command readers can consume contextual values from the active scene

Apple’s menu-bar guidance explicitly shows:

- publishing the active scene’s model or selected item ID
- reading it in `Commands`
- disabling commands when the focused scene does not provide the needed value

What this means for `gmax`:

- frontmost-window command routing is supposed to come from SwiftUI scene focus
- we do not need an app-global selection model to decide which window owns a command
- if a command is acting on the wrong window, the first question is whether our focused-scene data is too custom or too indirect, not whether SwiftUI lacks a routing model

### 3. Built-in command groups

SwiftUI already provides built-in command groups for common window chrome:

- `SidebarCommands`
  - built-in show/hide sidebar commands
- `InspectorCommands`
  - built-in inspector toggle commands
  - Apple documents the built-in keyboard shortcut as Control-Command-I
- `ToolbarCommands`
  - built-in toolbar manipulation commands

SwiftUI also provides standard command placements like:

- `.sidebar`
- `.toolbar`

What this means for `gmax`:

- we should prefer built-in sidebar and inspector command sets unless we have a concrete product reason to replace them
- if we override or replace built-in command behavior, that should be an explicit product decision, not just habit

### 4. Sheets, inspectors, and dismiss behavior

SwiftUI already provides built-in presentation and dismissal rules:

- `.sheet(isPresented:)`
  - standard modal presentation
- `.inspector(isPresented:content:)`
  - standard inspector presentation
- `@Environment(\.dismiss)`
  - dismisses the current presentation
  - if called inside a sheet, it dismisses the sheet
  - if called from the root view of a window, it can close the window instead
- `DismissWindowAction`
  - dismisses the current window, a window by ID, or a specific value-based `WindowGroup` instance
- `DismissBehavior`
  - controls whether programmatic window dismissal acts interactively or destructively

Apple is explicit about one important rule:

- if a sheet is open, dismissing from the sheet environment should dismiss the sheet first
- if you instead call a close action from the wrong environment, you can close the window rather than the sheet

What this means for `gmax`:

- `⌘W` should not skip over a presented library sheet and mutate workspace state underneath it
- sheet dismissal precedence is something SwiftUI already models
- custom close logic should not outrank sheet dismissal without a very specific reason

### 5. Window closing and window lifecycle

AppKit already provides the correct close model:

- `NSWindow.performClose(_:)`
  - simulates the user clicking the close button
  - consults `windowShouldClose(_:)`
- `NSWindow.close()`
  - closes immediately
  - does not consult `windowShouldClose(_:)`
- `NSWindowDelegate.windowShouldClose(_:)`
  - standard close-veto hook
- `NSApplication.keyWindow`
  - the window currently receiving keyboard events
- `NSApplication.mainWindow`
  - the app’s main window

Apple is explicit that:

- `performClose(_:)` is the correct path when honoring normal close behavior matters
- `close()` is not the right substitute when you want delegate-driven confirmation

What this means for `gmax`:

- using `performClose(_:)` for real window-close behavior is correct
- the custom AppKit bridge for last-pane close confirmation may be justified, because SwiftUI does not provide a generic built-in “confirm before closing a non-document window” modifier
- even so, that custom AppKit bridge should stay narrow and should not become a general command-routing layer

### 6. Responder chain action dispatch and validation

AppKit already provides the native action and validation model:

- `NSApplication.sendAction(_:to:from:)`
  - when target is `nil`, AppKit routes through the responder chain
- `NSWindow.tryToPerform(_:with:)`
  - window-level responder dispatch
- `NSUserInterfaceValidations`
  - protocol for enabling or disabling UI based on current state
- `NSMenuItemValidation`
  - menu item validation hook
- `NSToolbarItemValidation`
  - toolbar item validation hook
- `NSToolbarItem.validate()`
  - standard items auto-validate
  - custom-view toolbar items need custom validation

What this means for `gmax`:

- AppKit already knows how to ask the active responder chain whether a command is valid
- if we need true window-first enablement and disablement, AppKit validation is a better native escape hatch than inventing our own pseudo-responder layer
- if we continue using fully SwiftUI-defined toolbar buttons, some enablement may still live in view state, but that is different from creating a second application-level command framework

### 7. Event handling boundaries

AppKit already warns against overreaching low-level event overrides:

- Apple documents subclassing or overriding application-level event dispatch as critical and complex work

What this means for `gmax`:

- hand-built event-routing infrastructure should be treated as a last resort
- if SwiftUI or AppKit already has a model for the job, we should not invent an event path first

## Current Repo Overlays

### A. `MainShellSceneContext`

Current role:

- owns selected workspace ID
- owns inspector visibility
- owns sidebar visibility
- owns library-sheet presentation
- owns pending delete confirmation state
- owns a number of imperative command methods

Good part:

- scene-local selection and scene-local presentation state are real needs

Overbuilt part:

- it acts like a private command framework
- it duplicates framework-owned responsibilities for close routing, presentation precedence, and command dispatch
- it exposes too many imperative wrappers around model mutations

### B. `ShellModel.currentWorkspaceID`

Current role:

- app-global selected workspace state
- drives convenience accessors like `selectedWorkspaceIndex`, `selectedWorkspace`, and `focusedPane`
- still gets mutated by workspace create, duplicate, reopen, and navigation flows

Why this is a problem:

- it is a global backchannel under a scene-local app
- it can cause window A to mutate window B’s apparent selection state
- it recreates exactly the kind of cross-window ambiguity SwiftUI scene scoping is supposed to remove

### C. No-argument model command helpers

Examples:

- `createPane()`
- `relaunchFocusedPane()`
- `splitFocusedPane(_:)`
- `closeFocusedPane()`
- `movePaneFocus(_:)`
- `performCloseCommand()`

Why these are risky:

- they silently consult app-global selection
- they are easy to call from the wrong context
- they keep the old global-selection architecture alive even after scene-local command routing was introduced

### D. Manual close routing in `MainShellSceneContext`

Examples:

- `performContextualClose()`
- `performWorkspaceClose()`
- `performWindowClose()`
- direct `NSApp.keyWindow?.performClose(nil)` calls

What is legitimate:

- using `performClose(_:)` instead of `close()` is correct when normal window-close behavior matters

What is not healthy:

- using a scene-owned helper object as a general close router
- mixing pane-close rules, workspace-close rules, settings-window routing, and raw key-window closing into one custom command surface
- letting that custom surface bypass normal sheet dismissal precedence

### E. `WindowSceneInterop.swift`

Current role:

- tags windows with a role identifier
- installs an `NSWindowDelegate` to show a last-pane close confirmation

Audit result:

- `WindowRoleAccessor` is a light AppKit interop shim, not obviously a problem on its own
- `WindowCloseConfirmationAccessor` may be justified because a generic “confirm app-defined close of a non-document window” flow is not something SwiftUI models directly
- this file should stay extremely narrow and should not absorb broader command logic

## Keep, Collapse, Remove

### Keep

- `NavigationSplitView` plus `List(selection:)` as the primary workspace selection model
- `@SceneStorage` for lightweight per-window state like selected workspace ID, inspector visibility, and sidebar visibility
- `focusedSceneValue` or `focusedSceneObject` for scene-local command context
- `.sheet` and `.inspector` for presentation
- `NSWindow.performClose(_:)` for real window-close behavior
- a narrow AppKit bridge for last-pane close confirmation, if SwiftUI still does not provide a cleaner built-in equivalent

### Collapse into framework behavior

- scene command enablement should lean harder on SwiftUI scene focus and, where necessary, AppKit validation
- close behavior should respect SwiftUI dismissal precedence before running custom workspace-close logic
- inspector and sidebar command behavior should use built-in command groups unless we are intentionally replacing them
- window targeting should come from scene focus and the responder chain, not from a parallel app-global selection path

### Remove

- `ShellModel.currentWorkspaceID` as the source of truth for normal shell selection
- `selectedWorkspaceIndex`, `selectedWorkspace`, and `focusedPane` when they derive from app-global selection instead of explicit workspace IDs
- no-argument pane and workspace command helpers that silently depend on global selection
- custom command helpers whose only job is compensating for the global-selection model
- any command path that closes or mutates workspace state while a frontmost sheet should have handled dismissal first

## File-by-File Recommendations

### `gmax/Views/Scenes/MainShellSceneView.swift`

Keep:

- `NavigationSplitView`
- `.inspector`
- `.sheet`
- `@SceneStorage`
- `focusedSceneValue`

Change:

- prefer SwiftUI-owned selection and presentation rules over imperative scene-context methods where possible
- consider whether the command-state snapshot should become a smaller scene value or a focused scene object instead of a paired custom value type plus context object

### `gmax/App/MainShellCommands.swift`

Keep:

- `Commands`
- `CommandMenu`
- `CommandGroup`
- scene-focused command consumption

Change:

- stop replacing built-in behavior unless the product intentionally diverges from it
- use `InspectorCommands` and `SidebarCommands` where they match the actual UI
- reduce custom close routing and let built-in dismissal behavior handle frontmost sheet and window semantics first

### `gmax/App/gmaxApp+Actions.swift`

Keep:

- only the minimum scene-local state that SwiftUI does not already own directly and that is truly app-specific

Remove or shrink aggressively:

- the command-router shape of `MainShellSceneContext`
- imperative wrappers that only forward to model methods
- close-routing methods that duplicate framework behavior

### `gmax/Models/ShellModel.swift`

Keep:

- shared workspace and pane data
- persistence, session registry, and pane controller ownership
- explicit methods that act on explicit workspace IDs and pane IDs

Remove:

- app-global selection ownership
- convenience selection accessors that depend on `currentWorkspaceID`

### `gmax/Models/ShellModel+WorkspaceManagement.swift`

Keep:

- explicit workspace lifecycle methods that accept a workspace ID

Remove:

- implicit selection side effects inside create, duplicate, reopen, and workspace navigation flows unless the caller explicitly wants that result
- global-selection-only helpers like `closeSelectedWorkspace()` and workspace cycling helpers that mutate `currentWorkspaceID`

### `gmax/Models/ShellModel+PaneManagement.swift`

Keep:

- explicit pane lifecycle operations that accept a workspace ID and pane ID

Remove:

- no-argument helpers that infer the target workspace from app-global selection

### `gmax/App/WindowSceneInterop.swift`

Keep for now:

- the narrow AppKit bridge that adds last-pane close confirmation to a real window close

Do not expand:

- no general command routing
- no menu validation framework
- no event routing layer

## Immediate Audit Conclusions

### 1. The app should not have an app-global selected workspace source of truth anymore

That responsibility belongs to the active scene.

### 2. The model should operate on explicit IDs, not on “whatever the app currently thinks is selected”

That means explicit workspace- and pane-targeting methods are the durable core API.

### 3. The command layer should publish context, not invent a parallel command runtime

SwiftUI already provides scene-scoped command context.

### 4. Close behavior should defer to built-in dismissal semantics before custom workspace mutation

If a sheet is open, the sheet should be the first thing that closes.

### 5. AppKit interop should stay narrow and justified

Using AppKit for a missing native close-confirmation hook is different from replacing the responder chain with custom infrastructure.

## Next Refactor Order

1. Remove `ShellModel.currentWorkspaceID` and the accessors and helpers that depend on it.
2. Convert model command APIs so the durable public surface is explicit-ID-based.
3. Shrink `MainShellSceneContext` down to true scene-local view and presentation state.
4. Rework close handling so sheet dismissal and window dismissal use built-in SwiftUI/AppKit precedence first.
5. Re-introduce only the custom command logic that still has a documented, approved framework gap after the above cleanup.

## Apple Documentation Relied On

### SwiftUI

- `NavigationSplitView`
  - <https://developer.apple.com/documentation/swiftui/navigationsplitview>
- `SceneStorage`
  - <https://developer.apple.com/documentation/swiftui/scenestorage>
- `Restoring your app’s state with SwiftUI`
  - <https://developer.apple.com/documentation/swiftui/restoring-your-app-s-state-with-swiftui>
- `focusedSceneValue(_:_:)`
  - <https://developer.apple.com/documentation/swiftui/view/focusedscenevalue(_:_:)> 
- `focusedValue(_:_:)`
  - <https://developer.apple.com/documentation/swiftui/view/focusedvalue(_:_:)> 
- `focusedSceneObject(_:)`
  - <https://developer.apple.com/documentation/swiftui/view/focusedsceneobject(_:)> 
- `Building and customizing the menu bar with SwiftUI`
  - <https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui>
- `SidebarCommands`
  - <https://developer.apple.com/documentation/swiftui/sidebarcommands>
- `InspectorCommands`
  - <https://developer.apple.com/documentation/swiftui/inspectorcommands>
- `ToolbarCommands`
  - <https://developer.apple.com/documentation/swiftui/toolbarcommands>
- `dismiss`
  - <https://developer.apple.com/documentation/swiftui/environmentvalues/dismiss>
- `DismissWindowAction`
  - <https://developer.apple.com/documentation/swiftui/dismisswindowaction>
- `WindowGroup`
  - <https://developer.apple.com/documentation/swiftui/windowgroup>
- `Windows`
  - <https://developer.apple.com/documentation/swiftui/windows>

### AppKit

- `NSApplication.sendAction(_:to:from:)`
  - <https://developer.apple.com/documentation/appkit/nsapplication/sendaction(_:to:from:)>
- `NSUserInterfaceValidations`
  - <https://developer.apple.com/documentation/appkit/nsuserinterfacevalidations>
- `NSMenuItemValidation`
  - <https://developer.apple.com/documentation/appkit/nsmenuitemvalidation>
- `NSToolbarItemValidation`
  - <https://developer.apple.com/documentation/appkit/nstoolbaritemvalidation>
- `NSToolbarItem.validate()`
  - <https://developer.apple.com/documentation/appkit/nstoolbaritem/validate()>
- `NSWindow.performClose(_:)`
  - <https://developer.apple.com/documentation/appkit/nswindow/performclose(_:)> 
- `NSWindow.close()`
  - <https://developer.apple.com/documentation/appkit/nswindow/close()> 
- `NSWindowDelegate.windowShouldClose(_:)`
  - <https://developer.apple.com/documentation/appkit/nswindowdelegate/windowshouldclose(_:)> 
- `NSWindow.endSheet(_:returnCode:)`
  - <https://developer.apple.com/documentation/appkit/nswindow/endsheet(_:returncode:)> 
