//! Phantom - The Next-Gen TUI Framework for Zig
//! A lightning-fast, async-native TUI framework inspired by Rattatui
const std = @import("std");

// Core exports
pub const App = @import("app.zig").App;
pub const AppConfig = @import("app.zig").AppConfig;
pub const Terminal = @import("terminal.zig").Terminal;
pub const Event = @import("event.zig").Event;
pub const EventLoop = @import("event.zig").EventLoop;

// Widget system
pub const widgets = @import("widgets/mod.zig");
pub const layout = @import("layout/mod.zig");
pub const render = @import("render/mod.zig");

// Input and events
pub const input = @import("input/mod.zig");

// Core types
pub const Rect = @import("geometry.zig").Rect;
pub const Position = @import("geometry.zig").Position;
pub const Size = @import("geometry.zig").Size;
pub const Color = @import("style.zig").Color;
pub const Style = @import("style.zig").Style;

// Async runtime
pub const runtime = @import("runtime.zig");

// For compatibility with existing code
pub fn bufferedPrint() !void {
    const stdout_file = std.fs.File.stdout().deprecatedWriter();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("Phantom TUI Framework initialized!\n", .{});
    try bw.flush();
}

// Test utilities
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
