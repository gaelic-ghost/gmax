# CEF Pane Embedding Plan

## Purpose

This note captures the current recommended architecture for embedding Chromium Embedded Framework (CEF) into `gmax` as a pane-local web surface on macOS.

The target product shape is:

- each pane can host its own independently navigable webpage
- panes remain first-class nodes in the existing recursive split tree
- each embedded browser surface behaves like a native pane-sized view
- SwiftUI remains responsible for shell layout and pane orchestration
- CEF remains behind a narrow bridge instead of leaking into the Swift app model

This is a durable building-block proposal, not a stopgap.

It is specifically written for the current `gmax` architecture:

- `Workspace` owns a recursive `PaneNode` tree
- `PaneLeaf` currently maps to `TerminalPaneController`
- leaf content is already hosted via `NSViewRepresentable`
- pane focus and frame tracking already exist as shell primitives

## Core Conclusion

If `gmax` adds web panes backed by CEF, the preferred model is:

- one `CefBrowser` instance per pane
- one native AppKit host view per pane
- one Objective-C++ bridge layer that owns all direct CEF interaction
- one Swift-facing pane controller per browser pane
- one SwiftUI `NSViewRepresentable` wrapper per browser-pane host view

This is the easiest correct route for the desired UX.

Important distinction:

- one browser per pane is the right app-level primitive
- one renderer process per pane is not something `gmax` should depend on

CEF internally decides renderer-process allocation according to Chromium process rules. The app should model pane-local browser instances, not renderer-process isolation.

## Why This Fits `gmax`

The current shell model already assumes that a leaf node hosts a view-sized interactive surface that:

- can be focused independently
- can be resized arbitrarily by split movement
- can be torn down without disturbing sibling panes
- can publish pane-local metadata back into the shell

That is already how terminal panes work today:

- `PaneLeaf`
- `TerminalPaneController`
- `TerminalPaneRepresentable`
- `TerminalHostingContainerView`

CEF fits the same structural shape well. The main change is not the pane tree. The main change is the hosted-surface backend and the bridge boundary.

## Recommended Integration Boundary

The preferred boundary is:

- Swift and SwiftUI own pane layout, focus, pane identity, commands, persistence, and inspector state
- Objective-C++ owns AppKit plus CEF object lifetime
- CEF C++ types stay inside `.mm` and `.hpp` implementation files

The app should not try to expose raw `CefRefPtr`, `CefBrowser`, `CefClient`, or similar CEF-heavy types directly to Swift.

## Why Objective-C++ Is Preferred Over Direct Swift C++ Interop

Modern Swift C++ interop is real and useful, but CEF is a poor candidate for a direct Swift-first integration surface.

Reasons:

- CEF APIs are inheritance-heavy and callback-heavy
- CEF uses intrusive ref-counted C++ object graphs
- CEF frequently exposes pointer and reference-oriented APIs
- renderer and browser callbacks are thread-affine and lifecycle-sensitive
- Swift C++ interop still has practical limits around imported inheritance relationships and reference-heavy APIs

Objective-C++ is the calmer seam because a single `.mm` file can:

- subclass AppKit types
- hold Objective-C delegates and notifications
- own CEF C++ handlers and `CefRefPtr` objects
- translate Cocoa lifecycle events into CEF calls

That keeps Swift out of the dangerous part of the embedding.

## Platform Guidance This Plan Relies On

This proposal depends on the following documented behavior:

- SwiftUI `NSViewRepresentable` creates the AppKit view in `makeNSView`, updates configuration in `updateNSView`, and supports cleanup in `dismantleNSView`.
- SwiftUI fully controls the hosted AppKit view's frame and bounds. The representable-managed view should not fight SwiftUI by setting those layout properties independently.
- AppKit child-view layout should be driven by Auto Layout constraints or standard AppKit layout rules.
- CEF supports creating browser instances as child views on macOS via `CefWindowInfo::SetAsChild(...)`.
- CEF also supports windowless rendering via `SetAsWindowless(...)`, but that mode is not the preferred first pass for pane-hosted browser content.
- On macOS, CEF message-loop integration uses the existing app message loop rather than the Windows/Linux `multi_threaded_message_loop` path.

