# Ghostty Pane Integration Plan

## Purpose

This note records the two clean ways `gmax` could integrate Ghostty panes through
Ghostty's embedding API, especially `ghostty_surface_new`.

It is a planning document, not an implementation commitment. The current
production terminal backend remains SwiftTerm.

Use this note when discussing:

- a Ghostty-backed terminal pane
- a Ghostty surface spike inside an existing `gmax` pane
- a long-term terminal-backend choice between SwiftTerm and Ghostty
- why vendoring Ghostty's macOS app view is not the preferred path

## Current Recommendation

Build the Ghostty work in two steps:

1. Create a deliberately small Ghostty surface spike.
2. Promote that spike into a backend adapter only after it proves the critical
   pane behavior.

The spike proves whether Ghostty can live inside one `gmax` pane. The adapter
work decides how Ghostty and SwiftTerm coexist as product-supported terminal
backends.

Do not vendor Ghostty's full macOS `SurfaceView` unless upstream makes that view
a supported embeddable component. That path imports Ghostty app structure into
`gmax` instead of keeping a clear terminal-surface boundary.

## Source Snapshot

This plan was written against Ghostty `main` at:

- Commit:
  [`4ceeba4851030e75398cf1e5d3f7d8c7ed645e87`](https://github.com/ghostty-org/ghostty/commit/4ceeba4851030e75398cf1e5d3f7d8c7ed645e87)
- Commit date: 2026-04-24
- Commit title: `config: use Config to check key binding instead of App (#12415)`

Primary upstream references:

- Ghostty embedding header:
  [`include/ghostty.h`](https://github.com/ghostty-org/ghostty/blob/main/include/ghostty.h)
- Ghostty embedded apprt implementation:
  [`src/apprt/embedded.zig`](https://github.com/ghostty-org/ghostty/blob/main/src/apprt/embedded.zig)
- Ghostty macOS AppKit surface:
  [`macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Ghostty/Surface%20View/SurfaceView_AppKit.swift)
- Ghostty keybinding action reference:
  <https://ghostty.org/docs/config/keybind/reference>
- `libghostty-vt` documentation:
  <https://libghostty.tip.ghostty.org/>
- SwiftUI `NSViewRepresentable`:
  <https://developer.apple.com/documentation/swiftui/nsviewrepresentable>

The upstream header itself describes the embedding API as not yet intended as a
general-purpose embedding API. Treat every concrete API name in this note as
subject to re-verification before implementation.

## Apple Behavior Relied On

SwiftUI's `NSViewRepresentable` is the supported boundary for integrating an
AppKit `NSView` into a SwiftUI view tree. SwiftUI asks the representable to
create the AppKit view, update it when SwiftUI state changes, and dismantle it
when the SwiftUI view is removed.

For `gmax`, that means the SwiftUI pane should remain the workspace and focus
participant, while the hosted AppKit view remains the terminal interaction
surface. Live terminal rendering and byte flow should not move through SwiftUI
state.

## Existing `gmax` Boundary To Preserve

The existing SwiftTerm pane model should remain the reference shape:

- `gmax` owns workspace windows, pane identity, pane focus, pane topology,
  persistence metadata, scene commands, and app-level accessibility labels.
- The terminal surface owns prompt input, scrollback selection, terminal search,
  terminal-native copy/select-all behavior, mouse behavior, and terminal
  rendering.
- The AppKit boundary hosts the terminal view inside a pane; it should not
  become a custom scene focus router or a replacement responder chain.

For Ghostty, the same rule applies. A Ghostty surface is a terminal surface,
not a workspace coordinator.

## Option 1: Thin Ghostty Pane Host

### Real Job

This option answers one question:

Can one Ghostty terminal surface run correctly inside one existing `gmax` pane?

It is the smallest useful proof of `ghostty_surface_new`.

### Shape

Create a new AppKit host, probably named something like
`GhosttyPanePrototypeView`, outside the main terminal-backend architecture at
first.

The host would:

- retain a process-wide or app-wide `ghostty_app_t`
- create one `ghostty_surface_t` for the pane
- pass the host `NSView` through `ghostty_surface_config_s.platform.macos.nsview`
- provide the pane working directory, command, environment, font size, content
  scale, and context
- forward AppKit focus, resize, scale, keyboard, text, IME, mouse, scroll, and
  draw events into `ghostty_surface_*`
- translate Ghostty runtime callbacks into a small local diagnostic state

The SwiftUI side would be a narrow `NSViewRepresentable` wrapper, following the
same AppKit-hosting rule as the current SwiftTerm pane.

### `gmax` Responsibilities

In this spike, `gmax` should own only the pane shell around Ghostty:

- create and retain the host view for one pane
- decide the initial working directory and shell command
- provide the environment values that matter to `gmax`
- keep pane focus visual treatment scene-owned
- expose a minimal pane label and accessibility fallback
- log Ghostty lifecycle, surface creation, and callback failures with
  human-readable messages

### Ghostty Responsibilities

Ghostty should own the terminal behavior inside the surface:

- terminal emulator state
- PTY/session behavior created by the Ghostty surface
- renderer and Metal-backed drawing
- input encoding once AppKit events are converted into Ghostty input events
- terminal selection
- terminal search internals
- clipboard and OSC 52 mediation through its runtime callbacks
- process exit and quit-confirmation state

### Required Callback Mapping

The spike should prove that these callbacks or actions can be observed and
translated:

- title changes
- current working directory changes, if exposed through the embedding action
  surface
- bell or attention requests
- explicit notification requests
- child-process exit
- close-surface requests
- clipboard read/write requests
- wakeup or redraw requests
- config or color-scheme updates

If current-directory changes are not exposed directly enough, the spike should
record that as a Ghostty-surface gap rather than adding a parallel terminal
parser immediately.

### Success Criteria

The spike is successful if one Ghostty pane can:

- create a surface without owning the whole app window
- render nonblank terminal content inside a `gmax` pane
- accept keyboard input, pasted text, IME preedit, mouse selection, and scroll
- resize correctly when the pane split changes
- follow `gmax` scene focus visually without forcing custom focus routing
- report enough metadata for title, exit, bell, and close behavior
- release cleanly when the pane closes

### Failure Criteria

The spike should be considered a poor fit if it requires:

- vendoring Ghostty's full macOS `SurfaceView`
- adopting Ghostty's app-level scene or window model
- routing `gmax` pane focus through Ghostty app state
- bypassing `gmax` pane topology for Ghostty's own split model
- sending terminal output through SwiftUI state
- duplicating terminal emulator state in SwiftTerm and Ghostty at the same time

### Expected Files In A Spike

A first spike should stay small and obviously removable. A likely file shape:

- `gmax/Terminal/Ghostty/GhosttyPanePrototypeView.swift`
- `gmax/Terminal/Ghostty/GhosttySurfaceRuntime.swift`
- `gmax/Terminal/Ghostty/GhosttyInputTranslator.swift`

Those names are illustrative. The important rule is that prototype code should
not be scattered through the workspace scene, persistence model, or SwiftTerm
controller.

### Current Spike Implementation

The current branch contains that thin host spike behind one process environment
switch:

```sh
GMAX_GHOSTTY_PANE_SPIKE=1
```

When the switch is absent, panes still use SwiftTerm. When the switch is set to
`1`, `ContentPaneLeafView` creates `GhosttyPaneView` instead of
`TerminalPaneView` for terminal leaves. The rest of the pane chrome, focus
highlighting, accessibility label, split controls, current-directory footer, and
ended-session overlay remain owned by the existing workspace view.

The spike is deliberately split into two pieces:

- Swift code under `gmax/Ghostty/` owns the SwiftUI-to-AppKit pane host, dynamic
  shim loading, `NSView` geometry, basic keyboard/mouse forwarding, and
  translation of Ghostty lifecycle callbacks into the existing
  `TerminalSession` metadata.
- `tools/ghostty-spike/` owns the tiny C shim that includes Ghostty's embedding
  header, dynamically links the installed `Ghostty.app` binary, creates the
  Ghostty runtime, and exposes a narrow C ABI that Swift can call without
  importing Zig/Clang struct details directly.

Build the shim before launching the spike:

```sh
tools/ghostty-spike/build-shim.sh
```

The script downloads the pinned `ghostty.h`, builds
`build/GhosttyPaneSpike/libgmax-ghostty-shim.dylib`, and ad-hoc signs the shim.
The built dylib is intentionally ignored local build output.

The default runtime paths are:

- Ghostty binary:
  `/Applications/Ghostty.app/Contents/MacOS/ghostty`
- Sparkle preload:
  `/Applications/Ghostty.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle`
- Shim:
  `build/GhosttyPaneSpike/libgmax-ghostty-shim.dylib`

These can be overridden for local experiments:

```sh
GMAX_GHOSTTY_APP_BINARY=/path/to/Ghostty.app/Contents/MacOS/ghostty
GMAX_GHOSTTY_SPARKLE_PATH=/path/to/Sparkle
GMAX_GHOSTTY_SHIM_PATH=/path/to/libgmax-ghostty-shim.dylib
```

One important finding from the installed Ghostty app is that the pinned header
declares `ghostty_surface_draw`, `ghostty_surface_refresh`, and
`ghostty_config_free`, but this local `Ghostty.app` binary does not currently
export them. The shim treats draw and refresh as optional no-ops and avoids
calling `ghostty_config_free`. If the first app run creates a surface but does
not render nonblank content, the next thing to validate is a Ghostty build whose
exported symbols match the pinned embedding header.

The current spike validates dynamic runtime loading with:

```sh
tools/ghostty-spike/build-shim.sh
swift tools/ghostty-spike/smoke-runtime.swift
```

The real surface validation still requires launching `gmax` with
`GMAX_GHOSTTY_PANE_SPIKE=1`, because `ghostty_surface_new` needs the live
pane-owned `NSView`.

### Live Spike Findings

The first live run of the thin host is promising enough to continue. It proves
that Ghostty can render inside a `gmax` pane while `gmax` still owns workspace
chrome, pane focus visuals, split layout, and the detail inspector.

Confirmed behavior:

- The shim can load the installed Ghostty app binary, create the runtime, and
  create pane surfaces with `ghostty_surface_new`.
- The renderer is alive in ordinary split panes; cursor blink and terminal
  output render inside the pane.
- A Ghostty terminal pane can coexist beside a browser pane in the same
  workspace.
- After the `ccab323` input fix, printable keys and core control keys flow
  through `ghostty_surface_key`; commands such as `ls`, `pwd`, `echo $0`,
  `true`, and `false` execute.
- Shell metadata is good enough to drive the existing `TerminalSession` UI:
  successful commands set shell phase back to prompt with exit status `0`, and
  failing commands produce the existing failure indicator.

Observed limitations:

- The initial raw-text path displayed typed text but did not reliably execute
  commands. Ghostty needs key events for normal keyboard input, not just
  `ghostty_surface_text`.
- Bell reporting is incomplete. Delete on an empty prompt produced a bell once,
  but bell state was inconsistent in live testing.
- Surface contents disappear on workspace switch. This is expected for the
  current thin host because SwiftUI view removal destroys the AppKit host and
  therefore the Ghostty surface and its shell/session state.
- Current-directory reporting can arrive in a form like `file://Mac.lan%23/...`;
  a product adapter should normalize or source this metadata more deliberately.
- The installed Ghostty app still does not export `ghostty_surface_draw`,
  `ghostty_surface_refresh`, or `ghostty_config_free` despite the pinned header
  declaring them, so this spike should stay tied to local validation rather than
  treated as an API-stability proof.

The practical implication is that the view-only spike is useful evidence, but
it is not the product shape. A real integration should promote Ghostty into a
backend object that owns the Ghostty runtime, surface, and shell/session
lifetimes independently from transient SwiftUI view presence. The view should
attach to that backend; it should not be the only owner of the terminal session.

## Option 2: Backend Adapter Beside SwiftTerm

### Real Job

This option answers the product question:

Can `gmax` support SwiftTerm and Ghostty as sibling terminal backends without
letting backend details leak into workspace, command, persistence, and focus
code?

This is the shape to ship if the option 1 spike works.

### Integration Map

The backend adapter should make terminal panes work the way browser panes and
SwiftTerm panes already want to work: the pane model identifies a long-lived
session, a registry keeps that session available while the workspace owns it,
and SwiftUI/AppKit views attach to that session when they are present.

The adapter is a durable building-block change, not just a Ghostty local detail.
It exists because the thin spike proved a concrete failure mode: when the
Ghostty surface is owned only by the transient AppKit view, SwiftUI view removal
also removes terminal contents and shell state. The backend object should be the
owner of terminal lifetime; the view should only be the visible attachment.

The design should combine:

- a shared terminal backend contract
- explicit backend capabilities
- a persistent per-pane terminal backend object
- backend-specific restore behavior
- a small compatibility path for the current SwiftTerm implementation

It should not introduce a new command router, focus bridge, pane selection
model, or workspace coordinator.

### Shape

Introduce an app-facing terminal backend contract. SwiftTerm and Ghostty would
each provide one implementation.

The app-facing contract should describe the terminal host from `gmax`'s point
of view:

- AppKit view to embed in the pane
- launch context consumed by the backend
- pane metadata output
- capability flags
- lifecycle operations
- cleanup behavior

SwiftTerm would keep using `LocalProcessTerminalView` behind this contract.
Ghostty would use the option 1 host internally.

The first implementation can be narrower than the final protocol, but it should
name the real roles from the start:

- `TerminalBackendKind` identifies the selected backend, probably `swiftTerm`
  and `ghostty`.
- `TerminalBackendCapabilities` reports what a backend can honestly do.
- `TerminalBackendState` is the normalized state consumed by pane chrome,
  inspector UI, persistence, and accessibility.
- `TerminalBackendHost` owns one backend session for one pane/session pair.
- `TerminalBackendView` or a similarly named AppKit host view attaches the
  backend's terminal view into SwiftUI.
- `TerminalBackendRegistry` retains backend hosts by terminal session ID or pane
  ID while the workspace still owns the pane.

The exact names can change, but those jobs should stay separate. A capability
value should not own views. A host should not own scene commands. The pane view
should not decide how Ghostty launches.

### Ownership Boundary

`gmax` owns:

- pane identity and split topology
- workspace windows and scene-local focus state
- scene commands and menu availability
- terminal launch configuration selected by the app
- normalized pane metadata shown in chrome and the inspector
- persistence of backend identity and supported restoration payloads
- app-level accessibility fallback labels and actions

The terminal backend owns:

- terminal process/session lifetime
- terminal renderer state
- terminal input translation after AppKit receives events
- terminal-native copy, paste, select all, selection, search, and scroll behavior
- backend-specific transcript or restore capture
- backend-specific metadata extraction
- backend-specific teardown

The SwiftUI/AppKit boundary owns:

- creating an `NSViewRepresentable` wrapper
- attaching the backend's AppKit view when the SwiftUI pane is visible
- updating size, scale, appearance, focus, and accessibility snapshots
- detaching the visible view without destroying the backend session unless the
  pane/session is actually closed or relaunched

### Capability Model

Backend differences should be visible, not hidden behind false parity. The
first capability set should cover the behaviors `gmax` already shows or is
about to expose:

| Capability | SwiftTerm expectation | Ghostty spike expectation |
| --- | --- | --- |
| `title` | Available from terminal callbacks or session state | Available from Ghostty title callback |
| `currentDirectory` | Available from launch config and shell integration | Available, but needs URL/path normalization |
| `shellPhase` | Available from shell integration parser | Partially available through Ghostty command events |
| `lastCommandExitStatus` | Available from shell integration parser | Available for observed commands |
| `bell` | Available through SwiftTerm bell override | Present but inconsistent in live spike |
| `notification` | Available through parsed OSC notification | Available through Ghostty callback |
| `copyPaste` | Terminal view owns responder behavior | Must be verified through Ghostty surface callbacks/actions |
| `selection` | Terminal view owns selection | Must be verified |
| `search` | SwiftTerm owns terminal search | Unknown or Ghostty-specific |
| `historyTextExport` | Available through current transcript capture | Possible through text-read APIs or scrollback file action |
| `historyRestore` | Available through current SwiftTerm restore path | Unsupported until Ghostty exposes a clean restore surface |
| `closeRequest` | App owns pane close, terminal can report process exit | Available from Ghostty close request callback |
| `readableAccessibilityText` | Partial through SwiftTerm text extraction | Possible through selection/text-read APIs |

The important product rule is that missing Ghostty capabilities should degrade
honestly. A Ghostty pane can initially restore launch context without claiming
to restore transcript history.

### Ghostty Text And Scrollback Capabilities

Ghostty's current embedding header exposes text-read helpers:

- `ghostty_surface_has_selection`
- `ghostty_surface_read_selection`
- `ghostty_surface_read_text`
- `ghostty_surface_free_text`

Those APIs are useful for selection, accessibility, and maybe text-only history
export, but they are not a complete restore model. They do not promise a
serializable terminal state that includes scroll position, alternate-screen
state, style runs, prompt markers, graphics protocol content, or renderer state.

Ghostty also exposes keybinding actions such as `write_scrollback_file`,
`write_screen_file`, and `write_selection_file`. Because the embedding surface
has `ghostty_surface_binding_action`, `gmax` may be able to trigger one of
those actions and intercept the resulting clipboard or file flow through the
runtime callbacks. Treat that as a diagnostic or archive workaround, not as the
main restore path.

The initial capability stance should be:

- `historyTextExport`: maybe, text-only, behind explicit validation
- `historyArchive`: possible as a separate saved artifact
- `historyRestore`: unsupported for Ghostty
- `sessionContinuityWhileAlive`: required for the backend adapter

This means a Ghostty pane can preserve live contents while the app process and
backend host are alive, but after app restart it should relaunch from the saved
launch context rather than replaying scrollback into Ghostty.

Avoid raw PTY-output replay as a restore strategy. The current embedding surface
does not expose a "feed historical terminal output" API, and sending recorded
output through `ghostty_surface_text` would be input to the child process, not
terminal output into the emulator.

### Ghostty Dependency Path

There are three dependency stages:

1. Local installed-app spike.
2. Pinned Ghostty source or binary artifact behind a `gmax` shim.
3. Optional upstream embedding package if Ghostty publishes one later.

The installed-app path is only for concept validation. It relies on a local
`Ghostty.app`, dynamic loading, and hardened-runtime settings that are
acceptable for a spike but not the product dependency story.

The product-shaped path should keep a `gmax`-owned shim. The shim should expose
only the C ABI `gmax` actually uses, keep Ghostty/Zig layout details out of
Swift, and make header/export mismatches fail with readable diagnostics.

The shim should cover, at minimum:

- app/runtime create, tick, and destroy
- surface create and destroy
- size, content scale, display ID, focus, occlusion, color scheme, refresh, and
  draw when exported
- keyboard, text, preedit, mouse button, mouse position, mouse scroll, and
  mouse capture state
- selection and text read APIs
- binding actions for copy, paste, select all, search, and text export
- foreground process ID and TTY name
- close request, process-exited query, and quit-confirmation query
- runtime callbacks for wakeup, actions, clipboard, close-surface, and
  notifications

Do not import Ghostty's macOS app view, app scene model, tab model, split model,
menus, settings UI, or persistence assumptions. Those are Ghostty.app product
surfaces, not the terminal-surface dependency boundary `gmax` needs.

### State Flow

The backend should publish normalized state into the existing `TerminalSession`
surface or into a successor object with the same app-facing meaning:

1. Workspace model contains a terminal pane with a stable terminal session ID.
2. The terminal session registry creates or restores the session metadata.
3. The backend registry creates or retrieves the backend host for that session.
4. The pane view asks the backend host for an attachable AppKit view.
5. Backend callbacks update normalized terminal state.
6. Pane chrome, inspector UI, persistence capture, and accessibility read the
   normalized state without inspecting the backend type.

This keeps dependency direction straight: Ghostty knows how to report terminal
events to the backend host; the backend host knows how to update terminal state;
workspace views read terminal state. Workspace views should not call Ghostty
runtime APIs directly.

### Persistence And Restore

The first persistence change should add backend identity separately from
restored content. A terminal snapshot should be able to say:

- this was a SwiftTerm-backed terminal
- this was a Ghostty-backed terminal
- this backend can restore transcript content
- this backend can only restore launch context right now

The current `WorkspaceSessionSnapshot` shape already carries session ID, title,
launch configuration, and SwiftTerm-oriented history. The backend work should
avoid forcing Ghostty data into that history payload. Either add backend
identity and a backend-specific restoration payload, or split the terminal
snapshot into common fields plus backend restore fields.

Early Ghostty restore should be explicit:

- restore pane layout
- restore backend identity
- restore launch command and working directory
- start a fresh Ghostty terminal session
- leave transcript restore unsupported until a Ghostty-owned transcript or
  surface-restore API is proven

### Implementation Slices

Build this in small slices so each step can be validated:

1. Add backend identity and capability types without changing runtime behavior.
2. Wrap the current SwiftTerm controller behind the backend contract.
3. Move the env-gated Ghostty host behind the same contract.
4. Add a backend registry that retains backend hosts independently from
   SwiftUI view presence.
5. Prove Ghostty survives workspace switching when the pane/session still
   exists.
6. Validate Ghostty text export, selection read, copy, paste, and select-all
   through capabilities rather than assuming parity.
7. Move pane chrome and inspector reads to normalized backend/session state.
8. Add persistence for backend identity while keeping SwiftTerm as the default.
9. Replace the installed-app spike dependency with a pinned Ghostty source or
   binary artifact behind the `gmax` shim.
10. Add user-facing backend selection only after lifecycle, teardown, and restore
   behavior are documented.

The first red/green behavior should be simple: run a Ghostty command, switch to
another workspace, switch back, and confirm the command output is still present
because the backend host survived view detachment.

### Open Design Choices

The main design choice is the key used by the backend registry.

Using `TerminalSessionID` makes backend lifetime match terminal session
identity. That is attractive for persistence and restore, and it avoids tying
session lifetime to transient pane geometry. Using `PaneID` would match the
browser pane controller store, but pane IDs are layout identity rather than
terminal session identity.

The initial recommendation is to retain backend hosts by terminal session ID,
and let a host also know its current pane ID for logging and accessibility. If a
future feature allows moving one terminal session between panes, this choice
will compose better.

The second choice is whether `TerminalSession` remains the normalized state
object or whether a new `TerminalBackendState` replaces it. The initial
recommendation is to keep `TerminalSession` as the app-facing state surface
while extracting backend-specific behavior out of `TerminalPaneController`.
That reduces churn and lets the inspector keep working while the backend
contract takes shape.

The third choice is how far the spike path remains env-gated. The initial
recommendation is to keep `GMAX_GHOSTTY_PANE_SPIKE=1` as the only selector until
backend lifetime works, then replace the flag with persisted backend identity or
an internal debug setting.

### Shared App-Facing State

The rest of `gmax` should consume normalized pane state instead of backend
specifics:

- title
- current working directory
- foreground process identifier when available
- terminal size or cell metrics when useful
- shell phase when available
- latest command exit status when available
- bell or attention state
- explicit terminal notification state
- process exit state
- quit-confirmation need
- selection availability
- search availability
- readable transcript or restored-history capability
- accessibility summary capability

Not every backend has to provide every value. The contract should make
capability differences explicit rather than hiding them behind false parity.

### Shared Lifecycle Operations

The common backend surface should cover:

- create terminal host
- start or attach session
- apply appearance settings
- apply focus state
- apply content scale and size
- request copy, paste, select all, and search when supported
- request close
- capture restorable history when supported
- release resources

The contract should not ask every backend to expose raw terminal cells or raw
byte streams unless a product feature actually needs that. Ghostty should not
be forced to look like SwiftTerm internally.

### Persistence Model

The first product version should persist backend identity separately from
restored content.

Likely durable metadata:

- terminal backend: SwiftTerm or Ghostty
- launch command
- working directory
- environment overrides
- display settings selected by `gmax`
- backend-specific restoration payload, if any

SwiftTerm's current transcript-backed restore should remain SwiftTerm-specific
until Ghostty exposes a clean equivalent. A Ghostty pane may initially restore
layout and launch context without full readable history restore.

### Command And Focus Model

The scene command model should not split by backend.

The pane remains the workspace command target. The terminal surface decides
whether it can satisfy terminal-native commands such as copy, paste, select
all, or search.

The backend contract should report command capability or availability upward;
the scene command layer should not inspect Ghostty or SwiftTerm concrete types.

### Accessibility Model

The pane host should provide app-level accessibility labels and actions in the
same spirit as the SwiftTerm host. Backend-specific terminal accessibility can
be richer, but `gmax` still needs a consistent fallback for:

- pane identity
- title
- working directory
- process state
- restart or close actions

If Ghostty exposes readable selected text or visible text through
`ghostty_surface_read_selection` or `ghostty_surface_read_text`, the adapter can
use that for richer accessibility. That should remain inside the Ghostty
backend.

### Expected Files In A Product Adapter

The product version would likely touch a broader, intentional surface:

- a shared terminal backend contract under `gmax/Terminal/`
- a SwiftTerm backend implementation that wraps the current controller
- a Ghostty backend implementation under `gmax/Terminal/Ghostty/`
- pane creation or session registry code that selects a backend
- persistence payload code that records backend identity and backend-specific
  restore metadata
- settings UI only after the backend is stable enough to expose

This is intentionally more work than option 1. The point is to keep the rest of
the app from accumulating `if ghostty` branches.

## Option 1 Versus Option 2

Option 1 is a local integration spike. It should be fast, small, and easy to
delete.

Option 2 is a durable product architecture. It should be slower, explicit, and
designed to keep backend differences behind one terminal-host boundary.

Practical differences:

| Concern | Option 1: Thin Host | Option 2: Backend Adapter |
| --- | --- | --- |
| Goal | Prove Ghostty can live in a pane | Ship Ghostty beside SwiftTerm |
| Scope | One host view and runtime wrapper | Shared terminal backend contract |
| Risk | Ghostty details leak if shipped directly | More design before visible payoff |
| Persistence | Minimal or none | Backend identity and restore policy |
| Commands | Mostly manual spike behavior | Backend capability feeds normal commands |
| Focus | Prove no custom focus router is needed | Preserve current scene-owned focus model |
| Tests | Manual behavior and lifecycle checks | Contract tests plus backend-specific checks |
| Outcome | Keep, revise, or delete the spike | Supported product path |

## Rejected Path: Vendoring Ghostty's AppKit `SurfaceView`

Ghostty's macOS `SurfaceView` is useful evidence, but it is not the desired
dependency boundary for `gmax`.

It already handles many hard AppKit concerns:

- first responder behavior
- key handling
- IME preedit
- mouse handling
- search UI
- clipboard services
- drag and drop
- accessibility
- surface model updates

The cost is that it is coupled to Ghostty's app model, app configuration,
environment, Combine state, notification behavior, and SwiftUI/AppKit surface
structure.

Using it directly would make `gmax` adapt to Ghostty.app instead of embedding a
Ghostty terminal surface. That is the wrong direction for this product.

## Rejected Path: Shared SwiftTerm And Ghostty Terminal State

Do not feed the same terminal byte stream into SwiftTerm and Ghostty as two live
terminal engines.

That creates two emulator states that can disagree on:

- cursor position
- alternate screen behavior
- scrollback
- selection
- terminal modes
- graphics protocols
- mouse reporting
- title and metadata parsing

If Ghostty renders the pane, Ghostty should own that pane's terminal state. If
SwiftTerm renders the pane, SwiftTerm should own that pane's terminal state.

## Implementation Phases

### Phase 0: Source Re-Verification

Before implementation, re-check Ghostty `main` or the pinned dependency tag for:

- whether `ghostty_surface_new` is still the correct creation API
- whether `ghostty_surface_config_s` still accepts `platform.macos.nsview`
- which runtime callbacks are required
- which action tags report title, cwd, bell, notification, exit, search, and
  close behavior
- whether an official package, xcframework, or module map exists for the
  embedding surface we need

### Phase 1: Disposable Surface Spike

Build option 1 with the least possible app integration.

The spike should be hidden behind a development flag or local prototype entry
point. It should not replace SwiftTerm as the default backend.

### Phase 2: Pane Behavior Validation

Manually validate:

- creation and teardown
- typing and paste
- IME preedit
- mouse selection and scroll
- split-pane resize
- retina and external-display scale changes
- light and dark appearance updates
- `Command-W` close behavior
- clipboard requests
- bell and notification behavior
- child-process exit
- multi-window behavior with independent panes

### Phase 3: Backend Contract

Only after the spike behaves well, define the shared terminal backend contract.

The contract should be shaped from actual backend needs observed in the spike,
not from speculative parity with every terminal feature.

### Phase 4: Product Adapter

Move the Ghostty host behind the shared contract. Keep SwiftTerm as the default
until Ghostty can satisfy the baseline product behavior.

### Phase 5: User-Facing Choice

Expose Ghostty as a setting only after:

- the dependency story is reliable
- pane lifecycle is stable
- focus and commands match the rest of `gmax`
- crash and teardown behavior has been exercised
- accessibility fallback is acceptable
- restore semantics are clearly described

## Open Questions

- Will Ghostty expose a stable enough embedding package for a third-party app
  to consume without tracking `main` closely?
- Can a `gmax` host provide the runtime callbacks without importing Ghostty's
  macOS app model?
- Is current-directory reporting exposed directly enough, or would `gmax` need
  a Ghostty-side metadata hook?
- Can Ghostty's surface provide readable text and selection data in a form good
  enough for `gmax` accessibility and restored-history needs?
- How should `gmax` handle Ghostty's own split actions if the app pane topology
  already owns splits?
- Is the dependency size and build complexity acceptable compared with writing
  a `gmax`-owned Metal renderer for SwiftTerm state?

## Decision Checklist

Before promoting Ghostty panes beyond a prototype, answer:

1. Does the Ghostty surface render and resize correctly in a `gmax` pane?
2. Does the surface participate in AppKit first responder behavior without a
   custom scene focus router?
3. Can `gmax` keep pane focus, commands, and workspace lifecycle scene-owned?
4. Can metadata flow through normalized pane state instead of backend-specific
   branches?
5. Can close, teardown, and child-exit behavior be logged and handled clearly?
6. Can we explain restoration honestly as either restored history or fresh
   launch context, depending on backend capability?
7. Can the dependency be built, updated, and debugged without vendoring
   Ghostty.app internals?

## Decision Summary

The clean path is not "use Ghostty's app view." The clean path is:

1. Prove `ghostty_surface_new` inside a narrow AppKit pane host.
2. If that works, wrap it as a sibling terminal backend beside SwiftTerm.
3. Keep `gmax` ownership focused on workspace windows, pane topology,
   persistence metadata, scene commands, and app-level accessibility.
4. Let each terminal backend own its own terminal state, input behavior,
   selection, search, and rendering.

## Product Integration Readiness

As of 2026-04-25, the branch is ready to start the first product-quality
integration pass, but not ready to expose Ghostty as a user-facing backend
choice.

Readiness evidence:

- the Ghostty shim builds locally with `tools/ghostty-spike/build-shim.sh`
- the runtime smoke script passes when pointed at the worktree-built shim
- `scripts/repo-maintenance/validate-all.sh` passes
- `xcodebuild -project gmax.xcodeproj -scheme gmax -destination 'platform=macOS' build`
  succeeds

The first implementation pass should focus on terminal lifetime ownership, not
settings UI. The current spike proved the concrete failure mode: a Ghostty
surface owned only by the transient AppKit view disappears when SwiftUI removes
that view during workspace switching. A product integration needs a
session-keyed backend host that outlives SwiftUI view attachment while the pane
and terminal session still exist.

First-pass scope:

- add terminal backend identity and capability types
- introduce a shared app-facing backend host contract
- keep SwiftTerm as the default backend and wrap its existing controller behind
  that contract
- move the Ghostty spike behind the same backend host contract
- retain backend hosts by `TerminalSessionID`
- preserve `TerminalSession` as the normalized app-facing state surface
- keep `GMAX_GHOSTTY_PANE_SPIKE=1` as the only Ghostty selector until lifecycle
  behavior is proven

The first red/green behavior is intentionally small: run a command in a Ghostty
pane, switch to another workspace, switch back, and confirm the command output
is still present because the backend host survived SwiftUI view detachment.

Known blockers before product exposure:

- the installed Ghostty app dependency is still a spike-only path
- the pinned header and installed app exports still disagree for some declared
  symbols
- current-directory metadata needs normalization before it becomes product UI
- bell, copy, paste, selection, search, readable text, and text export need
  capability-specific validation
- Ghostty restore should initially mean launch-context restore, not transcript
  history restore
