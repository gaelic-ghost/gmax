# SwiftUI Terminal Shell Architecture

> Status
> Historical shell-architecture background. This note still contains useful
> context, but it is no longer the authoritative source for current focus,
> command, or persistence behavior.
>
> Use these notes instead:
> - [`workspace-focus-target-plan.md`](./workspace-focus-target-plan.md) for
>   current focus decisions
> - [`workspace-window-scene-command-focus-map.md`](./workspace-window-scene-command-focus-map.md)
>   for current scene-command behavior
> - [`framework-command-audit.md`](./framework-command-audit.md) for current
>   command risks and test gaps
> - [`workspace-window-state-and-persistence-model.md`](./workspace-window-state-and-persistence-model.md)
>   for current persistence structure
> - [`swiftterm-surface-investigation.md`](./swiftterm-surface-investigation.md)
>   for the current SwiftTerm boundary

## Purpose

This note is background context for the broader shell architecture.

It is no longer the active planning surface for focus, command, or persistence
work. Keep it for high-level product-shape context and earlier architectural
tradeoff history, not for day-to-day planning.

## Current Source Organization

The source tree is now organized to match the current ownership boundaries in the app:

- `gmaxApp.swift` keeps app bootstrap and scene declarations
- `gmaxApp.swift` and the scene roots hold app bootstrap, menu commands, and UI-test launch behavior
- `Scenes/WorkspaceWindowGroup/` keeps workspace state plus pane and workspace management split by concern
- `Persistence/Workspace/` keeps Core Data setup, persistence profiles, and workspace payload plus placement storage split by concern
- `Terminal/` keeps the SwiftUI representable boundary, coordinator, AppKit host, and terminal-session plumbing
- `Scenes/WorkspaceWindowGroup/` keeps top-level workspace-window scene composition and scene-bound presentation surfaces
- `Scenes/Settings/` keeps the settings entry view plus the terminal appearance and workspace sections
- `Views/Sheets/` keeps the workspace rename and saved-workspace library sheets

This is a durable building-block cleanup, not a stopgap. The source layout should continue to reflect ownership boundaries rather than collapsing unrelated shell, persistence, or AppKit code back into oversized single files.

## Scene Model

The main shell now uses a `WindowGroup`, not a single unique `Window`.

That choice is intentional and grounded in SwiftUI's documented scene model:

- `Window` is the right fit for a unique singleton-style scene
- `WindowGroup` is the standard macOS main-scene surface when users may open multiple primary windows
- `WindowGroup` contributes the standard window-management command surface, including the normal File-menu new-window behavior

This is a durable building-block change, not a testing stopgap.

Why this shape is preferred now:

- it matches the product direction better than a single forced main window
- it gives users native macOS flexibility for arranging multiple shell windows
- it makes scene-local state restoration a better fit for the real UX
- it keeps the app aligned with SwiftUI's expected routing for frontmost-window commands

The current code now uses a data-driven `WindowGroup` scene identity plus
scene-owned `WorkspaceStore` instances:

- each window scene restores its own live and recent workspace state
- the saved workspace library remains the app-wide repository surface
- the persistence boundary is now one payload model plus one placement model

See
[`workspace-window-state-and-persistence-model.md`](./workspace-window-state-and-persistence-model.md)
for the detailed persistence model and follow-through notes.

## Frontmost-Window Command Routing

Menu commands now route through the frontmost shell window's scene context instead of a single app-global workspace-selection binding.

The current preferred model is:

- let each window scene own its own `WorkspaceStore`, initialized with that
  scene's restored `WorkspaceSceneIdentity`
- keep per-window selection and presentation state in scene-local state
- expose that context through `focusedSceneValue`
- have `Commands` read it through `@FocusedValue`
- keep destructive confirmations owned by the scene context instead of burying them inside one sidebar or content subview

This keeps command behavior aligned with native macOS expectations:

- `New Window` should be window-system behavior, not custom shell behavior
- shell actions like save, split, rename, close-to-library, and pane focus should act on the frontmost shell window
- destructive menu actions like workspace deletion should present a confirmation in the frontmost shell window before mutating shared model state
- different shell windows can select different workspaces without fighting over one app-global binding

This boundary should remain explicit as the app grows. If future work adds more cross-window behavior, start by asking whether it is truly app-global or whether it belongs to the frontmost scene.

## High-Level Shell Structure

The root shell should use a three-column `NavigationSplitView`:

- `sidebar`: workspace list
- `content`: selected workspace pane tree
- `detail`: active pane inspector and badges

The intended shell shape is:

```swift
NavigationSplitView {
    WorkspaceSidebar(...)
} content: {
    WorkspaceContentView(...)
} detail: {
    ActivePaneInspector(...)
}
```

This is a durable building-block choice, not a stopgap.

Why this shape is preferred:

- workspaces are a first-class navigation concept
- pane layouts belong to a workspace, not to global shell state
- the right rail is contextual to the active pane, not a second navigation hierarchy
- the shape matches terminal products better than a flat tab bar or a document-centric split view

## SwiftTerm Integration Model

SwiftTerm on macOS should be treated as an AppKit terminal surface that we host from SwiftUI using `NSViewRepresentable`.

Important distinction:

- `TerminalView` is the embeddable terminal UI and emulator surface
- `LocalProcessTerminalView` is `TerminalView` plus a built-in local PTY-backed process runner

The current preferred default is:

- use AppKit-hosted SwiftTerm views in terminal panes
- keep terminal session ownership out of SwiftUI view state
- choose between `TerminalView` and `LocalProcessTerminalView` based on backend needs

Guidance:

- choose `LocalProcessTerminalView` for a native local shell flow on macOS
- choose `TerminalView` when the backend is remote, virtualized, multiplexed, custom, or otherwise not "launch one local shell process in a PTY"

## Performance Model

The main performance goal is to avoid routing live terminal output through SwiftUI state.

The terminal text stream should not drive `@State`, `@Published` UI text snapshots, or body recomputation for the shell hierarchy.

Instead:

- the terminal session emits data into SwiftTerm and AppKit
- SwiftTerm updates and renders inside the hosted AppKit view
- SwiftUI only reacts to structural shell changes

Examples of state that *should* live in SwiftUI:

- workspace list
- selected workspace
- pane tree topology
- active pane identity
- sidebar and inspector visibility
- split fractions
- infrequent title or badge updates if throttled

Examples of state that *should not* live in SwiftUI:

- terminal buffer text
- cursor motion
- per-byte output
- paint timing
- high-frequency session output events

This keeps multiple active terminals from turning the SwiftUI shell into the rendering hot path.

## Pane Topology

The pane layout should be modeled as a recursive split tree, not as a flat grid.

This matters because the intended behavior is split-driven:

- split the active pane to the right
- split the active pane downward
- preserve the rest of the layout
- move focus into the newly created pane

That is naturally a tree rewrite operation, not a row/column matrix rewrite.

Preferred model:

```swift
struct Workspace {
    var id: WorkspaceID
    var title: String
    var root: PaneNode
}

enum PaneNode {
    case leaf(PaneLeaf)
    case split(PaneSplit)
}

struct PaneLeaf {
    var id: PaneID
    var sessionID: TerminalSessionID
}

struct PaneSplit {
    enum Axis {
        case horizontal
        case vertical
    }

    var axis: Axis
    var fraction: CGFloat
    var first: PaneNode
    var second: PaneNode
}
```

This tree model gives us:

- arbitrary nested split layouts
- predictable split-right and split-down behavior
- stable focus targeting
- a clean path for future pane moves, zooming, collapsing, or replacement

## Pane Identity vs Session Identity

Pane identity and terminal session identity should remain separate.

Why this separation is worth keeping:

- a pane can be replaced while preserving the session
- a session can move between panes later if we add rearrangement
- leaf identity can remain UI-focused while session identity remains backend-focused
- the model composes better if we later support non-terminal pane content

Preferred separation:

```swift
struct PaneLeaf {
    var id: PaneID
    var sessionID: TerminalSessionID
}
```

If needed for an early prototype, these can temporarily collapse to the same value, but the separate model is the preferred primitive.

## Workspace Persistence Layers

Workspace persistence should be treated as three distinct layers with different semantics:

- live session persistence for the workspaces currently open in the window
- recently closed persistence for fast undo-style recovery
- saved workspace library persistence for durable saved entries that can be listed, searched, reopened, or managed later

These layers should stay separate in both the app model and the persistence model.

Why this separation matters:

- live session state answers "what is open right now"
- recently closed answers "what did the user just close and may want to undo"
- saved library answers "what saved workspaces should exist independently of the current live session"

The current implementation is:

- `WorkspaceEntity` is the canonical workspace payload row
- `WorkspacePlacementEntity` tracks whether that payload is `.live`, `.recent`,
  or `.library`, and which scene identity owns the live or recent placement
- the in-memory recently closed stack in `WorkspaceStore` is restored from and
  persisted back to `.recent` placements
- the saved library is browsed through lightweight listing metadata denormalized
  onto `.library` placements

## Saved Workspace Library

The saved workspace library should be a durable saved-workspace index, not a
second name for the live session.

A saved workspace entry should store or reference:

- workspace title
- save timestamps such as created and updated dates
- optional user metadata such as notes or pinned state
- the recursive pane tree layout
- per-pane launch context such as shell command and working directory
- per-pane preserved transcript text for restore and search
- a flattened search field derived from title, notes, and transcript content

The current implementation is one payload-plus-placement model inside
`WorkspacePersistenceController`, not a second parallel saved-workspace graph.

This gives us a clean path to:

- `Save Workspace`
- `Close to Library`
- `Open Workspace...`
- searchable saved-workspace lists
- pinning or starring saved entries
- future import/export if we later add file-based saved workspace bundles
- future saved revision history if we decide to retain older payloads per
  library entry

## Transcript-Backed Scrollback Persistence

The current saved-workspace implementation preserves scrollback as transcript text rather than as a fully serialized terminal emulator state.

This distinction is important:

- transcript-backed persistence preserves readable shell history and command output
- full terminal-state persistence would try to preserve emulator details such as alternate-screen state, cursor state, or TUI presentation exactly

SwiftTerm already gives us a strong path for transcript-backed persistence
through its scrollback and buffer inspection APIs, and that path is now what
the app uses for both live recent-close restore and library saves.

The current restore model is:

1. capture transcript text from each pane up to a configured retention limit
2. save the pane launch context alongside that transcript
3. reopen the workspace by restoring layout first
4. restore preserved transcript history into the pane's history presentation
5. launch a fresh shell for each pane using the saved launch context

This should continue to be described in the product as restored history, not as the same suspended process being resumed.

If a more faithful restoration is needed later, that should be treated as a second-phase terminal replay feature rather than as part of the initial saved-workspace library.

## Close, Undo, and Save Matrix

The user-facing settings should make the difference between close behavior and save behavior explicit.

Preferred settings:

- `Keep recently closed workspaces`
- `Auto-save closed workspaces`
- `Restore workspaces on launch`

## Current Command Surface Status

The command surface is now intentionally split across three menu homes:

- `File` owns file-like workspace actions such as `New Workspace`, `Open Workspace...`, `Save Workspace`, and contextual `Close`
- `Workspace` owns workspace lifecycle and workspace-to-workspace navigation
- `Pane` owns pane creation, pane splits, and pane focus movement

This is a durable building-block cleanup, not a stopgap.

The current preferred shortcut model is:

- `cmd-n`: `New Workspace`
- `cmd-o`: `Open Workspace...`
- `cmd-s`: `Save Workspace`
- `cmd-shift-o`: `Undo Close Workspace`
- `cmd-w`: contextual `Close`
- `cmd-option-w`: `Close Workspace`
- `cmd-t`: `New Pane`
- `cmd-d`: `Split Right`
- `cmd-shift-d`: `Split Down`
- `cmd-option-arrow`: directional pane focus
- `cmd-option-[` / `cmd-option-]`: previous and next pane focus
- `cmd-shift-[` / `cmd-shift-]`: previous and next workspace

