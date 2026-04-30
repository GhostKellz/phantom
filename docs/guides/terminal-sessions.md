# Terminal Session Manager

Phantom exposes a platform-aware PTY manager that lets you launch interactive shells or background processes from inside your application. The manager lives at `phantom.terminal_session.Manager` and bridges PTY output into Phantom's async runtime so that widgets can consume terminal data without blocking the UI thread.

The current feature-enabled terminal path has been re-verified on the Zig `0.17.0-dev` workspace baseline with:

- `zig build -Dterminal-widget=true demo-terminal-session`
- `zig build -Dterminal-widget=true test`

## When to use it

- Embedding a shell or REPL next to other widgets (editor + terminal layouts)
- Running build/test commands inside your TUI and streaming output live
- Capturing tool output while keeping scrollback and exit status information
- Forwarding PTY data into higher-level widgets (e.g. upcoming Terminal widget RFC)

## Prerequisites

1. Use the current Phantom Zig `0.17.0-dev` baseline.
2. Initialize the shared async runtime (`phantom.async_runtime.AsyncRuntime`) and keep it running for the lifetime of the manager.
3. Provide a PTY configuration (`phantom.terminal_session.Config`), typically specifying the command, columns, and rows.

Phantom's async runtime is the intended public surface here. Use `runtime.spawn(...)`, `handle.wait()`, and the global runtime helpers from `phantom.async_runtime` rather than depending on zsync internals directly from app code.

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

## Terminal widget behavior

The PTY-backed widget path is intentionally narrower than a full terminal emulator, but it now has a concrete supported behavior set:

- plain text buffering and scrollback retention
- ANSI SGR color/style application for rendered cells
- basic cursor editing on the active line
  - cursor left/right
  - cursor column positioning
  - save/restore cursor column
  - delete-char and erase-char handling
- bounded line-oriented behavior for common shell output
  - linefeed, carriage return, tab, backspace
  - keeping the active line visible in constrained viewports
- PTY-backed interactive input through widget key events
- manager-owned session attachment without transferring ownership to the widget

It does not yet aim to be a full escape-sequence-complete terminal emulator. Multi-line cursor addressing, scroll regions, and deeper terminal state modeling are still partial.

## Supported ANSI and CSI behavior

Current widget-side parsing/rendering support includes:

- text and UTF-8 character input
- linefeed, carriage return, tab, backspace, and delete
- SGR attribute application for common style and color changes
  - reset
  - bold, dim, italic, underline, blink, reverse, strikethrough
  - 8-color, bright 8-color, 256-color, and RGB foreground/background colors
- cursor movement on the buffered view
  - cursor left/right
  - cursor next line / previous line
  - cursor column and cursor position column handling
  - cursor line targeting in the current buffered view
  - save/restore cursor position within the widget's bounded row/column model
- character and line edits in the bounded buffer model
  - erase line
  - erase display
  - delete chars
  - erase chars
  - insert lines
  - delete lines
  - scroll up / scroll down as buffer edits

Still partial or intentionally limited:

- full terminal-emulator-accurate multi-line cursor state
- scroll region semantics
- alternate screen behavior
- comprehensive DEC/private mode handling
- full shell-grade redraw fidelity for all terminal applications

## Follow mode and scrolling

The terminal widget now exposes explicit viewport controls:

- `setAutoFollow(bool)` keeps the view pinned to the newest output when enabled
- `scrollLines(delta)` moves the viewport away from the newest output
- `scrollToBottom()` restores the latest-output view and re-enables follow mode
- `scrollOffset()` reports the current manual offset from the bottom

The demo exposes these controls directly:

- `PageUp` scrolls upward
- `PageDown` scrolls downward
- `End` jumps back to the bottom
- `f` toggles follow mode

When the viewport is not following the latest output, the widget also renders a compact in-viewport hint showing the current follow mode and scroll offset.

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

Run `zig build -Dterminal-widget=true demo-terminal-session` to see the full integration in action, including live PTY metrics plus follow-mode and manual scroll controls in the status line.

## Platform notes

- **Linux/macOS:** Uses native PTY syscalls via Zig's `std.posix` bindings.
- **Windows:** Wraps ConPTY under the hood (requires Windows 10 build 1903 or later).
- If PTY creation fails (unsupported platform, missing shell, etc.), `manager.spawn` returns the underlying error so you can present a friendly message to the user.

## Next steps

- Adapt the demo handler pattern to your own layout so other widgets redraw as PTY events stream in.
- Keep expanding observability: feed more sessions into `TaskMonitor` or aggregate metrics into dashboards.
- Explore `docs/rfcs/terminal_widget_mvp.md` for the larger roadmap that this manager unlocks.
