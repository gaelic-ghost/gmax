/*

This note records the current workspace persistence foundation for the
intentionally multi-window, per-window scene model in gmax, plus the remaining
follow-through work.

It is the pass-two data-model companion to the workspace-focus redesign notes.
The main structural change already landed: the app no longer keeps one
app-global live-workspace persistence story and a separate saved-library
payload story. It now uses one canonical workspace payload model plus one
explicit placement model.

*/

# Workspace Window State And Persistence Model

## Purpose

This note defines the current on-disk model for:

- live workspaces in a specific window
- recently closed workspaces in a specific window
- saved workspaces in the library
- future saved revisions for those library workspaces over time

The product model is:

- the library owns stable saved entries on disk
- the library UI is filled from lightweight listing records
- opening from the library fetches the saved payload revision and clones it into
  a live working copy
- saving writes a new saved payload back to that stable library entry
- explicit saved revision history remains follow-through work, not landed behavior

Under that model:

- one concrete workspace state revision should be stored in one canonical
  durable payload shape
- where that payload currently appears should be modeled separately from the
  payload itself

That separation keeps the data model simpler and makes the per-window scene
model fit SwiftUI's documented `WindowGroup` and `SceneStorage` behavior more
cleanly.

Use this together with:

- [`workspace-focus-guide.md`](./workspace-focus-guide.md)
- [`swiftui-terminal-shell-architecture.md`](./swiftui-terminal-shell-architecture.md)

This note now serves two jobs:

- document the current shipped persistence shape
- record the intended next simplification so future persistence work keeps
  converging instead of branching again

## Documented Apple Behavior This Depends On

This model depends on three Apple behaviors:

- every `WindowGroup` window maintains independent state
- `SceneStorage` is lightweight, per-scene state restoration, not a place for
  real model payloads
- `FetchRequest` and `FetchedResults` are appropriate for Core Data-backed UI
  collections, but they should not replace scene-local working state when the
  view is really rendering a per-window working set

Relevant Apple docs:

- `WindowGroup`
  - <https://developer.apple.com/documentation/swiftui/windowgroup>
- `WindowGroup.init(id:for:content:)`
  - <https://developer.apple.com/documentation/swiftui/windowgroup/init(id:for:content:)>
- `WindowGroup.init(id:for:content:defaultValue:)`
  - <https://developer.apple.com/documentation/swiftui/windowgroup/init(id:for:content:defaultvalue:)>
- `SceneStorage`
  - <https://developer.apple.com/documentation/swiftui/scenestorage>
- `ScenePhase`
  - <https://developer.apple.com/documentation/swiftui/scenephase>
- `Scene.onChange(of:initial:_:)`
  - <https://developer.apple.com/documentation/swiftui/scene/onchange(of:initial:_:)> 
- `FetchRequest`
  - <https://developer.apple.com/documentation/swiftui/fetchrequest>
- `FetchedResults`
  - <https://developer.apple.com/documentation/swiftui/fetchedresults>

## Current Model

The app now has three workspace buckets backed by one payload entity and one
placement entity:

### 1. Live workspaces

- `WorkspaceStore.workspaces` is the live array used by the sidebar and content
  views
- each window scene owns its own `WorkspaceStore`
- the store restores live workspaces by loading `.live`
  `WorkspacePlacementEntity` rows for that scene's `WorkspaceSceneIdentity`
- the placement points at a canonical `WorkspaceEntity` payload row that owns
  the pane tree and per-pane session snapshot data

### 2. Recently closed workspaces

- recently closed workspaces are now driven by durable workspace-owned recency
  metadata on `WorkspaceEntity`, keyed by the owning window identity
- legacy `.windowRecent` placement rows are still lazily migrated forward from
  older stores, but new recent-close writes no longer create that placement
  role
- `WorkspaceStore` no longer keeps a parallel in-memory workspace undo stack
- `Undo Close Workspace` now restores the most recent durable workspace
  associated with the current window
- recency is driven by durable timestamps such as `lastActiveAt`
- this is the preferred direction for workspace recency inside Slice 1, even
  though the later model still wants cleaner explicit library-item entities

### 3. Library workspaces

- the saved workspace library is now backed by stable `.library`
  `WorkspacePlacementEntity` rows
- those placements carry lightweight listing metadata for library browsing
- each `.library` placement points at the current saved `WorkspaceEntity`
  payload for that library entry
- the library sheet now loads listing values first, then fetches the payload on
  demand when the user opens that saved workspace

The old `WorkspaceSnapshotEntity` graph is gone from the active codebase.
The runtime model no longer carries a compatibility bridge for older databases;
the only persistence model we build on now is the payload-plus-placement store.

## Next Model Direction

The next persistence pass should simplify the product model further.

The intended direction is:

- keep Core Data as the durable source of truth for windows, workspaces,
  library items, and reopenable history
- use `SceneStorage` only for lightweight per-window presentation details that
  are pleasant to restore but are not the durable model itself
- use `AppStorage` and `UserDefaults` for settings and small preference values
  rather than for reopenable workspace or window data
- give each workspace one stable durable identity instead of splitting live and
  library identity into separate long-lived concepts
- evolve the library into one repository surface that can list both saved
  workspaces and saved windows without pretending they are the same payload type

This section is the preferred architectural direction, even where the current
code has not finished landing it yet.

### Durable ownership by storage surface

The intended storage split is:

- Core Data owns:
  - live workspaces
  - inactive workspaces associated with a window
  - saved library entries
  - saved windows
  - per-window selection and other reopenable window state
  - any durable reopen, recency, or archive metadata
- `SceneStorage` owns:
  - lightweight scene presentation details
  - transient selection or presentation hints that are safe to lose
  - temporary state that helps SwiftUI restore a scene smoothly but is not the
    model
- `AppStorage` and `UserDefaults` own:
  - user preferences
  - app-wide feature toggles
  - small launch and behavior settings such as restore-on-launch or background
    save interval

That split follows SwiftUI's documented intent more closely than asking
`SceneStorage` or `UserDefaults` to carry the real window or workspace model.

### Stable workspace identity

The current code now uses one durable workspace identity across the live window
model and the saved-workspace library:

- `WorkspaceID` is the durable identity
- library save and reopen operate on that same workspace identity
- placements, not alternate identifiers, describe whether that workspace is
  live, recent, or in the library

The preferred model is:

- one stable durable workspace identity
- one current payload for that identity
- zero or more placements that say where that workspace currently appears
- optional later revision history for older saved payloads of that same
  workspace identity

Under that model:

- saving a workspace updates the same durable workspace entry
- closing and later reopening a workspace continues the same durable identity
- the library is not a second identity namespace for the same conceptual
  workspace
- explicit revision retention, if added later, is history for one workspace
  identity rather than a replacement identity

In practical terms, the app should stop treating "live workspace" and "saved
workspace" as separate long-lived things. They are one workspace with different
placements and persistence states.

### One library surface, two item kinds

The library should become one app-wide repository surface, but it should do
that without flattening windows and workspaces into one payload type.

The preferred model is:

- one library UI surface
- one shared listing model for library rows
- two payload kinds behind that listing model:
  - saved workspace items
  - saved window items

That means the library row model should grow a kind field, something like:

```swift
enum LibraryItemKind: String, Codable, Hashable {
    case workspace
    case window
}
```

The shared listing surface can carry:

- stable library item identity
- item kind
- title
- preview text
- updated date
- last active or last opened date
- pin state
- lightweight count metadata such as pane or workspace count

But the underlying payloads should stay distinct:

- a workspace payload is one workspace tree plus its pane and session snapshots
- a window payload is one ordered set of workspace references plus per-window
  state such as selected workspace and window-specific restore metadata

This keeps the library unified for the user without muddying the persistence
model.

### Hide currently live workspaces from the library

The preferred product rule is:

- a workspace that is currently open live in any window should not appear as an
  openable library item

Why:

- opening the same workspace again would create a forked live copy
- those forks would immediately drift unless the app also grows a much more
  complex merge or multi-open ownership model
- the current product direction does not want that complexity

So the library query should eventually:

- include saved workspace entries that are not currently live
- include saved window entries
- exclude workspace entries whose durable identity currently has a `.live`
  placement

If the UI later needs to tell the user that a workspace already exists and is
open somewhere, that should be modeled as an activation path, not as "open a
second copy from the library."

### Replace the in-memory recent-close stack with durable recency

This is now the active implementation direction.

The simpler target model is:

- closing a workspace always writes its durable state to disk
- the workspace remains associated with its owning window identity while it is
  part of that window's reopenable history
- recency is derived from durable timestamps such as `lastActiveAt` rather than
  from a separate in-memory LIFO stack

Under that model, "recently closed in this window" means:

- workspaces associated with this window identity
- not currently `.live`
- sorted by most recent `lastActiveAt`

That means `Undo Close Workspace` or `Open Recent Workspace` can be implemented
as:

1. query durable workspaces associated with the active window identity
2. exclude any workspace that is currently live
3. sort by latest durable activity timestamp
4. reopen the top result into the active window

That is simpler than maintaining:

- a live array
- an in-memory recent-close stack
- a mirrored recent-close placement list
- separate stack bookkeeping rules

The app may still want a small in-memory cache for performance, but the product
model should be "durable recency derived from disk," not "an in-memory stack
that happens to get persisted too."

## Concrete Target Schema

This section records the preferred concrete schema target for the next
implementation pass.

The important simplification is:

- keep one durable workspace identity
- keep one durable window identity
- keep placements and library entries as representation metadata
- stop making "saved copy" versus "live copy" the primary identity boundary

### 1. Workspace record

Preferred role:

- the durable identity and current payload for one workspace

Preferred shape:

```swift
WorkspaceEntity
- id: UUID
- title: String
- createdAt: Date
- updatedAt: Date
- lastActiveAt: Date
- notes: String?
- previewText: String?
- searchText: String?
- isArchived: Bool
- rootNode: PaneNodeEntity?
- sessionSnapshots: Set<PaneSessionSnapshotEntity>
```

Important notes:

- `id` is the one stable durable workspace identity
- `lastActiveAt` is the timestamp used for recency queries
- `isArchived` is optional but useful if the app wants a durable "kept for
  later but not currently live" concept without inventing a second payload
  identity
- this record remains the owner of the workspace tree and session snapshot
  payload

Explicitly not part of this record:

- whether the workspace is currently live in a specific window
- sidebar ordering inside one window
- whether the workspace is shown in the library
- whether the workspace is the newest reopen candidate for a specific window

Those are representation or query concerns, not payload-identity concerns.

### 2. Workspace placement record

Preferred role:

- represent that a workspace currently appears in a specific surface

Preferred shape:

```swift
WorkspacePlacementEntity
- id: UUID
- workspaceID: UUID
- role: String
- windowID: UUID?
- sortOrder: Int64
- createdAt: Date
- updatedAt: Date
- title: String
- previewText: String?
- searchText: String?
- paneCount: Int64
```

Preferred enum:

```swift
enum WorkspacePlacementRole: String, Codable, Hashable {
    case live
    case windowRecent = "recent"
    case library
}
```

Important direction:

- long term, `WorkspacePlacementEntity` should only model current appearance
- recent-close behavior should be derived from durable timestamps and
  workspace-owned window association instead of a dedicated recent placement
  role
- library representation should also move off the generic placement role and
  into an explicit library-entry model, because library membership is not just
  another transient appearance of the same shape as a live sidebar row

That means the preferred end state is:

- `WorkspacePlacementEntity` for current live placement only
- explicit library-entry entities for repository browsing
- durable recency derived from `WorkspaceEntity.lastActiveAt` plus window
  association, not from `.windowRecent`

### 3. Window record

Preferred role:

- the durable identity and reopenable state for one workspace window

Preferred shape:

```swift
WorkspaceWindowEntity
- id: UUID
- createdAt: Date
- updatedAt: Date
- lastActiveAt: Date
- selectedWorkspaceID: UUID?
- title: String?
- isOpen: Bool
```

Important notes:

- this replaces the split between `WorkspaceSceneIdentity` plus
  `WorkspaceWindowStateEntity` plus `UserDefaults` launch-restore bookkeeping
- `id` should align with `WorkspaceSceneIdentity.windowID`
- `isOpen` is the durable source for launch restore and closed-window reopening
- `lastActiveAt` supports "Undo Close Window" or "reopen last closed window"
  without needing a separate in-memory stack as the source of truth

### 4. Window membership record

Preferred role:

- associate workspaces with a specific window, including current order

Preferred shape:

```swift
WindowWorkspaceMembershipEntity
- id: UUID
- windowID: UUID
- workspaceID: UUID
- sortOrder: Int64
- createdAt: Date
- updatedAt: Date
```

Why this record exists:

- a workspace can belong to one window's working set without that relationship
  being identical to "this workspace is live right now in the sidebar"
- a window may want to remember workspace association even after a workspace is
  closed from the live set
- the membership record gives the app a durable answer to "which workspaces
  belong to this window's history?"

This record is what makes the durable recency query simple:

- fetch workspaces associated with the active window
- exclude those that currently have a `.live` placement
- sort by `lastActiveAt`

### 5. Library item record

Preferred role:

- one stable repository row in the library UI

Preferred shape:

```swift
LibraryItemEntity
- id: UUID
- kind: String
- workspaceID: UUID?
- windowID: UUID?
- createdAt: Date
- updatedAt: Date
- lastOpenedAt: Date?
- isPinned: Bool
- title: String
- previewText: String?
- searchText: String?
- itemCount: Int64
```

Preferred enum:

```swift
enum LibraryItemKind: String, Codable, Hashable {
    case workspace
    case window
}
```

Important rules:

- exactly one of `workspaceID` or `windowID` should be set
- workspace library items point at one durable workspace identity
- window library items point at one durable window identity or saved window
  payload identity, depending on the final reopen strategy
- currently live workspaces should be excluded from the library query even if a
  `LibraryItemEntity` exists for them

### 6. Optional saved-revision record

Preferred role:

- older retained snapshots for history, if and when the app wants them

Preferred shape:

```swift
WorkspaceRevisionEntity
- id: UUID
- workspaceID: UUID
- createdAt: Date
- title: String
- notes: String?
- previewText: String?
- rootNode: PaneNodeEntity?
- sessionSnapshots: Set<PaneSessionSnapshotEntity>
```

This is explicitly follow-through work, not required to land the identity and
library simplification first.

## Concrete Query Model

The next code pass should be able to answer the app's key questions with a
small set of durable queries.

### Query: restore one window

Inputs:

- `windowID`

Fetch:

1. `WorkspaceWindowEntity` by `windowID`
2. `WindowWorkspaceMembershipEntity` rows for that window, ordered by
   `sortOrder`
3. `WorkspacePlacementEntity` rows with `.live` for that window
4. `WorkspaceEntity` payloads referenced by those rows

Result:

- one ordered live workspace array
- one durable selected workspace ID
- one restored window model

### Query: reopen most recent inactive workspace for this window

Inputs:

- `windowID`

Fetch:

1. `WindowWorkspaceMembershipEntity` rows for that window
2. join to `WorkspaceEntity`
3. exclude workspace IDs that currently have a `.live` placement anywhere
4. sort by `WorkspaceEntity.lastActiveAt` descending
5. take the first row

Result:

- the single best durable reopen candidate for `Undo Close Workspace` or
  `Open Recent Workspace`

### Query: list library items

Inputs:

- optional search text

Fetch:

1. `LibraryItemEntity` rows, ordered by pin and recency
2. if filtering workspace items, exclude rows whose `workspaceID` currently has
   a `.live` placement
3. if searching, filter on `searchText`

Result:

- one unified library list containing workspace and window items

### Query: reopen a library workspace item

Inputs:

- `LibraryItemEntity.id`

Fetch:

1. fetch the library item
2. resolve its `workspaceID`
3. if that workspace already has a `.live` placement, activate the existing
   window and workspace rather than opening a second copy
4. otherwise attach it to the target window through membership plus a `.live`
   placement

Result:

- one reopened durable workspace identity, not a forked copy

### Query: reopen a library window item

Inputs:

- `LibraryItemEntity.id`

Fetch:

1. fetch the library item
2. resolve its `windowID`
3. reopen or reconstruct that durable window record
4. restore its memberships, selected workspace, and live placements

Result:

- one reopened window with its durable workspace set

## Concrete API Plan

The persistence controller should grow toward a smaller number of clearer
durable operations.

### Window-oriented API

Preferred surface:

```swift
func loadWindow(id: UUID) -> PersistedWindow?
func saveWindowState(_ input: PersistedWindowStateInput)
func listRestorableWindows() -> [PersistedWindowListing]
func markWindowOpen(_ id: UUID)
func markWindowClosed(_ id: UUID)
func mostRecentlyClosedWindow() -> PersistedWindowListing?
```

Purpose:

- one place to answer launch restore and undo-close-window
- stop splitting these questions across Core Data and `UserDefaults`

### Workspace-oriented API

Preferred surface:

```swift
func loadWorkspace(id: UUID) -> Workspace?
func saveWorkspace(_ input: PersistedWorkspaceInput)
func markWorkspaceActive(_ id: UUID, in windowID: UUID)
func markWorkspaceInactive(_ id: UUID, in windowID: UUID)
func mostRecentInactiveWorkspace(in windowID: UUID) -> PersistedWorkspaceListing?
```

Purpose:

- one stable identity surface for live, inactive, and saved behavior
- explicit durable recency updates instead of stack mutation as the primary
  model

### Library-oriented API

Preferred surface:

```swift
func listLibraryItems(matching query: String?) -> [LibraryItemListing]
func saveWorkspaceToLibrary(_ workspaceID: UUID) -> LibraryItemListing?
func saveWindowToLibrary(_ windowID: UUID) -> LibraryItemListing?
func openLibraryWorkspaceItem(_ id: UUID, in targetWindowID: UUID) -> UUID?
func openLibraryWindowItem(_ id: UUID) -> UUID?
func deleteLibraryItem(_ id: UUID) -> Bool
```

Purpose:

- one library API family
- one shared listing model
- separate open behavior by item kind

## Migration Plan

The next implementation pass should land in ordered slices instead of trying to
replace every persistence surface at once.

### Slice 1. Stabilize workspace identity

Goals:

- make one durable workspace identity primary
- stop treating library save as the creation of a second long-lived identity

Likely work:

- remove the remaining compatibility seams from the earlier split-identity
  model
- migrate current library references onto the durable workspace identity
- update save/open/delete codepaths to operate on that identity

### Slice 2. Introduce durable window records

Goals:

- move reopenable window registry state into Core Data
- stop relying on `UserDefaults` as the durable source for launch-restore
  window IDs

Likely work:

- add `WorkspaceWindowEntity`
- migrate `WorkspaceWindowStateEntity` into it
- migrate launch-restore window bookkeeping into Core Data queries

### Slice 3. Introduce window membership plus durable recency

Goals:

- stop relying on `WorkspaceStore.recentlyClosedWorkspaces` as the source of
  truth
- answer reopen queries from disk

Likely work:

- add `WindowWorkspaceMembershipEntity`
- add `lastActiveAt` to durable workspace records
- replace `.windowRecent`-driven reopen logic with membership plus recency queries

### Slice 4. Split library entries out cleanly

Goals:

- stop treating library membership as just another generic placement role
- prepare one combined library that can hold both workspaces and windows

Likely work:

- add `LibraryItemEntity`
- migrate current `.library` rows into explicit library items
- add item kind plus unified listing queries

### Slice 5. Add saved windows to the library

Goals:

- let closed windows appear in the library
- reopen them through the same combined library browser

Likely work:

- save a window record and its memberships as one library item
- implement open/delete/list behavior for `LibraryItemKind.window`

## Command And UI Implications

The data-model simplification changes some behavior details even if the visible
commands stay familiar.

### Undo Close Workspace

The label can stay the same, but the implementation should become:

- "reopen the most recently active inactive workspace associated with this
  window"

That is a clearer durable rule than "pop the top of an in-memory stack."

### Open Recent Workspace

If the app later wants an explicit recent-open command, it should use the same
query as undo:

- filter by window membership
- exclude currently live workspaces
- sort by `lastActiveAt`

### Open Workspace

The library browser should eventually:

- show both workspace and window items
- hide workspaces that are already live
- activate an already-live workspace instead of cloning it if a direct reopen
  path is triggered by ID

### Close Workspace

Closing should become:

- remove the current live placement
- update durable activity timestamps
- keep the workspace available for window-local recency queries
- optionally ensure the workspace has a library item if the archive setting is
  enabled

That is less stateful and easier to reason about than "close mutates a live
array, a stack, and possibly a library copy."

## Core Simplification

The durable model is now:

- one canonical workspace payload record
- one placement record that says where that payload currently appears

This is the main simplification that landed in the current pass.

### Why not put `role` and `windowID` directly on the workspace record?

Because those are not really attributes of the workspace payload itself.

They are attributes of how that payload is currently being used.

Examples:

- the same saved workspace can live in the library and also be open in a window
- the same payload could later be opened in multiple windows
- a library-specific property like pinning does not necessarily belong to the
  workspace contents themselves

If we put `.live`, `.windowRecent`, `.library`, and `windowID` directly on the
workspace entity, the model starts assuming one payload can only occupy one
role and one restored window placement at a time.