The current toolbar and sidebar affordance direction is:

- keep menu-bar actions with keyboard shortcuts in the menu bar as the primary discoverability surface
- avoid duplicating those same actions in the sidebar toolbar dropdown when they already have a stable menu home and a shortcut
- reserve the sidebar toolbar dropdown for contextual leftovers that still benefit from local access, such as rename, duplicate layout, close to library, or delete

The current built-in-command guidance is:

- prefer SwiftUI-provided command sets such as `SidebarCommands` when the app has the matching capability
- only keep custom command wiring when the built-in command set does not map cleanly to the app's current scene structure

## Current Follow-Ups

The command and keyboard pass is in a good place structurally, but two follow-ups remain active:

- workspace rename is currently presented from the top-level `Workspace` menu through a notification bridge into the sidebar-owned rename sheet; this works, but it should move to a cleaner scene-level presentation seam
- inspector visibility still uses custom command wiring even though the current shell now presents inspector content through SwiftUI's `.inspector(...)` API; revisit whether a more native inspector command path is worthwhile before a `0.1.0` release

These are polish follow-ups, not blockers for the current command architecture.

Recommended semantics:

- `Keep recently closed workspaces` controls whether close operations populate the undo stack
- `Auto-save closed workspaces` controls whether closing a workspace also persists it into the saved library automatically
- `Restore workspaces on launch` controls whether the live session reopens on app launch

The intended behavior matrix is:

| Keep recently closed | Auto-save closed | Close Workspace result |
| --- | --- | --- |
| Off | Off | Close removes the workspace from the live session only. It is not undoable and does not enter the saved library. |
| On | Off | Close removes the workspace from the live session and pushes it into the recently closed stack only. |
| Off | On | Close removes the workspace from the live session and saves it into the library only. |
| On | On | Close removes the workspace from the live session, pushes it into recently closed, and saves it into the library. |

This is the preferred matrix because it keeps each setting orthogonal:

- one setting controls undo
- one setting controls automatic archival
- neither setting has to silently override the other

That means `Auto-save closed workspaces` should not depend on `Keep recently closed workspaces` being enabled. They should compose cleanly when both are on, and they should continue to make sense when either one is off.

This matrix is now implemented in the app settings and close-workspace behavior.

## Command Model

The command model should map to these layers clearly:

- `Close Workspace`: remove from live session, then apply the settings matrix above
- `Undo Close Workspace`: restore from the recently closed stack only
- `Save Workspace`: explicitly persist the current live workspace into the saved library without closing it
- `Open Workspace...`: browse and reopen saved workspaces from the saved library
- `Delete Saved Workspace`: remove a saved workspace from the saved library without affecting any currently live workspace

This means `Undo Close Workspace` and `Open Workspace...` should remain distinct:

- undo is temporal and stack-based
- open is indexed and library-based

That distinction should remain visible in both commands and internal APIs.

## Current Implementation Status

The app now has the following workspace-lifecycle surfaces in place:

- a searchable saved-workspace library sheet
- explicit `Save Workspace` and `Open Workspace...` commands
- `Close Workspace to Library` for one-step archival
- transcript-backed restore so reopened workspaces preserve shell history
- reopen-title disambiguation when a saved workspace is opened while its original live workspace is still open
- user-facing settings for restore-on-launch, recently closed workspaces, and auto-save closed workspaces

The command surface is also now split intentionally across:

- `File` for new, open, save, and contextual close
- `Workspace` for workspace lifecycle and navigation
- `Pane` for pane creation, splitting, and focus movement

That menu split should be treated as current architecture, not as temporary cleanup.

The test surface is also now grouped by domain:

- shared builders and fixtures in `gmaxTests/TestSupport.swift`
- workspace lifecycle behavior in `gmaxTests/WorkspaceLifecycleTests.swift`
- workspace persistence and saved-library behavior in `gmaxTests/WorkspacePersistenceTests.swift`

That test grouping should be preserved as the app grows so workspace, persistence, and future pane-tree coverage remain readable and maintainable.

## Implementation Plan

The older saved-workspace implementation sketch in this section has been
superseded.

The structural persistence work that actually landed is:

- one canonical `WorkspaceEntity` payload model
- one `WorkspacePlacementEntity` model for `.live`, `.recent`, and `.library`
- one data-driven `WindowGroup` scene identity for per-window restore

Use
[`workspace-window-state-and-persistence-model.md`](./workspace-window-state-and-persistence-model.md)
as the current source of truth for persistence structure and follow-through
work.

The remaining medium-term persistence work is about:

- saved revision history retention
- transcript retention policy
- migration cleanup
- any later higher-fidelity replay work if transcript-backed restore proves
  insufficient

## Split Behavior

The intended pane behavior should work like this:

1. Start with one active pane filling the content area.
2. `splitRight` on that pane replaces the leaf with a horizontal split:
   - `first` child is the original pane
   - `second` child is a new pane
3. Focus moves to the newly created right pane.
4. `splitDown` on that right pane replaces only that leaf with a vertical split:
   - `first` child is the previous right pane
   - `second` child is a new pane
5. Focus moves to the newly created bottom-right pane.

This yields:

- left pane occupying full height on the left half
- top-right pane occupying half height on the top-right quarter
- bottom-right pane occupying half height on the bottom-right quarter

This behavior is a direct fit for recursive split-tree rewriting.

## SwiftUI Rendering Strategy

The center content column should render the pane tree recursively.

Recommended first pass:

- render split nodes with `HSplitView` or `VSplitView`
- render leaf nodes with a terminal pane container that hosts SwiftTerm using `NSViewRepresentable`

Sketch:

```swift
struct PaneNodeView: View {
    let node: PaneNode
    let focusedTarget: WorkspaceFocusTarget?
    let onFocusPane: (PaneID) -> Void
    let onSplit: (PaneID, SplitDirection) -> Void

    var body: some View {
        switch node {
        case .leaf(let leaf):
            TerminalPaneContainer(...)

        case .split(let split):
            if split.axis == .horizontal {
                HSplitView {
                    PaneNodeView(node: split.first, ...)
                    PaneNodeView(node: split.second, ...)
                }
            } else {
                VSplitView {
                    PaneNodeView(node: split.first, ...)
                    PaneNodeView(node: split.second, ...)
                }
            }
        }
    }
}
```

