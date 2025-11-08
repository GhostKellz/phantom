# Phantom TUI Framework

Terminal user interface framework for Zig, inspired by Ratatui.

[![Zig v0.16+](https://img.shields.io/badge/zig-0.16+-f7a41d?logo=zig\&logoColor=white)](https://ziglang.org/)

## Features

* Widget library with 30+ components
* Constraint-based layout system
* Data visualization (charts, gauges, sparklines, canvas)
* Tree-sitter syntax highlighting via Grove
* Advanced text editor with multi-cursor support
* Font rendering with ligatures and Nerd Font icons
* Unicode processing with gcode
* Mouse and keyboard input handling
* Animation framework
* Animated layout transitions for widget entry/resizing
* Clipboard integration
* Theme system
* Token-aware dashboards with streaming-backed data sources
* Hardened renderer with dirty-region merging, stats, and CPU fallback
* Async PTY session manager with cross-platform spawn support
* Configurable event loop with zigzag backend, frame budgeting, and telemetry
* Structured async runtime with nurseries, test harness, and lifecycle hooks

## Widgets

**Basic:** Text, Block, List, Button, Input, TextArea, Border, Spinner
**Layout:** Container, Stack, Tabs, FlexRow, FlexColumn, ScrollView
**Data:** ProgressBar, Table, TaskMonitor, ListView, RichText, ThemeTokenDashboard
**Visualization:** BarChart, Chart, Gauge, Sparkline, Calendar, Canvas
**Advanced:** TextEditor, SyntaxHighlight, StreamingText, CodeBlock, ThemePicker
**System:** UniversalPackageBrowser, AURDependencies, SystemMonitor, NetworkTopology, CommandBuilder
**Blockchain:** BlockchainPackageBrowser

## Installation

Requires Zig 0.16+

```bash
zig fetch --save https://github.com/ghostkellz/phantom/archive/refs/tags/v0.7.0.tar.gz
```

In `build.zig`:

```zig
const phantom_dep = b.dependency("phantom", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("phantom", phantom_dep.module("phantom"));
```

## Quick Start

```zig

## Layout Engine & Migration Helpers

The unified constraint engine lives under `phantom.layout.engine`. Start by creating a `LayoutBuilder`, register nodes, and let the solver resolve rectangles:

```zig
const engine = phantom.layout.engine;
const Rect = phantom.geometry.Rect;

var builder = engine.LayoutBuilder.init(allocator);
defer builder.deinit();

const root = try builder.createNode();
try builder.setRect(root, Rect{ .x = 0, .y = 0, .width = 120, .height = 32 });

const left = try builder.createNode();
const right = try builder.createNode();

try builder.row(root, &.{
    .{ .handle = left, .weight = 1.0 },
    .{ .handle = right, .weight = 2.0 },
});

var resolved = try builder.solve();
defer resolved.deinit();

const left_rect = resolved.rectOf(left);
const right_rect = resolved.rectOf(right);
```

Legacy helpers such as `layout.constraint.Layout.split` still work but emit compile-time notices steering you to the new engine. If you need a temporary bridge, import `phantom.layout.migration`—its `splitRowLegacy`, `splitColumnLegacy`, and `splitGridLegacy` helpers convert raw weights to the new `WeightSpec` API while logging a reminder during compilation.

> **Heads-up:** Migration helpers allocate short-lived buffers per call; they are designed for transitional code and will be removed before v1.0.

const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Start the global async runtime (zsync powered)
    _ = try phantom.async_runtime.startGlobal(allocator, .{
        .worker_threads = 2,
        .name = "demo-runtime",
    });
    defer phantom.async_runtime.shutdownGlobal();

    var app = try phantom.App.init(allocator, .{
        .tick_rate_ms = 50,
        .event_loop_config = .{
            .backend = .auto,
            .frame_budget_ms = 12,
            .trace_overruns = true,
        },
    });
    defer app.deinit();

    try app.run();
}
```

## Theme Manifest Prototype

Phase 2 adds a JSON-powered theme manifest that captures palette tokens, typography presets, and component overrides in one place. The schema and parser live in `src/style/theme.zig` and are re-exported as `phantom.style_theme`. You can load and validate manifests at runtime:

```zig
const std = @import("std");
const phantom = @import("phantom");

pub fn loadTheme(allocator: std.mem.Allocator, bytes: []const u8) !phantom.theme.Theme {
    var manifest = try phantom.style_theme.Manifest.parse(allocator, bytes);
    defer manifest.deinit();
    try manifest.validate();
    return try manifest.toTheme(allocator);
}
```

Starter manifests are available under `examples/themes/phantom-nightfall.json` (dark) and `examples/themes/phantom-daybreak.json` (light). Each file wires up the required palette tokens, typography presets, and a couple of component styles so you can experiment with hot-swapping themes without writing Zig code.

Run `zig build demo-theme-gallery` to launch the Theme Gallery demo, which watches those manifests, hot-reloads changes on the fly, and previews how buttons, notices, and surface tokens adapt per theme.

## Local Build & Test Workflow

Phantom deliberately ships without hosted CI. Instead, keep validation in your local environment with `scripts/run-tests.sh`:

```bash
scripts/run-tests.sh
```

The script runs `zig build` followed by `zig build test`. Pass `--release-safe`, `--release-fast`, or `--release-small` to exercise other optimize modes, `--skip-build`/`--skip-tests` to narrow the run, and `--zig-flag <flag>` to forward any extra flag to both commands. All additional arguments are forwarded to the `zig build test` step, so you can target specific build steps if you add them to `build.zig`.

> **Tip:** If you maintain multiple Zig toolchains, set `ZIG` in your shell before invoking the script to pick a specific compiler binary.

## Streaming Theme Dashboards

Phase 3 introduces streaming-aware data plumbing and a token-centric dashboard widget:

* `phantom.data_streaming.StreamingListSource` – wraps a zsync channel and feeds updates into any `ListDataSource` consumer.
* `phantom.widgets.ThemeTokenDashboard` – renders semantic, palette, and syntax tokens with live contrast metrics.

Pair them to surface theme changes in real time:

```zig
const phantom = @import("phantom");
const ThemeToken = phantom.widgets.ThemeToken;
const StreamingListSource = phantom.data_streaming.StreamingListSource(ThemeToken);

// Start the async runtime once in your app bootstrap
const runtime = try phantom.async_runtime.startGlobal(allocator, .{});
defer phantom.async_runtime.shutdownGlobal();

var stream = try StreamingListSource.init(allocator, runtime, .{});
defer stream.deinit();
try stream.start();

// Suppose `active_theme` is your current phantom.theme.Theme instance
const theme_tokens = try phantom.widgets.buildThemeTokenEntries(allocator, &active_theme);
defer theme_tokens.deinit();
try stream.setItems(theme_tokens.items);

const dashboard = try phantom.widgets.ThemeTokenDashboard.init(
    allocator,
    stream.asListDataSource(),
    "Theme Tokens",
    .{ .auto_follow = true },
);
// Attach the dashboard to your app: try app.addWidget(&dashboard.widget);

// Push updates as your theme changes or live metrics arrive
try stream.push(.{
    .name = "Live Accent",
    .group = "Semantic",
    .color = phantom.Color.magenta,
    .text_color = phantom.Color.white,
    .description = "Runtime accent override",
});
```

Call `stream.finish()` when you want to stop accepting updates; the dashboard will transition into the exhausted state and keep its last snapshot.

## Async Runtime Lifecycle

Phantom wraps the zsync runtime with a thin layer that exposes lifecycle hooks, telemetry, and a global singleton for UI apps. The helpers live under `phantom.async_runtime`:

* `startGlobal(allocator, config)` – initialize (or reuse) the global runtime and start it if needed.
* `ensureGlobal(allocator, config)` – obtain a handle without starting it; useful when another subsystem owns the lifecycle.
* `shutdownGlobal()` – tear down the runtime and release threads/resources.
* `globalRuntime()` – fetch the currently running instance, if any.

The config structure lets you pick worker counts, friendly names, debug logging, and lifecycle callbacks:

```zig
const runtime = try phantom.async_runtime.startGlobal(allocator, .{
    .worker_threads = 4,
    .debug_logging = true,
    .hooks = .{
        .on_start = myStartHook,
        .on_shutdown = myStopHook,
    },
});
defer phantom.async_runtime.shutdownGlobal();

runtime.logStats(); // emits structured metrics on shutdown when debug_logging is true
```

Need structured concurrency? `phantom.async_runtime.nursery.Nursery` gives you spawn/cancel/wait semantics, and `phantom.async_runtime.withTestHarness` wraps common testing patterns:

```zig
fn doWork() !void {
    // Simulate async work here
}

try phantom.async_runtime.withTestHarness(allocator, .{ .worker_threads = 1 }, struct {
    fn body(h: *phantom.async_runtime.TestHarness) !void {
        try h.spawn(doWork, .{});
        try h.waitAll();
    }
}.body);
```

## Event Loop Configuration & Metrics

The `phantom.EventLoop` now accepts a `Config` so you can choose the backend, frame pacing, and telemetry toggles up front. `App.init` propagates the `AppConfig.event_loop_config`, but you can also drive the loop manually:

```zig
var loop = phantom.EventLoop.initWithConfig(allocator, .{
    .backend = .zigzag,
    .tick_interval_ms = 8,
    .frame_budget_ms = 10,
    .trace_overruns = true,
});
defer loop.deinit();

loop.addHandler(handleEvent) catch {};
try loop.run();

const metrics = loop.getMetrics();
std.log.info("frame budget(ns) = {d}, queue depth = {d}", .{
    metrics.frame_budget_ns,
    metrics.queue_depth,
});
```

`loop.logMetrics()` prints a single structured line containing frame durations, queue depth, dropped events, and over-budget frame counts—handy for profiling and budgets.

## Telemetry & Diagnostics

Both the event loop and async runtime expose lightweight metrics:

* `phantom.EventLoop.getMetrics()` returns frame timing, queue depth, pending command counts, peak backlog, and overrun totals.
* Enabling `Config.trace_overruns` logs a warning whenever a frame exceeds its budget.
* `phantom.async_runtime.AsyncRuntime.getStats()` captures spawn/completion counts, pending futures, IO ops, uptime, and worker provisioning. Call `logStats()` to emit them via `std.log`.

Feed these into your observability pipeline or just keep an eye on them during development when tuning back-pressure or frame budgets.

## Terminal Sessions

Phantom ships an async-native PTY session manager that lets you embed real shells or background commands alongside your widgets. The manager lives at `phantom.terminal_session.Manager` and requires the shared async runtime:

```zig
const std = @import("std");
const phantom = @import("phantom");
const session = phantom.terminal_session;

var runtime = try phantom.async_runtime.AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
defer runtime.deinit();
try runtime.start();
defer runtime.shutdown();

var manager = try session.Manager.init(allocator, runtime);
defer manager.deinit();

const handle = try manager.spawn(.{
    .command = &.{ "/bin/sh", "-c", "printf phantom" },
    .columns = 80,
    .rows = 24,
});

var done = false;
while (!done) {
    if (try manager.tryNextEvent()) |evt| {
        switch (evt.event) {
            .data => |payload| {
                // ...push payload into your widget...
            },
            .exit => |status| {
                std.log.info("session exited {any}", .{status});
                done = true;
            },
        }

        manager.recycleEvent(evt.handle, evt.event) catch {};
    } else {
        std.time.sleep(2 * std.time.ns_per_ms);
    }
}

manager.release(handle);
```

Remember to recycle each event once processed so that the session can reuse its internal buffers.

Want to see the full UI loop integration? Run the new demo and watch PTY output flow into a `StreamingText` widget while a `TaskMonitor` tracks bytes in real time:

```bash
zig build demo-terminal-session
```

## Rendering Pipeline

Phantom now ships a dedicated `render.Renderer` with a hardened CPU pipeline. The renderer wraps the Unicode-aware `CellBuffer`, merges adjacent dirty regions, tracks detailed frame statistics, and outputs directly to stdout, files, or in-memory buffers.

```zig
const std = @import("std");
const phantom = @import("phantom");

var renderer = try phantom.render.Renderer.init(allocator, .{
    .size = phantom.Size.init(80, 24),
    .target = .stdout,
});
defer renderer.deinit();

var frame = renderer.beginFrame();
_ = try frame.writeText(0, 0, "Hello Phantom", phantom.Style.default());
try renderer.flush();

const stats = renderer.getStats();
std.debug.print("frames: {}, dirty regions: {}\n", .{ stats.frames, stats.last_dirty_regions });
```

Need to repaint the whole surface? Call `renderer.requestFullRedraw()`. Resize events automatically mark the full surface dirty so the next flush updates every cell. Dirty region merging can be toggled per configuration.

## Animations & Transitions

The animation subsystem now includes timeline-driven transitions for layout changes and widget entrance effects. `App` automatically animates vertical layouts—new widgets grow into place, and resizes morph between rectangles—when `enable_transitions` is `true` (the default).

```zig
var app = try phantom.App.init(allocator, .{
    .tick_rate_ms = 50,
    .enable_transitions = true,
    .transition_duration_ms = 220,
    .transition_curve = phantom.animation.TransitionCurve.ease_out,
});
```

Need custom effects? Use the timeline-aware helpers exposed under `phantom.animation`:

```zig
var manager = phantom.animation.TransitionManager.init(allocator);
defer manager.deinit();

const spec = phantom.animation.TransitionSpec{
    .duration_ms = 180,
    .phase = .entering,
    .auto_remove = false,
};

const fade = try phantom.animation.Transitions.fade(&manager, 0.0, 1.0, spec);
// Query progress each frame
_ = fade.progressValue();
```

Transitions can morph rectangles (`Transitions.rectMorph`) or slide positions, and they integrate with the existing `Animation` easing catalog. Tie them to widget state, or tap into the built-in manager that powers the default app layout animations.

## Examples

```bash
# Data visualization demo
zig build demo-data-visualization

# Grove syntax highlighting demo
zig build run-grove-demo

# Other demos
zig build demo-feature-showcase
zig build demo-stability-test
zig build run-reaper-aur
zig build run-ghostty-perf
zig build demo-terminal-session
```

## Documentation

* [Grove Integration Guide](docs/GROVE_INTEGRATION.md)
* [Phantom Integration Guide](docs/PHANTOM_INTEGRATION.md)
* [Features Overview](docs/FEATURES.md)
* [Widget Documentation](docs/widgets/)
* [Search Functionality](docs/SEARCH.md)
* [Unicode Support](docs/UNICODE.md)
* [Terminal Session Manager](docs/TERMINAL_SESSIONS.md)
* [Transitions](docs/TRANSITIONS.md)

## Build Configuration

Customize which widgets are included:

```bash
# Full build (all widgets)
zig build

# Minimal build (basic widgets only)
zig build -Dpreset=basic

# Package manager preset
zig build -Dpreset=package-mgr

# Individual feature flags
zig build -Dbasic-widgets=true -Ddata-widgets=false
```

Presets: `basic`, `package-mgr`, `crypto`, `system`, `full`

## License

See LICENSE file

## 👻 Built with next-gen Zig by [GhostKellz](https://github.com/ghostkellz)