That is the wrong ownership boundary for a product that intentionally supports
multiple independent workspace windows with their own persisted state.

## Durable Model

### A. Workspace payload entity

Current role:

- "What concrete workspace state revision is this?"

This entity stores one durable workspace payload.

That payload might be:

- a live working copy currently open in a window
- the current saved payload for a library entry
- a future historical saved revision once explicit revision retention is added

Current shape:

```swift
WorkspaceEntity
- id: UUID
- title: String
- createdAt: Date
- updatedAt: Date
- notes: String?
- previewText: String?
- searchText: String?
- rootNode: PaneNodeEntity?
- sessionSnapshots: Set<PaneSessionSnapshotEntity>
```

This entity should own:

- the pane tree
- per-pane launch configuration snapshots
- transcript and preview metadata
- searchable text derived from the workspace contents

This entity should not own:

- which window currently shows it
- whether it is live, recent, or in the library
- ordering in a sidebar or recent list
- whether it is the current saved revision for a library entry

### B. Workspace placement entity

Current role:

- "Where is this workspace currently represented?"

Current shape:

```swift
WorkspacePlacementEntity
- id: UUID
- role: String
- windowID: UUID?
- sortOrder: Int64
- restoreSortOrder: Int64
- createdAt: Date
- updatedAt: Date
- lastOpenedAt: Date?
- isPinned: Bool
- title: String
- previewText: String?
- searchText: String?
- paneCount: Int64
- workspace: WorkspaceEntity
```

The `role` field is the thing that wants enum semantics:

```swift
enum WorkspacePlacementRole: String {
    case live
    case windowRecent = "recent"
    case library
}
```

Interpretation:

- `.live`
  - this workspace is part of one specific window's current sidebar working set
- `.windowRecent`
  - this workspace is part of one specific window's recent-close stack
- `.library`
  - this placement is the stable saved library entry and points at that entry's
    current saved payload revision

`windowID` rules:

- required for `.live`
- required for `.windowRecent`
- `nil` for `.library`

This separation lets one workspace payload be referenced by:

- one stable library placement as the current saved payload for a library entry
- zero or more live placements
- zero or more window-recent placements

without changing the payload itself.

## Node And Session Entities

The current node and pane-session snapshot entities are now attached to the
payload record instead of living in a parallel saved-workspace payload graph.

Current direction:

```swift
PaneNodeEntity
- id: UUID
- kind: String
- sessionSnapshotID: UUID?
- axis: String?
- fraction: Double
- workspace: WorkspaceEntity?
- firstChild: PanePayloadNodeEntity?
- secondChild: PanePayloadNodeEntity?

PaneSessionSnapshotEntity
- id: UUID
- executable: String
- argumentsData: Data?
- environmentData: Data?
- currentDirectory: String?
- title: String
- transcript: String?
- transcriptByteCount: Int64
- transcriptLineCount: Int64
- previewText: String?
- workspace: WorkspaceEntity?
```

The important point is that the app no longer has one payload shape for "live
workspaces" and another payload shape for "saved workspaces."

## Scene Model

With the durable model above, each workspace window scene restores from a
small data-driven scene identity plus lightweight UI state.

### Window identity

The Apple docs do not appear to expose a plain built-in "window instance ID"
from an ordinary `WindowGroup` scene.

The cleanest documented identity surface SwiftUI does give us is a
data-presenting `WindowGroup`, where the presented data value is automatically
persisted and restored as part of scene restoration.

That makes the implemented direction:

- define our own small `WorkspaceSceneIdentity` value
- make it `Codable` and `Hashable`
- use a data-driven `WindowGroup` so SwiftUI restores that value for each window

Current shape:

```swift
struct WorkspaceSceneIdentity: Codable, Hashable {
    var windowID: UUID
}
```

Current scene declaration shape:

```swift
WindowGroup(id: "main-window", for: WorkspaceSceneIdentity.self, defaultValue: {
    WorkspaceSceneIdentity(windowID: UUID())
}) { sceneIdentity in
    WorkspaceWindowSceneView(sceneIdentity: sceneIdentity.wrappedValue)
}
```

Why this is preferred over inventing a second ad hoc persistence path:

- SwiftUI explicitly documents that the presented data binding for a
  data-driven `WindowGroup` is persisted and restored
- the value is already scoped to one window instance
- the identity stays lightweight and scene-oriented
- `SceneStorage` can remain focused on small UI state rather than carrying a
  duplicate copy of the scene identity

Current recommendation remains:

- use the data value of a data-driven `WindowGroup` as the durable scene
  identity
- let SwiftUI persist and restore that value for each window instance
- do not create a second ad hoc scene-identity persistence path
- do not mirror that identity into `SceneStorage`
- continue using `SceneStorage` only for lightweight per-window UI state

That gives us a durable, documented per-window identity without needing a plain
SwiftUI "window identifier" API that does not seem to exist in the current
surface, and without building a second persistence layer around that identity
ourselves. This is the intended foundation for multiple concurrently restored
workspace windows, not a stopgap for a single-window app.

### What `SceneStorage` should hold

`SceneStorage` should remain lightweight.

Good candidates:

- selected workspace ID
- sidebar visibility
- inspector visibility

Potentially:

- a small scene-restoration version token if needed later

Bad candidates:

- the live workspace list itself
- pane trees
- transcripts
- recent-close payloads

### Restore flow

On scene restore:

1. read the restored scene identity from the data-driven `WindowGroup`
2. read lightweight UI state from `SceneStorage`
3. fetch `.live` placements for that scene identity
4. query workspace-owned recent-close metadata for that scene identity
5. restore the scene-local live workspace list and recent-close state from the
   live placements plus the recent metadata query
6. lazily fetch `.library` placements when the user opens the library, or
   prewarm them later on a lower-priority path if desired

That gives us:

- fast per-window restore for what the scene actually needs
- no need to load the whole library before the main shell becomes usable
- a much cleaner boundary between scene state and app-wide repository state

## Useful SwiftUI Lifecycle Hooks

The restore model above wants a small set of documented SwiftUI lifecycle hooks.

Relevant Apple docs:

- `View.onAppear(perform:)`
  - <https://developer.apple.com/documentation/swiftui/view/onappear(perform:)>
- `View.onDisappear(perform:)`
  - <https://developer.apple.com/documentation/swiftui/view/ondisappear(perform:)>
- `View.onChange(of:initial:_:)`
  - <https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)>
- `View.task(id:name:priority:file:line:_:)`
  - <https://developer.apple.com/documentation/swiftui/view/task(id:name:priority:file:line:_:)>
- `Scene.onChange(of:initial:_:)`
  - <https://developer.apple.com/documentation/swiftui/scene/onchange(of:initial:_:)>
- `Scene.restorationBehavior(_:)`
  - <https://developer.apple.com/documentation/swiftui/scene/restorationbehavior(_:)> 
- `Restoring your app's state with SwiftUI`
  - <https://developer.apple.com/documentation/swiftui/restoring-your-app-s-state-with-swiftui>
- `Restoring your app's state with SwiftUI: Use scene storage`
  - <https://developer.apple.com/documentation/swiftui/restoring-your-app-s-state-with-swiftui#Use-scene-storage>
- `Migrating to the SwiftUI life cycle: Monitor life cycle changes`
  - <https://developer.apple.com/documentation/swiftui/migrating-to-the-swiftui-life-cycle#Monitor-life-cycle-changes>

### Scene-level hooks

- `@Environment(\\.scenePhase)`
  - use for scene activation and backgrounding policy
- `.onChange(of: scenePhase)`
  - use for scene-level persistence triggers, cleanup, or low-priority prewarm
    policy
- `@Environment(\\.appearsActive)`
  - use for frontmost-window activation changes that are narrower than the
    coarse scene phase
- `.restorationBehavior(_:)`
  - use when we need to make restoration participation explicit for a scene

### View-level hooks

- `.task`
  - good for idempotent async restore work when a scene view becomes active
- `.task(id:)`
  - good when restore or fetch work needs to be rerun for a specific identity or
    query key
- `.onAppear`
  - good for lightweight appearance work, but not a great place for fragile or
    once-only restore logic because views can appear multiple times
- `.onDisappear`
  - good for local teardown or a best-effort final flush when a scene window is
    closed, but not something to treat as the only guaranteed persistence hook
- `.onChange(of:)`
  - good for writing lightweight scene state like selected workspace ID,
    sidebar visibility, and inspector visibility

Practical guidance:

- use the data-driven `WindowGroup` binding as the durable window identity
- use `SceneStorage` for lightweight UI restoration keys
- use `.task` or `.task(id:)` for the actual scene rehydration path
- use `.task(id:)` for per-window periodic background persistence when the
  interval is user-configurable
- use `.onChange(of: scenePhase)` for save, flush, or prewarm decisions that
  belong to the whole scene
- use `appearsActive` when window-to-window activation changes matter more than
  coarse app or scene activation
- do not rely on `onAppear` alone as if it were a one-time scene constructor

## How The Three Buckets Should Behave

### Live

`live` means:

- part of one window's current sidebar working set
- ordered within that window
- restorable for that window

This is scene-local runtime state with durable backing.

### Recent

`recent` means:

- not currently open in that window
- still attached to one window's undo-like recent-close history
- ordered as a stack, newest first or oldest first depending on persistence
  query strategy

This is scene-local state with optional durable backing.

### Library

`library` means:

- globally saved and intentionally reusable
- not tied to one specific window
- queryable by title, preview text, and content-derived search text

This is the app-wide repository view.

## Sidebar And Library Query Guidance

### Sidebar list

Recommendation:

- do not move the live sidebar list to view-level `@FetchRequest`

Why:

- the sidebar is rendering a scene-local working set, not a global repository
  surface
- the scene already owns selection, modal presentation, and focus
- pass two is trying to make live workspaces more scene-local, not less

The current shape is:

- a scene-local working model
- hydrated from `.live` placements for the current scene identity
- then rendered through ordinary SwiftUI state and bindings

### Saved workspace library

Recommendation:

- the library list and library detail or form surfaces should be driven by
  lightweight listing values derived from library entries and their associated
  placements
- `FetchRequest` or `SectionedFetchRequest` is still much more plausible here
  than it is for the live sidebar if the library ever wants to move closer to
  Core Data-backed view queries

Why:

- the library is a true Core Data-backed repository surface
- it is app-wide, not scene-local
- the sheet is already acting like a repository browser rather than a local
  working-state editor
- the same library surface should eventually be able to present both saved
  workspaces and saved windows

The current implementation still uses `WorkspacePersistenceController` plus
lightweight listing values rather than a direct `FetchRequest`, which is fine
for now.

## Placement Records As Listing Metadata