Why this is the recommended first pass:

- native split dividers
- minimal custom layout code
- matches the recursive data model directly
- fast route to a functioning prototype

## Why Not Grid or GridLayout

`Grid` and `GridLayout` are not the preferred primitives for this shell.

Reasons:

- the product behavior is split-based, not table-based
- grid models fight "split this one pane and preserve the rest"
- a recursive split tree is a better semantic match
- `GridLayout` does not solve the main performance concern, which is avoiding terminal output flowing through SwiftUI state

`GridLayout` should only re-enter consideration if the product later wants true row/column coordination semantics rather than nested pane splits.

## Why Not Custom Layout First

A custom `Layout` should not be the first implementation.

We considered starting with `Layout` or `AnyLayout`, but the simpler extension path should come first:

- `HSplitView`
- `VSplitView`
- recursive tree rendering

This keeps the first working version closer to platform-native split behavior and lowers implementation risk.

## When Custom Layout Becomes Worth It

Promote split nodes to a custom `Layout` only if concrete needs appear, such as:

- explicit control over divider fractions beyond what split views give us
- strict minimum pane sizes across recursive layouts
- custom drag handles or snap behavior
- animated pane insertion and removal behavior
- pane zooming and unzooming
- more direct control over hit testing or keyboard-driven divider movement

That would be a durable building-block change if it is driven by clear product requirements. It should not be added speculatively.

## Current Split Rendering Decision

The first prototype used recursive `HSplitView` and `VSplitView` rendering.

That was a good local implementation detail for proving out the pane tree, but it did not hold up once the app started doing real split and close operations. The pane sizes jumped during topology changes because the SwiftUI split containers were free to recompute divider positions, while the pane model already had a stored `fraction` value that the renderer ignored.

The current renderer therefore uses a custom split container that:

- reads `PaneSplit.fraction` from the workspace tree
- writes divider drags back into that same model value
- keeps split sizes stable when sibling panes are added or removed

This is now a durable building-block change, not a cosmetic refactor. It unlocks:

- stable pane geometry during split and close operations
- real future persistence of split ratios
- a straight path to keyboard-driven divider adjustments or snap behavior later

The simpler extension path that was considered first was to keep using `HSplitView` and `VSplitView` and rely on SwiftUI view identity more carefully. We did not continue with that approach because the documented SwiftUI split-view surface does not provide the divider-state binding we would need for predictable restoration.

## AnyLayout Guidance

`AnyLayout` is not the main architectural answer for pane rendering.

It can still be useful in narrow situations:

- dynamically swapping a single local container type while preserving subtree identity
- animating between layout strategies

But the main problem here is pane topology and AppKit hosting, not conditional layout type erasure.

## Terminal Hosting Layer

Each terminal leaf should be backed by a stable controller object, not by ephemeral SwiftUI view structs.

Preferred shape:

```swift
@MainActor
final class TerminalPaneController: ObservableObject {
    let paneID: PaneID
    let sessionID: TerminalSessionID
    let session: TerminalSession
}
```

And then:

```swift
struct TerminalPaneView: NSViewRepresentable {
    let controller: TerminalPaneController
    let isFocused: Bool

    func makeNSView(context: Context) -> TerminalHostingView { ... }
    func updateNSView(_ nsView: TerminalHostingView, context: Context) { ... }
}
```

Important rule:

- SwiftUI owns the shell structure
- the controller owns the terminal session
- the AppKit host owns the live terminal view instance

This avoids view churn from destroying and recreating active terminals during ordinary SwiftUI updates.

## Concrete Host and Session Sketch

The preferred first implementation should introduce four distinct layers:

1. session objects
2. a session registry
3. a pane controller
4. an AppKit host wrapped in `NSViewRepresentable`

These layers should remain separate even in an early prototype.

Why the separation matters:

- terminal sessions have different lifetime rules than panes
- panes can move, split, or close without redefining the session model
- SwiftUI should not own the terminal transport lifecycle
- the AppKit host should stay stable while the shell UI changes around it

### Session Object

Each live terminal backend should be represented by a long-lived session object.

The session should own:

- the backend choice
- local process or remote transport lifetime
- title and cwd state
- badge and activity metadata
- focus or visibility callbacks if needed

The session should not own:

- SwiftUI view identity
- pane tree topology
- split state

Sketch:

```swift
import Foundation

@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    let id: TerminalSessionID

    @Published var title: String
    @Published var workingDirectory: String?
    @Published var badgeCount: Int
    @Published var hasActivity: Bool

    let backend: TerminalBackend

    init(
        id: TerminalSessionID = TerminalSessionID(),
        title: String = "Terminal",
        workingDirectory: String? = nil,
        badgeCount: Int = 0,
        hasActivity: Bool = false,
        backend: TerminalBackend
    ) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.badgeCount = badgeCount
        self.hasActivity = hasActivity
        self.backend = backend
    }
}
```

### Backend Protocol

The host layer should talk to a small backend protocol rather than to raw process or socket code directly.

This keeps the view and coordinator isolated from backend transport choices.

Sketch:

```swift
import Foundation

@MainActor
protocol TerminalBackend: AnyObject {
    func makeHostAdapter() -> TerminalHostAdapter
    func startIfNeeded()
    func stop()
}
```

The backend may be:

- a local process backend that uses `LocalProcessTerminalView`
- a custom transport backend that uses plain `TerminalView`
- a mock backend for previews and tests

### Host Adapter

The AppKit host should depend on a view-facing adapter, not directly on app-wide model types.

The adapter should be the smallest bridge between the terminal view and the backend/session world.

It should own:

- terminal delegate behavior
- title and cwd callbacks
- outgoing input routing
- focus and link callbacks
- access to the concrete AppKit terminal view

Sketch:

