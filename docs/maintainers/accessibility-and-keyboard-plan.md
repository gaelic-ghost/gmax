# Accessibility And Keyboard Plan

## Purpose

This note maps the accessibility and keyboard-work plan for the current `gmax` shell before `v0.1.0`.

It is intentionally maintainer-facing. The goal is to describe:

- which user-facing surfaces need explicit accessibility work
- which parts should rely on built-in SwiftUI or AppKit behavior
- where the custom pane tree and SwiftTerm host create risk
- which gaps are acceptable for a first usable internal build and which are not

This document is planning guidance, not a claim that the current app already meets these expectations.

## Apple Platform Expectations This Plan Relies On

This plan is grounded in documented Apple behavior:

- SwiftUI standard controls, lists, text fields, buttons, and navigation structures already expose baseline accessibility behavior by default.
- SwiftUI expects apps to add explicit labels, values, focus handling, and accessibility actions where custom views or custom interaction models would otherwise be ambiguous.
- SwiftUI provides `focusable(_:, interactions:)` and `focusSection()` to shape keyboard focus behavior for custom view hierarchies on macOS.
- SwiftUI provides `accessibilityElement(children:)`, `accessibilityChildren`, and `accessibilityRepresentation` for custom accessibility containers and custom controls.
- SwiftUI provides `accessibilityAction` and related modifiers so assistive technologies can invoke the same app actions as pointer users.
- When SwiftUI hosts AppKit content through `NSViewRepresentable`, the app is responsible for ensuring that the hosted AppKit view exposes meaningful accessibility information if the underlying view does not already do so.
- AppKit views inherit baseline accessibility behavior through `NSAccessibilityProtocol`, and custom `NSView` subclasses are expected to customize or extend that behavior directly when defaults are insufficient.
- If a custom user-interface element does not map cleanly to an `NSView`, AppKit expects the app to expose `NSAccessibilityElement` children explicitly.

Primary references:

- SwiftUI Accessibility fundamentals: https://developer.apple.com/documentation/swiftui/accessibility-fundamentals
- SwiftUI Accessibility modifiers: https://developer.apple.com/documentation/swiftui/view-accessibility
- SwiftUI `focusSection()`: https://developer.apple.com/documentation/swiftui/view/focussection()
- SwiftUI `focusable(_:,interactions:)`: https://developer.apple.com/documentation/swiftui/view/focusable(_:interactions:)
- AppKit Accessibility for AppKit: https://developer.apple.com/documentation/appkit/accessibility-for-appkit
- AppKit `NSAccessibilityProtocol`: https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol
- AppKit Custom Controls: https://developer.apple.com/documentation/appkit/custom-controls
- AppKit `NSAccessibilityElement`: https://developer.apple.com/documentation/appkit/nsaccessibilityelement-swift.class

## Accessibility Goals For `v0.1.0`

For the first usable internal build, `gmax` should meet these practical expectations:

- every primary shell action is reachable without a mouse
- pane focus is obvious visually and understandable audibly
- the workspace sidebar, inspector, toolbar, dialogs, and saved-workspace sheet behave like normal accessible macOS UI
- custom pane surfaces expose enough metadata and actions that VoiceOver and Full Keyboard Access users can understand which pane is active and what actions are available
- known accessibility limitations in the embedded terminal surface are explicit and documented instead of being accidental

This does **not** require `v0.1.0` to make every interactive terminal application inside SwiftTerm fully accessible. That terminal-emulator problem is materially harder and may remain a known limitation for the internal release as long as the shell-level accessibility story is honest and usable.

## Cross-Cutting Implementation Principles

### Prefer Native Semantics First

Where the app uses standard SwiftUI surfaces such as `List`, `Button`, `TextField`, sheets, alerts, search fields, and command menus, prefer the built-in semantics and only add targeted labels, values, hints, or action names where the default phrasing would be vague.

### Keep Pointer And Accessibility Actions Aligned

Any action available from a context menu, toolbar, or inline button should also be reachable from:

- a menu command or keyboard shortcut where that action is part of the main workflow
- a VoiceOver or accessibility action where the action is pane-local or row-local

The accessible path should invoke the same underlying model operation as the pointer path.

### Make Focus State A First-Class Shell Primitive

`WorkspaceStore` already treats focused-pane identity as real state. The accessibility and keyboard story should build on that instead of inventing a second focus model. Visual focus, keyboard focus, and accessible focus should all describe the same active pane as often as the platform allows.

