# gmax

`gmax` is a macOS terminal workspace app built with SwiftUI and [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).

The product direction is a keyboard-forward shell for managing multiple terminal workspaces, each with nested split panes, a contextual inspector, durable state, and an early settings foundation for terminal appearance.

## Table of Contents

- [Overview](#overview)
- [Current Architecture](#current-architecture)
- [Repository Layout](#repository-layout)
- [Setup](#setup)
- [Usage](#usage)
- [Development](#development)
- [Keyboard Commands](#keyboard-commands)
- [Verification](#verification)
- [Status](#status)
- [License](#license)

## Overview

Today the app already has the core product shape in place:

- a three-column `NavigationSplitView`
- a workspace sidebar
- a center pane tree with recursive horizontal and vertical splits
- a right-side inspector for the active pane
- embedded local shell sessions backed by SwiftTerm
- explicit workspace and pane creation commands
- keyboard commands for workspace, pane, and close lifecycle actions
- a saved-workspace library with searchable reopen
- transcript-backed workspace snapshots so reopened workspaces preserve shell history
- Core Data persistence for both live workspace topology and saved workspace snapshots
- per-scene restoration for the selected workspace and inspector visibility
- a settings window for terminal appearance and workspace persistence behavior

This repository is the successor to the earlier exploration work. It is intended to keep moving toward a finished product.

### Motivation

The goal is to build a terminal app that feels native on macOS, is practical to extend, and has a much better long-term story for product features than heavyweight embedders or renderer-first terminal stacks.

The architectural priorities are:

- native SwiftUI shell structure with AppKit-hosted terminal surfaces where needed
- durable pane and workspace primitives that compose cleanly as features grow
- strong keyboard navigation and command-driven workflows
- room for accessibility, theming, workspace management, and sync-worthy settings later

## Current Architecture

The shell uses a split-tree model rather than a flat grid:

- each workspace owns a recursive pane tree
- leaf nodes host terminal sessions
- split nodes store axis and fraction
- the active pane drives the inspector content
- the selected workspace and inspector visibility restore per scene
- terminal appearance is driven by persisted app settings for font, size, and theme
- saved workspaces are stored as durable snapshots with pane launch context and preserved transcript text

SwiftTerm is hosted through AppKit using `NSViewRepresentable`, so live terminal output stays inside the hosted terminal view instead of driving SwiftUI body churn.

Persistence is handled with Core Data using relational live-workspace records plus a parallel saved-workspace snapshot graph. That gives the app a cleaner path toward undo-friendly workspace closure, searchable reopen, richer restoration, and future sync-friendly expansion if that becomes worthwhile.

The maintainer-facing architecture note lives at [docs/maintainers/swiftui-terminal-shell-architecture.md](docs/maintainers/swiftui-terminal-shell-architecture.md).

## Repository Layout

- `gmax/`: app source
- `gmax/Models/`: shell and pane model types
- `gmax/Terminal/`: SwiftTerm hosting and terminal session plumbing
- `gmax/Persistence/`: Core Data persistence for shell state
- `gmax/Views/`: sidebar, content, detail, and pane rendering
- `gmaxTests/`: focused model-level tests
- `gmaxUITests/`: UI test target scaffolding
- `docs/maintainers/`: architecture and maintainer notes
- `docs/maintainers/accessibility-and-keyboard-plan.md`: release-oriented accessibility and keyboard plan
- `docs/maintainers/v0.1.0-release-checklist.md`: first internal release checklist
- `scripts/repo-maintenance/`: repo validation, sync, and release helpers

## Setup

### Requirements

- macOS
- Xcode with SwiftUI and AppKit support

### Open The Project

Open [gmax.xcodeproj](gmax.xcodeproj) in Xcode.

## Usage

Build and run the `gmax` scheme from Xcode.

The app launches as a macOS window with the workspace sidebar, pane content area, and inspector rail. The active pane drives the detail inspector, and the center column renders the recursive split-pane tree for the selected workspace.

From there you can:

- create a new workspace from the toolbar or `cmd-n`
- open the saved-workspace library from the toolbar or `cmd-o`
- save the selected workspace into the library with `cmd-s`
- create a new pane from the toolbar or `cmd-t`
- split the focused pane right or down with keyboard commands
- close a workspace directly or close it into the saved-workspace library
- reopen a previously saved workspace with its layout and preserved shell history
- hide or show the sidebar and inspector independently
- open the settings window to adjust terminal appearance plus restore, recent-close, and auto-save workspace behavior

## Development

### Build From The Command Line

```sh
xcodebuild -project gmax.xcodeproj -scheme gmax -destination 'platform=macOS' build
```

### Run Tests

```sh
xcodebuild -project gmax.xcodeproj -scheme gmax -destination 'platform=macOS' test
```

### Run The App

Build and run the `gmax` scheme from Xcode.

The app launches as a macOS window with the workspace sidebar, pane content area, and inspector rail.

### Repo Maintenance Scripts

For maintainer-oriented repo checks and shared sync steps, use:

```sh
scripts/repo-maintenance/validate-all.sh
scripts/repo-maintenance/sync-shared.sh
```

## Keyboard Commands

The current shell exposes a command-first keyboard model across the `File`, `Workspace`, and `Pane` menus:

- `cmd-n`: create a new workspace
- `cmd-o`: open the saved-workspace library
- `cmd-s`: save the selected workspace to the library
- `cmd-shift-o`: undo the most recent workspace close during the current app session
- `cmd-b`: hide or show the workspace sidebar
- `cmd-shift-b`: hide or show the inspector
- `cmd-shift-[` and `cmd-shift-]`: move between workspaces
- `cmd-t`: create a new pane in the selected workspace
- `cmd-d`: split the focused pane to the right
- `cmd-shift-d`: split the focused pane downward
- `cmd-option-left/right/up/down`: move focus directionally
- `cmd-option-[` and `cmd-option-]`: move focus in pane order
- `cmd-w`: close the focused pane, then close the workspace if it was the last pane, then close the window if it was the last workspace
- `cmd-option-w`: close the selected workspace directly
- `cmd-shift-w`: close the current window directly

## Status

The app is already past the pure-prototype stage. The shell shape, pane model, terminal embedding, directional focus movement, saved-workspace library, transcript-backed restore path, and persistence layers are all real.

What remains is product completion work: command-surface polish, library and rename refinements, accessibility, richer terminal controls, deeper integrations, and the details that make the app feel intentional rather than merely viable.

The test surface is still early. There is a real unit-test foothold around core workspace mutations, but broader persistence, UI-flow, and release-readiness coverage is still ahead of the project.

## Verification

Use the project-aware Apple workflow first when validating changes in this repo.

For code changes inside the app, prefer:

```sh
xcodebuild -project gmax.xcodeproj -scheme gmax -destination 'platform=macOS' build
```

For test validation, prefer:

```sh
xcodebuild -project gmax.xcodeproj -scheme gmax -destination 'platform=macOS' test
```

For repo-maintenance validation after guidance syncs, use:

```sh
scripts/repo-maintenance/validate-all.sh
```

## License

`gmax` is currently source-available under the Functional Source License 1.1,
Apache 2.0 future-license variant (`FSL-1.1-ALv2`).

That means this repository is available for permitted non-competing use now,
including internal use, non-commercial education, and non-commercial research.
Competing commercial use is outside the permitted-purpose grant during the
protected window.

Each covered release converts to Apache License 2.0 on the second anniversary
of the date that release was made available.

See [LICENSE](LICENSE), [NOTICE](NOTICE), and
[LICENSE-TRANSITION.md](LICENSE-TRANSITION.md).
