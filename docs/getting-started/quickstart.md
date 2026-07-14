# Phantom Quickstart

A hands-on tour of the core Phantom loop on the current `0.17.0-dev` baseline. Each
step builds on the previous one and uses only supported `phantom.App` + widget APIs.

Prerequisites: you have added Phantom to your `build.zig` as described in
[`integration.md`](integration.md).

## 1. Hello World

Every Phantom program creates an `App`, adds one or more widgets, and calls `run`.
`run` installs a default handler that quits on `Esc`/`Ctrl+C`.

```zig
const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try phantom.App.init(allocator, .{ .title = "Hello" });
    defer app.deinit();

    const hello = try phantom.widgets.Text.initWithStyle(
        allocator,
        "Hello from Phantom",
        phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold(),
    );
    try app.addWidget(&hello.widget);

    try app.run();
}
```

Widgets are heap-allocated and owned by the caller. Adding them to the `App` wires
them into the render + event loop; the `App` renders every widget you add.

## 2. Stateful Counter

Widget state lives in the widget. To drive it from your own logic, keep a pointer to
the widget and mutate it in response to events. The simplest approach is a small
custom widget, but you can also update a `Text` widget's content on each tick.

```zig
var count: i64 = 0;
var label_buf: [32]u8 = undefined;

const label = try phantom.widgets.Text.init(allocator, "count: 0");
try app.addWidget(&label.widget);

// Later, from an event or tick handler:
count += 1;
const rendered = try std.fmt.bufPrint(&label_buf, "count: {d}", .{count});
try label.setContent(rendered);
```

`Text.setContent` copies the slice, so a reused stack buffer is safe.

## 3. List Selection

`List` handles arrow keys (and `j`/`k`) internally once it has focus. Selection is
part of its snapshotable state.

```zig
const list = try phantom.widgets.List.init(allocator);
try list.addItemText("Overview");
try list.addItemText("Metrics");
try list.addItemText("Logs");
try app.addWidget(&list.widget);

// Read the current selection at any time:
if (list.getSelectedItem()) |item| {
    // item.text is the selected label
}
```

Because `List` conforms to `StatefulWidget`, you can capture and restore its
selection and scroll position:

```zig
const snapshot = list.state();   // .{ .selected_index, .scroll_offset }
// ... rebuild or navigate away ...
list.applyState(snapshot);       // restore selection + scroll
```

## 4. Form Input

`Input` is a single-line text field with placeholder text, cursor handling, and
change/submit callbacks.

```zig
fn onSubmit(_: *phantom.widgets.Input, text: []const u8) void {
    std.log.info("submitted: {s}", .{text});
}

const field = try phantom.widgets.Input.init(allocator);
try field.setPlaceholder("Enter your name...");
field.setOnSubmit(&onSubmit);
try app.addWidget(&field.widget);

// Read the value directly whenever you need it:
const value = field.getText();
```

`Input` also conforms to `StatefulWidget` (`cursor_pos`, `selection_start`,
`scroll_offset`), so form field state can be saved and restored the same way.

## 5. Async Data Refresh

Long-running or streaming work runs on the async runtime so it never blocks the
render loop. Feed results to the UI through a `StreamingListSource`, which is backed
by a bounded channel.

```zig
const async_runtime = phantom.async_runtime;

const runtime = try async_runtime.AsyncRuntime.init(allocator, .{ .worker_threads = 2 });
defer runtime.deinit();
try runtime.start();
defer runtime.shutdown();

const Row = struct { id: u32, text: []const u8 };

var stream = try phantom.data.StreamingListSource(Row).init(
    allocator,
    runtime,
    .{ .channel_capacity = 128 },
);
defer stream.deinit();
try stream.start();

// Producer running on the runtime pushes rows as they arrive:
fn produce(s: *phantom.data.StreamingListSource(Row)) !void {
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try s.push(.{ .id = i, .text = "row" });
    }
    s.finish();
}

var task = try runtime.spawn(produce, .{&stream});
defer task.deinit();
```

The channel's capacity bounds how far the producer may run ahead of the consumer, so
a fast producer applies natural backpressure instead of unbounded buffering.

For a single shared runtime across your whole app, `async_runtime.startGlobal` /
`shutdownGlobal` manage a process-wide instance instead of a local one.

## Where to Go Next

- [`../reference/api.md`](../reference/api.md) — the supported public API surface.
- [`../reference/api-stability.md`](../reference/api-stability.md) — which APIs are
  stable, advanced, experimental, or migration-only.
- [`../guides/ratatui-migration.md`](../guides/ratatui-migration.md) — concept map for
  developers coming from ratatui.
- [`../guides/async-streaming.md`](../guides/async-streaming.md) — deeper async and
  streaming patterns.
