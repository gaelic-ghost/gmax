# Basic WebView Pane Options

## Purpose

This note captures the current options for adding a basic browser pane to
`gmax` using Apple's built-in WebKit stack instead of a heavier embedded
Chromium runtime.

The question here is not just "can we show a webpage in a pane?" The real
question is how well a `WKWebView`-backed pane fits the current `gmax` pane,
focus, and persistence model, and what the smallest durable integration cut
would be.

Use this note before implementing any browser-pane prototype.

## Settled Product Decisions

These are now treated as decided for the basic WebView-pane direction:

- browser panes are created intentionally through dedicated split actions, not
  by converting an existing pane back and forth between terminal and browser
  modes
- each browser pane leaf owns one durable `BrowserSessionID`
- new browser panes start blank or on a lightweight start page by default
- the app now exposes a configurable browser home URL in Settings
- browser panes use one shared app-owned persistent WebKit data store
- ordinary `http` and `https` navigation stays inside the pane
- special URL schemes should hand off through the system instead of being
  forced into the pane
- browser inspector metadata should eventually include URL, title, loading
  state, and back-forward availability

On commands, the current intended browser-pane creation surface is:

- `New Browser Pane Right`: `Option-Command-D`
- `New Browser Pane Down`: `Shift-Option-Command-D`
- `Focus Address Bar`: `Command-L` when a browser pane is focused
- `Back`: `Command-[` when a browser pane is focused
- `Forward`: `Command-]` when a browser pane is focused
- `Reload`: `Command-R` when a browser pane is focused

These are additive pane-creation actions. They should not imply a reversible
"switch this pane type" model.

## Current Constraints

The current architecture already has a strong answer for pane layout and pane
focus:

- the workspace tree is recursive and pane-shaped already
- each `PaneLeaf` is independently splittable, closable, and focusable
- the scene owns pane focus, pane commands, and pane geometry
- leaf content is hosted as a pane-sized AppKit-backed surface through SwiftUI

That means a browser pane fits the shell shape well at the layout level.

The harder constraint used to be the leaf payload model. Slice 1 groundwork is
now in place, so `PaneLeaf` is no longer terminal-only:

```swift
enum PaneContent: Hashable, Codable {
    case terminal(TerminalSessionID)
    case browser(BrowserSessionID)
}

struct PaneLeaf: Identifiable, Hashable, Codable {
    var id = PaneID()
    var content: PaneContent = .terminal(TerminalSessionID())
}
```

What is true now:

- the pane tree can already encode terminal versus browser leaf identity
- persistence can already encode and decode browser leaf payloads honestly
- browser panes now have real runtime ownership through
  `BrowserSessionRegistry` and `BrowserPaneControllerStore`
- browser leaves now render through the active `WKWebView` host path instead of
  the earlier unsupported-pane placeholder
- browser session metadata now persists and restores basic pane state including
  title, URL, last committed URL, and loading or failure text
- focused browser panes now expose a lightweight top-center omnibox overlay
  that expands on hover or `Command-L` instead of living in a permanent
  toolbar strip

What is still terminal-specific:

- `TerminalSessionRegistry` remains the terminal-session registry
- `TerminalPaneControllerStore` remains the terminal-controller cache
- `ContentPaneLeafView` is still terminal-only
- browser history-stack persistence is still deferred

So the current shell is no longer lying about leaf content, and it now has a
real browser runtime and rendering path. The remaining work is mostly about the
deeper browser product surface and any richer persistence we choose to add
later.

## Apple Framework Behavior This Plan Relies On

These options rely on four Apple-owned rules:

- `WKWebView` is a native AppKit view for interactive web content, suitable for
  an in-app browser surface.
- `NSViewRepresentable` is the SwiftUI entry point for hosting an AppKit view.
- SwiftUI owns the hosted AppKit view's frame and bounds inside
  `NSViewRepresentable`; the hosted view should not fight SwiftUI's layout.
