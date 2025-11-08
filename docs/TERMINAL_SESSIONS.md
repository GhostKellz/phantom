# Terminal Session Manager

Phantom exposes a platform-aware PTY manager that lets you launch interactive shells or background processes from inside your application. The manager lives at `phantom.terminal_session.Manager` and bridges PTY output into Phantom's async runtime so that widgets can consume terminal data without blocking the UI thread.

## When to use it

- Embedding a shell or REPL next to other widgets (editor + terminal layouts)
- Running build/test commands inside your TUI and streaming output live
- Capturing tool output while keeping scrollback and exit status information
- Forwarding PTY data into higher-level widgets (e.g. upcoming Terminal widget RFC)

## Prerequisites

1. Use Zig 0.16.0-dev or newer.
2. Initialize the shared async runtime (`phantom.async_runtime.AsyncRuntime`) and keep it running for the lifetime of the manager.
3. Provide a PTY configuration (`phantom.terminal_session.Config`), typically specifying the command, columns, and rows.

## Quick start

```zig
const std = @import("std");
const phantom = @import("phantom");
const session = phantom.terminal_session;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    var finished = false;
    while (!finished) {
        if (try manager.tryNextEvent()) |evt| {
            const event = evt.event;
            switch (event) {
                .data => |payload| try output.appendSlice(payload),
                .exit => |status| {
                    std.debug.print("session exited: {any}\n", .{status});
                    finished = true;
                },
            }

            // Always recycle events so the session can reuse buffers.
            manager.recycleEvent(evt.handle, event) catch {};
        } else {
            std.time.sleep(2 * std.time.ns_per_ms);
        }
    }

    manager.release(handle);

    std.debug.print("terminal said: {s}\n", .{output.items});
}
```

### Recycle events

Each PTY read allocates a buffer owned by the session. After consuming an event, call `manager.recycleEvent(handle, event)` (or `Session.recycleEvent`) so that the allocator can reuse or free that memory. Exit events are no-ops, but recycling them keeps the API consistent.

### Access metrics

The manager keeps per-session metrics behind atomics so you can inspect health without contending on locks:

```zig
// assuming `monitor` is a phantom.widgets.TaskMonitor and `finished`
// flips to true once the PTY sends an exit event
const metrics = try manager.metrics(handle);
const read = metrics.bytes_read.load(.acquire);
const written = metrics.bytes_written.load(.acquire);
const dropped = metrics.dropped_bytes.load(.acquire);
```

### Cleaning up

`manager.release(handle)` stops the session, drains pending events, destroys the PTY resources, and frees its metrics block. Releasing every handle before `manager.deinit()` keeps shutdown predictable.

## Hook into the Phantom app loop

When you embed a terminal inside a full `phantom.App`, register a tick handler that polls the manager and invalidates the UI when new data arrives:

```zig
var updated = false;
while (try manager.tryNextEvent()) |evt| {
    switch (evt.event) {
        .data => |payload| {
            try terminal_view.addChunk(payload);
            updated = true;
        },
        .exit => |status| {
            terminal_view.stopStreaming();
            updated = true;
            app.stop(); // exit once the PTY finishes
        },
    }

    manager.recycleEvent(evt.handle, evt.event) catch {};
}

if (updated) {
    app.invalidate();
}
```

The [terminal session integration demo](../examples/terminal_session_integration.zig) wires this handler into `App.event_loop`, pairing a `StreamingText` widget with live PTY output.

## Monitor PTY metrics

Each session exposes atomics with byte counters and exit information. They plug nicely into the `TaskMonitor` widget so you can display status next to the live terminal:

```zig
const metrics = try manager.metrics(handle);
const read = metrics.bytes_read.load(.acquire);
const written = metrics.bytes_written.load(.acquire);
const dropped = metrics.dropped_bytes.load(.acquire);

const status = if (finished) TaskStatus.completed else TaskStatus.running;
const message = try std.fmt.allocPrint(allocator,
    "read {d} B • wrote {d} B • dropped {d} B", .{ read, written, dropped });
defer allocator.free(message);

try monitor.updateTask("pty-session", status, message);
if (finished) {
    monitor.completeTask("pty-session");
} else {
    monitor.updateProgress("pty-session", 42.0);
}
```

Run `zig build demo-terminal-session` to see the full integration in action, including a compact TaskMonitor that tracks read/write totals while the shell runs.

## Platform notes

- **Linux/macOS:** Uses native PTY syscalls via Zig's `std.posix` bindings.
- **Windows:** Wraps ConPTY under the hood (requires Windows 10 build 1903 or later).
- If PTY creation fails (unsupported platform, missing shell, etc.), `manager.spawn` returns the underlying error so you can present a friendly message to the user.

## Next steps

- Adapt the demo handler pattern to your own layout so other widgets redraw as PTY events stream in.
- Keep expanding observability: feed more sessions into `TaskMonitor` or aggregate metrics into dashboards.
- Explore `docs/rfcs/terminal_widget_mvp.md` for the larger roadmap that this manager unlocks.
