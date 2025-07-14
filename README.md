# 👻 Phantom — The Next-Gen TUI Framework for Zig

[![Zig v0.15+](https://img.shields.io/badge/zig-0.15+-f7a41d?logo=zig\&logoColor=white)](https://ziglang.org/)
[![Async by zsync](https://img.shields.io/badge/async-zsync-blue)]()
[![Rattatui-inspired](https://img.shields.io/badge/tui-rattatui-ghostly)]()
[![Pure Zig](https://img.shields.io/badge/pure-zig-success)]()

---

**Phantom** is a lightning-fast, async-native TUI (terminal user interface) framework for Zig — inspired by Rattatui/tui-rs, rebuilt from scratch for Zig v0.15+ and the zsync async runtime.

---

## ✨ Features

* 🚀 **Pure Zig:** Zero C glue, idiomatic types
* ⚡ **zsync-powered async:** True async event loop, input, timers, and UI refresh
* 🧱 **Widgets Galore:** Tabs, lists, tables, trees, grids, progress, forms, modals, markdown, and more
* 🖼️ **Compositional Layouts:** Flex, grid, stack, float, absolute
* 🌈 **Styled Output:** Colors, gradients, bold, underline, Unicode, Nerd Font
* 🖱️ **Input Handling:** Keyboard, mouse, focus, signals
* 🔄 **Live Updates:** Async render loop—UI never blocks
* 🧩 **Extensible:** Custom widgets, event hooks, async actions
* 🧪 **Testable:** Snapshot and integration tests

---

## 🛠️ Quick Start

**Requirements:**

* Zig v0.15+
* (Optional) zsync for async workflows

```sh
git clone https://github.com/ghostkellz/phantom.git
cd phantom
zig build run
```

Or add to your build.zig:

```zig
const phantom_dep = b.dependency("phantom", .{ .target = target, .optimize = optimize });
const phantom = phantom_dep.module("phantom");
```

---

## 👾 Example Usage

```zig
const phantom = @import("phantom");

pub fn main() !void {
    var app = try phantom.App.init(.{ .title = "👻 Phantom Demo" });
    defer app.deinit();
    
    app.addWidget(phantom.widgets.List(.{ .items = &[_][]const u8{"Zig", "Async", "Phantom"} }));
    app.addWidget(phantom.widgets.ProgressBar(.{ .progress = 42 }));

    try app.run();
}
```

---

## ⚡️ Async Power

* **zsync integration:** Use async/await everywhere—event handlers, widgets, background jobs
* **Non-blocking input:** UI, signals, and timers run in async tasks
* **Async hooks:** Live network, file, or shell ops in your TUI (great for dashboards, chat, logs, etc)

---

## 🗺️ Roadmap

* [x] Async event loop with zsync
* [x] Core widgets: List, Table, Progress, Input, Tabs
* [x] Styled/colorized output
* [ ] Mouse support and focus
* [ ] Markdown/emoji rendering
* [ ] Custom layout engine (flex, grid)
* [ ] Async modals, popups, overlay support
* [ ] Snapshot testing
* [ ] WASM + Ghostty support

---

## 🤝 Contributing

PRs, issues, widget ideas, and flames welcome!
See [`CONTRIBUTING.md`](CONTRIBUTING.md) for guidelines and style.

---

## 👻 Built with next-gen Zig by [GhostKellz](https://github.com/ghostkellz)