- `WKWebsiteDataStore` lets the app choose whether browser state is persistent,
  nonpersistent, or profile-like by configuration.

References:

- Apple `WKWebView`:
  <https://developer.apple.com/documentation/webkit/wkwebview>
- Apple `WKNavigationDelegate`:
  <https://developer.apple.com/documentation/webkit/wknavigationdelegate>
- Apple `WKWebsiteDataStore`:
  <https://developer.apple.com/documentation/webkit/wkwebsitedatastore>
- Apple `WKWebViewConfiguration.websiteDataStore`:
  <https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/websitedatastore>
- Apple `NSViewRepresentable`:
  <https://developer.apple.com/documentation/swiftui/nsviewrepresentable>
- Apple `focusable(_:interactions:)`:
  <https://developer.apple.com/documentation/swiftui/view/focusable(_:interactions:)>
- Apple `openURL`:
  <https://developer.apple.com/documentation/swiftui/environmentvalues/openurl>

In plain language:

- WebKit can already give `gmax` a real browser view.
- SwiftUI can already host that view in the same way we host SwiftTerm now.
- The shell does not need a new split-tree or a new window model to make room
  for a browser surface.
- The integration pressure is in the leaf content model, not in the scene
  model.

## Option 1: External Browser Only

This is the smallest possible path:

- keep panes terminal-only
- add actions that open URLs in the default browser with `openURL`
- do not embed a browser surface inside `gmax`

This is easy and low-risk, but it is not really a browser pane feature. It
solves "open this URL" rather than "make the webpage a first-class pane in the
workspace tree."

This is a stopgap, not a durable browser-pane model.

## Option 2: Add A Special-Case WebView Pane Without Generalizing Leaves

This is the fastest embedded-browser path:

- keep `PaneLeaf` terminal-shaped
- special-case certain leaves as browser leaves somewhere outside the leaf type
- add a parallel browser-session map and a parallel host path
- keep persistence and content resolution aware of both the normal terminal path
  and an extra browser exception path

This can work for a quick prototype, but it fits the current system poorly.

Why it is awkward:

- the pane tree would still claim that every leaf is a terminal session
- persistence would need compatibility exceptions instead of a real leaf-content
  model
- `ContentPane` would need branching logic that is not reflected in the
  persisted tree shape
- future mixed-pane commands and inspector state would end up leaning on
  hidden parallel maps instead of the leaf payload itself

This is a conscious stopgap. It could get something on screen quickly, but it
would make the model less honest.

## Option 3: Generalize Leaf Content And Add A Basic WebView Pane

This is the smallest durable path and the current recommended option.

The core change is:

```swift
enum PaneContent: Hashable, Codable {
    case terminal(TerminalSessionID)
    case browser(BrowserSessionID)
}

struct BrowserSessionID: RawRepresentable, Hashable, Codable, Identifiable {
    var rawValue = UUID()
    var id: UUID { rawValue }
}

struct PaneLeaf: Identifiable, Hashable, Codable {
    var id = PaneID()
    var content: PaneContent
}
```

That keeps the existing pane tree, split behavior, focus model, and window
model, while making the leaf payload tell the truth about what kind of surface
the pane actually hosts.

Then the supporting pieces become parallel in a clean way:

- `TerminalSessionRegistry` stays terminal-specific
- add `BrowserSessionRegistry`
- `TerminalPaneControllerStore` stays terminal-specific
- add `BrowserPaneControllerStore`
- `ContentPane` switches on `PaneLeaf.content`
- persistence encodes a leaf content kind plus the matching session identifier

This is a durable building-block change.

It unlocks:

- terminal panes and browser panes in the same split tree
- future pane replacement or duplication without tree-level hacks
- pane-local inspector support for browser metadata
- honest persistence for mixed workspaces

## Recommended Basic Browser Scope

For a first WebKit-backed pass, keep the browser model intentionally small.

