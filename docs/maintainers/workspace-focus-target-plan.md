# Workspace Focus Target Plan

## Purpose

This note proposes the next design pass for workspace focus in `gmax` after the
first structural implementation pass landed.

It starts from the framework model first:

- `NavigationSplitView` is the root container for the workspace window, and selections in leading columns are supposed to control later columns.
- `List(selection:)` plus `NavigationLink(value:)` is the standard SwiftUI shape for sidebar-driven selection in a split view.
- `focusedValue` and `focusedSceneValue` are for publishing command context, not for inventing a custom runtime focus engine.
- modal presentation should normally belong to the view layer that owns the associated presentation state, and should stay as local as possible without splitting state ownership from the command surface.
- `WindowGroup` windows are supposed to maintain independent state, and `SceneStorage` is per scene rather than shared across the whole app.

Use this together with:

- [`workspace-focus-removal-and-redesign-notes.md`](./workspace-focus-removal-and-redesign-notes.md)
- [`workspace-focus-implementation-boundary.md`](./workspace-focus-implementation-boundary.md)
- [`workspace-focus-first-pass-plan.md`](./workspace-focus-first-pass-plan.md)
- [`swiftterm-surface-investigation.md`](./swiftterm-surface-investigation.md)
- [`workspace-window-scene-command-focus-map.md`](./workspace-window-scene-command-focus-map.md)
- [`swiftui-command-and-focus-architecture.md`](./swiftui-command-and-focus-architecture.md)

## Core Design Goal

Define a small, stable set of logical focus targets for the workspace window, then shape the view hierarchy around those targets.

Define the window’s scene-owned state just as clearly, so each `WindowGroup` instance can restore and operate independently.

The design should avoid treating every wrapper view as a focus participant. A view should only become a first-class focus target if all of the following are true:

- the user can reasonably think of it as a place they are working in
- entering it changes command meaning or keyboard behavior
- it has a stable identity
- it is not just a visual shell around a more meaningful target

## Proposed Logical Focus Targets

These are the focus targets worth designing around.

### 1. Sidebar workspace list

This should be the root selection surface for workspace navigation in the window scene.

This is already close to the right framework shape in [`gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/SidebarPanel/SidebarPane.swift`](../../gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/SidebarPanel/SidebarPane.swift):

- `List(selection: $selection)`
- `ForEach(model.workspaces)`
- `NavigationLink(value: workspace.id)`

That matches Apple’s documented `NavigationSplitView` pattern, where list selection in the leading column controls the later column.

### 2. Workspace listing row

Each row should be a small view of its own, likely something like `WorkspaceListingView`, rendered by the `ForEach`.

That row view should:

- own the row label and subtitle layout
- remain selection-driven through the enclosing `List`
- keep context menu and row-level accessibility together

It should not become its own custom focus engine. It is a row in the sidebar’s native focus and selection system.

### 3. Pane container

Each visible workspace pane should have a stable logical focus identity.

This is the main custom focus target in the content column. It is the thing pane commands should target:

- close pane
- split pane
- relaunch pane
- directional pane navigation

The likely long-term identity shape is something like:

- `WorkspaceFocusTarget.sidebar`
- `WorkspaceFocusTarget.pane(PaneID)`
- `WorkspaceFocusTarget.inspector`

The pane should be the semantic command target even if some lower AppKit control inside it owns text input.

### 4. Terminal prompt and scrollback behavior

Prompt input and scrollback selection should not be modeled as separate
scene-level or command-level focus targets in `gmax`.

This is now considered settled:

- the pane is the workspace-level focus and command target
- SwiftTerm owns prompt input, scrollback selection, find, copy, and other
  internal terminal interaction behavior
- `gmax` should not layer a second prompt-versus-scrollback focus model on top
  unless a future product requirement proves SwiftTerm's existing surface
  insufficient

### 5. Inspector region

The inspector likely deserves to be a real focus region, but not a pane command target.

That means:

- it should participate honestly in native focus movement
- pane-targeted commands should usually disable when focus leaves content and moves here
- scene-wide commands can still remain available

### 6. Modal surfaces

Modal surfaces should use native modal focus and presentation rules rather than joining the workspace pane focus graph.

That includes:

- saved workspace library
- rename workspace sheet
- destructive delete confirmation

## Proposed Scene-Owned Window State

The workspace window likely needs a clearer scene-owned state model in addition to a clearer focus model.

### State that should stay per window scene

This state should likely be independent for each `WindowGroup` window:

- selected workspace
- the set and order of workspaces currently open in that window
- sidebar visibility
- inspector visibility
- active modal presentation state
- current logical focus target

This matters because `WindowGroup` windows are supposed to maintain independent state, and `SceneStorage` is explicitly per scene. If multiple windows are currently sharing the same “open workspaces in the sidebar” state, that strongly suggests our current ownership or persistence model is treating window-local workspace state as app-global state.

### Likely implication

The list of currently open workspaces in the sidebar should likely be scene state, not global workspace persistence state.

That means the app may need to distinguish between:

- saved workspace snapshots or library entries
  - app-wide persisted resources
