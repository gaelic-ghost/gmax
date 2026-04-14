# Logging And Telemetry Options

## Purpose

This note maps the current logging and telemetry options for `gmax` before `v0.1.0`.

The goal is to keep the first release lightweight and Swift-friendly while leaving a clean path for:

- readable operator-facing logs during development and support work
- user-triggered feedback bundles that can include recent logs and errors
- crash and hang diagnostics
- optional future telemetry or tracing if `gmax` grows into a distributed or service-backed product

This is an evaluation note, not a claim that every option here should be adopted immediately.

## What `gmax` Actually Needs First

Near-term, `gmax` does not need a large observability stack. It needs a reliable local-first diagnostics story for a native macOS app.

For `v0.1.0`, the real requirements are:

- structured, human-readable app logs
- stable subsystem and category naming
- the ability to inspect recent app logs during debugging and support
- a path to export relevant logs into a user-facing feedback or support bundle later
- a lightweight way to capture crashes and hangs when we are ready to process them

That means the first decision is not "which telemetry framework should we install?" It is "what should be the canonical diagnostics surface for a native macOS app?"

## Apple-Native Logging

### `Logger` and Unified Logging

Apple's current native logging surface is `Logger` on top of the unified logging system.

Why it fits `gmax` well:

- it is the platform-native path for a macOS app
- it integrates with Console and Instruments
- it supports subsystem and category organization cleanly
- it works well with privacy annotations and structured interpolation
- it gives us a direct future path to local log export through `OSLogStore`

For this app, that makes `Logger` the cleanest default for ordinary app logs, warnings, and errors.

### `OSLogStore`

`OSLogStore` matters because it turns logging into something we can eventually ship in a user-facing support flow.

It gives `gmax` a credible future path to:

- collect recent entries for the app's subsystem
- filter by time, category, or level
- generate a support bundle the user can review and attach to feedback

That is much more aligned with the product than inventing a custom rolling log file system too early.

### Strengths

- zero extra package dependency for the main path
- best integration with Apple debugging tools
- straightforward support-bundle story on macOS
- low conceptual overhead for a SwiftUI and AppKit app

### Risks and Constraints

- unified logging retention is not guaranteed forever, so support export should be treated as "recent diagnostics" rather than a durable history archive
- privacy and redaction discipline matter from day one if logs may later be user-exported
- if we build a cross-platform or server-side companion later, Apple-native logging alone may feel too app-local

## `swift-log`