Suggested persisted browser session surface:

- `BrowserSessionID`
- current URL
- title
- loading state
- last committed URL
- loading or last-error text

Suggested runtime-only state:

- back/forward availability
- estimated load progress
- transient navigation errors
- WebKit process termination status

What this first pass should not try to persist:

- full page snapshots
- every transient web process detail
- script injection or extension-style features
- forensic browser-session reconstruction

One explicit follow-through target should stay on the table:

- persist the browser back-forward history stack too, if WebKit gives us a
  practical and maintainable way to restore it without turning browser-session
  persistence into a much heavier reconstruction problem

So the first durability contract should be:

- definitely persist last committed URL, title, and loading or error text
- attempt to preserve history stack if that proves practical
- do not block the basic feature on exact browser-session replay

The restore goal should be:

- reopen the pane
- load the last committed URL
- restore basic pane-local browser metadata when possible

The restore goal should not be:

- recreate a full tab-session browser history exactly

## Data Store Choice

`WKWebsiteDataStore` gives us three obvious choices:

- `default()`
  - simple and persistent
  - shares one app-wide WebKit store
- `nonPersistent()`
  - private-session behavior
  - easiest safety boundary
  - weakest continuity story
- `init(forIdentifier:)`
  - app-owned persistent profiles keyed by identifiers
  - better long-term fit if pane or workspace browser state needs durable but
    app-scoped storage

Recommended first pass:

- use one explicit app-owned persistent data store, not `nonPersistent()`
- do not attempt Chrome or Safari profile sharing
- keep the policy simple and app-owned

That keeps the browser pane feature practical without importing the much larger
profile-migration problem from the earlier CEF planning.

## How Well It Fits The Current System

### What already fits well

- pane splitting
- pane close behavior
- pane-local focus
- pane geometry reporting
- scene-owned pane commands
- AppKit-hosted leaf content through SwiftUI

The shell already knows how to host an interactive AppKit surface in a pane and
how to treat that pane as a first-class focus target.

### What needs generalized

- `PaneLeaf`
- persistence coding for leaf payloads
- `ContentPane` leaf resolution
- leaf controller caches and session registries
- inspector assumptions that the focused pane is terminal-backed

This is real work, but it is local and conceptually clean. It does not require
another scene or window architecture reset.

### What should stay unchanged

- `WorkspaceSceneIdentity`
- the recursive `PaneNode` tree
- scene-owned focus and command routing
- sidebar and library model
- per-window workspace persistence model

The browser feature should plug into the existing shell, not fork it.

## Recommended First Implementation Slice

If `gmax` pursues basic WebView panes now, the clean first slice is:

1. Generalize `PaneLeaf` from terminal-only to `PaneContent`.
2. Add a minimal `BrowserSession` model plus `BrowserSessionRegistry`.
3. Add a `BrowserPaneController` and `BrowserPaneView` backed by `WKWebView`
   through `NSViewRepresentable`.
4. Update `ContentPane` to render terminal or browser content based on the leaf
   payload.
5. Persist browser leaves honestly in the workspace payload graph.
6. Start with basic navigation, title, URL, loading state, and reload support.

That is the smallest durable browser-pane cut that fits the current systems
well.

## Non-Goals For The First Pass

- CEF or Chromium runtime packaging
- multi-profile browser management UI
- browser extension support
- devtools integration
- exact browser-session restoration
- cross-app cookie/profile sharing
- a second pane tree dedicated to browser content

## Bottom Line

A basic `WKWebView` pane fits `gmax` well at the shell level and poorly at the
current terminal-only leaf payload level.

So the real answer is:

- yes, browser panes fit the current window, focus, and split systems well
- no, they do not fit cleanly if we keep pretending every leaf is a terminal
  session

The right first pass is not a parallel browser system and not a heavy Chromium
stack. The right first pass is:

- generalize leaf content
- keep the existing shell architecture
- host a `WKWebView` as just another pane surface
- persist only basic browser session state

