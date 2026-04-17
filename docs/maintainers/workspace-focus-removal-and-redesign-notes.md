# Workspace Focus Removal and Redesign Notes

> Status
> Historical cleanup note.
>
> The major removal work described here is complete. Do not use this note as an
> active plan.
>
> Use these notes instead:
> - [`workspace-focus-target-plan.md`](./workspace-focus-target-plan.md)
> - [`workspace-focus-implementation-boundary.md`](./workspace-focus-implementation-boundary.md)
> - [`workspace-window-scene-command-focus-map.md`](./workspace-window-scene-command-focus-map.md)
> - [`framework-command-audit.md`](./framework-command-audit.md)

## What Was Removed

The focus cleanup that used to be planned here has already landed.

Removed from the live architecture:

- `Workspace.focusedPaneID` as runtime focus truth
- store-owned pane focus history and pane-frame ownership
- pane and inspector tap handlers that manually shoved scene focus around
- the SwiftTerm-specific focus bridge and custom first-responder adapter

What remains active is not another removal pass. The remaining work is ordinary
verification and product polish around the current scene-local focus model.