References:

- Apple `NSViewRepresentable`: https://developer.apple.com/documentation/swiftui/nsviewrepresentable
- Apple `makeNSView(context:)`: https://developer.apple.com/documentation/swiftui/nsviewrepresentable/makensview(context:)
- Apple `updateNSView(_:context:)`: https://developer.apple.com/documentation/swiftui/nsviewrepresentable/updatensview(_:context:)
- Apple `dismantleNSView(_:coordinator:)`: https://developer.apple.com/documentation/swiftui/nsviewrepresentable/dismantlensview(_:coordinator:)
- Apple AppKit integration overview: https://developer.apple.com/documentation/swiftui/appkit-integration
- Apple AppKit layout overview: https://developer.apple.com/documentation/appkit/layout
- CEF general usage: https://chromiumembedded.github.io/cef/general_usage
- CEF tutorial: https://chromiumembedded.github.io/cef/tutorial
- CEF `CefWindowInfo`: https://cef-builds.spotifycdn.com/docs/128.3/classCefWindowInfo.html
- Swift C++ interop: https://www.swift.org/documentation/cxx-interop/

## One Browser Per Pane

The preferred pane-level primitive is:

- each web pane owns exactly one `CefBrowser`

That gives the app a clean mental model:

- one pane identity
- one host view
- one browser lifecycle
- one navigation state
- one set of pane-local callbacks

This matches how the shell already thinks about terminal panes.

What this does not mean:

- it does not guarantee one Chromium renderer process per pane
- it does not imply process-level isolation between arbitrary webpages

That distinction should be explicit in the product design and maintainer docs.

## Child-View Rendering vs Off-Screen Rendering

The recommended first pass is child-view hosting, not off-screen rendering.

Preferred first pass:

- create each browser as a child AppKit-hosted view
- let SwiftUI arrange pane containers
- let the Objective-C++ host attach the CEF browser view into the pane container

Why child-view hosting is preferred:

- it matches the current terminal-pane hosting model
- AppKit event routing is simpler
- resize behavior is more natural
- text input and focus handling are less exotic
- GPU and compositor behavior are less custom

Off-screen or windowless rendering should be treated as a later, explicit pivot only if the product needs one of these:

- custom cross-pane compositor effects
- deep visual blending between browser content and other pane surfaces
- rendering into custom layers instead of native child views
- browser surfaces that must draw into a non-view-backed canvas

Windowless mode is a conscious architectural pivot, not a default.

## Recommended Bridge Layout

The bridge should be narrow and explicit.

Swift-facing API surface:

- create a browser pane controller
- create or obtain the pane host `NSView`
- load a URL or HTML content
- navigate back and forward
- reload and stop loading
- focus the browser
- close the browser
- observe pane-local title, URL, loading, and crash state

Swift should not know about:

- `CefClient`
- `CefBrowserHost`
- `CefLifeSpanHandler`
- `CefDisplayHandler`
- `CefRequestHandler`
- renderer-process callbacks
- CEF ref-count semantics

## Proposed File Layout

This layout keeps the existing terminal integration shape while creating a parallel browser-pane path.

Suggested new surfaces:

- `gmax/Browser/BrowserPaneController.swift`
- `gmax/Browser/BrowserPaneRepresentable.swift`
- `gmax/Browser/BrowserPaneSession.swift`
- `gmax/Browser/BrowserPaneState.swift`

Suggested bridge surfaces:

- `gmax/BrowserBridge/GMAXBrowserPaneHostView.h`
- `gmax/BrowserBridge/GMAXBrowserPaneHostView.mm`
- `gmax/BrowserBridge/GMAXBrowserPaneController.h`
- `gmax/BrowserBridge/GMAXBrowserPaneController.mm`
- `gmax/BrowserBridge/CEF/GMAXCEFClient.hpp`
- `gmax/BrowserBridge/CEF/GMAXCEFClient.cpp`
- `gmax/BrowserBridge/CEF/GMAXCEFApp.hpp`
- `gmax/BrowserBridge/CEF/GMAXCEFApp.cpp`
- `gmax/BrowserBridge/CEF/GMAXCEFMessagePump.hpp`
- `gmax/BrowserBridge/CEF/GMAXCEFMessagePump.mm`

