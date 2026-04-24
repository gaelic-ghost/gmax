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

`gmax` is in early development and already stable enough for maintainers to build, run, and iterate on locally.

### What This Project Is

`gmax` is a native macOS shell workspace app for managing multiple terminal workspaces across an intentional multi-window SwiftUI scene model. The shipped repo surface already includes a data-driven `WindowGroup` shell, recursive split-pane workspaces, SwiftTerm-hosted local shell sessions, a saved-workspace library with transcript-backed restore, Core Data persistence for live, recent, and saved workspace state, durable per-window restoration, scene-local command context, and a settings window for terminal appearance plus persistence behavior.

This repository is the app itself. It also carries the maintainer notes, release checklists, and repo-maintenance scripts that document how the current shell is supposed to behave and how maintainers validate it.

### Motivation

The project exists to build a terminal app that feels native on macOS while still leaving room for product features that are awkward in renderer-first terminals. The core bet is that SwiftUI should own the app shell, scenes, commands, and window behavior, while AppKit interop stays narrow around the embedded terminal surface where it is actually needed.

## Quick Start

There is not a polished end-user quick start yet. The fastest way to try `gmax` today is to open the project in Xcode, build the `gmax` scheme, and run the app locally.

If you want the maintainer workflow and validation commands, jump to [Development](#development).

## Usage

The current app launches into a macOS `WindowGroup` shell with a sidebar, pane content area, and inspector. Each window keeps its own selected workspace plus sidebar and inspector visibility, and menu commands follow that window's scene-local context.

From the current app surface you can:

- create and switch workspaces
- split panes right or down inside the selected workspace
- move focus across panes with keyboard commands
- save workspaces into the library and reopen them later
- restore transcript-backed shell history for reopened saved workspaces
- hide or show the sidebar and inspector independently
- adjust terminal appearance and workspace persistence behavior in Settings

The command surface is intentionally keyboard-forward. The current menu and shortcut model includes:

- `cmd-n` for `New gmax Window`
- `cmd-shift-n` for a new workspace
- `cmd-o` to open the saved-workspace library
- `cmd-s` to save the selected workspace
- `cmd-shift-o` to reopen the most recently closed workspace for the active window
- `cmd-b` and `cmd-shift-b` to toggle the sidebar and inspector
- `cmd-t`, `cmd-d`, and `cmd-shift-d` for pane creation and splits
- `cmd-option-left/right/up/down` plus `cmd-option-[` and `cmd-option-]` for pane focus movement
- `cmd-w` for the context-sensitive close behavior documented in [docs/maintainers/workspace-focus-guide.md](docs/maintainers/workspace-focus-guide.md)
- `cmd-option-w` for `Close Window`
- `shift-cmd-option-w` for `Undo Close Window`

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
- `gmax/Terminal/` holds the SwiftTerm hosting boundary, launch/session types, and pane controllers.
- `gmax/Persistence/Workspace/` holds Core Data-backed workspace persistence plus the saved-workspace model.
- `docs/maintainers/` holds the architectural and maintainer-facing source of truth for focus, persistence, accessibility, telemetry, and browser-pane planning.
- `docs/releases/` holds release-oriented checklists such as [docs/releases/v0.1.0-release-checklist.md](docs/releases/v0.1.0-release-checklist.md).

## Release Notes

The repository already has release tags through `v0.0.5`. The current release-prep checkpoint is [docs/releases/v0.0.6-release-notes.md](docs/releases/v0.0.6-release-notes.md), and the broader internal-release quality bar is tracked in [docs/releases/v0.1.0-release-checklist.md](docs/releases/v0.1.0-release-checklist.md). Both release docs assume `README.md`, `ROADMAP.md`, and the maintainer notes stay aligned with the shipped persistence, library, and window-restoration model.

## License

`gmax` is currently source-available under the Functional Source License 1.1, Apache 2.0 future-license variant (`FSL-1.1-ALv2`).

That means the repository is available for permitted non-competing use during the protected window, and each covered release converts to Apache License 2.0 on the second anniversary of the date that release was made available.

See [LICENSE](LICENSE), [NOTICE](NOTICE), and [LICENSE-TRANSITION.md](LICENSE-TRANSITION.md).
