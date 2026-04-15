/*

This note captures what SwiftTerm already owns as an AppKit terminal surface,
what gmax is currently layering on top of it, and which integration direction
looks safest for the workspace focus redesign.

The goal is to separate pane-level workspace focus from terminal-level first
responder, selection, and text interaction behavior. SwiftTerm already provides
substantial AppKit behavior in that second category, so this note exists to
keep us from reimplementing or fighting the framework and library surfaces that
already exist.

*/

# SwiftTerm Surface Investigation

## Purpose

This note answers a narrow architectural question:

- What does [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) already own?
- What are we currently wrapping or overriding in `gmax`?
- Where is the cleanest seam between workspace pane focus and terminal text/input behavior?

This is a companion to:

- [workspace-focus-removal-and-redesign-notes.md](workspace-focus-removal-and-redesign-notes.md)
- [workspace-focus-target-plan.md](workspace-focus-target-plan.md)

## Primary References

- SwiftTerm repository:
  - <https://github.com/migueldeicaza/SwiftTerm>
- SwiftTerm README:
  - <https://github.com/migueldeicaza/SwiftTerm/blob/main/README.md>
- SwiftTerm API docs:
  - `TerminalView`: <https://migueldeicaza.github.io/SwiftTerm/Classes/TerminalView.html>
  - `LocalProcessTerminalView`: <https://migueldeicaza.github.io/SwiftTerm/Classes/LocalProcessTerminalView.html>
  - `TerminalViewDelegate`: <https://migueldeicaza.github.io/SwiftTerm/Protocols/TerminalViewDelegate.html>
  - `LocalProcessTerminalViewDelegate`: <https://migueldeicaza.github.io/SwiftTerm/Protocols/LocalProcessTerminalViewDelegate.html>

## What SwiftTerm Already Owns

SwiftTerm is not just a rendering canvas. On macOS, `TerminalView` is already an
AppKit `NSView` control that participates in the responder chain and text-input
system.

Based on the SwiftTerm docs and source:

- `TerminalView` is an `NSView` control, not a passive draw-only surface.
- `TerminalView` already participates in first-responder behavior.
- `TerminalView` already supports text selection.
- `TerminalView` already validates standard menu items such as copy, select all,
  and find-related actions.
- `TerminalView` already implements built-in search and the macOS find bar.
- `TerminalView` already owns mouse-driven selection behavior.
- `TerminalView` already models terminal-specific tradeoffs such as mouse
  reporting conflicting with normal text selection.

This means the terminal surface itself is already the correct home for:

- prompt input
- scrollback selection
- copy/select-all availability
- find-in-terminal behavior
- first-responder text handling

Those are terminal-surface concerns, not workspace-layout concerns.

## What `LocalProcessTerminalView` Adds

`LocalProcessTerminalView` is SwiftTerm's convenience subclass for a local PTY.
It wires a `TerminalView` to a local process.

The important design constraint from the docs and source is:

- `LocalProcessTerminalView` already uses `TerminalView`'s delegate internally.
- Host applications are expected to use `processDelegate` for process-level
  signals.
- If a host app needs more control than that reduced delegate surface provides,
  SwiftTerm explicitly recommends subclassing `LocalProcessTerminalView`.

That recommendation matters for us. It means the most natural extension point is
not "keep bolting external gesture and responder behavior onto the outside of
the view." The natural extension point is "subclass the terminal host view if we
need terminal-specific policy or hooks."

## What `gmax` Currently Wraps Around SwiftTerm

The current wrapper lives mainly in:

- `gmax/Terminal/Panes/TerminalPaneController.swift`
- `gmax/Terminal/Panes/TerminalPaneHostView.swift`
- `gmax/Terminal/Panes/TerminalPaneView.swift`
- `gmax/Terminal/Panes/TerminalPaneView+Coordinator.swift`
- `gmax/Scenes/WorkspaceWindowGroup/NavigationSplitView/ContentPanel/ContentPaneLeafView.swift`

Today that wrapper does several distinct jobs:

### 1. Process/session lifecycle

This part is healthy and clearly belongs outside SwiftTerm:

- create or retain a terminal host for a pane session
- start the local process
- reconnect to restored session state
- capture transcript for persistence
- observe terminal title and current-directory updates

### 2. Workspace pane focus signaling

This part is currently custom and tied to the workspace model:

- `ContentPaneLeafView` still receives an `isFocused` flag, but that flag is now derived from scene-owned SwiftUI focus
- tapping the pane now updates the scene-local `@FocusState`
- `Workspace.focusedPaneID` still exists as persisted workspace metadata, but it is no longer the live runtime source of truth for pane focus
- pane close command publication now follows scene-local focus rather than store-owned focus

This is the part we already expect to redesign toward native SwiftUI focus.

### 3. Terminal responder forcing

This is where the wrapper is currently fighting the terminal surface a bit:

- `updateNSView` forces `window?.makeFirstResponder(terminalView)` whenever
  `isFocused` is true
- a custom click gesture recognizer is installed on the SwiftTerm view
- the click handler calls `onFocus()` and then forces first responder
- accessibility "Focus Pane" also forces first responder