- open workspaces in a specific window
  - scene-local runtime state with scene restoration

If that split is correct, a new window should get either:

- a default starting workspace set
- or a restored scene-local workspace set

but not automatically mirror another live window’s current sidebar contents.

## Things That Should Not Be First-Class Custom Focus Targets

These should remain implementation detail or visual structure, not logical focus identities:

- split containers
- overlay title capsules
- decorative `VStack` or `ZStack` wrappers
- geometry-reporting helpers
- noninteractive status labels
- root content wrappers that only exist for layout

## View-Shape Adjustments Likely Needed

To support the better focus model, some views probably need reshaping.

### Sidebar

The sidebar is already close to the ideal structure, but it likely wants one more decomposition step:

- `SidebarPane`
  - owns `List(selection:)`
  - owns toolbar-level sidebar actions
  - owns workspace selection binding
- `WorkspaceListingView`
  - owns row appearance, row accessibility, and possibly row-local menu content

That keeps the sidebar root as the owner of workspace selection and split-view coordination, which matches the standard `NavigationSplitView` model.

The sidebar root is also the strongest current candidate for owning window-local workspace list presentation, because it is the scene’s leading-column selection surface.

### Content pane

The content column likely wants a clearer boundary between:

- pane layout tree
- pane focus identity
- terminal interaction surface

The current `ContentPaneLeafView` is doing all three at once:

- visual pane wrapper
- focusable surface
- terminal hosting wrapper
- overlay presentation
- local command-context publishing

It may need to split into something more like:

- `PaneContainerView`
  - pane identity
  - pane focus state
  - pane-local command context
  - visual selected/focused styling
- `PaneTerminalSurfaceView`
  - terminal host bridge
  - SwiftTerm-owned internal terminal interaction behavior

That is not a guarantee, but it is a likely consequence of the design you described.

### Inspector

The inspector may want an explicit region wrapper if we decide it participates in the shared focus graph as a named target.

### Modal ownership

The current root scene view owns:

- saved workspace library sheet
- rename workspace sheet
- delete confirmation alert

That is defensible, because the scene root currently owns the presentation state and the scene-wide command surface that triggers those actions.

However, this should be revisited with one question in mind:

- is this modal truly scene-owned, or is it actually owned by a narrower feature surface?

Current recommendation:

- keep rename and delete presentation scene-owned for now, because they act on the selected workspace in the active window and are command-triggered from the scene surface
- re-evaluate the saved workspace library as a possible dedicated scene-level presentation surface with a more explicit owner, especially if it becomes more navigational or document-like over time

Do not move presentation lower in the tree unless the lower layer also becomes the clear owner of the associated state and command context.

One important corollary is that rename and delete action availability should not be treated as “sidebar-only” if the active target is the selected workspace in the active window. If those actions conceptually operate on the active window’s selected workspace, the cleanest default is:

- scene owns the presentation state
- scene publishes the rename and delete actions
- sidebar and content both contribute whatever context is needed to identify the active workspace truthfully

That may mean the current selected-workspace scene context is already the right backbone, and the question is less “which panel owns delete?” than “which layer truthfully defines the active workspace for this window?”

## Proposed Focus Architecture Direction

### Scene-owned state

The window scene should own:

- selected workspace
- open workspaces for this window
- sidebar visibility
- inspector visibility
- current modal presentation state
- current logical focus target

That suggests a scene-level focus state, likely something like:

- `@FocusState private var focusedTarget: WorkspaceFocusTarget?`

### Logical target enum

A likely first proposal:

```swift
enum WorkspaceFocusTarget: Hashable {
	case sidebar
	case pane(PaneID)
	case inspector
}
```

This is intentionally small. Modal surfaces should not join this enum unless a concrete reason appears.

### Pane-local lower-level interaction

Within a focused pane, SwiftTerm may still manage lower-level internal terminal
states like prompt input versus scrollback selection.

That distinction belongs below the scene-wide focus enum. The higher-level
command system should not need to care.

## Recommended Sequencing

### Phase 1: define next-pass ownership boundaries

Decide:

- whether sidebar, pane, and inspector are the only logical window focus targets
- whether any future product requirement truly needs more than SwiftTerm's
  existing internal prompt-versus-scrollback behavior
- whether modals remain scene-owned
- whether the set of open workspaces belongs to scene-local state rather than global persistence
- whether the active workspace is defined entirely by scene selection, or by some more local panel-specific rule

### Phase 2: reshape views

Adjust view structure so each logical focus target has a clean owning view:

- sidebar root
- workspace listing row
- pane container
- terminal surface
- optional inspector region wrapper

### Phase 3: narrow remaining terminal-side glue

Keep scene-owned native focus as the source of truth, then remove or narrow the
remaining terminal bridge behavior that still follows derived pane focus.

### Phase 4: re-evaluate scene-local restoration and persistence

Now that runtime focus is no longer model-owned, decide how per-window open
workspace state, recent-close behavior, and any restoration metadata should be
persisted without collapsing window-local state back into app-global state.

## Immediate Next-Pass Questions

These are the decisions worth making before the next implementation pass:

1. Is the pane, not the embedded terminal control, the main command target?
2. Does any product requirement actually need `gmax` to distinguish more than
   SwiftTerm already distinguishes internally?
3. Should pane commands disable whenever focus moves to the sidebar or inspector?
4. Should modal presentations remain scene-owned at the workspace window root?
5. Is the smallest useful logical target set just `sidebar`, `pane(PaneID)`, and `inspector`?
6. Is the list of open workspaces in a window scene-local state that must restore independently per window?
7. If so, what is the app-wide persisted thing: saved workspace library entries, reusable templates, or some other snapshot type, rather than the live sidebar contents of every window?
8. Are rename and delete commands scene-level commands that operate on the selected workspace in the active window, regardless of whether the user reached them from sidebar or content?

## Provisional Design Decisions

This section records the current intended direction before implementation. These
decisions should be treated as the working target model unless a later
investigation shows a concrete framework constraint.

### 1. Pane versus embedded terminal as the main command target

Current decision:

- the pane remains the main command target
- the embedded terminal surface is still important enough to investigate as its own extension or integration point

The current design decision is that prompt-versus-scrollback behavior belongs
below the pane-level command surface, inside SwiftTerm. Closing, splitting,
relaunching, and pane navigation should still target the enclosing pane.

Follow-up required:

- inspect what SwiftTerm’s view surface can expose or support directly
- avoid promoting prompt-versus-scrollback into a scene-level focus taxonomy
  unless a future command surface proves SwiftTerm's existing behavior
  insufficient

### 2. Prompt versus scrollback

Current decision:

- prompt versus scrollback changes terminal-native text interaction behavior,
  not pane command meaning
- SwiftTerm, not `gmax`, owns that distinction

That means:

- the pane is still the focused pane while interaction is in either prompt or scrollback
- `Close Pane` should close the pane in both cases
- lower-level text selection, copy, edit, and input behavior may differ inside the pane

### 3. Pane commands versus sidebar or inspector focus

Current decision:

- pane-oriented commands should disable when focus leaves content and moves to the sidebar or inspector

This is important because sidebar focus should make sidebar-relevant commands possible. For example, if the user is navigating the sidebar list with the keyboard and has a workspace row focused or selected there, `Close Workspace` should act on that selected workspace rather than acting like a pane command.

### 4. Modal ownership

Current decision:

- modal presentation remains scene-owned at the workspace window root

Rationale:

- the same modal may be triggered from multiple subtrees
- modal state is important enough to keep centralized
- the app should require the user to resolve or dismiss the modal before continuing normal interaction in the window

### 5. Smallest useful logical focus-target set

Current decision:

- the smallest useful set is probably larger than just `sidebar`, `pane(PaneID)`, and `inspector`
- however, the additional sidebar granularity may come from native `List` behavior rather than from a larger custom scene-level focus enum

That means the model should distinguish between:

- custom logical focus targets we define explicitly
- native built-in focus behavior we intentionally rely on inside those regions

For now, the likely scene-level custom focus targets are still:

- `sidebar`
- `pane(PaneID)`
- `inspector`

while individual `WorkspaceListing` rows are likely native focus participants inside the sidebar’s built-in list behavior rather than extra custom enum cases.

### 6. Open workspaces in a window

Current decision:

- the set of open workspaces is scene-local state and should restore independently per window

Each `WindowGroup` window should maintain its own:

- open workspace set
- ordering of those workspaces
- current selection
- live recent-close stack

### 7. App-wide persisted state versus scene-local state

Current decision:

- the true app-wide persisted state is the workspace library index plus the persisted workspace payloads behind those library entries
- the live sidebar contents of a window are not the app-wide truth

The app-wide library should include:

- an index of saved workspaces
- one `LibraryListing`-like metadata record per saved workspace
- metadata roughly parallel to what a `WorkspaceListing` exposes

Opening a saved workspace from the library should:

- load the workspace from disk
- add it into the active window’s scene-local open workspace state
- make it available in that window’s sidebar

### 7a. Recently closed workspaces

Current decision:

- recently closed workspaces become scene-local, window-scoped state

The intended behavior is:

- maintain a live in-memory LIFO stack per window
- cap the stack at a configurable recent limit
- when the stack exceeds the limit, evict the oldest entry
- eviction behavior should depend on user preference:
  - delete it
  - or persist it to disk

On window close:

- the same persistence setting should apply to these recent items
- if persisted, they should be restored with the rest of that window’s scene-local state

### 8. Rename and delete command ownership

Current decision:

- rename and delete are scene-level commands that operate on the selected workspace in the active window

That means:

- they should not be treated as sidebar-only commands
- scene state should own their presentation
- sidebar and content can both contribute the context that identifies the active workspace, but the scene remains the owner of the command and modal behavior

## Outstanding Investigation

One meaningful technical question remains open:

- should the embedded SwiftTerm view need any extension at all beyond letting
  SwiftTerm continue owning its internal prompt and scrollback interaction
  model?

This needs investigation before finalizing the pane-level implementation shape.

If these are answered clearly, the implementation plan should become much safer and much smaller.