### Be Honest About The AppKit Boundary

The SwiftUI shell can be made accessible with view modifiers and focus helpers. The embedded terminal host is different: it crosses into `NSViewRepresentable` and `LocalProcessTerminalView`. The plan should explicitly separate:

- shell accessibility, which `gmax` owns directly
- terminal-emulator accessibility, which may require AppKit overrides or SwiftTerm-local work

## Surface Plans

## Sidebar

### Current Shape

The workspace sidebar is a SwiftUI `List(selection:)` with:

- one row per workspace
- contextual workspace actions in a context menu
- rename and delete flows through a sheet and alert

### Plan

- Keep the `List` as the primary accessible container because it already matches macOS expectations for row selection and keyboard navigation.
- Make each row read as a concise grouped summary:
  - primary label: workspace title
  - value: pane count
  - optional secondary detail only when it adds meaning
- Ensure every contextual action available from the row context menu is also available from the command surface or a visible button path.
- Verify rename-sheet and delete-alert copy so VoiceOver reads the target workspace name and the consequence clearly.

### Risks

- The current row content uses stacked `Text` views, which may read acceptably or may become too verbose depending on VoiceOver grouping.
- If the context menu remains the only obvious route to certain row-local actions, Full Keyboard Access users may still discover those actions poorly even though the menu exists.

### macOS Alignment Notes

- `List` selection should remain the primary navigation pattern here; do not replace it with a custom tap-only sidebar.
- Contextual actions should stay supplemental. Primary lifecycle actions should remain available through commands and visible controls.

## Toolbar And Command Surface

### Current Shape

The app already exposes meaningful menu commands and keyboard shortcuts for workspaces, panes, close behavior, and inspector visibility.

The current command surface is also frontmost-window scoped:

- the main shell uses a `WindowGroup`
- each shell window owns scene-local selection plus sidebar and inspector visibility
- menu commands resolve through `focusedSceneValue` instead of one app-global selection binding

### Plan

- Treat the command surface as part of accessibility, not just power-user polish.
- Keep keyboard shortcuts stable and discoverable in menus.
- Ensure toolbar buttons and matching menu commands use the same terminology so Voice Control and keyboard users are not learning two vocabularies for the same action.

### Risks

- If toolbar labels and menu section titles drift apart, Voice Control and spoken-navigation users get a worse experience even when all actions technically exist.
- If command routing, toolbar focus, and scene-local selection disagree, a keyboard or spoken-navigation user may act on the wrong window even though the command itself succeeded.

### macOS Alignment Notes

- On macOS, menu commands are part of the accessibility story. They should stay canonical and descriptive.

## Pane Tree

### Current Shape

The pane tree is a custom SwiftUI composition:

- recursive split containers
- custom draggable split dividers
- pane cards that host `TerminalPaneView`
- pane focus driven by `WorkspaceStore.focusedPaneID`
- pane activation currently triggered mainly by click or commands

### Plan

#### Pane Card Semantics

- Make each pane card a deliberate custom accessibility element instead of relying on the raw stacked overlay structure.
- Give each pane card:
  - accessibility label: pane title or a stable fallback like "Shell pane"
  - accessibility value: focused state, running or exited state, and current directory when available
  - accessibility actions: Restart Shell, Split Right, Split Down, Close Pane
- Treat the pane card as a focusable custom control for keyboard navigation, not just a painted background around an AppKit child view.
- Status:
  - implemented as pane-level labels, values, hints, selected-state traits, and custom actions on `PaneLeafCard`
  - still needs manual validation for VoiceOver phrasing, focus order, and Full Keyboard Access behavior

#### Keyboard Focus Shape

- Use SwiftUI focus helpers intentionally around the pane tree.
- Apply `focusSection()` to the pane-tree region so sequential keyboard movement stays within the pane cohort in a predictable order before escaping to adjacent shell chrome.
- Evaluate `focusable(interactions: .activate)` or a similar constrained focus interaction on pane cards so they participate in keyboard navigation without pretending to be generic button rows.
- Keep pane focus changes routed through scene-owned SwiftUI focus state so the visual highlight, inspector, and command context remain synchronized without restoring store-owned runtime focus.
- Status:
  - `focusable(interactions: .activate)` is already applied to pane cards
  - the remaining work is to validate how that behaves against the embedded terminal host and decide whether additional focus shaping is still needed

