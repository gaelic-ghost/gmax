/*

This note records the current workspace persistence foundation for the
per-window scene model in gmax, plus the remaining follow-through work.

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

- [`workspace-focus-target-plan.md`](./workspace-focus-target-plan.md)
- [`workspace-focus-implementation-boundary.md`](./workspace-focus-implementation-boundary.md)
- [`workspace-focus-removal-and-redesign-notes.md`](./workspace-focus-removal-and-redesign-notes.md)
- [`swiftterm-surface-investigation.md`](./swiftterm-surface-investigation.md)

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

- `WorkspaceStore.recentlyClosedWorkspaces` is an in-memory LIFO stack
- the stack is restored from `.recent` `WorkspacePlacementEntity` rows for the
  active scene identity
- the runtime stack is still store-local in memory, but it now has durable
  scene-scoped backing

### 3. Library workspaces

- the saved workspace library is now backed by stable `.library`
  `WorkspacePlacementEntity` rows
- those placements carry lightweight listing metadata for library browsing
- each `.library` placement points at the current saved `WorkspaceEntity`
  payload for that library entry
- the library sheet now loads listing values first, then fetches the payload on
  demand when the user opens that saved workspace

The old `WorkspaceSnapshotEntity` graph still exists only as a migration bridge
for older databases. The runtime model no longer uses it as the primary saved
workspace surface.

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

If we put `.live`, `.recent`, `.library`, and `windowID` directly on the
workspace entity, the model starts assuming one payload can only occupy one role
and one window at a time.

That is the wrong ownership boundary.

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
- savedWorkspaceID: UUID?
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
    case recent
    case library
}
```

Interpretation:

- `.live`
  - this workspace is part of one specific window's current sidebar working set
- `.recent`
  - this workspace is part of one specific window's recent-close stack
- `.library`
  - this placement is the stable saved library entry and points at that entry's
    current saved payload revision

`windowID` rules:

- required for `.live`
- required for `.recent`
- `nil` for `.library`

This separation lets one workspace payload be referenced by:

- one stable library placement as the current saved payload for a library entry
- zero or more live placements
- zero or more recent placements

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
WindowGroup(id: "main-shell", for: WorkspaceSceneIdentity.self, defaultValue: {
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
ourselves.

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
4. fetch `.recent` placements for that scene identity
5. restore the scene-local live workspace list and recent-close stack from
   those placement records
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
  - good for local teardown, but not something to treat as a guaranteed final
    persistence callback
- `.onChange(of:)`
  - good for writing lightweight scene state like selected workspace ID,
    sidebar visibility, and inspector visibility

Practical guidance:

- use the data-driven `WindowGroup` binding as the durable window identity
- use `SceneStorage` for lightweight UI restoration keys
- use `.task` or `.task(id:)` for the actual scene rehydration path
- use `.onChange(of: scenePhase)` for save, flush, or prewarm decisions that
  belong to the whole scene
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
  lightweight listing values derived from `.library` placements
- `FetchRequest` or `SectionedFetchRequest` is still much more plausible here
  than it is for the live sidebar if the library ever wants to move closer to
  Core Data-backed view queries

Why:

- the library is a true Core Data-backed repository surface
- it is app-wide, not scene-local
- the sheet is already acting like a repository browser rather than a local
  working-state editor

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
- the recent-close stack can render from `.recent` placements using the same
  listing shape
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

- yes, make placements the common small listing surface for live, recent, and
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

1. remove the `.live` placement for the active scene identity
2. optionally create or update a `.recent` placement for that same scene
   identity
3. optionally create or update a `.library` placement if auto-save-on-close is
   enabled

### Undo close

1. fetch the newest `.recent` placement for the active scene identity
2. remove or demote that recent placement
3. create a `.live` placement at the restored sidebar index

### Save to library

1. treat the live workspace as the current working copy
2. clone the live payload into a new saved payload
3. keep one stable `.library` placement for the saved workspace entry
4. update that library placement so it points at the newest saved payload
5. refresh the lightweight library listing metadata from that newest saved
   payload

Current status:

- steps 1 through 5 are implemented
- older saved payload revisions are not yet retained as explicit history

### Open from library

- fetch the saved payload revision currently referenced by the stable `.library`
  placement
- clone that saved payload revision into a new live workspace payload
- create a `.live` placement for the cloned payload in the active window

Current recommendation:

- library entries are durable saved workspace entries
- opening from the library always creates a new live working copy
- editing the reopened live workspace never mutates the saved library revision
  directly

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

## Migration Status

The compatibility bridge that landed in this pass does the following:

1. introduces the new placement role enum and placement entity
2. treats `WorkspaceEntity` as the canonical payload entity
3. migrates legacy live `WorkspaceEntity` records into `.live` placements
4. migrates legacy `WorkspaceSnapshotEntity` records into payload plus
   `.library` placements
5. restores recent-close state from `.recent` placements
6. updates `WorkspaceStore` and scene restore so the live sidebar hydrates from
   scene-identity-scoped placements rather than from one app-wide live list

The old snapshot entities remain only as a migration bridge and should
eventually become removable once legacy-store support is no longer needed.

## Recommended Next Follow-Through

The persistence foundation is now in place. The next follow-through decisions
are:

1. what exact saved-revision retention policy should back save-over-time
   behavior
2. whether library history needs user-facing browse, restore, or diff surfaces
3. when the legacy snapshot migration bridge can be removed

Everything else can now evolve incrementally without changing the underlying
payload-plus-placement model again.
