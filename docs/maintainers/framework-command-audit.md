# Workspace Window Command and Focus Gap Audit

## Purpose

This document is the current gap audit for the workspace-window scene, command,
focus, and dismissal architecture in `gmax`.

It is intentionally different from the related maintainer guide:

- [`workspace-focus-guide.md`](./workspace-focus-guide.md) records the repo's
  preferred defaults, ownership boundary, and current implementation map.

Read
[`workspace-focus-guide.md`](./workspace-focus-guide.md)
first for the current defaults, ownership model, and implementation map.

This file answers the next question: where the current implementation is solid,
where it is merely awkward, where it is risky, and what deserves redesign
attention first.

## Audit Basis

This audit is based on the current implementation in:

- [`gmax/gmaxApp.swift`](../../gmax/gmaxApp.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneView.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneCommands.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneCommands.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/SidebarPanel/SidebarPane.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/SidebarPanel/SidebarPane.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore.swift`](../../gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore+PaneActions.swift`](../../gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore+PaneActions.swift)
- [`gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore+WorkspaceActions.swift`](../../gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore+WorkspaceActions.swift)
- [`gmax/Views/Sheets/SavedWorkspaceLibrarySheet.swift`](../../gmax/Views/Sheets/SavedWorkspaceLibrarySheet.swift)
- [`gmaxUITests/WorkspaceSidebarUITests.swift`](../../gmaxUITests/WorkspaceSidebarUITests.swift)
- [`gmaxUITests/SavedWorkspaceLibraryUITests.swift`](../../gmaxUITests/SavedWorkspaceLibraryUITests.swift)
- [`gmaxUITests/UITestSupport.swift`](../../gmaxUITests/UITestSupport.swift)

It was also checked against the Apple APIs the implementation is relying on:

- [`Scene.commands(content:)`](https://developer.apple.com/documentation/swiftui/scene/commands(content:))
- [`Commands`](https://developer.apple.com/documentation/swiftui/commands)
- [`CommandGroup`](https://developer.apple.com/documentation/swiftui/commandgroup)
- [`Building and customizing the menu bar with SwiftUI`](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui)
- [`focusedSceneObject(_:)`](https://developer.apple.com/documentation/swiftui/view/focusedsceneobject(_:))
- [`focusedSceneValue(_:_:)`](https://developer.apple.com/documentation/swiftui/view/focusedscenevalue(_:_:))
- [`focusedObject(_:)`](https://developer.apple.com/documentation/swiftui/view/focusedobject(_:))
- [`focusedValue(_:_:)`](https://developer.apple.com/documentation/swiftui/view/focusedvalue(_:_:))
- [`DismissAction`](https://developer.apple.com/documentation/swiftui/dismissaction)
- [`WindowGroup`](https://developer.apple.com/documentation/swiftui/windowgroup)
- [`Settings`](https://developer.apple.com/documentation/swiftui/settings)
- [`PreferenceKey`](https://developer.apple.com/documentation/swiftui/preferencekey)
- [`NSWindow.performClose(_:)`](https://developer.apple.com/documentation/appkit/nswindow/performclose(_:))

## Executive Read

The current workspace-window architecture is mostly on the right side of the SwiftUI and AppKit boundary.

The good news:

- scene commands live on the scene
- scene-wide context is published with `focusedSceneObject` and `focusedSceneValue`
- pane-specific command behavior is derived from the scene-owned focus target
- pane geometry uses `PreferenceKey` as a real child-to-container signal instead of a command backchannel
- ordinary window content is still mostly driven by straightforward parent-child state ownership rather than a custom routing layer

The bigger problems are not "the whole model is wrong." The bigger problems are:

- the adaptive `Command-W` slot still carries a lot of context-sensitive behavior
- naming drift still leaks shell-era vocabulary into live implementation and tests
- the command surface mixes scene-owned closures and direct store mutation in a way that is coherent but not yet explicit enough
- test coverage around command and focus behavior is thin compared with the importance of this surface

So the overall assessment is:

- foundation: mostly sound
- implementation clarity: mixed
- behavioral risk: moderate and concentrated in close behavior and command coverage
- redesign need: real, but not because the entire scene model needs to be thrown away

## What Is Actually Working Well

### 1. Scene ownership is mostly correct

`WorkspaceWindowSceneView` owns:

- selected workspace
- scene presentation state
- sidebar and inspector visibility
- the per-window `WorkspaceStore`

That is the correct side of the boundary for a multi-window SwiftUI app. The app is no longer depending on a global "current workspace" backchannel to decide which window owns the current command target.

### 2. Scene and focused-view context are separated in the right direction

The current architecture uses:

- `focusedSceneObject(workspaceStore)`
- `focusedSceneValue` for scene-wide command context
- scene-owned pane action closures derived from the focused pane target

That matches Apple's intended distinction between:

- scene-wide active window context
- focused-subtree participation

This is one of the healthiest parts of the current architecture.

### 3. Preferences are being used for layout metadata, not command routing

`ContentPaneFramePreferenceKey` is used to push pane frame rectangles upward so
the content container and scene root can reason about pane geometry.

That is a legitimate use of `PreferenceKey`, and it avoids one of the main
mistakes from the earlier architecture work. Pane geometry is no longer part of
the store's responsibilities here.

## Findings

## 1. The current adaptive `Command-W` slot is still doing too many jobs

Severity: high

Evidence:

- [`WorkspaceWindowSceneCommands.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneCommands.swift)
- [`WorkspaceWindowSceneView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneView.swift)
- [`ContentPaneLeafView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift)

Current behavior:

- if the active focus target is a pane, `Command-W` becomes `Close Pane`
- else the scene resolves close behavior from the active focus target plus the selected workspace state
- window close remains the final scene-owned fallback when no narrower close target applies
- a separate explicit `Close Window` command and `Open Recent Window` command now exist alongside that adaptive slot

Why this was called out:

- three different ownership layers are being multiplexed through one command slot
- the resulting behavior is not obvious from the UI unless someone already understands the focus model
- the command implementation must infer what "close" means from a combination of scene activity, pane focus, and workspace emptiness

Why it matters:

- close behavior is one of the most user-visible and least forgiving menu and keyboard surfaces
- command ambiguity here will be hard to reason about during future refactors
- this is exactly the kind of surface where a small regression can feel like an architectural bug

Recorded decision:

- this adaptive `Command-W` model is an explicit product decision
- `Command-W` closes an actively focused pane
- if the actively selected workspace has no panes, `Command-W` closes that workspace
- if focus is in the sidebar and a workspace listing is focused, `Command-W` closes that workspace
- if focus is on the only workspace in a window and that workspace has no panes, `Command-W` closes the window
- if focus is in the inspector, `Command-W` does nothing
- `Close Window` remains available as a dedicated explicit action with its own shortcut
- `Open Recent Window` reopens the most recently closed `WorkspaceSceneIdentity` with `openWindow(value:)`

Implementation follow-through:

- keep the semantics above fixed
- simplify the command code until those semantics are expressed directly and read clearly from the command surface

## 2. The command surface is coherent, but not yet explicit enough about ownership

Severity: medium-high

Evidence:

- [`WorkspaceWindowSceneCommands.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneCommands.swift)
- [`WorkspaceWindowSceneView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneView.swift)

Current behavior:

- some commands mutate `WorkspaceStore` directly
- some commands call scene-owned closures published through focused scene values

Direct store examples:

- create workspace
- duplicate workspace
- close workspace

Scene-owned closure examples:

- open saved workspace library
- present rename flow
- present deletion flow
- move pane focus
- split pane
- close pane

Why this is a gap:

- the split is rational, but the code does not document it as a deliberate boundary
- without that explanation, the implementation can look arbitrary
- future cleanup work may "normalize" this in the wrong direction by pushing scene presentation into the store or by pushing store mutations into scene glue

Recommendation:

- document this boundary as intentional:
  - store owns workspace graph and mutations
  - scene owns presentation and per-window UI state
  - scene-owned window restoration state owns the recently closed window identity stack
- if a redesign happens later, preserve that distinction unless there is a strong reason to collapse it

## 3. The focused-value key registry and command implementation are coupled more tightly than they need to be

Severity: medium

Evidence:

- [`WorkspaceWindowSceneCommands.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneCommands.swift)

Current behavior:

- the file declares the `FocusedValues` entries
- the same file also implements the full menu and keyboard command surface

Why this is a gap:

- this makes one file the owner of both command vocabulary and command rendering
- if the command context surface grows, this file will become an awkward mixed boundary
- it also makes reusing or testing the focused-value contract harder than it needs to be

Recommendation:

- this does not require immediate change
- if the command surface expands or becomes more test-driven, consider splitting:
  - one file for workspace window command-context keys
  - one file for the `Commands` implementation

## 4. Shell-era naming still leaks into live scene state and test-facing identifiers

Severity: medium

Evidence:

- [`WorkspaceWindowSceneView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneView.swift)
- [`gmaxUITests/UITestSupport.swift`](../../gmaxUITests/UITestSupport.swift)
- [`gmaxUITests/SavedWorkspaceLibraryUITests.swift`](../../gmaxUITests/SavedWorkspaceLibraryUITests.swift)

Current examples:

- `@SceneStorage("workspaceWindow.selectedWorkspaceID")`
- `@SceneStorage("workspaceWindow.isInspectorVisible")`
- `@SceneStorage("workspaceWindow.isSidebarVisible")`
- toolbar accessibility identifiers like:
  - `workspaceWindow.openSavedWorkspacesButton`
  - `workspaceWindow.newWorkspaceButton`
  - `workspaceWindow.toggleInspectorButton`
- UI-test helper names like:
  - `assertActiveWorkspaceWindowIsVisible`
  - `attemptToPresentAnotherWorkspaceWindow`

Why this is a gap:

- the repo has already renamed the product and model vocabulary toward
  `Workspace...`
- but the current scene-storage keys, toolbar accessibility identifiers, and
  some UI-test helper names still use the older `workspaceWindow...` family
- the drift is now bounded and easy to enumerate, but it has not been cleaned
  up yet

Recommendation:

- plan a single naming-alignment cleanup pass rather than a piecemeal rename
- include:
  - scene storage keys
  - accessibility identifiers
  - UI-test helper names
  - maintainer-doc wording where the old names still survive

## 5. The unified guide is stronger, but this audit still matters separately

Severity: medium

Evidence:

- older versions of the maintainer docs were still describing earlier paths and
  earlier "main shell" vocabulary

Why this matters:

- this surface is subtle enough that stale docs quickly become worse than no docs
- future redesign work needs a map, not just a style note

Current status:

- the canonical guide now carries the default model, ownership boundary, and
  current implementation map in one place
- this audit now acts as the narrower companion read for risk, awkward edges,
  and redesign priority

Recommendation:

- keep the split between:
  - one canonical guide
  - one narrower gap audit
- do not let this audit regrow a second source of truth for settled behavior or
  implementation detail that now belongs in the guide

## 6. Command and focus behavior is under-tested relative to its importance

Severity: high

Evidence:

- unit tests have no direct scene/focus/command coverage for this surface
- UI tests currently cover only a subset of behaviors through:
  - [`WorkspaceSidebarUITests.swift`](../../gmaxUITests/WorkspaceSidebarUITests.swift)
  - [`SavedWorkspaceLibraryUITests.swift`](../../gmaxUITests/SavedWorkspaceLibraryUITests.swift)

What is covered today:

- workspace deletion confirmation through the menu
- opening the saved workspace library
- closing a workspace to the library and reopening it
- deleting a saved snapshot
- toolbar new-workspace action
- inspector toggle behavior through the menu and toolbar label state
- pane split actions and one contextual pane-close path

What is not clearly covered:

- the full three-way `Command-W` behavior across:
  - focused pane close
  - empty workspace close
  - window close fallback
- rename presentation through the command layer
- command enablement and disablement state when scene focus changes
- behavior when focus is in sidebar versus content versus inspector
- whether scene-focused values keep the correct target across multiple
  intentionally independent workspace windows
- whether the command layer keeps targeting the frontmost active scene rather
  than another restored workspace window

Why this is a gap:

- the architecture now depends on focused scene context doing the right thing
  in a deliberately multi-window app
- that is exactly the area where there is the least direct regression protection

Recommendation:

- treat behavioral coverage as one of the next real engineering tasks here
- the highest-value UI-test cases would be:
  1. verify `Command-W` in all three modes
  2. verify rename and delete command availability by selection state
  3. verify pane commands disable when pane focus is absent
  4. verify command routing across two workspace windows

## 7. The current scene root is justified, but still carrying a lot of responsibility

Severity: medium

Evidence:

- [`WorkspaceWindowSceneView.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneView.swift)

Current responsibilities include:

- owning the store
- owning selection
- owning scene restoration
- owning inspector and sidebar visibility
- owning saved-library presentation
- owning rename and delete presentation
- publishing scene command context
- defining toolbar behavior

Why this is not automatically a bug:

- these are mostly scene-root concerns
- this view really is the scene root, not a thin wrapper

Why it is still a gap:

- this file is now the densest ownership point in the scene architecture
- future additions could turn it into the next hard-to-refactor choke point

Recommendation:

- do not split it reactively just to reduce file length
- but if new scene behavior gets added, organize by responsibility inside the file or by narrow scene-owned surfaces rather than by generic helper extraction

## 8. The settings surface is cleanly separate, but not integrated into command discussion yet

Severity: low

Evidence:

- [`SettingsUtilityWindow.swift`](../../gmax/Scenes/Settings/SettingsUtilityWindow.swift)

Current behavior:

- settings use `@AppStorage` directly
- settings are isolated in a `Settings` scene

Why this is mostly fine:

- settings do not currently need the command-and-focus architecture used by the workspace window

Residual gap:

- the maintainer notes talk extensively about command and scene behavior, but barely mention the settings scene as a consciously separate surface

Recommendation:

- no urgent code change required
- just keep the docs explicit that settings are intentionally outside the workspace-window command model

## Risk Ranking

Highest-priority gaps:

1. overloaded `Command-W` semantics
2. weak command/focus behavioral test coverage
3. implicit ownership split between scene closures and direct store mutations

Second-order cleanup gaps:

4. shell-era naming drift in scene storage, accessibility IDs, and UI tests
5. tight coupling between focused-value key declarations and command implementation
6. scene-root density in `WorkspaceWindowSceneView`

Lower-priority documentation and surface-shape gaps:

7. keeping the audit and the canonical guide aligned
8. keeping settings explicitly outside the workspace-window command model

## Recommended Next Sequence

If this area gets a real redesign pass, the safest order is:

1. Keep the recorded `Command-W` semantics fixed while the implementation is simplified around them.
2. Add behavioral tests for the current command and focus model.
3. Align the remaining shell-era naming so the code and tests read like the architecture they now represent.
4. Revisit whether the command-context key declarations should stay co-located with the menu implementation.
5. Only after those steps, consider any larger structural simplification of the scene root.

## Bottom Line

The current architecture does not look like it needs a total reset.

It does look like it needs:

- explicit decisions about close semantics
- stronger behavioral protection around scene and focus routing
- one more terminology cleanup pass

That is a much more manageable problem than "SwiftUI command and focus architecture is fundamentally broken here," and it gives future work a clearer target: make the current model more explicit, better tested, and less ambiguous before reaching for a deeper rewrite.
