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
- explicit workspace creation and pane creation commands
- keyboard commands for splitting panes, moving focus, and closing panes or workspaces
- Core Data persistence for workspace and pane topology
- a settings window for terminal font and theme controls

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
- terminal appearance is driven by persisted app settings for font, size, and theme

SwiftTerm is hosted through AppKit using `NSViewRepresentable`, so live terminal output stays inside the hosted terminal view instead of driving SwiftUI body churn.

Persistence is handled with Core Data using relational workspace and pane-node records, which gives the app a cleaner path toward richer restoration, future undo-friendly operations, and eventual CloudKit-backed sync if that becomes worthwhile.

The maintainer-facing architecture note lives at [docs/maintainers/swiftui-terminal-shell-architecture.md](docs/maintainers/swiftui-terminal-shell-architecture.md).

## Repository Layout

- `gmax/`: app source
- `gmax/Models/`: shell and pane model types
- `gmax/Terminal/`: SwiftTerm hosting and terminal session plumbing
- `gmax/Persistence/`: Core Data persistence for shell state
- `gmax/Views/`: sidebar, content, detail, and pane rendering
- `docs/maintainers/`: architecture and maintainer notes

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
- create a new pane from the toolbar or `cmd-t`
- split the focused pane right or down with keyboard commands
- hide or show the sidebar and inspector independently
- open the settings window to adjust terminal font, size, and theme

## Development

### Build From The Command Line

```sh
xcodebuild -project gmax.xcodeproj -scheme gmax -destination 'platform=macOS' build
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

The app is already past the pure-prototype stage. The shell shape, pane model, terminal embedding, directional focus movement, and persistence layer are all real.

What remains is product completion work: fuller workspace lifecycle tooling, terminal-native polish, accessibility, richer settings, deeper terminal integrations, and the details that make the app feel intentional rather than merely viable.

## Verification

Use the project-aware Apple workflow first when validating changes in this repo.

For code changes inside the app, prefer:

```sh
xcodebuild -project gmax.xcodeproj -scheme gmax -destination 'platform=macOS' build
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