#### Split Divider Accessibility

- Decide whether split dividers need direct accessibility exposure for `v0.1.0` or whether pane-local split commands are sufficient for the internal build.
- If direct divider accessibility is required, expose it as an adjustable control with increment/decrement semantics rather than as a pointer-only drag strip.
- If direct divider accessibility is deferred, document that split sizing remains pointer-driven while pane-local split creation and pane focus remain keyboard-accessible.

### Risks

- This is the highest-risk shell surface because it is a custom layout with custom hit-testing and no built-in row or button semantics.
- The current pane card is primarily a `ZStack` with `.onTapGesture`, which gives little semantic guidance to VoiceOver or Full Keyboard Access by itself.
- If pane cards become separately focusable while the embedded terminal view also takes first responder, keyboard focus and accessible focus can diverge unless the relationship is managed deliberately.
- Split dividers are especially likely to be inaccessible if they remain purely drag-based.

### macOS Alignment Notes

- Custom interactive regions on macOS should expose a clear control role, stable label, and predictable keyboard activation path.
- Focus should not jump unpredictably between panes and shell chrome when tabbing or using Full Keyboard Access.

## Embedded Terminal Host (`NSViewRepresentable` + SwiftTerm)

### Current Shape

`TerminalPaneView` hosts `LocalProcessTerminalView` inside `TerminalPaneHostView`, and the hosted view becomes first responder when the pane is focused.

### Plan

#### First Phase: Shell-Level Accessibility Around The Terminal

- Ensure the surrounding pane card exposes enough metadata that users can identify:
  - which pane is active
  - whether the shell is running or exited
  - what directory or title the pane represents
  - which pane-local actions are available
- This shell-level layer should exist even if SwiftTerm itself is imperfect with VoiceOver.
- Status:
  - implemented for pane cards and split dividers in the SwiftUI pane tree
  - implemented for the AppKit host container as pane-level label, value, help text, and custom actions without replacing the underlying terminal view's own semantics

#### Second Phase: Evaluate The AppKit View Directly

- Inspect `LocalProcessTerminalView` behavior under VoiceOver and Full Keyboard Access before making architectural promises.
- If the view already exposes useful text and focus behavior, keep the wrapper light and only add labels or focus coordination where needed.
- If the view exposes weak or confusing semantics, customize the AppKit side explicitly through `NSAccessibilityProtocol` overrides on the host view or through child accessibility elements.
- Current finding:
  - `LocalProcessTerminalView` inherits from SwiftTerm's `TerminalView`, which already posts accessibility notifications when terminal content changes
  - the SwiftTerm checkout used by the project still appears to have limited macOS-specific accessibility service implementation depth, so `gmax` should currently treat deep live-terminal accessibility as a validation risk rather than an already-solved dependency capability
  - for `v0.1.0`, prefer a small host-container bridge that describes the pane and exposes pane-local actions, then validate the live terminal surface manually before promising more

#### Likely AppKit Considerations

- the host view may need an explicit accessibility label or role
- the host view may need to expose shared focus or child relationships so the shell-level pane summary and the terminal surface do not feel unrelated
- if the terminal content itself is not meaningfully accessible, the app may need a separate accessibility summary or representation for shell metadata while documenting the live-terminal limitation honestly

### Risks

- This is the biggest technical unknown in the entire accessibility plan.
- TUI-style terminal content can be difficult to expose well even when the surrounding app shell is accessible.
- If the terminal view captures first responder aggressively, Full Keyboard Access may have trouble reaching adjacent shell chrome.
- If `SwiftTerm` lacks the needed AppKit accessibility hooks, `gmax` may need a local extension path or a maintained fork for serious terminal-surface accessibility work.

### macOS Alignment Notes

- Standard AppKit views come with baseline accessibility, but custom `NSView` subclasses are expected to customize their own `NSAccessibilityProtocol` behavior when defaults are not enough.
- `gmax` should not assume that `NSViewRepresentable` automatically makes a custom terminal host accessible.

## Inspector

### Current Shape

The inspector is now a standard SwiftUI inspector surface showing:

- workspace
- title
- state
- current directory
- pane and session IDs

### Plan

- Keep the inspector as a standard SwiftUI information surface that stays aligned with focused-pane state.
- Group the metadata blocks with concise accessibility labels so they read as intentional sections rather than a flat wall of text.
- Consider de-emphasizing raw IDs for general navigation while leaving them selectable for debugging; they should not dominate the VoiceOver reading order.