```swift
import AppKit
import SwiftTerm

@MainActor
protocol TerminalHostAdapter: AnyObject {
    var sessionID: TerminalSessionID { get }
    var terminalView: NSView { get }

    func focus()
    func applyTheme(_ theme: TerminalTheme)
    func setVisible(_ isVisible: Bool)
    func refreshConfiguration()
}
```

### Local Process Adapter

For the native local-shell path, the adapter can directly own `LocalProcessTerminalView`.

Sketch:

```swift
import AppKit
import SwiftTerm

@MainActor
final class LocalProcessHostAdapter: NSObject, TerminalHostAdapter, LocalProcessTerminalViewDelegate {
    let sessionID: TerminalSessionID
    let localView: LocalProcessTerminalView

    var terminalView: NSView { localView }

    private let session: TerminalSession

    init(session: TerminalSession) {
        self.sessionID = session.id
        self.session = session
        self.localView = LocalProcessTerminalView(frame: .zero)
        super.init()
        self.localView.processDelegate = self
    }

    func startIfNeeded(shell: String = "/bin/zsh") {
        localView.startProcess(executable: shell)
    }

    func focus() {
        localView.window?.makeFirstResponder(localView)
    }

    func applyTheme(_ theme: TerminalTheme) {
        theme.apply(to: localView)
    }

    func setVisible(_ isVisible: Bool) {
        // Hook for future throttling or visibility-based behavior.
    }

    func refreshConfiguration() {
        // Apply font, mouse, cursor, clipboard, or scrollback configuration.
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        session.title = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        session.workingDirectory = directory
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        session.hasActivity = false
    }
}
```

### Embedded Adapter

For custom transports, the adapter should own plain `TerminalView` and implement `TerminalViewDelegate`.

Sketch:

```swift
import AppKit
import SwiftTerm

@MainActor
final class EmbeddedHostAdapter: NSObject, TerminalHostAdapter, TerminalViewDelegate {
    let sessionID: TerminalSessionID
    let embeddedView: TerminalView

    var terminalView: NSView { embeddedView }

    private let session: TerminalSession
    private let transport: TerminalTransport

    init(session: TerminalSession, transport: TerminalTransport) {
        self.sessionID = session.id
        self.session = session
        self.transport = transport
        self.embeddedView = TerminalView(frame: .zero)
        super.init()
        self.embeddedView.terminalDelegate = self
    }

    func focus() {
        embeddedView.window?.makeFirstResponder(embeddedView)
    }

    func applyTheme(_ theme: TerminalTheme) {
        theme.apply(to: embeddedView)
    }

    func setVisible(_ isVisible: Bool) {}

    func refreshConfiguration() {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        transport.send(data)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        transport.resize(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        session.title = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        session.workingDirectory = directory
    }

    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
```

### Session Registry

The shell should look up sessions through a registry keyed by `TerminalSessionID`.

Responsibilities:

- create sessions
- retain live sessions while workspaces reference them
- release sessions when panes close
- provide stable lookup for inspectors and pane hosts

Sketch:

```swift
import Foundation

@MainActor
final class TerminalSessionRegistry {
    private var sessions: [TerminalSessionID: TerminalSession] = [:]

    subscript(_ id: TerminalSessionID) -> TerminalSession? {
        sessions[id]
    }

    func createLocalSession() -> TerminalSession {
        let session = TerminalSession(backend: LocalProcessBackend())
        sessions[session.id] = session
        return session
    }

    func insert(_ session: TerminalSession) {
        sessions[session.id] = session
    }

    func remove(_ id: TerminalSessionID) {
        sessions[id]?.backend.stop()
        sessions[id] = nil
    }
}
```

The registry should stay app-scoped or window-scoped depending on future product decisions.

For the first pass, app-scoped ownership is fine.

### Pane Controller

Each pane leaf should resolve to a controller that binds one pane identity to one session identity and one host adapter.

Responsibilities:

- provide a stable bridge from pane model to host view
- cache the host adapter
- expose focus and visibility methods
- avoid repeated adapter construction during ordinary SwiftUI updates

Sketch:

```swift
import Foundation

@MainActor
final class TerminalPaneController: ObservableObject, Identifiable {
    let id: PaneID
    let sessionID: TerminalSessionID

    private(set) var adapter: TerminalHostAdapter

    init(id: PaneID, session: TerminalSession) {
        self.id = id
        self.sessionID = session.id
        self.adapter = session.backend.makeHostAdapter()
    }

    func focus() {
        adapter.focus()
    }

    func setVisible(_ isVisible: Bool) {
        adapter.setVisible(isVisible)
    }

    func refreshConfiguration() {
        adapter.refreshConfiguration()
    }
}
```

### Pane Controller Store

The shell should also keep a lightweight pane-controller cache keyed by `PaneID`.

This prevents accidental recreation of adapters when SwiftUI redraws the layout tree.

Sketch:

```swift
import Foundation

@MainActor
final class PaneControllerStore {
    private var controllers: [PaneID: TerminalPaneController] = [:]

    func controller(for pane: PaneLeaf, session: TerminalSession) -> TerminalPaneController {
        if let existing = controllers[pane.id] {
            return existing
        }
        let created = TerminalPaneController(id: pane.id, session: session)
        controllers[pane.id] = created
        return created
    }

    func remove(_ paneID: PaneID) {
        controllers[paneID] = nil
    }
}
```

## NSViewRepresentable Shape

The representable should stay extremely thin.

It should not:

- create sessions
- own global shell state
- interpret pane tree mutations
- subscribe to terminal output streams

It should:

- create the AppKit host view once
- apply small configuration updates
- request focus when SwiftUI marks the pane focused

Sketch:

```swift
import SwiftUI
import AppKit

struct TerminalPaneView: NSViewRepresentable {
    let controller: TerminalPaneController
    let isFocused: Bool
    let theme: TerminalTheme

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> TerminalPaneHostView {
        context.coordinator.makeHostingView(theme: theme)
    }

    func updateNSView(_ nsView: TerminalPaneHostView, context: Context) {
        context.coordinator.update(
            hostingView: nsView,
            isFocused: isFocused,
            theme: theme
        )
    }
}
```

### Coordinator Shape

