# Phantom TUI Framework

Terminal user interface framework for Zig, inspired by Ratatui.

<p align="center">
  <img src="https://img.shields.io/badge/Built_with-Zig-F7A41D?style=for-the-badge&logo=zig&logoColor=white" alt="Built with Zig">
  <img src="https://img.shields.io/badge/Zig-0.17.0-F7A41D?style=for-the-badge&logo=zig&logoColor=white" alt="Zig 0.17.0">
  <img src="https://img.shields.io/badge/TUI-Framework-0078D4?style=for-the-badge&logo=gnometerminal&logoColor=white" alt="TUI Framework">
  <img src="https://img.shields.io/badge/30+-Widgets-E91E63?style=for-the-badge" alt="30+ Widgets">
  <img src="https://img.shields.io/badge/Animated-Transitions-9B59B6?style=for-the-badge" alt="Animated Transitions">
  <img src="https://img.shields.io/badge/Unicode-Ready-00D4AA?style=for-the-badge" alt="Unicode Ready">
</p>

## What Phantom Is Best At

* Building app-style TUIs around `App`, core widgets, and `layout.engine`
* Theme-driven interfaces with manifest loading and live refresh workflows
* Dashboards, monitoring views, and async-backed data presentation
* Unicode-aware rendering, transitions, and a configurable event loop
* Advanced integrations such as Grove syntax highlighting and PTY-backed terminal sessions

## Recommended Surface

**Canonical widgets:** Text, Paragraph, Block, List, Button, Input, TextArea, ProgressBar, Table

**Rich text primitives:** `phantom.text.{Span, Line, Text}` back the `Paragraph` widget for styled, wrapped, multi-line content

**Canonical composition path:** Container, ScrollView, ListView, `layout.engine`

**Canonical advanced workflows:** Theme Gallery, Data Dashboard, Grove syntax highlighting, PTY terminal integration

Everything else in Phantom is available, but these are the surfaces the project should feel strongest and most trustworthy on first.

## Installation

**Requires Zig 0.17.0-dev** (verified with `0.17.0-dev.56+a8226cd53`)

```bash
zig fetch --save https://github.com/ghostkellz/phantom/archive/refs/tags/v0.8.7.tar.gz
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
const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = try phantom.async_runtime.startGlobal(allocator, .{});
    defer phantom.async_runtime.shutdownGlobal();

    var app = try phantom.App.init(allocator, .{
        .title = "Phantom Demo",
        .tick_rate_ms = 50,
    });
    defer app.deinit();

    const text = try phantom.widgets.Text.initWithStyle(
        allocator,
        "Welcome to Phantom",
        phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold(),
    );
    try app.addWidget(&text.widget);

    try app.run();
}
```

## Layout Engine & Migration Helpers

The unified constraint engine lives under `phantom.layout.engine`. Start by creating a `LayoutBuilder`, register nodes, and let the solver resolve rectangles:

```zig
const phantom = @import("phantom");
const engine = phantom.layout.engine;
const Rect = phantom.Rect;

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

Legacy helpers such as `layout.constraint.Layout.split` still work but emit compile-time notices steering you to the new engine. If you need a temporary bridge, import `phantom.layout.migration` - its `splitRowLegacy`, `splitColumnLegacy`, and `splitGridLegacy` helpers convert raw weights to the new `WeightSpec` API while logging a reminder during compilation.

> **Heads-up:** Migration helpers allocate short-lived buffers per call; they are designed for transitional code and will be removed before v1.0.

## Theme Workflow

Phantom's strongest differentiation today is its manifest-driven theme workflow. The schema and parser live in `src/style/theme.zig` and are re-exported as `phantom.style_theme`. You can load and validate manifests at runtime:

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

## Support Matrix

| Surface | Status | Notes |
| --- | --- | --- |
| `App` + core widgets + `layout.engine` | Recommended | Best default path for new applications |
| themes, dashboards, async runtime | Supported | Strong product story today |
| Grove syntax highlighting | Supported advanced | Heavier dependency surface |
| `vxfw` | Advanced | Lower-level, more specialized than the main path |
| terminal widget and PTY sessions | Supported advanced | Build with `-Dterminal-widget=true` and use the dedicated demo/doc path |
| workspace-style apps | Supported advanced | Use `demo-workspace` for the canonical sidebar + editor + terminal path |

## Local Build & Test Workflow

Phantom deliberately ships without hosted CI. Instead, keep validation in your local environment with `scripts/run-tests.sh`:

```bash
scripts/run-tests.sh
```

The script runs `zig build` followed by `zig build test`. Pass `--release-safe`, `--release-fast`, or `--release-small` to exercise other optimize modes, `--skip-build`/`--skip-tests` to narrow the run, and `--zig-flag <flag>` to forward any extra flag to both commands. All additional arguments are forwarded to the `zig build test` step, so you can target specific build steps if you add them to `build.zig`.

By default, `zig build` only validates and installs the core Phantom executable. Demos and benchmarks remain available as explicit `zig build <step>` targets. If you want the default build to install those optional artifacts too, pass `-Dinstall-optional-artifacts=true`.

## Workspace Path

Phantom now has a canonical workspace-style demo for editor and shell applications:

```bash
zig build -Dterminal-widget=true demo-workspace
```

That path combines:

* routed App focus handling
* a sidebar list
* workspace tabs for multi-buffer and pane switching
* a supported `CodeEditor` widget path
* a PTY-backed terminal pane
* a status line for workspace feedback

The current demo also shows the recommended pane command flow:

* `Enter` opens the sidebar selection into the editor
* `Tab` / `Shift-Tab` switch editor and terminal tabs inside the workspace
* `/`, `n`, and `N` drive editor search navigation
* `g` and `G` jump to the top or bottom of the buffer
* `p` uses the terminal paste path
* `Esc` returns focus to the sidebar

This is the recommended starting point for applications closer to `ghostshell`, `grim`, or other pane-oriented TUI workspaces.

The current workspace demo is backed by real repository files, so editor buffers, dirty tracking, and `s` saves now operate on the listed filesystem paths instead of seeded sample text.

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

Phantom ships a PTY-backed terminal path that is now worth treating as a real advanced workflow rather than a hidden experiment. Use it when you want a real shell or subprocess output inside a Phantom app.

The manager lives at `phantom.terminal_session.Manager` and the widget lives at `phantom.widgets.Terminal`. Build with `-Dterminal-widget=true` to enable the path.

The current feature-enabled path is verified with:

- `zig build -Dterminal-widget=true demo-terminal-session`
- `zig build -Dterminal-widget=true test`

Current mouse forwarding uses xterm SGR sequences and now carries mode-aware modifier and motion bits. Full hover and richer drag fidelity are still bounded by Phantom's current `MouseEvent` surface.

The manager requires the shared async runtime:

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

Want to see the full UI loop integration? Run the dedicated demo and watch PTY output flow into a real terminal widget while Phantom tracks session bytes in the status line:

```bash
zig build -Dterminal-widget=true demo-terminal-session
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

## Canonical Demos

```bash
# Curated overview demo
zig build demo-feature-showcase

# Theme system and manifest hot reload
zig build demo-theme-gallery

# Data-bound widgets and dashboard flow
zig build demo-data-dashboard

# Lower-level advanced framework demo
zig build demo-vxfw

# Syntax highlighting integration
zig build run-grove-demo

# PTY-backed terminal integration
zig build -Dterminal-widget=true demo-terminal-session

# Run the curated set together
zig build demo
```

## Documentation

* [Docs Index](docs/README.md)
* [Integration Guide](docs/getting-started/integration.md)
* [API Reference](docs/reference/api.md)
* [Features Overview](docs/reference/features.md)
* [Widget Inventory](docs/reference/widget-inventory.md)
* [Widget Guide](docs/widgets/widget-guide.md)
* [Grove Integration Guide](docs/guides/grove-integration.md)
* [Search Guide](docs/guides/search.md)
* [Unicode Guide](docs/guides/unicode.md)
* [Terminal Session Manager](docs/guides/terminal-sessions.md)
* [Workspace Apps](docs/guides/workspace-apps.md)
* [Transitions](docs/architecture/transitions.md)

## Build Configuration

Customize which widgets are included:

```bash
# Full build (core validated by default)
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