## Concrete Implementation Map

This section turns the recommendation into the actual repo surfaces that would
need to move.

### Slice 1: Generalize Leaf Content

This is the foundation slice. It does not need a visible browser feature yet.

Primary goal:

- make the pane tree honest about what a leaf contains

Primary source edits:

- `gmax/Scenes/WorkspaceWindowGroup/WorkspaceLayout.swift`
  - add `BrowserSessionID`
  - add `PaneContent`
  - change `PaneLeaf` to hold `content` instead of a terminal-only `sessionID`
- `gmax/Persistence/Workspace/WorkspacePersistenceEntities.swift`
  - add leaf content kind and browser-session identifier fields to
    `PaneNodeEntity`
- `gmax/Persistence/Workspace/WorkspacePersistenceController+CoreData.swift`
  - add the matching Core Data model attributes and migration defaults
- `gmax/Persistence/Workspace/WorkspacePersistenceController+WorkspaceCoding.swift`
  - encode and decode terminal versus browser leaf payloads honestly
- `gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore+PaneActions.swift`
  - stop assuming every pane leaf can seed or relaunch a terminal session
- `gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore+WorkspaceActions.swift`
  - clone, restore, recent-history capture, and library reopen paths only for
    terminal leaves where terminal session state actually exists
- `gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift`
  - render a temporary browser placeholder for browser leaves and an
    unsupported-pane fallback for anything else
- `gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/DetailPanel/DetailPane.swift`
  - show temporary browser inspector metadata and an unsupported-pane fallback

Important rule:

- do not keep a terminal-only `sessionID` plus a sidecar browser map
- the leaf payload should become the source of truth immediately

What this slice buys us:

- the pane tree can support multiple content kinds cleanly
- persistence stops lying about leaf identity
- later browser work becomes additive instead of workaround-heavy

Current status:

- Slice 1 groundwork is landed and build-verified
- focused persistence and lifecycle tests are green
- browser leaves are a real persisted content kind now
- browser runtime, WebKit hosting, and browser commands still belong to later
  slices

### Slice 2: Add Browser Runtime Models

This slice introduces the browser-side equivalents of the terminal runtime
surfaces.

Primary goal:

- give browser leaves a real runtime model without disturbing the existing
  terminal runtime

Primary source edits:

- `gmax/Browser/Sessions/BrowserSession.swift`
- `gmax/Browser/Sessions/BrowserSessionRegistry.swift`
- `gmax/Browser/Panes/BrowserPaneController.swift`
- `gmax/Browser/Panes/BrowserPaneControllerStore.swift`
- `gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore.swift`
  - own browser session and controller stores alongside the terminal ones
- `gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore+PaneActions.swift`
  - trim browser runtime state when browser leaves disappear
- `gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift`
  - resolve `.browser(sessionID)` into a browser-aware placeholder view backed
    by a real browser session
- `gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/DetailPanel/DetailPane.swift`
  - inspect browser session metadata instead of falling back to generic
    unsupported-pane copy
- `gmaxTests/WorkspaceLifecycleTests.swift`
  - cover browser-session bootstrap and cleanup

Suggested first browser-session fields:

- `id`
- `url`
- `title`
- `isLoading`
- `estimatedProgress`
- `canGoBack`
- `canGoForward`
- `lastCommittedURL`
- `lastErrorDescription`

Runtime ownership should mirror the terminal side:

- registry owns session lookup by ID
- controller owns the pane-local AppKit host wiring
- store owns controller lookup by `PaneID`

What this slice buys us:

- a browser leaf can exist as a real runtime thing
- `ContentPane` will have somewhere honest to go when it sees
  `.browser(sessionID)`

Current status:

- Slice 2 runtime groundwork is landed and build-verified
- focused persistence and lifecycle tests are green with browser-session
  bootstrap and cleanup coverage