The coordinator should own one stable AppKit container per representable lifetime.

Sketch:

```swift
import SwiftUI
import AppKit

final class Coordinator: NSObject {
    private let controller: TerminalPaneController
    private weak var hostingView: TerminalPaneHostView?

    init(controller: TerminalPaneController) {
        self.controller = controller
    }

    func makeHostingView(theme: TerminalTheme) -> TerminalPaneHostView {
        let hostingView = TerminalPaneHostView(hostedView: controller.adapter.terminalView)
        controller.adapter.applyTheme(theme)
        controller.refreshConfiguration()
        self.hostingView = hostingView
        return hostingView
    }

    func update(
        hostingView: TerminalPaneHostView,
        isFocused: Bool,
        theme: TerminalTheme
    ) {
        controller.adapter.applyTheme(theme)
        controller.refreshConfiguration()
        controller.setVisible(true)
        if isFocused {
            controller.focus()
        }
    }
}
```

### Hosting Container View

The container should be a tiny AppKit wrapper whose only job is to embed the hosted SwiftTerm view and let SwiftUI size it.

Sketch:

```swift
import AppKit

final class TerminalPaneHostView: NSView {
    let hostedView: NSView

    init(hostedView: NSView) {
        self.hostedView = hostedView
        super.init(frame: .zero)

        hostedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostedView)

        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

This is the preferred place to add:

- focus ring drawing
- pane border visuals
- drag target affordances
- accessibility summaries outside SwiftTerm itself

without muddying the terminal host adapter.

## Focus and Update Rules

The host/session layer should follow these rules:

- terminal output should never be copied into SwiftUI view state
- `updateNSView` should apply configuration, not rebuild backend state
- focus changes should be explicit and driven by pane identity
- adapters should be constructed once per pane controller, not once per body pass
- pane closure should release the pane controller and then decide whether to retain or release the session

## Preview and Testability

This layered shape gives us three useful test levels:

- model tests for pane tree rewrites
- adapter tests with mock transports
- headless session tests using SwiftTerm's non-UI path

It also gives us a practical preview path:

- create a mock session
- create a mock backend adapter
- inject it into a pane controller
- render the representable inside a preview shell

## First Implementation Recommendation

Build the first terminal host/session layer with:

1. `TerminalSession`
2. `TerminalBackend`
3. `TerminalSessionRegistry`
4. `PaneControllerStore`
5. `TerminalPaneController`
6. `TerminalPaneView`
7. `TerminalPaneHostView`

Use the local-process backend first if the earliest product milestone is a local shell app.

Keep the embedded-backend adapter sketched and ready, but do not force both backends into the first milestone unless the product needs them immediately.

## Pane Tree Mutation API

The pane-tree mutation surface should stay small, explicit, and topology-aware.

It should not expose low-level "edit arbitrary node graph" operations to the view layer.
Instead, the shell model should provide intent-shaped operations like:

- split pane right
- split pane down
- focus pane
- close pane
- replace pane session
- resize split

This keeps the UI straightforward and prevents pane-management logic from leaking into view code.

### Preferred Mutation Surface

Sketch:

```swift
import Foundation

@MainActor
extension WorkspaceStore {
    func splitPane(_ paneID: PaneID, in workspaceID: WorkspaceID, direction: SplitDirection)
    func closePane(_ paneID: PaneID, in workspaceID: WorkspaceID)
    func replaceSession(in paneID: PaneID, workspaceID: WorkspaceID, with sessionID: TerminalSessionID)
    func updateSplitFraction(_ fraction: CGFloat, for splitPath: PanePath, in workspaceID: WorkspaceID)
}
```

The view layer should call these operations rather than mutating `Workspace.root` directly.

## Split Direction

The shell-level split intent should be separate from the stored split axis.

Sketch:

```swift
enum SplitDirection {
    case right
    case down
}
```

Mapping:

- `.right` creates a `.horizontal` split
- `.down` creates a `.vertical` split

This makes the action vocabulary match the product UI while still storing the correct tree shape.

## Recursive Helpers

Tree operations should be implemented with recursive helpers on `PaneNode`.

Recommended helper responsibilities:

- find a pane leaf by ID
- rewrite one target leaf into a split
- remove one target leaf and repair the tree
- gather leaves in visual order if needed
- locate a split path for persisted divider state

Sketch:

```swift
extension PaneNode {
    func findPane(id: PaneID) -> PaneLeaf?
    func containsPane(id: PaneID) -> Bool
    mutating func split(
        paneID: PaneID,
        direction: SplitDirection,
        newPane: PaneLeaf,
        initialFraction: CGFloat = 0.5
    ) -> Bool
    mutating func removePane(id: PaneID) -> RemovalResult?
}
```

### findPane

Sketch:

```swift
extension PaneNode {
    func findPane(id: PaneID) -> PaneLeaf? {
        switch self {
        case .leaf(let leaf):
            return leaf.id == id ? leaf : nil

        case .split(let split):
            return split.first.findPane(id: id) ?? split.second.findPane(id: id)
        }
    }
}
```

### split

The split helper should only replace the targeted leaf.

Sketch:

```swift
extension PaneNode {
    mutating func split(
        paneID: PaneID,
        direction: SplitDirection,
        newPane: PaneLeaf,
        initialFraction: CGFloat = 0.5
    ) -> Bool {
        switch self {
        case .leaf(let leaf):
            guard leaf.id == paneID else { return false }

            let axis: PaneSplit.Axis = switch direction {
            case .right: .horizontal
            case .down: .vertical
            }

            self = .split(
                PaneSplit(
                    axis: axis,
                    fraction: initialFraction,
                    first: .leaf(leaf),
                    second: .leaf(newPane)
                )
            )
            return true

        case .split(var split):
            if split.first.split(
                paneID: paneID,
                direction: direction,
                newPane: newPane,
                initialFraction: initialFraction
            ) {
                self = .split(split)
                return true
            }

            if split.second.split(
                paneID: paneID,
                direction: direction,
                newPane: newPane,
                initialFraction: initialFraction
            ) {
                self = .split(split)
                return true
            }

            return false
        }
    }
}
```

This is the helper that directly implements the interaction we want:

- split the active pane
- preserve the rest of the tree
- place the old pane first
- place the new pane second

## Close Semantics

Closing a pane needs an explicit tree-repair rule.

Preferred first-pass rule:

- removing one child of a split collapses that split into the surviving sibling

That keeps the topology simple and matches terminal-app expectations.

Sketch:

```swift
enum RemovalResult {
    case removedLeaf
    case collapsedTo(PaneNode)
}
```

Possible implementation direction:

```swift
extension PaneNode {
    mutating func removePane(id: PaneID) -> RemovalResult? {
        switch self {
        case .leaf(let leaf):
            return leaf.id == id ? .removedLeaf : nil

        case .split(var split):
            if let result = split.first.removePane(id: id) {
                switch result {
                case .removedLeaf:
                    self = split.second
                    return .collapsedTo(split.second)
                case .collapsedTo(let node):
                    split.first = node
                    self = .split(split)
                    return .collapsedTo(self)
                }
            }

            if let result = split.second.removePane(id: id) {
                switch result {
                case .removedLeaf:
                    self = split.first
                    return .collapsedTo(split.first)
                case .collapsedTo(let node):
                    split.second = node
                    self = .split(split)
                    return .collapsedTo(self)
                }
            }

            return nil
        }
    }
}
```

This shape may be simplified when the real implementation lands, but the behavioral rule should remain:

- closing one side of a split promotes the surviving sibling

## Focus Rules

Focus changes should be deterministic after each mutation.

Preferred rules:

- splitting a pane focuses the newly created pane
- focusing a pane changes the scene-owned pane focus target for that window
- closing a focused pane should move focus to the nearest surviving sibling in the repaired tree
- closing a non-focused pane should preserve focus if still valid

The scene should own those rules, not the persistence model.

Sketch:

```swift
@MainActor
extension WorkspaceStore {
    func splitPane(_ paneID: PaneID, in workspaceID: WorkspaceID, direction: SplitDirection) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return
        }

        let session = sessions.createLocalSession()
        let newPane = PaneLeaf(sessionID: session.id)

        guard workspaces[workspaceIndex].root.split(
            paneID: paneID,
            direction: direction,
            newPane: newPane
        ) else {
            return
        }

        focusedTarget = .pane(newPane.id)
    }
}
```

## Pane Paths and Split Fractions

Divider persistence should not depend on view position alone.

If we want durable split resizing, each split should be addressable by a stable path.

A lightweight first pass is to define a structural path:

```swift
enum PanePathStep: Codable, Hashable {
    case first
    case second
}

