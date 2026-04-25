# Shell Integration Protocol

## Purpose

This note defines the smallest useful shell-integration protocol for `gmax`.

The goal is not to recreate every terminal-specific integration feature from
kitty or iTerm2. The goal is to make shell sessions report a small set of
semantic events that `gmax` can use for better pane UX, restoration, and
future command-aware features.

Use this note when discussing:

- prompt and command-boundary reporting
- shell-driven current-directory updates
- bell and notification routing
- command completion and exit-status metadata
- future terminal-history and command-history product work

This note now covers both the shipped `v0.1.0` shell-integration baseline and
the still-deferred follow-through beyond it.

## Why Shell Integration Exists

Without shell integration, the terminal emulator mostly sees a stream of bytes.
It can render text, detect title changes, honor bells, and sometimes parse
escape codes such as current-directory reporting, but it usually cannot tell:

- where the prompt begins
- where the user-entered command begins
- where the command output begins
- when the command finished
- what exit status the command produced

Shell integration solves that by having the shell emit explicit escape
sequences that describe those boundaries and bits of metadata.

That gives a terminal product a much better model of what the user is doing
than raw text alone.

## What SwiftTerm Already Gives `gmax`

SwiftTerm already exposes several useful hooks through `TerminalDelegate`.
These do not require custom `gmax` shell integration to exist:

- window-title changes
- icon-title changes
- terminal bell
- current-directory reporting through `OSC 7`
- current-document reporting through `OSC 6`
- clipboard writes through `OSC 52`
- notification requests through `OSC 777`
- progress reports through `OSC 9;4`
- mouse-mode changes
- cursor-style changes
- color changes

Those hooks are enough for:

- pane cwd metadata
- badges and attention markers
- native notifications from explicit terminal escape codes
- future progress UI

They are not enough for a first-class command lifecycle model.

## What `gmax` Still Does Not Get For Free

SwiftTerm does not currently give `gmax` a ready-made structured event model
for:

- prompt start
- prompt end
- command line start
- command execution start
- command completion
- command exit status as a durable event

Those are the highest-value gaps for a `gmax`-specific shell integration layer.

## Product Goals

The first `gmax` shell integration pass should unlock these product outcomes:

- know whether a pane is sitting idle at a prompt or actively running a command
- know the most recent command exit status for a pane
- navigate or reason about command boundaries in scrollback later
- attribute output to commands more accurately than line-oriented heuristics
- capture more precise restoration metadata over time
- surface terminal notifications and bells through pane or window UI

The currently shipped baseline does this much:

- parses prompt-start, command-start, and command-finish markers
- emits those markers from the `zsh`, `bash`, and `fish` launch paths
- tracks prompt-idle versus command-running session state
- surfaces pane-local running, success, failure, and bell-attention chrome
- aggregates active bell attention into workspace-local sidebar counts
- records explicit terminal notifications in pane session state and the
  inspector
- uses a generated `bash` `--rcfile` wrapper to recreate login-style startup
  before installing prompt markers
- uses a generated `fish` `XDG_CONFIG_HOME` wrapper to source the user's
  original `conf.d` snippets and `config.fish` before installing prompt
  markers
- has focused wrapper-generation and launch-plan tests for all three shells,
  with live local runtime verification currently exercised for `zsh` and
  `bash`; `fish` still needs a machine with fish installed for a real manual
  runtime check

The main follow-through still ahead is:

- routing explicit terminal notifications into real macOS notifications
- deciding whether richer shell-integration events are worth durable product
  surface area beyond the current runtime metadata

The first pass should not try to solve:

- full shell-state serialization
- shell-independent command parsing
- job-control introspection
- exact restoration of every in-progress shell interaction
- remote-shell metadata beyond the same generic protocol

## Recommended Protocol Shape

The recommended first pass is intentionally small:

### 1. Current directory

Keep using `OSC 7` for the current working directory.

Why:

- SwiftTerm already understands it
- `gmax` already benefits from it
- it is useful for restore, UI metadata, and future “open new pane here”
  behavior

### 2. Prompt start

Use `OSC 133;A` immediately before the primary prompt is drawn.

Meaning in `gmax`:

- the pane is back at a shell prompt
- any prior command has finished
- the next user command boundary begins after this point

### 3. Command start

Use `OSC 133;C` immediately before the shell executes the command.

Meaning in `gmax`:

- the pane has left prompt-idle state
- a command is now running
- command-scoped output begins after this event

### 4. Command finish with exit status

Use `OSC 133;D;<status>` when the shell regains control after command
completion.

Meaning in `gmax`:

- the command is complete
- the exit status is known
- the pane can update failure/success affordances
- the pane can transition back toward prompt-idle state

### 5. Optional command line reporting

Later, if we want it, attach the command line to `OSC 133;C`.

That should stay optional in the first pass because:

- command text can contain sensitive material
- persistence and privacy semantics become more important immediately
- the first product wins do not require durable command capture

## Recommended Event Model Inside `gmax`

The terminal boundary should normalize shell integration into a small app-owned
event model instead of letting every downstream UI surface inspect raw escape
codes.

The smallest useful shape is something like:

```swift
enum ShellIntegrationEvent: Equatable {
    case promptStarted
    case commandStarted
    case commandFinished(exitStatus: Int32)
    case currentDirectoryChanged(URL)
    case bell
    case notification(title: String, body: String)
    case progress(Terminal.ProgressReport)
}
```

This does not need to be the exact final type. The point is the ownership
boundary:

- SwiftTerm parses terminal escape behavior
- the terminal host or controller translates that into app-meaningful events
- workspace and pane UI observe those events without speaking raw terminal
  protocol directly

## Recommended Ownership Boundary

The preferred ownership split is:

- shell snippets emit the integration escape codes
- SwiftTerm or the terminal host boundary receives and parses them
- `TerminalPaneController` owns the app-local session interpretation
- `WorkspaceStore` and SwiftUI scene code consume only normalized pane state,
  not raw terminal protocol

That keeps the terminal protocol local to the terminal boundary instead of
spreading escape-sequence knowledge across scene or persistence code.

## First-Pass State `gmax` Should Track Per Pane

The first shell-aware pane state should stay small:

- current working directory
- whether the pane is at a prompt
- whether a command is currently running
- most recent command exit status
- timestamp of the most recent shell event
- optional last notification or bell timestamp

That is enough to support future product work such as:

- “busy” pane badges
- last-command success or failure indicators
- command-aware restore heuristics
- future prompt-to-prompt scrollback navigation

## Notifications And Bells

These should remain separate concepts.

### Bell

Bell is low-level terminal attention.

Possible `gmax` uses:

- flash a pane activity marker
- animate a subtle pane-attention affordance
- eventually route to a user preference for sound or quiet visual attention

### Explicit terminal notifications

Notification escape codes are higher-level requests from the process running in
the shell.

Possible `gmax` uses:

- forward to macOS notifications
- record recent pane notifications in memory
- expose notification provenance in the inspector later

The current follow-through priority after pane and sidebar attention affordances
is to route explicit terminal notifications into real macOS notifications
before doing deeper notification persistence work.

These should not be collapsed into one generic “activity happened” signal.

## Prompt Markers Versus Exact Command Boundaries

Prompt markers are the right first pass.

Why:

- they are already used by terminals such as iTerm2 and kitty
- they let `gmax` distinguish prompt-idle versus command-running
- they are much simpler than trying to infer command boundaries from text
- they avoid deep shell parsing or shell-specific AST work

The product should accept that this is shell-assisted metadata, not a perfect
formal execution trace.

## Privacy And Persistence Guardrails

The first pass should treat shell integration as runtime metadata first, not
persistence data first.

That means:

- cwd can remain persisted where it already has product value
- prompt-idle or command-running state can be transient
- exit status can be transient until a real use case justifies persistence
- command text should not be persisted by default in the first pass

If later work wants command-line persistence, that should be a separate product
decision with explicit operator and privacy reasoning.

## Built-In Shell Coverage

If `gmax` adds its own snippets, the intended first shells are:

- `zsh`
- `bash`
- `fish`

That should be treated as a narrow compatibility matrix, not a promise to
support every shell-specific prompt framework in the first pass.

## Recommended Implementation Order

1. Keep using `OSC 7` and make sure the current path continues flowing cleanly
   through the existing terminal host and pane metadata surfaces.
2. Keep the built-in shell snippets aligned across `zsh`, `bash`, and `fish`
   so they all emit:
   - `OSC 133;A`
   - `OSC 133;C`
   - `OSC 133;D;<status>`
3. Teach the terminal boundary to convert those prompt markers into normalized
   pane session state.
4. Add subtle pane-level UI for:
   - running versus prompt-idle
   - most recent command success or failure
5. Only after the cross-shell marker baseline is stable, route explicit
   terminal notifications into real macOS notifications and then decide
   whether command text, command regions, or richer command-history features
   are worth carrying.

## Explicit Non-Goals

- full shell replication inside `gmax`
- reproducing every iTerm2 or kitty shell-integration feature
- shell-state persistence that tries to recreate exact interactive sessions
- command-text persistence by default
- using shell integration as a substitute for a future remote-session model

## Decision Summary

The recommended `gmax` shell-integration protocol is:

- `OSC 7` for cwd
- `OSC 133;A` for prompt start
- `OSC 133;C` for command start
- `OSC 133;D;<status>` for command completion
- existing SwiftTerm bell, notification, and progress hooks for auxiliary
  attention and status

That is the smallest durable protocol that gives `gmax` meaningful shell
semantics without overcommitting to a much larger terminal-product architecture
too early.
