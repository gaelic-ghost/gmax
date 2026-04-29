# gmax

`gmax` is a macOS terminal workspace app built with SwiftUI and [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Development](#development)
- [Repo Structure](#repo-structure)
- [Release Notes](#release-notes)
- [License](#license)

## Overview

### Status

`gmax` is in development, but already stable enough for maintainers to build, run, and iterate on locally.

### What This Project Is

`gmax` is a native macOS shell workspace app for managing mixed terminal and browser workspaces across an intentional multi-window SwiftUI scene model. The current shipped surface includes a data-driven `WindowGroup` shell, recursive split-pane workspaces, SwiftTerm-hosted local shell sessions, basic `WKWebView` browser panes, a unified library for saved workspaces and windows, Core Data persistence for live, recent, and saved state, durable per-window restoration, restored terminal history with ordinary shell scrollback on relaunch, scene-local command context, and a settings window for terminal appearance plus workspace persistence and browser-home behavior.

This repository is the app itself. It also carries the maintainer notes, release checklists, and repo-maintenance scripts that document how the current shell is supposed to behave and how maintainers validate it.

### Motivation

The project exists to build a terminal app that feels native on macOS while still leaving room for product features that are awkward in renderer-first terminals. The core bet is that SwiftUI should own the app shell, scenes, commands, and window behavior, while AppKit interop stays narrow around the embedded terminal surface where it is actually needed.

## Quick Start

Download the latest packaged app from [GitHub Releases](https://github.com/gaelic-ghost/gmax/releases). The current release includes [`Gmax-v0.1.7.dmg`](https://github.com/gaelic-ghost/gmax/releases/download/v0.1.7/Gmax-v0.1.7.dmg) plus a matching SHA-256 checksum file.

For local development, open the project in Xcode, build the `gmax` scheme, and run the app from the debugger.

If you want the maintainer workflow and validation commands, jump to [Development](#development).

## Usage

The current app launches into a macOS `WindowGroup` shell with a sidebar, pane content area, and inspector. Each window keeps its own selected workspace plus sidebar and inspector visibility, and menu commands follow that window's scene-local context.

From the current app surface you can:

- create and switch workspaces
- split panes right or down inside the selected workspace
- move focus across panes with keyboard commands
- save workspaces and windows into the library and reopen them later
- restore terminal history for reopened workspaces and ordinary live relaunches, including ordinary scroll position when available
- surface shell-aware pane status for running, completed, failed, and bell-attention states when the integrated shell markers are available
- split dedicated browser panes into a workspace and navigate them in place
- show active terminal bell counts in the workspace sidebar and terminal inspector
- hide or show the sidebar and inspector independently
- adjust terminal appearance and workspace persistence behavior in Settings

The command surface is intentionally keyboard-forward. The current menu and shortcut model includes:

- `cmd-n` for a new workspace
- `cmd-shift-n` for `New gmax Window`
- `cmd-o` to open the library
- `cmd-option-o` to open the most recently closed workspace for the active window
- `cmd-shift-o` to open the most recently closed window
- `cmd-option-s` to close the selected workspace into the library
- `cmd-shift-s` to close the active window into the library
- `cmd-b` and `cmd-shift-b` to toggle the sidebar and inspector
- `cmd-d` and `cmd-shift-d` for terminal pane splits
- `cmd-option-d` and `cmd-option-shift-d` for browser-pane splits
- `cmd-option-left/right/up/down` plus `cmd-option-[` and `cmd-option-]` for pane focus movement
- `cmd-l`, `cmd-[`, `cmd-]`, and `cmd-r` for focused browser-pane address, back, forward, and reload
- `cmd-w` for the context-sensitive close behavior documented in [docs/maintainers/workspace-focus-guide.md](docs/maintainers/workspace-focus-guide.md)
- `cmd-option-w` for `Close Workspace`
- `cmd-shift-w` for `Close Window`

## Development

### Setup

- Use macOS with Xcode installed.
- Open [gmax.xcodeproj](gmax.xcodeproj) in Xcode.
- Read [docs/maintainers/workspace-focus-guide.md](docs/maintainers/workspace-focus-guide.md) before changing scene, command, focus, or close behavior.

### Workflow

Apple's SwiftUI app model puts window structure and command ownership on the `App` and `Scene` side, and `WindowGroup` gives each macOS window its own independent scene state plus standard window-management behavior. In this repo that means we keep scene selection, command context, sidebar state, inspector state, and modal presentation local to the workspace window scene instead of rebuilding that behavior through custom routing layers.

Normal maintainer work here is:

1. Open the project in Xcode and work inside the `gmax` scheme.
2. Keep the source-of-truth architecture grounded in the maintainer docs under [docs/maintainers/](docs/maintainers/).
3. Use the repo-maintenance scripts for guidance sync, validation, and release preparation.

### Validation

Build the app:

```sh
xcodebuild -project gmax.xcodeproj -scheme gmax -destination 'platform=macOS' build
```

Run the tests:

```sh
xcodebuild -project gmax.xcodeproj -scheme gmax -destination 'platform=macOS' test
```

Run the maintainer validation wrapper:

```sh
scripts/repo-maintenance/validate-all.sh
```

For log validation during manual testing:

```sh
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.gaelic-ghost.gmax"'
```

## Repo Structure

```text
.
├── gmax/
│   ├── Scenes/
│   │   ├── WorkspaceWindowGroup/
│   │   └── Settings/
│   ├── Terminal/
│   ├── Browser/
│   ├── Persistence/
│   ├── Views/
│   └── Support/
├── gmaxTests/
├── gmaxUITests/
├── docs/
│   ├── maintainers/
│   └── releases/
├── scripts/
│   └── repo-maintenance/
├── README.md
└── ROADMAP.md
```

Key repo surfaces:

- `gmax/Scenes/WorkspaceWindowGroup/` holds the main window-scene composition, scene-local selection, pane focus publication, and command wiring.
- `gmax/Browser/` holds the browser-pane runtime, WebKit host boundary, and browser session models.
- `gmax/Terminal/` holds the SwiftTerm hosting boundary, launch/session types, and pane controllers.
- `gmax/Persistence/Workspace/` holds Core Data-backed workspace persistence plus the unified library and session snapshot models.
- `docs/maintainers/` holds the architectural and maintainer-facing source of truth for focus, persistence, accessibility, telemetry, and browser-pane planning.
- `docs/releases/` holds release-oriented checklists such as [docs/releases/v0.1.0-release-checklist.md](docs/releases/v0.1.0-release-checklist.md).

## Release Notes

The current split-pane resize stability checkpoint is documented in [docs/releases/v0.1.7-release-notes.md](docs/releases/v0.1.7-release-notes.md), and the broader internal-release quality bar remains tracked in [docs/releases/v0.1.0-release-checklist.md](docs/releases/v0.1.0-release-checklist.md). Release docs assume `README.md`, `ROADMAP.md`, and the maintainer notes stay aligned with the shipped persistence, library, command, window-restoration, browser-pane, shell-integration, and split-resize model.

## License

`gmax` is currently source-available under the Functional Source License 1.1, Apache 2.0 future-license variant (`FSL-1.1-ALv2`).

That means the repository is available for permitted non-competing use during the protected window, and each covered release converts to Apache License 2.0 on the second anniversary of the date that release was made available.

See [LICENSE](LICENSE), [NOTICE](NOTICE), and [LICENSE-TRANSITION.md](LICENSE-TRANSITION.md).