typealias PanePath = [PanePathStep]
```

This allows us to:

- identify a split node during recursive rendering
- bind a divider state to that split location
- persist fractions alongside the workspace tree if needed

If later edits make structural paths too unstable, we can promote split identity into the model with a dedicated split ID.

That should only happen if concrete use cases demand it.

## Workspace Store Responsibilities

The workspace store should remain the owner of:

- workspace list
- pane-tree mutations
- session creation and release decisions
- persistence triggers for layout changes

The scene should remain the owner of:

- selected workspace
- focus rules
- sidebar and inspector presentation state

The view layer should not:

- allocate sessions
- manipulate tree nodes directly
- decide focus outcomes after mutations

## Suggested WorkspaceStore Sketch

```swift
import SwiftUI

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var workspaces: [Workspace]
    @Published var selectedWorkspaceID: WorkspaceID?
    @Published var columnVisibility: NavigationSplitViewVisibility = .all

    let sessions: TerminalSessionRegistry
    let panes: PaneControllerStore

    init(
        workspaces: [Workspace] = [],
        selectedWorkspaceID: WorkspaceID? = nil,
        sessions: TerminalSessionRegistry = TerminalSessionRegistry(),
        panes: PaneControllerStore = PaneControllerStore()
    ) {
        self.workspaces = workspaces
        self.selectedWorkspaceID = selectedWorkspaceID
        self.sessions = sessions
        self.panes = panes
    }
}
```

Useful computed accessors:

```swift
@MainActor
extension WorkspaceStore {
    var selectedWorkspaceIndex: Int? {
        guard let selectedWorkspaceID else { return nil }
        return workspaces.firstIndex { $0.id == selectedWorkspaceID }
    }

    var selectedWorkspace: Workspace? {
        guard let index = selectedWorkspaceIndex else { return nil }
        return workspaces[index]
    }