- browser panes now have real session and controller ownership
- browser duplication now remints `BrowserSessionID` and seeds the new session
  from the source pane's last committed URL
- browser persistence now carries basic browser-session metadata instead of
  stopping at leaf identity alone
- browser-only commands now cover creation, navigation, reload, and omnibox
  focus through the scene command surface

### Slice 3: Add The WebView Host

This slice gets the first real browser pane on screen.

Primary goal:

- host `WKWebView` in a pane with the same shell-level responsibilities that a
  terminal pane already has

Suggested new types:

- `gmax/Browser/Panes/BrowserPaneView.swift`
- `gmax/Browser/Panes/BrowserPaneView+Coordinator.swift`
- `gmax/Browser/Panes/BrowserPaneHostView.swift`
- `gmax/Browser/WebKit/BrowserWebViewFactory.swift`

Recommended host shape:

- use `NSViewRepresentable`, not `NSViewControllerRepresentable`
- keep one `WKWebView` per browser pane
- give the controller ownership of the `WKWebView`
- let the representable create and update the host view
- keep AppKit interop narrow, the same way the terminal path does

Recommended first browser actions:

- load URL
- reload
- stop
- back
- forward
- observe title and URL changes
- observe loading state and web-process termination

What this slice buys us:

- a browser pane becomes a real pane-sized interactive surface
- we can validate focus, resize, and close behavior against the current shell

Current status:

- Slice 3 WebKit hosting is landed and build-verified
- `BrowserPaneView`, its coordinator, and the shared WebKit factory are now the
  active browser-pane path
- browser leaves render a real `WKWebView` instead of the earlier placeholder
  card
- ordinary `http`, `https`, `about`, and `file` navigation stays in-pane
- special URL schemes hand off through the system instead of being forced into
  the embedded browser
- browser session restore now reloads basic browser metadata and the last
  committed URL across live restore, saved-workspace reopen, and recent-history
  reopen paths
- browser history-stack persistence is still deferred
- scene commands now expose `New Browser Pane Right` and `New Browser Pane
  Down` as dedicated browser-pane creation actions instead of overloading the
  existing terminal split commands
- scene commands now expose browser-only `Back`, `Forward`, and `Reload`
  actions for the focused browser pane instead of treating navigation as a
  terminal-style pane command
- Settings now expose a configurable browser home URL, and new browser panes
  fall back to that URL when there is no restored last-committed page
- focused browser panes now use a compact omnibox overlay instead of a fixed
  toolbar strip, with `Command-L` revealing and focusing the address field

### Slice 4: Connect `ContentPane` To Mixed Leaves

This is the shell integration slice.

Primary goal:

- render terminal or browser content based on the leaf payload

Primary source edits:

- `gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift`
  - replace the terminal-only `controllerForPane` path with a content switch
- `gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift`
  - either generalize it into a leaf chrome wrapper that can host either
    content kind, or split the terminal-specific part out and keep shared pane
    chrome around it
- `gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore.swift`
  - instantiate and retain browser registries and browser controller stores

Current status:

- the active content tree already switches on `PaneLeaf.content`
- terminal leaves still use the existing terminal-pane path
- browser leaves now resolve into the real WebKit-backed browser pane path
- later browser work can focus on commands, persistence, and settings instead of
  basic mixed-leaf rendering

Recommended direction:

- keep one shared pane-chrome shell around both content kinds
- do not fork the entire leaf view into unrelated terminal and browser layout
  systems

The focus model should stay the same:

- the pane is the shell focus target
- browser internal focus is still inside that pane
- `Command-W`, split, and pane navigation remain scene-owned

### Slice 5: Creation, Replacement, And Basic Commands

This is where the feature becomes usable rather than just technically present.

Primary goal:

- let users create and interact with browser panes intentionally

Likely source edits:

- `gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore+PaneActions.swift`
  - add creation or replacement helpers for browser leaves