[`apple/swift-log`](https://github.com/apple/swift-log) is the standard Swift logging API package.

It is useful when you want a backend-neutral logging API and pluggable log handlers.

Why it is attractive:

- it is lightweight and Swift-native
- it is widely adopted across the server and package ecosystem
- it makes backend swapping easier if we later want different handlers for tests, file logs, or remote sinks

Why it is not an obvious primary choice for `gmax` right now:

- `gmax` is currently a native macOS app, not a server or cross-platform foundation package
- the product benefit comes from Apple toolchain integration and future support-bundle export, which `Logger` and unified logging already provide directly
- making `swift-log` the main API too early can hide some of the richer Apple-native ergonomics behind a portability abstraction we do not yet need

### Best Use For `gmax`

If we adopt `swift-log` at all in the near term, the clean reason would be:

- we want a narrow app-local diagnostics facade that can optionally emit to unified logging now and remain compatible with future alternate handlers later

That is a reasonable second step, but it should be justified by a concrete use case. It should not be added just because the package exists.

### Risks

- extra abstraction without immediate product payoff
- temptation to design an app-wide logging architecture before we know the actual support workflow
- possible drift between Apple-native categories and a generic metadata model if the wrapper becomes the center of gravity

## MetricKit

Apple's [`MetricKit`](https://developer.apple.com/documentation/metrickit) is the strongest native candidate for low-overhead crash and hang diagnostics on macOS.

Important current documented behavior:

- it supports macOS apps
- it can deliver diagnostic reports for crashes and hangs
- it delivers diagnostics immediately on supported systems and daily metrics on a separate cadence

For `gmax`, that makes MetricKit interesting for:

- crash diagnostics
- hang diagnostics
- future responsiveness and launch analysis

It does **not** replace ordinary logging. It is a diagnostics feed, not the day-to-day operator log surface.

### Strengths

- Apple-native
- lightweight relative to a full external observability backend
- directly relevant to crash and hang reporting

### Risks and Constraints

- event timing and delivery model are not the same as immediate local logs
- it adds subscriber and payload-processing work
- it still needs a place in the product where diagnostics are stored, summarized, or attached to feedback

## `swift-distributed-tracing`

[`apple/swift-distributed-tracing`](https://github.com/apple/swift-distributed-tracing) is about spans, context propagation, and trace instrumentation.

This becomes valuable when there are meaningful trace boundaries such as:

- app -> helper service
- app -> remote backend
- app -> local daemon or support service
- a larger plugin or workflow system with nested operations worth timing and correlating

For today's `gmax`, this is probably too early to make part of the core app baseline. The product is still a local-first macOS shell, and ordinary logs plus targeted diagnostics carry more value than introducing trace context across code that still lives in one process.

### Best Use For `gmax`

Keep it in mind as a future expansion path if the architecture grows cross-process or remote.

## `swift-otel` and OpenTelemetry

[`swift-otel/swift-otel`](https://github.com/swift-otel/swift-otel) and the broader [OpenTelemetry Swift guidance](https://opentelemetry.io/docs/languages/swift/getting-started/) are the most relevant current Swift-facing route if `gmax` eventually wants real telemetry export.

This is useful when there is a defined backend or collector and a real need for:

- traces across boundaries
- metrics export
- correlation between logs, spans, and errors

For `gmax` today, that is likely premature.

Why:

- it adds dependency and conceptual weight
- it is most valuable when there is already a telemetry destination and an operations workflow
- it does not solve the first-order problem of readable local diagnostics in a native macOS app

### Best Use For `gmax`

Treat OpenTelemetry as a later-stage integration if we add:

- a remote service backend
- distributed execution
- a hosted feedback and diagnostics pipeline
- cross-process traces that are otherwise hard to correlate

## Recommended Path

### For `v0.1.0`

Use Apple-native unified logging as the canonical baseline.

That means:

- use `Logger` for operator-facing logs
- define one stable app subsystem plus clear categories
- keep messages descriptive and support-oriented
- avoid introducing `swift-log`, distributed tracing, or OpenTelemetry as release blockers

### For the First Support-Bundle Pass

Build the support story around unified logging instead of custom files first.

That suggests:

- collect recent app entries with `OSLogStore`
- filter to the `gmax` subsystem and relevant categories
- package those entries with any user-facing feedback metadata and recent app state summaries

### For Crash and Hang Diagnostics

Evaluate MetricKit next, after the app's ordinary logging taxonomy is stable.

That order matters because:

- logs tell us what the app thought it was doing
- MetricKit tells us when the process crashed or hung
- those two surfaces become much more useful together than either one alone

### For Future Telemetry

Only add tracing or OpenTelemetry when the product has a concrete destination and cross-boundary diagnostic need.

If that happens, the most coherent layering would be:

- `Logger` and unified logging remain the local operator log surface
- MetricKit handles native crash and hang diagnostics
- tracing and OpenTelemetry are added only for new cross-process or remote workflows

## Suggested Initial Policy

For the near term, `gmax` should prefer this policy:

- ordinary app logs: Apple `Logger`
- local diagnostics export: `OSLogStore`
- crash and hang diagnostics: evaluate `MetricKit` after the main logging taxonomy is in place
- generic logging facade: defer unless a real multi-backend use case appears
- tracing and OTel: defer until there is a backend and a real distributed workflow

This is the smallest approach that still leaves us a clean growth path.

## Open Questions

- Which subsystem and category taxonomy best matches the current app boundaries?
- Do we want a thin `gmax` diagnostics helper for message consistency, or should feature code call `Logger` directly?
- What should a future feedback bundle include besides logs: workspace summaries, persistence diagnostics, recent alerts, terminal-session state, or saved-workspace metadata?
- When we add crash and hang diagnostics, do we want the app to store summarized MetricKit payloads locally, or only surface them when the user exports feedback?

## References

- Apple `Logger`: https://developer.apple.com/documentation/os/logger
- Apple unified logging overview: https://developer.apple.com/documentation/os/logging
- Apple `OSLogStore`: https://developer.apple.com/documentation/oslog/oslogstore
- Apple `MetricKit`: https://developer.apple.com/documentation/metrickit
- Apple `MXMetricManager`: https://developer.apple.com/documentation/metrickit/mxmetricmanager
- `apple/swift-log`: https://github.com/apple/swift-log
- `apple/swift-distributed-tracing`: https://github.com/apple/swift-distributed-tracing
- `apple/swift-service-context`: https://github.com/apple/swift-service-context
- `swift-otel/swift-otel`: https://github.com/swift-otel/swift-otel
- OpenTelemetry Swift getting started: https://opentelemetry.io/docs/languages/swift/getting-started/
