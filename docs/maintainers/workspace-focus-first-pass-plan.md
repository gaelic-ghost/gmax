# Workspace Focus First Pass Plan

> Status
> Historical implementation-pass record.
>
> This pass is complete. Do not use this note for current planning.
>
> Use these notes instead:
> - [`workspace-focus-target-plan.md`](./workspace-focus-target-plan.md)
> - [`workspace-focus-implementation-boundary.md`](./workspace-focus-implementation-boundary.md)
> - [`workspace-window-scene-command-focus-map.md`](./workspace-window-scene-command-focus-map.md)
> - [`framework-command-audit.md`](./framework-command-audit.md)

## What This Note Still Exists For

This file remains only as a breadcrumb for commit history and older references.

The historical first pass did three things:

- moved live pane focus out of `Workspace` and `WorkspaceStore`
- made scene-owned `@FocusState` the workspace-window focus model
- kept sidebar selection native and list-driven while narrowing the SwiftTerm bridge

That work is done. Current planning lives elsewhere.