Yes, the placement records should probably carry enough lightweight metadata to
populate the sidebar and library listings before the app hydrates a full
workspace payload.

That is a good simplification, with one caveat:

- the placement record can be the common lightweight listing surface
- the payload record should still remain the canonical source for the full pane
  tree and per-pane session data that we fetch on demand when the user opens or
  inspects a workspace deeply

That means the placement record can safely denormalize display metadata such as:

- title
- paneCount
- previewText
- updatedAt
- lastOpenedAt
- isPinned
- sortOrder

Potentially:

- a small status summary if live and recent rows later need one

Why this is worth doing:

- the sidebar can load quickly from `.live` placements without decoding full
  pane trees immediately
- the library can load quickly from `.library` placements without hydrating the
  full saved payload for every row
- the recent-close stack can render from durable window-associated workspace
  metadata using the same payload revision shape
- the library view can stay responsive even when full payload fetches are
  deferred until the user opens a workspace

That gives us one common lightweight listing model, likely something like:

```swift
struct WorkspacePlacementListing: Identifiable, Hashable {
    var placementID: UUID
    var payloadID: UUID
    var role: WorkspacePlacementRole
    var windowID: UUID?
    var title: String
    var paneCount: Int
    var previewText: String?
    var updatedAt: Date
    var lastOpenedAt: Date?
    var isPinned: Bool
    var sortOrder: Int
}
```

Current recommendation:

- yes, make placements the common small listing surface for live, window-recent, and
  library queries
- no, do not make placements the only durable entity
- keep the full workspace payload separate so listing speed and payload
  complexity do not get tangled together
- fill the library list and library form surfaces from listing values first
- fetch the full saved payload revision only when the user opens or explicitly
  drills into that saved workspace

## Lifecycle Operations

### Create workspace

1. create a new `WorkspaceRecordEntity`
2. create a `.live` placement for the active scene identity
3. append it to that window's sort order

### Close workspace

Current implementation:

1. remove the `.live` placement for the active scene identity
2. optionally update the workspace's durable recent-window metadata for that
   same scene identity
3. optionally create or update a `.library` placement if auto-save-on-close is
   enabled

Preferred follow-through:

1. remove the `.live` placement for the active scene identity
2. update the workspace's durable `lastActiveAt`
3. keep the workspace associated with that window identity for durable reopen
   history
4. if the close path is also an archive path, ensure the workspace has a stable
   library entry instead of creating a forked saved copy

### Undo close

Current implementation:

1. fetch the newest durable recent workspace associated with the active window
2. clear that recent-window association after restore
3. create a `.live` placement at the restored sidebar index

Preferred follow-through:

1. fetch durable workspaces associated with the active window identity
2. exclude any workspace that is currently live
3. sort by descending `lastActiveAt`
4. promote the top result back into a `.live` placement at the intended
   sidebar position

### Save to library

Current implementation:

1. treat the live workspace as the current working copy
2. clone the live payload into a new saved payload
3. keep one stable `.library` placement for the saved workspace entry
4. update that library placement so it points at the newest saved payload
5. refresh the lightweight library listing metadata from that newest saved
   payload

Current status:

- steps 1 through 5 are implemented
- older saved payload revisions are not yet retained as explicit history

Preferred follow-through:

1. treat the current durable workspace identity as the thing being saved
2. update that workspace's current persisted payload in place
3. ensure there is one stable library entry for that same workspace identity
4. refresh the shared library listing metadata from that persisted workspace
5. avoid creating a second durable identity just because the workspace entered
   or updated in the library

### Open from library

Current implementation:

- fetch the saved payload revision currently referenced by the stable `.library`
  placement
- if the requested workspace is already live in the current store, reuse that
  same durable workspace identity instead of duplicating it
- if the workspace is not already live, reactivate that durable workspace
  identity into a `.live` placement in the active window

Current recommendation:

- library entries are durable saved workspace entries
- opening from the library should reactivate that same workspace identity rather
  than cloning a forked working copy
- currently live workspaces should be hidden from the library query so the user
  does not take a second-open path by mistake

Preferred follow-through:

- for workspace items:
  - if the workspace is already live anywhere, do not offer it as an openable
    library row
  - if it is not live, reactivate that durable workspace identity into a `.live`
    placement instead of creating a forked working copy
- for window items:
  - reopen the saved window payload under the intended window identity or saved
    window entry identity
  - restore that window's workspace set and durable selected workspace state

## Core Data History Versus App Revision History

Core Data is the storage substrate for this design, but the saved-workspace
revision model is ours.

What the long-term product model still wants is:

- one stable library entry
- one current saved revision for that entry
- zero or more older saved revisions retained as history

Core Data stores that model for us. It does not define the product behavior on
its own.

### Undo and rollback

`NSManagedObjectContext` provides:

- `undoManager`
- `undo()`
- `redo()`
- `rollback()`

These are for context-local editing history and uncommitted change reversal.
They are useful for in-memory editing workflows, but they are not a durable
saved-workspace history on disk.

### Persistent history tracking

Core Data also provides persistent history tracking through:

- `NSPersistentHistoryTrackingKey`
- `NSPersistentHistoryChangeRequest`
- `NSPersistentHistoryTransaction`

That is useful for:

- consuming store transactions
- syncing changes across contexts or processes
- inspecting which transactions changed which objects

It is not the same thing as an app-defined sequence of saved workspace
revisions. Persistent history is store transaction history, not a stable
user-facing version history for one library item.