    var focusedPane: PaneLeaf? {
        guard
            let workspace = selectedWorkspace,
            case .pane(let paneID) = focusedTarget
        else {
            return nil
        }
        return workspace.root.findPane(id: paneID)
    }
}
```

## Persistence Hooks

Layout persistence should happen after successful model mutations, not during view rendering.

Recommended rule:

- mutate workspace tree
- update focus
- schedule persistence

Persistence should observe:

- workspace creation and deletion
- pane tree rewrites
- split fraction changes
- workspace title changes

Persistence should not depend on the representable layer.

## First Implementation Recommendation for Tree Logic

The first concrete pane-management pass should implement:

1. `findPane`
2. `split`
3. `removePane`
4. `focusPane`
5. `splitPane`
6. `closePane`

That is enough to support:

- selecting a workspace
- focusing panes
- split-right
- split-down
- close pane
- keeping the right inspector synchronized with the active pane

Additional operations like move, swap, drag-to-reorder, and pane zoom should wait until the basic mutation model is proven.

## Session Registry

Terminal sessions should be looked up from a registry or store rather than embedded directly into `Workspace`.

Benefits:

- clear lifetime control
- easier detaching and reattaching
- easier process cleanup
- easier future background session support
- easier future persistence boundaries

Suggested ownership:

- `WorkspaceStore` owns workspace topology
- `TerminalSessionRegistry` owns live session objects

## Focus Model

The focused pane should not be persisted as part of workspace state anymore.

This allows:

- the content column to highlight the active pane
- split commands to target the correct pane
- the detail column to inspect the correct pane
- per-workspace focus restoration when switching among workspaces

Recommended rule:

- the scene owns the active `WorkspaceFocusTarget`
- the shell derives the active pane inspector from the selected workspace plus
  that scene-owned focused pane target

## Directional Pane Navigation

Directional focus movement should be geometric and deterministic, not purely tree-structural.

The pane tree is the right primitive for split and close operations, but it is not by itself a good navigation policy when panes become uneven. A purely tree-driven rule tends to feel arbitrary once a large pane sits beside multiple smaller panes.

The preferred navigation rule is:

1. collect the live rendered frames of all leaf panes inside a named SwiftUI coordinate space
2. when moving left, right, up, or down, keep only panes that are actually in that direction from the currently focused pane
3. rank candidates using this priority order:
   - largest overlap on the perpendicular axis
   - smallest distance on the movement axis
   - most recent focus history as the human-friendly tie breaker
   - stable final tie break by pane identity if needed

Examples:

- moving right from a tall left pane toward two stacked right panes should prefer the right-hand pane whose vertical span overlaps the current pane centerline best
- moving left from either right-hand pane back toward the tall left pane should choose that left pane because it is the nearest valid pane in that direction with strong overlap

The first implementation should be pane-frame-aware, but not cursor-aware.

That means:

- track pane frames, not terminal cursor rows
- use pane centerlines and overlap scoring
- keep the ranking rules stable and explainable

Cursor-aware navigation can be added later if the product needs it, but pane-frame-aware navigation is the durable building-block change that removes the current fake linear ordering while still composing cleanly with arbitrary recursive splits.

## Persistence Strategy

Use `SceneStorage` only for lightweight scene-scoped shell state.

Good candidates for `SceneStorage`:

- selected workspace ID
- sidebar visibility
- right inspector visibility
- perhaps the active pane ID for the current scene

Do not use `SceneStorage` as the primary persistence for full workspace and pane-layout documents.

The durable persistence direction for this app is Core Data, not a raw JSON snapshot file and not hand-managed SQLite.

Why:

- the shell model is now a structured, frequently edited graph
- pane splits, closes, focus updates, and workspace lifecycle events all benefit from targeted writes rather than full-tree blob replacement
- the platform-native future sync path is `NSPersistentCloudKitContainer`

Recommended split of responsibility:

- Core Data stores durable shell model state
- scene-scoped selection and visibility state can still remain scene-scoped later

Core Data should own:

- workspaces
- pane nodes
- split fractions and axes
- leaf session identifiers and pane identifiers
- focused pane per workspace
- future sync-worthy settings, themes, and custom actions

Core Data should not become the dump site for every transient UI detail.

### Relational Graph Shape

Persist the pane tree as relational nodes and edges, not as a serialized workspace blob.

Recommended first-pass shape:

- `WorkspaceEntity`
- `PaneNodeEntity`

`WorkspaceEntity` stores:

- stable workspace identifier
- title
- focused pane identifier
- sort order
- optional root-node relationship so an empty workspace is representable

That optional root relationship should be treated as a real product state, not just a recovery seam.

Normal user flows should still prefer creating workspaces with an initial pane, but closing the last pane in a selected workspace should leave that workspace behind as an explicit empty workspace. The shell UI should render that empty state intentionally in the content pane, because the model and persistence layer already admit that shape, restore or migration paths can encounter it, and the close-command model is simpler when pane close, workspace close, and window close remain distinct lifecycle steps.

`PaneNodeEntity` stores:

- stable node identifier
- node kind (`leaf` or `split`)
- optional session identifier for leaf nodes
- optional split axis and fraction for split nodes
- first-child and second-child relationships for binary tree structure

This is still a relational node-and-edge model even though the child edges are named rather than stored in a separate edge table.

Why this shape is preferred:

- it matches the binary split-tree semantics we already use in memory
- it keeps fetch and reconstruction straightforward
- it makes split and close operations natural to persist
- it gives us a better future path for undo, migrations, and CloudKit-backed sync than a serialized tree payload

### First Implementation Constraint

The first Core Data implementation should define the managed object model in code rather than through an `.xcdatamodeld` file.

This is a conscious implementation constraint for the current repository, not a statement that code-defined models are always superior.

Why:

- the repository rule forbids direct `.pbxproj` editing
- there is no existing safe project-aware path in this repo for introducing a new model resource
- a programmatic `NSManagedObjectModel` still uses documented Core Data APIs and keeps the persistence work unblocked

The relevant Apple API surface here is `NSPersistentContainer.init(name:managedObjectModel:)`, which explicitly supports providing a managed object model in code.

Reasons:

- Apple positions `SceneStorage` as lightweight scene-scoped state
- persistence timing is system-managed and not guaranteed
- large model payloads are a poor fit

Preferred persistence split:

- durable app storage for workspaces and pane trees
- `SceneStorage` for current scene context and lightweight restoration state

## Right Inspector Column

The detail column is intentionally not another navigation hierarchy.

It should stay scoped to the active pane in the selected workspace.

Examples of appropriate content:

- session title
- current directory
- process status
- unread or activity badges
- session mode indicators
- shell metadata
- pane-local actions

This keeps the shell model simple:

- sidebar chooses workspace
- content renders workspace
- detail inspects the active pane

## Accessibility and Future Considerations

SwiftTerm's current macOS accessibility posture looks incomplete, so this shell should preserve room for host-side accessibility improvements.

That means:

- avoid baking assumptions that terminal accessibility is "already solved"
- keep pane models and host controllers structured enough that accessibility overlays or summaries can be added later
- preserve the ability to add host-level focus descriptions and inspector-driven summaries without redesigning the pane tree

## Current Recommendation

Build the first pass with:

1. `NavigationSplitView` for shell structure
2. recursive split-tree model for pane topology
3. `HSplitView` and `VSplitView` for split-node rendering
4. `NSViewRepresentable` wrappers around AppKit SwiftTerm views
5. stable controller/session ownership outside SwiftUI view structs
6. lightweight `SceneStorage` only for per-window shell state
7. durable app storage for workspace layouts

This is the preferred baseline until concrete product needs justify moving split-node rendering to a custom `Layout`.