- `gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/WorkspaceWindowSceneCommands.swift`
  - add browser-specific actions only where they actually make sense
- `gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/DetailPane.swift`
  - add inspector metadata for browser panes

Recommended first product actions:

- create browser pane through dedicated split commands
- duplicate current pane split into a browser pane, if that proves useful
- open URL in focused browser pane
- reload focused browser pane
- navigate back and forward in focused browser pane

Settled command shape for the first pass:

- `New Browser Pane Right` with `Option-Command-D`
- `New Browser Pane Down` with `Shift-Option-Command-D`
- `Back` in the focused browser pane with `Command-[`
- `Forward` in the focused browser pane with `Command-]`
- `Reload` in the focused browser pane with `Command-R`
- `Focus Address Bar` in the focused browser pane with `Command-L`
- no pane-type conversion yet

### Slice 6: Browser Persistence

This slice makes browser panes survive workspace save and restore.

Primary goal:

- preserve basic browser-pane identity and last committed state across
  persistence flows

Persisted fields should stay intentionally small:

- `BrowserSessionID`
- last committed URL
- title
- loading or last error text

And one stretch goal is explicitly allowed here:

- preserve the back-forward history stack if WebKit makes that feasible without
  distorting the first-pass model

Restore behavior should stay modest:

- recreate the browser pane
- load the saved URL
- let the page render fresh

It should not try to:

- restore the full back-forward list
- reconstruct in-page state exactly
- capture per-page transient runtime state

### Slice 7: Browser-Focused UX Follow-Through

This is the cleanup slice after the basic feature works.

Primary goal:

- make browser panes feel native inside the existing shell

Likely follow-through areas:

- inspector metadata and actions
- accessibility labels and hints
- keyboard shortcut decisions for browser actions
- loading/error states inside the pane
- process-termination handling and pane-local recovery
- tests for mixed terminal plus browser workspace layouts

## File-Level Impact Summary

If we do this the recommended way, these are the main current files that will
move:

- `gmax/Scenes/WorkspaceWindowGroup/WorkspaceLayout.swift`
- `gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore.swift`
- `gmax/Scenes/WorkspaceWindowGroup/WorkspaceStore+PaneActions.swift`
- `gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPane.swift`
- `gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift`
- `gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/DetailPane.swift`
- `gmax/Persistence/Workspace/WorkspacePersistenceEntities.swift`
- `gmax/Persistence/Workspace/WorkspacePersistenceController+CoreData.swift`
- `gmax/Persistence/Workspace/WorkspacePersistenceController+WorkspaceCoding.swift`
- `gmax/Persistence/Workspace/WorkspaceSnapshots.swift`

And these new areas would likely be added:

- `gmax/Browser/Sessions/`
- `gmax/Browser/Panes/`
- maybe `gmax/Browser/WebKit/`

## Risk Map

These are the real risk seams, in order.

### Lowest risk

- `WKWebView` host creation
- pane resizing
- pane embedding through `NSViewRepresentable`

The frameworks already support this directly.

### Medium risk

- mixed-pane persistence
- inspector assumptions
- command enablement and targeting for browser-specific actions

This is mostly app-model cleanup, not framework hostility.

### Highest risk

- trying to avoid generalizing `PaneLeaf`
- trying to bolt browser state onto the side of terminal-only persistence
- overreaching on browser restoration or browser profile management in the first
  pass

That is where the design would start fighting itself.

## Recommended Coding Start

If we want to begin implementation soon, the best first coding checkpoint is:

1. land Slice 1 by generalizing `PaneLeaf` and persistence payload coding
2. stop there and verify the terminal-only app still works unchanged
3. then add the browser runtime and `WKWebView` host on top of that stronger
   model

That gives us a clean red-green path:

- first make the model honest
- then plug a browser surface into it

This is a slower start than a hacked prototype, but it is the cleanest fit with
the systems `gmax` already has.
