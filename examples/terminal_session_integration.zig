//! Terminal Session Integration Demo
//! PTY-backed terminal widget plus live session metrics in a Phantom app.

const std = @import("std");
const phantom = @import("phantom");

const term_session = phantom.terminal_session;

var global_app: *phantom.App = undefined;
var global_terminal: *phantom.widgets.Terminal = undefined;
var global_status: *phantom.widgets.Text = undefined;
var global_manager: *term_session.Manager = undefined;
var global_handle: term_session.SessionHandle = undefined;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try phantom.async_runtime.AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    var manager = try term_session.Manager.init(allocator, runtime);
    defer manager.deinit();
    global_manager = manager;

    const command = if (@import("builtin").os.tag == .windows)
        &.{"cmd.exe"}
    else
        &.{ "/bin/sh", "-i" };

    const handle = try manager.spawn(.{
        .command = command,
        .columns = 96,
        .rows = 24,
    });
    defer manager.release(handle);
    global_handle = handle;

    const session_ptr = try manager.getSession(handle);
    const metrics_ptr = try manager.metrics(handle);

    var terminal_widget = try phantom.widgets.Terminal.init(allocator, .{
        .runtime = runtime,
        .scrollback_limit = 4_000,
        .placeholder_text = "Terminal session starting...",
    });
    global_terminal = terminal_widget;
    terminal_widget.attachSession(session_ptr, metrics_ptr);

    var status = try phantom.widgets.Text.initWithStyle(
        allocator,
        "Starting PTY session...",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    global_status = status;

    var layout = try phantom.widgets.Container.init(allocator, .vertical);
    layout.setGap(1);
    layout.setPadding(1);
    try layout.addChildWithFlex(&terminal_widget.widget, 6);
    try layout.addChildWithFlex(&status.widget, 1);

    var app = try phantom.App.init(allocator, .{
        .title = "Phantom Terminal Session Demo",
        .tick_rate_ms = 40,
        .mouse_enabled = false,
        .add_default_handler = false,
    });
    defer app.deinit();
    global_app = &app;

    try app.addWidget(&layout.widget);
    try app.event_loop.addHandler(handleEvent);
    try app.run();
}

fn handleEvent(event: phantom.Event) !bool {
    switch (event) {
        .tick => {
            const dirty = global_terminal.poll();
            try updateStatus();
            if (dirty) global_app.invalidate();
            try global_app.render();
            return false;
        },
        .key => |key| {
            if (key.isChar('q') or key == .ctrl_c) {
                global_app.stop();
                return true;
            }

            switch (key) {
                .page_up => {
                    global_terminal.scrollLines(5);
                    global_app.invalidate();
                    return false;
                },
                .page_down => {
                    global_terminal.scrollLines(-5);
                    global_app.invalidate();
                    return false;
                },
                .end => {
                    global_terminal.scrollToBottom();
                    global_app.invalidate();
                    return false;
                },
                .char => |ch| {
                    if (ch == 'f') {
                        global_terminal.setAutoFollow(!global_terminal.isAutoFollow());
                        global_app.invalidate();
                        return false;
                    }
                },
                else => {},
            }

            if (global_terminal.widget.handleEvent(event)) {
                global_app.invalidate();
                return false;
            }
        },
        else => {},
    }
    return false;
}

fn updateStatus() !void {
    const metrics = try global_manager.metrics(global_handle);
    const read = metrics.bytes_read.load(.acquire);
    const written = metrics.bytes_written.load(.acquire);
    const dropped = metrics.dropped_bytes.load(.acquire);
    const exits = metrics.exits.load(.acquire);

    const exit_note = if (global_terminal.pending_exit) |status|
        switch (status) {
            .still_running => "running",
            .exited => |code| blk: {
                var buf: [32]u8 = undefined;
                break :blk std.fmt.bufPrint(&buf, "exit {d}", .{code}) catch "exited";
            },
            .signal => |sig| blk: {
                var buf: [32]u8 = undefined;
                break :blk std.fmt.bufPrint(&buf, "signal {d}", .{sig}) catch "signaled";
            },
        }
    else
        "running";

    const line = try std.fmt.allocPrint(
        global_app.allocator,
        "PTY status: {s} | read {d} B | wrote {d} B | dropped {d} B | exits {d} | follow {s} | scroll {d} | PgUp/PgDn scroll | End bottom | f toggle follow | q quits",
        .{ exit_note, read, written, dropped, exits, if (global_terminal.isAutoFollow()) "on" else "off", global_terminal.scrollOffset() },
    );
    defer global_app.allocator.free(line);
    try global_status.setContent(line);
}