This means our wrapper is currently trying to synchronize:

- workspace pane focus
- SwiftUI view activation
- AppKit first responder
- SwiftTerm terminal focus

with one custom path.

That is exactly the kind of coupling the focus redesign should break apart.

## What This Suggests About Prompt vs Scrollback

At this stage of the project, prompt versus scrollback is a terminal
interaction distinction, not a scene-command distinction.

That matches both our current product intent and SwiftTerm's surface:

- SwiftTerm presents one terminal control with internal selection, search, and
  input behavior.
- The docs and source do not present prompt and scrollback as two independent
  host views.
- Copy, selection, find, and text input are already handled inside the terminal
  control.

This is now the settled model for `gmax`:

- the pane is the workspace-level command target
- the terminal view is the text/input/responder surface inside that pane
- prompt versus scrollback remains an internal terminal interaction difference
  owned by SwiftTerm
- `gmax` should not add a parallel prompt-versus-scrollback focus or command
  model unless later product work proves SwiftTerm's existing behavior
  insufficient

That is a much cleaner boundary than trying to model prompt and scrollback as
separate scene-level focus targets today.

## Where Our Current Wrapper Is Most Fragile

The current integration has a few likely pain points:

### Forced responder sync in `updateNSView`

Forcing first responder whenever `isFocused` is true makes the terminal's
AppKit focus follow a workspace-model boolean. That is the reverse of the native
flow we likely want.

### Custom click recognizer installation

We currently remove SwiftTerm click recognizers and install our own
`NSClickGestureRecognizer`. That is risky because SwiftTerm already owns mouse
interaction and selection behavior. Even when this works today, it increases the
chance that we are shadowing or subtly changing terminal-native behavior.

### Mixed responsibility in `ContentPaneLeafView`

`ContentPaneLeafView` is currently carrying:

- pane-level visual container behavior
- workspace-level focused-pane publishing
- terminal hosting
- pane overlay UI
- accessibility affordances
- geometry reporting for directional focus

That is too many concerns for the focus redesign. Even if the type stays in one
file for a while, the design boundary wants to become clearer.

## Most Likely Integration Options

### Option A: Keep `LocalProcessTerminalView`, but subclass it

This is the most likely near-term best path.

Why:

- it preserves SwiftTerm's built-in local process handling
- it follows SwiftTerm's documented extension guidance
- it gives us a place for terminal-specific host behavior without overloading
  the SwiftUI wrapper
- it keeps terminal behavior close to the terminal surface

This would let us move terminal-specific policy into a terminal-side type while
letting SwiftUI own pane-level focus and command publication separately.

### Option B: Drop down to `TerminalView` directly and own `LocalProcess`

This is the lower-level, more powerful option.

Why we might want it later:

- full control over the transport and delegate model
- no convenience-subclass constraints
- cleaner separation if `LocalProcessTerminalView` proves too opinionated

Why it is probably not the first move:

- it widens scope significantly
- it requires us to take on more PTY/process plumbing immediately
- it solves a bigger problem than we have proven yet

### Option C: Keep the current wrapper shape and refine it

This is the least attractive option.

Why:

- it preserves the current mixed focus/responder coupling
- it keeps us in a model where pane focus truth drives terminal responder truth
- it risks continuing to fight SwiftTerm's built-in AppKit behavior

This may be acceptable as a stopgap, but it does not look like the durable model.

## Current Recommendation

The current best recommendation is:

1. Treat the pane as the workspace-level command target.
2. Treat the SwiftTerm view as the terminal text/responder surface inside that pane.
3. Stop using the workspace model as the live source of truth for terminal first
   responder.
4. Rebuild pane focus around native SwiftUI focus first.
5. If terminal-specific integration hooks are still needed after that, subclass
   `LocalProcessTerminalView` rather than continuing to bolt custom click and
   responder behavior onto it externally.

In other words:

- SwiftUI should own which pane is the active pane.
- SwiftTerm should own how terminal input, selection, search, and text behavior
  work once that pane's terminal surface is active.

That gives each layer a cleaner job.

## Concrete Follow-up Questions

Before implementation, we should answer these:

1. Can pane activation become a native `@FocusState`-driven concept without
   forcing first responder from `updateNSView`?
2. Can the terminal surface become first responder only in response to actual
   activation/click/focus transitions instead of every render update?
3. Is our custom click recognizer still needed once pane focus is modeled
   natively?
4. Which current accessibility actions are truly pane-level actions, and which
   should remain terminal-surface behavior?
5. Does `ContentPaneLeafView` want to split into a pane container plus a
   terminal-host subview during the redesign?

## Provisional Conclusion

SwiftTerm already provides the right primitive for a single terminal surface
that contains prompt input, scrollback, selection, and find/copy behavior.

So the main architectural job in `gmax` is not to invent a second terminal focus
system. It is to:

- define the correct workspace-level focus targets
- let SwiftUI own pane-level focus and command context
- let SwiftTerm own terminal-native responder and text behavior
- use subclassing or narrower terminal-side extension points only where the
  existing SwiftTerm surface is insufficient
