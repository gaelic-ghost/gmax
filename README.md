# gmax

`gmax` is a macOS terminal workspace app built with SwiftUI and [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).

The product direction is a keyboard-forward shell for managing multiple terminal workspaces, each with nested split panes, a contextual inspector, and durable state that can grow into a polished daily-driver app instead of staying an experiment.

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
- [Roadmap](#roadmap)
- [License](#license)

## Overview

Today the app already has the core product shape in place:

- a three-column `NavigationSplitView`
- a workspace sidebar
- a center pane tree with recursive horizontal and vertical splits
- a right-side inspector for the active pane
- embedded local shell sessions backed by SwiftTerm
- keyboard commands for splitting panes, moving focus, and closing panes or workspaces
- Core Data persistence for workspace and pane topology

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

## Development

### Build From The Command Line

```sh
xcodebuild -project gmax.xcodeproj -scheme gmax -destination 'platform=macOS' build
```

### Run The App

Build and run the `gmax` scheme from Xcode.

The app launches as a macOS window with the workspace sidebar, pane content area, and inspector rail.

## Keyboard Commands

The current shell already exposes a few important command-driven interactions:

- `cmd-d`: split the focused pane to the right
- `cmd-shift-d`: split the focused pane downward
- `cmd-option-left/right/up/down`: move focus directionally
- `cmd-option-[` and `cmd-option-]`: move focus in pane order
- `cmd-w`: close the focused pane, then empty workspace, then workspace, then window

## Status

The app is already past the pure-prototype stage. The shell shape, pane model, terminal embedding, directional focus movement, and persistence layer are all real.

What remains is product completion work: workspace management, polish, accessibility, settings, terminal-native refinement, and all the details that make the app feel intentional rather than merely viable.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the current product roadmap.

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

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
