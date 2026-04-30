# Phantom Integration Guide

This guide describes the recommended way to integrate Phantom into a Zig application on the current `0.17.0-dev` baseline.

## Supported Starting Point

For most applications, start with:

- `phantom.App`
- core widgets from `phantom.widgets`
- `phantom.layout.engine` for new layout work
- `phantom.async_runtime` when you need background work or streaming data

Avoid starting with `vxfw` unless you already know you need the lower-level surface. PTY integration is now a supported advanced path, but it should still come after you are comfortable with the normal `App` + widget flow.

## Add Phantom

```bash
zig fetch --save https://github.com/ghostkellz/phantom/archive/refs/tags/v0.8.7.tar.gz
```

## `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const phantom_dep = b.dependency("phantom", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("phantom", phantom_dep.module("phantom"));
    b.installArtifact(exe);
}
```

## Minimal App

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
        .title = "Phantom App",
        .tick_rate_ms = 50,
    });
    defer app.deinit();

    const title = try phantom.widgets.Text.initWithStyle(
        allocator,
        "Hello from Phantom",
        phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold(),
    );
    try app.addWidget(&title.widget);

    try app.run();
}
```

## Layout Recommendation

For new code, prefer `phantom.layout.engine` over older split helpers.

```zig
const phantom = @import("phantom");
const engine = phantom.layout.engine;

var builder = engine.LayoutBuilder.init(allocator);
defer builder.deinit();

const root = try builder.createNode();
try builder.setRect(root, .{ .x = 0, .y = 0, .width = 120, .height = 32 });

const left = try builder.createNode();
const right = try builder.createNode();

try builder.row(root, &.{
    .{ .handle = left, .weight = 1.0 },
    .{ .handle = right, .weight = 2.0 },
});
```

If you are maintaining older code, `phantom.layout.migration` provides temporary shims.

## Feature Surface

| Surface | Status | Notes |
| --- | --- | --- |
| `App` + core widgets | Recommended | Best onboarding path |
| data widgets and dashboards | Supported | Good fit for monitoring and status UIs |
| Grove syntax highlighting | Supported advanced | Heavier dependency footprint |
| `vxfw` | Advanced | Lower-level and more specialized |
| terminal widget / PTY sessions | Supported advanced | Opt-in via `-Dterminal-widget=true` |

## Verification

Use the local script for the standard verification path:

```bash
scripts/run-tests.sh
```

For explicit optional artifacts:

```bash
zig build demo-vxfw
zig build demo-theme-gallery
zig build demo-data-dashboard
zig build run-grove-demo
zig build -Dterminal-widget=true demo-terminal-session
```
