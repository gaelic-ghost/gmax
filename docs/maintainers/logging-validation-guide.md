# Logging Validation Guide

## Purpose

This note is the maintainer-facing companion to the `Logger` baseline in `gmax`.

Use it when you need to:

- verify that a new log line is actually reaching Apple's unified logging system
- check the expected categories during manual product or accessibility validation
- compare normal app behavior against persistence, restore, reopen, relaunch, or command-path failures
- capture the exact diagnostics surfaces a future support-bundle export should rely on

This note is about local validation and operator workflow. It is not a replacement for the product roadmap in `logging-and-telemetry-options.md`.

## Canonical Logging Surface

`gmax` uses Apple's unified logging system through `Logger`.

Current canonical subsystem:

- `com.gaelic-ghost.gmax`

Current expected categories:

- `app`
- `workspace`
- `pane`
- `persistence`
- `diagnostics`

When validating a new logging change, prefer confirming that the message appears under the correct subsystem and category before deciding whether the wording is good enough.

## Where To Inspect Logs

### Console.app

For exploratory debugging, Console.app is still the fastest way to browse the live stream and filter by:

- process: `gmax`
- subsystem: `com.gaelic-ghost.gmax`
- category: one of the current categories above

Use Console when you want to inspect a broader sequence of events and step through the app manually at the same time.

### Terminal

For deterministic validation and written verification notes, prefer the terminal.

Important shell note:

- in `zsh`, `log` may resolve to a shell built-in instead of Apple's log utility
- use `/usr/bin/log` explicitly in maintainer commands to avoid that ambiguity

Recommended base command:

```sh
/usr/bin/log stream --style compact --predicate 'subsystem == "com.gaelic-ghost.gmax"'
```

Recent-history command:

```sh
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.gaelic-ghost.gmax"'
```

## Useful Filters

### App And Scene Restore

Use this when checking launch, scene restore, and settings-related state:

```sh
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.gaelic-ghost.gmax" && category == "app"'
```

### Workspace Lifecycle

Use this when checking create, rename, duplicate, close, save-to-library, reopen, and recently-closed behavior:

```sh
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.gaelic-ghost.gmax" && category == "workspace"'
```

### Pane And Terminal Host Activity

Use this when checking pane relaunch, terminal launch, and shell termination:

```sh
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.gaelic-ghost.gmax" && category == "pane"'
```

### Persistence Outcomes

Use this when checking Core Data load, save, snapshot, or restore issues:

```sh
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.gaelic-ghost.gmax" && category == "persistence"'
```

### Commands, Settings, And Internal Diagnostics

Use this when checking toolbar commands, menu actions, inspector visibility, and maintainer-focused validation messages:

```sh
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.gaelic-ghost.gmax" && category == "diagnostics"'
```

## What To Expect During Normal Validation

### Launch And Restore

During an ordinary app launch, expect to see:

- one or more `app` messages describing whether persisted workspaces were restored
- one `app` message describing per-scene selection and inspector restoration
- one `diagnostics` message if inspector visibility was explicitly restored through scene state

### Workspace Actions

During manual product validation, expect `workspace` logs for:

- creating a workspace
- renaming a workspace
- duplicating a workspace
- closing a workspace
- presenting and confirming workspace deletion
- reopening a recently closed workspace
- saving a workspace to the library
- opening a saved workspace
- deleting a saved snapshot

### Pane And Shell Activity

During terminal-host validation, expect `pane` logs for:

- shell process launch
- shell process termination
- pane relaunch requests

### Settings And Command Validation

During command-surface and settings validation, expect `diagnostics` logs for:

- contextual close, workspace close, and frontmost-window command-routing outcomes
- save-workspace command requests
- saved-workspace library presentation requests
- rename-sheet presentation requests
- sidebar and inspector visibility changes
- workspace-related settings toggles in the Settings window

## Test Expectations

### Unit Tests

Most unit tests should not rely on live unified-log output as a direct assertion surface.

Instead, unit tests should verify:

- the state transition that the log is supposed to describe
- the persistence side effect or restore outcome behind the message
- the command result that would make the log line meaningful

The logs themselves should then be verified manually with `Console.app` or `/usr/bin/log`.

### UI Tests And Launch Scaffolding

Repeated app launches during UI tests are expected to produce repeated `app` category messages.

That is normal for:

- `gmaxUITests`
- the currently scaffolded launch-test surface once it grows into a real smoke harness
- any UI flow that restarts the app under automation

Do not treat repeated launch-restoration logs during those runs as an app bug by default. The first question should be whether the test intentionally launched the app again.

### Manual Accessibility Passes

When running the manual accessibility and keyboard audit, the most useful categories are usually:

- `app`
- `workspace`
- `pane`
- `diagnostics`

The goal is not to prove that every user action logs something. The goal is to confirm that the most failure-prone or stateful transitions leave a readable trace behind.

## Good Validation Habits

- validate new logs with `/usr/bin/log show` or `/usr/bin/log stream` before calling the work finished
- keep one log line tied to one meaningful action or outcome whenever possible
- prefer category-specific filtering before judging message quality
- record the exact command or Console filter used when writing maintainer notes or release findings
- treat repeated launch logs in UI automation as expected noise unless the content itself is wrong

## Current Limitations

- `gmax` does not yet export unified logs through `OSLogStore`
- crash and hang diagnostics are not yet integrated through `MetricKit`
- the current validation flow is local and maintainer-driven rather than user-facing

Those are later roadmap items, not gaps in this validation note.