Suggested app bootstrap surfaces:

- `gmax/Browser/CEFRuntime.swift`
- `gmax/BrowserBridge/GMAXCEFRuntime.h`
- `gmax/BrowserBridge/GMAXCEFRuntime.mm`

The Swift side should only import the Objective-C headers.

## Recommended Swift-Side Model Additions

The shell should not replace the existing pane tree. It should generalize leaf content.

Current shape:

- `PaneLeaf` assumes terminal session identity

Preferred future shape:

```swift
enum PaneContent: Hashable, Codable {
    case terminal(TerminalSessionID)
    case browser(BrowserSessionID)
}

struct BrowserSessionID: RawRepresentable, Hashable, Codable, Identifiable {
    var rawValue: UUID
    var id: UUID { rawValue }
}

struct PaneLeaf: Identifiable, Hashable, Codable {
    var id: PaneID
    var content: PaneContent
}
```

This is a durable building-block change because it unlocks:

- terminal panes and browser panes in the same tree
- future previews, inspectors, or custom surface types
- pane duplication or replacement without special-casing the tree model

This should be preferred over adding a parallel browser-only pane tree.

## Proposed Browser Session Surface

The browser-side equivalent of `TerminalSession` should stay app-model-friendly.

Suggested first-pass fields:

```swift
@MainActor
final class BrowserPaneSession: ObservableObject {
    let id: BrowserSessionID

    @Published var title: String
    @Published var urlText: String
    @Published var isLoading: Bool
    @Published var canGoBack: Bool
    @Published var canGoForward: Bool
    @Published var lastError: BrowserPaneFailure?
}
```

This state is suitable for:

- pane title badges
- inspector content
- toolbar actions
- persistence of last-opened URLs if desired later

The browser session should not store:

- DOM snapshots
- renderer-process details
- CEF object references
- pixel buffers

## Proposed Controller Shape

The controller should mirror the existing `TerminalPaneController` role.

Suggested first pass:

```swift
@MainActor
final class BrowserPaneController {
    let session: BrowserPaneSession

    func load(url: URL)
    func reload()
    func stopLoading()
    func goBack()
    func goForward()
    func focus()
    func close()
}
```

Its job is:

- hold the Swift-facing pane session
- own the Objective-C++ bridge object
- translate UI actions into bridge calls
- translate bridge callbacks into published pane state

Its job is not:

- global CEF initialization
- app-wide process coordination
- browser creation outside its pane boundary

## Proposed View Shape

The browser-pane host should follow the same representable model already used by terminal panes.

Suggested SwiftUI shape:

```swift
struct BrowserPaneRepresentable: NSViewRepresentable {
    let controller: BrowserPaneController
    let isFocused: Bool
    let onFocus: () -> Void
}
```

The representable should:

- create the pane host view once in `makeNSView`
- attach the browser view there
- update focus or simple configuration in `updateNSView`
- tear down browser resources in `dismantleNSView`

The representable should not:

- create and destroy browsers repeatedly during ordinary SwiftUI updates
- issue layout mutations that fight SwiftUI sizing
- become the long-term owner of browser state

## Native Host View Responsibilities

The Objective-C++ host view is the crucial seam.

Its responsibilities:

- create a container `NSView`
- create the CEF browser as a child view inside that container
- keep the child browser view pinned to the container edges
- translate AppKit focus and visibility changes into browser-host signals
- own teardown behavior so browser shutdown is deterministic

This host view should be treated like `TerminalHostingContainerView`, but for a browser surface.

## Focus Model

`gmax` already has pane-level focus as a shell primitive. Browser panes should integrate into that same model.

Required behavior:

- clicking inside a browser pane should mark that pane focused in the shell
- shell focus changes should make the browser view first responder when appropriate
- inspector content should switch based on the focused pane, not based on browser-internal focus heuristics

What this means architecturally:

- shell focus remains authoritative
- browser focus is a consequence of shell focus, not a second competing source of truth

This is important because CEF has its own input and focus behaviors, and those should not be allowed to redefine the pane model.