### Current recommendation

Keep modeling saved-workspace history explicitly as part of the app's Core Data
schema rather than pretending Core Data gives us that product behavior for
free.

The likely shape is:

- one stable library placement per saved workspace entry
- one current saved payload revision that placement points at
- zero or more older saved payload revisions retained as history
- lightweight listing metadata denormalized onto the stable library placement so
  the library UI stays fast

## Current Status

The current persistence model does the following:

1. uses `WorkspaceEntity` as the canonical payload entity
2. uses `WorkspacePlacementEntity` to describe whether that payload is
   `.live` or `.library`, while recent-close state lives on the workspace
   entity itself
3. restores live workspaces from scene-identity-scoped placements and recently
   closed workspaces from durable workspace-owned window metadata
4. restores saved library entries from `.library` placements
5. keeps scene-local UI restoration in `@SceneStorage` instead of mixing that
   state into the persistence store
6. intentionally allows different workspace windows to persist and restore
   independent live and recently closed state keyed by `WorkspaceSceneIdentity`
7. debounces mutation-triggered scene saves by 200 ms
8. also flushes scene persistence immediately when a window becomes active or
   inactive, when a scene becomes inactive or backgrounds, when the scene view
   disappears, and when the app is about to terminate
9. runs a per-window periodic background save task on a user-configurable
   interval that defaults to five minutes

## Recommended Next Follow-Through

The persistence foundation is in place, but the next design pass should
continue simplifying the model rather than adding new side paths.

The preferred follow-through order is:

1. unify workspace identity so one workspace has one stable durable identity
   across live, inactive, and library states
2. replace the in-memory recent-close stack with durable recency derived from
   disk by window identity plus `lastActiveAt`
3. move any remaining reopenable window-registry state from `UserDefaults`
   into Core Data so windows, workspaces, and library items all share one
   durable model
4. introduce a unified library listing surface that can hold both workspace and
   window items while preserving separate payload types underneath
5. decide the exact saved-revision retention policy for later history support
6. decide whether library history ever needs user-facing browse, restore, or
   diff surfaces

That order keeps the next work converging toward:

- one durable storage authority
- one stable identity model for workspaces
- one library surface
- fewer duplicated in-memory and on-disk representations

## Manual Persistence Checklist

Use this checklist when validating real window and app lifecycle persistence:

1. Window close flush
   Open a workspace window, make a visible change like renaming a workspace or splitting panes, then close that window within a second or two. Reopen the same window and confirm the latest live workspaces, pane layout, and recent-close state restored instead of older state.
2. App quit flush
   Make a fresh visible change in one or more windows, then quit immediately with `Command-Q`. Relaunch and confirm each restored window kept its latest workspace selection, pane tree, and recent-close state.
3. App deactivate flush
   Make a change, then immediately `Command-Tab` away to another app. Come back later and confirm the latest workspace state was persisted even if you left quickly after editing.
4. Window activation change flush
   Open two workspace windows with clearly different live state. Change something in window A, activate window B, then reactivate A. Confirm both windows still have their own correct latest state and that switching frontmost windows does not cross-contaminate persistence.
5. Background interval flush
   Set the background save interval to one minute in Settings, make a change, leave the window open without further edits, and wait a little over a minute. Then close or force-quit later and relaunch to confirm the periodic flush captured the idle state.
6. Settings persistence
   Change the background save interval, quit, relaunch, and confirm Settings still shows the same interval. Repeat once with another value to confirm normalization and storage are stable.
7. Recent-close restoration
   With `Keep recently closed workspaces` enabled, close a workspace, switch windows or quit soon after, then relaunch. Confirm the recently closed stack is still window-local and restores with the correct window.
8. Auto-save closed workspace interaction
   With `Auto-save closed workspaces` enabled, close a workspace and then immediately close the window or quit the app. Relaunch and confirm both the live-window persistence and saved-workspace-library write happened as expected.
9. Modal edge cases during lifecycle changes
   Leave a rename sheet, delete alert, or saved-workspace library open, then deactivate or reactivate the app or switch windows. Confirm persistence still feels correct and does not restore into obviously stale modal state.
10. Logging spot-check
   While doing the pass above, watch the `persistence` logs and confirm the save reason names match the action you just performed, without obvious duplicate-flush spam.

## Window Reopen Restoration

The window-restoration story now also has a narrow scene-owned reopen path.

Current behavior:

- each workspace window is still identified by one durable
  `WorkspaceSceneIdentity`
- `WorkspaceWindowSceneView` marks that identity as open when the scene appears
- when the scene disappears, it records that identity in the
  `WorkspaceWindowRestorationController` recently closed stack before the final
  scene-state flush
- `WorkspaceWindowSceneCommands` exposes a dedicated `Undo Close Window`
  command that pops the newest closed identity and calls `openWindow(value:)`
  with that same `WorkspaceSceneIdentity`

That matters because reopening by the same identity is what lets SwiftUI scene
restoration and our Core Data persistence model line up cleanly:

- the reopened window gets the same per-window live and recently closed
  workspace state keyed by `sceneIdentity.windowID`
- the reopened window also regains the same scene-local restoration surfaces
  tied to that scene identity, rather than creating a brand-new unrelated
  window record

This is intentionally different from creating a fresh new window:

- `New gmax Window` creates a new `WorkspaceSceneIdentity`
- `Undo Close Window` reopens the last closed identity so the same window can
  restore
