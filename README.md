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
* Clipboard integration
* Theme system

## Widgets

**Basic:** Text, Block, List, Button, Input, TextArea, Border, Spinner
**Layout:** Container, Stack, Tabs, FlexRow, FlexColumn, ScrollView
**Data:** ProgressBar, Table, TaskMonitor, ListView, RichText
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
const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try phantom.App.init(allocator, .{
        .tick_rate_ms = 50,
    });
    defer app.deinit();

    try app.run();
}
```

## Examples

```bash
# Data visualization demo
zig build run-demo-v0.7

# Grove syntax highlighting demo
zig build run-grove-demo

# Other demos
zig build run-demo-v0.6
zig build run-reaper-aur
zig build run-ghostty-perf
```

## Documentation

* [Grove Integration Guide](docs/GROVE_INTEGRATION.md)
* [Phantom Integration Guide](docs/PHANTOM_INTEGRATION.md)
* [Features Overview](docs/FEATURES.md)
* [Widget Documentation](docs/widgets/)
* [Search Functionality](docs/SEARCH.md)
* [Unicode Support](docs/UNICODE.md)

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