## Resize Model

Browser panes must behave correctly during recursive split changes.

Requirements:

- SwiftUI controls the pane container size
- the AppKit host container fills the representable slot
- the CEF child view fills the AppKit host container
- split dragging should resize the browser surface live without requiring browser recreation

Recommended implementation:

- pin the child browser view with constraints or equivalent AppKit container layout
- do not treat resize as a navigation or lifecycle event
- if CEF requires explicit size notifications beyond normal child-view layout, issue them in the bridge layer only

The SwiftUI layer should continue to think in terms of pane frames, not browser-specific layout rules.

## Event and Callback Model

The bridge should collapse the large CEF callback surface into app-meaningful events.

Useful first-pass events:

- title changed
- main frame URL changed
- loading state changed
- navigation capabilities changed
- browser process terminated unexpectedly
- renderer became unresponsive if that surface is available
- load failed with a pane-meaningful error

The bridge should publish these into the Swift controller or delegate layer with descriptive, operator-friendly strings.

The app should avoid publishing low-level CEF callback noise into Swift unless the UI truly needs it.

## Message Loop Integration

CEF message-loop integration is a first-class design concern on macOS.

The app should assume:

- CEF browser-process work needs to be integrated with the app's existing run loop
- the Windows/Linux `multi_threaded_message_loop` path is not the macOS answer

The preferred architecture is:

- one app-wide CEF runtime bootstrap
- one app-wide message-pump integration surface
- pane controllers create browsers only after the runtime is initialized

This should be an application service, not a pane-local concern.

Suggested runtime responsibilities:

- initialize CEF once
- configure framework/resource paths
- configure helper-subprocess path
- install message-pump integration
- perform orderly shutdown on app termination

## App Bundle and Packaging Realities

CEF on macOS is not just a code dependency. It is an app-bundle and helper-process integration project.

The integration plan must account for:

- `Chromium Embedded Framework.framework` in the app bundle
- the helper app required by Chromium/CEF
- correct `Resources` placement for CEF pack files and locales
- code signing of the main app, framework, and helper app
- notarization implications
- Xcode project integration without unsafe `.pbxproj` surgery

This is one of the reasons a proof of concept can be moderate effort while productionization is significantly harder.

The first milestone should separate:

- browser-pane API proof of concept
- app bundle packaging and distribution hardening

## Credential and Profile Sharing Reality

`gmax` should not plan on sharing a user's installed Google Chrome profile directly with CEF.

Current recommendation:

- do not mount or reuse Chrome's live user-data directory
- do not design around direct sharing of Chrome password storage
- do design explicit auth migration or session import flows if continuity matters

Reasons:

- CEF and Chrome are separate Chromium-based applications with separate runtime ownership
- live profile sharing is not a supported app-level contract
- Chromium user-data directories are not designed for concurrent cross-application access
- password storage is tied to Chromium internals and platform credential protections

This should be treated as a product and security constraint, not as an implementation detail we expect to smooth over later.

## What Can Potentially Be Shared

The only realistic first-pass continuity target is session state, not whole-profile state.

Possible targets:

- site cookies
- app-owned auth tokens
- last-visited URLs
- browser-pane restoration state

Poor targets for a first implementation:

- Chrome browsing history import
- Chrome extensions
- Chrome profile preferences
- Chrome password database reuse
- direct live reuse of a Chrome profile directory

## Cookie Continuity Direction

If browser sign-in continuity matters, the safest maintainable direction is explicit cookie or token migration.

That means:

- `gmax` owns its own browser storage through CEF configuration
- `gmax` optionally imports narrowly scoped session material into that storage
- imported state is treated as app-managed data after import

The plan should not depend on:

- two running apps sharing one cookie database
- using Chrome's active user-data directory as CEF's `cache_path`
- file-level cookie copying as a normal runtime mechanism

At most, file copying is a brittle offline migration technique when no browser is running and versions align. It is not a normal product architecture.

## Password and Credential Direction

There should be a strong bias against promising direct password reuse from a local Chrome install.

Recommended posture:

- do not claim Chrome password-store sharing
- do not assume CEF can attach to the user's installed Chrome credential database
- treat password import as a separate, explicit feature only if the product truly needs it

If credential continuity becomes important, the preferred product order is:

1. token or cookie import for known auth domains
2. explicit sign-in flows inside `gmax`
3. optional import/export tooling with clear user consent

Direct password-database reuse should be considered unlikely and high-risk until proven otherwise in a narrow, documented spike.

## Product Recommendation For Auth Continuity

If `gmax` adds browser panes and wants a practical continuity story, the preferred first-pass model is:

- app-owned CEF browser state
- optional session import for specific sites or auth domains
- no promise of direct Chrome profile compatibility

This is the least surprising approach for maintainers and the safest one to explain to users.

It also keeps the pane architecture clean:

- browser pane lifecycle remains app-owned
- credential movement becomes an explicit feature surface
- auth migration does not distort the browser-hosting architecture

## Licensing Direction For `gmax`

If `gmax` becomes source-available rather than fully open source, the recommended first candidate is the Functional Source License (`FSL`) with a later conversion to a permissive license.

Why `FSL` is currently the best middle-ground fit:

- it is source-available rather than closed
- it is designed to block competing commercial use in the near term
- it later converts each covered release to a permissive open-source license
- it is easier to explain to developers than a pure noncommercial license

This fits a project that wants:

- meaningful protection while the maintainer is still trying to build a viable business or support path
- a future path where old releases become broadly reusable

References:

- FSL overview: https://fsl.software/
- Fair Source licenses: https://fair.io/licenses/
- FSL 1.1 Apache variant: https://spdx.github.io/license-list-data/FSL-1.1-ALv2.html
- FSL 1.1 MIT variant: https://spdx.github.io/license-list-data/FSL-1.1-MIT.html
- PolyForm Perimeter overview: https://polyformproject.org/licenses/perimeter/
- PolyForm Perimeter 1.0.0: https://polyformproject.org/licenses/perimeter/1.0.0

## `FSL` vs `Perimeter`

The practical distinction is:

- `FSL` is a time-limited anti-competition license with later permissive conversion
- `Perimeter` is a stronger permanent no-compete source-available license

`FSL` is the better fit when the project wants:

- protection against a business or funded company taking the code into a competing product or service now
- a future where older releases become permissive
- a licensing posture that is more ecosystem-friendly than a permanent no-compete

`Perimeter` is the better fit when the project wants:

- the strongest long-term anti-competition wall
- protection even against free competing products in the broadest sense
- no automatic future conversion to permissive open source

## Important `FSL` Limitation

`FSL` is strong against business-backed or commercial competition, but it is not as broad as `Perimeter` against every imaginable free competitor.

Maintainer expectation should be:

- `FSL` is aimed at blocking competing use in a commercial product or service
- `FSL` is a good fit for the fear that a company will take `gmax` code and fold it into its own business-backed offering
- `FSL` is less absolute than `Perimeter` if the concern is every possible noncommercial or hobbyist free clone

That tradeoff is the cost of choosing the more moderate license family.

## Current Licensing Recommendation

If `gmax` changes license later, the current recommendation is:

1. prefer `FSL` over a plain noncommercial license
2. choose `Perimeter` only if later evidence shows `FSL` is too permissive for the actual threat model
3. document clearly that `gmax` is source-available during the protected window and only later converts to permissive open source

This keeps the project aligned with a middle-ground posture:

- protected while the maintainer is still trying to make the project viable
- not permanently sealed off if viability never materializes

## CEF Runtime Placement Inside `gmax`

The preferred runtime ownership point is near app startup, not inside the first pane that happens to open.

That means:

- initialize CEF from app-level bootstrap code
- fail early and visibly if the runtime cannot initialize
- keep pane creation blocked until runtime health is known

Suggested direction:

- `gmaxApp` or an app-level shell coordinator owns the runtime bootstrap
- browser-pane controllers depend on that runtime being available

This avoids a fragile model where pane creation races against CEF initialization.

## Inspector and Command Integration

A browser pane should plug into the same shell UX surfaces already used by terminal panes.

Good first-pass inspector content:

- page title
- current URL
- loading state
- back/forward availability
- last load failure or crash state

Good first-pass commands:

- open URL
- reload
- stop loading
- go back
- go forward
- duplicate pane with same URL later, if that becomes useful

These commands should operate at the `BrowserPaneController` level.

## Persistence Direction

The existing workspace and pane persistence model should be extended, not replaced.

Persistable first-pass browser state:

- pane content kind
- browser session identifier
- optional last URL text

Probably not worth persisting initially:

- navigation history stack
- scroll position
- live loading state
- process health

The durable goal is workspace restoration, not browser-session forensics.

## Crash and Failure Design

Browser panes will introduce new failure classes that terminal panes do not have.

The product should treat these as pane-local failures wherever possible:

- invalid URL input
- load failures
- browser process termination
- renderer crash or hang
- helper process startup failure

Recommended product rule:

- a broken browser pane should degrade that pane, not destabilize the shell

That implies:

- descriptive pane-local error state
- ability to recreate the browser for that pane
- shell model survives browser recreation

## What Not To Do

The first implementation should avoid these traps:

- do not expose raw CEF classes directly to SwiftUI
- do not make SwiftUI views the owners of browser lifecycle
- do not design around one renderer process per pane
- do not start with windowless rendering unless the product clearly requires it
- do not fork the pane tree into a separate browser-layout model
- do not hide CEF runtime initialization inside ad hoc pane code
- do not let browser-specific state become the shell's source of truth for focus or layout

## Suggested Milestones

### Milestone 1: Feasibility Spike

Goal:

- prove one CEF browser can live inside one AppKit host view inside one SwiftUI `NSViewRepresentable`

Deliverables:

- app-level CEF bootstrap
- one browser-pane host view
- one hard-coded test URL
- clean resize and focus behavior
- deterministic teardown

Success criteria:

- browser content renders in a pane-sized surface
- split resizing works
- focus can move in and out without breaking shell commands

### Milestone 2: Pane-Model Integration

Goal:

- generalize `PaneLeaf` content from terminal-only to terminal-or-browser

Deliverables:

- `PaneContent`
- `BrowserSessionID`
- `BrowserPaneSession`
- `BrowserPaneController`
- browser pane rendering path in `WorkspacePaneTreeView`

Success criteria:

- terminal and browser panes coexist in the same recursive split tree
- shell focus and inspector state continue to behave correctly

### Milestone 3: Navigation and Inspector Surface

Goal:

- make browser panes actually usable

Deliverables:

- URL loading
- back/forward/reload
- pane-local title and URL reporting
- inspector data for browser panes

Success criteria:

- browser pane state feels like a first-class shell citizen

### Milestone 4: Packaging Hardening

Goal:

- make the integration survivable outside a local dev machine

Deliverables:

- helper app integration
- framework/resource placement
- code signing and notarization validation path
- maintainer build notes for Xcode integration

Success criteria:

- reproducible local build
- predictable launch behavior
- maintainable packaging story

## Difficulty Assessment

Relative to ordinary SwiftUI feature work, this is hard.

Rough breakdown:

- pane-hosting proof of concept: moderate to hard
- maintainable bridge layer: moderate
- shell-model integration: moderate
- packaging and signing story: hard
- production-quality browser-pane UX: hard

The integration is feasible, but it is not cheap. Most of the complexity is not in split-pane layout. Most of the complexity is in:

- bridge correctness
- app bundle integration
- lifecycle management
- failure isolation

## Current Recommendation

If `gmax` pursues browser panes, the preferred plan is:

1. keep the existing recursive pane tree
2. generalize leaf content from terminal-only to terminal-or-browser
3. use one `CefBrowser` per browser pane
4. host each browser in its own AppKit container view
5. bridge through Objective-C++ rather than direct Swift-first C++ interop
6. keep CEF runtime bootstrap app-global and browser lifecycle pane-local
7. start with child-view hosting, not off-screen rendering
8. assume app-owned browser storage rather than Chrome-profile sharing
9. treat bundle integration and helper-process packaging as an explicit later milestone

That is the least surprising architecture for maintainers and the best fit for the shell structure `gmax` already has.