### Risks

- The current inspector includes UUID-heavy details that are useful for debugging but noisy for spoken output.
- If the inspector reads every field literally in order, it may become tedious and distract from the pane identity and state users actually need.

### macOS Alignment Notes

- This surface should feel like a normal inspector: concise labels, grouped metadata, and ordinary accessible buttons.

## Saved-Workspace Library Sheet

### Current Shape

The saved-workspace library is a SwiftUI sheet with:

- `searchable`
- a `List(selection:)`
- Open and Delete buttons
- row preview text and timestamps

### Plan

- Keep the sheet structure because it already matches accessible macOS search-and-list patterns.
- Ensure each row combines:
  - title
  - pane count
  - relative timestamp
  - preview text only when it adds signal
- Confirm the default action remains the Open button and that keyboard users can search, arrow through rows, and press Return to open predictably.
- Verify that empty-state copy clearly distinguishes “no saved workspaces exist” from “no rows matched the search.”

### Risks

- Row summaries may become too verbose if preview text always participates in the spoken summary.
- Double-click-to-open is fine as a pointer affordance, but keyboard users still need an obvious default-action path.

### macOS Alignment Notes

- Search field + selectable list + explicit default action is the expected macOS shape here and should stay the backbone of the interaction model.

## Alerts, Sheets, And Empty States

### Plan

- Review all alerts and confirmation copy for concrete consequences.
- Ensure empty states name the missing thing and the recovery action plainly.
- Keep default actions and cancel actions explicit so keyboard users always know how to proceed.

### Risks

- The app already has a few meaningful empty states, but they need consistency so spoken output sounds intentional instead of ad hoc.

## Verification Plan

## Automated Checks

Automated tests can confirm only part of the story:

- shell commands continue to work
- the sidebar delete-confirmation flow still presents, cancels, and confirms correctly
- the saved-workspace library still opens, reopens, and deletes snapshots predictably

They will not prove VoiceOver or Full Keyboard Access quality by themselves.

For shell-driven XCUITest runs, keep failure diagnostics minimal and text-first. Avoid automatic hierarchy or capture-based debug output, and prefer stable accessibility identifiers plus human-readable failure messages. When deeper structure inspection is needed, prefer a manual Accessibility Inspector pass instead of expanding the automated test harness.

## Manual Accessibility Pass

For each release candidate:

1. Run a keyboard-only pass without using the mouse.
2. Run a Full Keyboard Access pass and record any unreachable controls.
3. Run a VoiceOver pass over:
   - sidebar
   - toolbar
   - pane tree
   - inspector
   - saved-workspace sheet
4. Run a multi-window command-routing pass:
   - open a second shell window
   - select different workspaces in each window
   - confirm `New Pane`, `Save Workspace`, `Open Workspace…`, `Close Workspace`, and `Delete Workspace` follow the frontmost window
   - confirm keyboard focus and spoken focus do not leave the wrong window appearing active
5. Record whether the terminal surface itself is:
   - meaningfully accessible
   - partially usable but limited
   - effectively inaccessible for live terminal content

## Release-Gating Guidance For `v0.1.0`

The following should be treated as release blockers for the first internal build:

- a primary shell action is unreachable without a mouse
- pane focus cannot be identified reliably by sight or speech
- the saved-workspace library cannot be searched and opened from the keyboard
- alerts or confirmations are too vague to explain what will close or be deleted

The following may be acceptable as documented known limitations for `v0.1.0`:

- incomplete accessibility of live terminal buffer content inside SwiftTerm
- pointer-only split-divider resizing, if pane creation and pane actions remain keyboard-accessible
- verbose or debug-heavy inspector fields, as long as primary actions and pane identity remain clear

## Recommended Next Implementation Order

1. Run the full manual keyboard-only, Full Keyboard Access, VoiceOver, and multi-window command-routing pass and capture exact findings.
2. Repair any blocker-level issues where the wrong window receives commands or where pane focus is not visually or audibly trustworthy.
3. Evaluate `LocalProcessTerminalView` directly with VoiceOver and Full Keyboard Access.
4. Decide whether split dividers need direct accessible adjustment for `v0.1.0`.
5. Tune inspector and saved-workspace row verbosity after the first spoken-navigation pass.
