//! Phantom - The Next-Gen TUI Framework for Zig
//! A lightning-fast, async-native TUI framework inspired by Rattatui
const std = @import("std");

// Build-time configuration
pub const phantom_config = @import("phantom_config");

// Core exports
pub const App = @import("app.zig").App;
pub const AppConfig = @import("app.zig").AppConfig;
pub const Terminal = @import("terminal.zig").Terminal;
pub const Event = @import("event.zig").Event;
pub const Key = @import("event.zig").Key;
pub const EventLoop = @import("event.zig").EventLoop;

// Widget system - conditionally exported based on build configuration
pub const widgets = if (phantom_config.enable_basic_widgets or phantom_config.enable_data_widgets or phantom_config.enable_package_mgmt or phantom_config.enable_crypto or phantom_config.enable_system or phantom_config.enable_advanced) @import("widgets/mod.zig") else struct {};

// Search functionality - conditionally exported with advanced widgets
pub const search = if (phantom_config.enable_advanced) @import("search/FuzzySearch.zig") else struct {};

// Advanced widget framework (vxfw) - always available
pub const vxfw = @import("vxfw.zig");

// Layout system - always available
pub const layout = @import("layout/mod.zig");
pub const render = @import("render/mod.zig");

// Input and events - always available
pub const input = @import("input/mod.zig");

// Core types - always available
pub const Rect = @import("geometry.zig").Rect;
pub const Position = @import("geometry.zig").Position;
pub const Point = @import("geometry.zig").Point;
pub const Size = @import("geometry.zig").Size;
pub const Color = @import("style.zig").Color;
pub const Style = @import("style.zig").Style;

// Widget system
pub const Widget = @import("widget.zig").Widget;
pub const SizeConstraints = @import("widget.zig").SizeConstraints;
pub const Buffer = @import("terminal.zig").Buffer; // Required for Widget.render signature
pub const Cell = @import("terminal.zig").Cell; // Required for Buffer.setCell

// Modern UI utilities - always available
pub const emoji = @import("emoji.zig");

// Async runtime - always available
pub const runtime = @import("runtime.zig");

// Font system with zfont + gcode integration
pub const font = @import("font/mod.zig");

// Unicode processing with gcode
pub const unicode = @import("unicode.zig");

// GPU rendering system (Vulkan + CUDA)
pub const gpu = @import("render/gpu/mod.zig");

// Animation system for smooth transitions
pub const animation = @import("animation.zig");

// Enhanced mouse support with hover, drag, etc.
pub const mouse = @import("mouse.zig");

// Clipboard integration (system copy/paste)
pub const clipboard = @import("clipboard.zig");

// Event system enhancements
pub const event_queue = @import("event/mod.zig");

// Async runtime for non-blocking operations
pub const async_runtime = @import("async/mod.zig");

// Theme system
pub const theme = @import("theme/mod.zig");

// Text processing
pub const fuzzy = @import("text/fuzzy.zig");
pub const unicode_helpers = @import("text/unicode_helpers.zig");

// Resource management
pub const resource_paths = @import("config/paths.zig");

// Constraint-based layout system
pub const Constraint = @import("layout/constraint.zig").Constraint;
pub const ConstraintLayout = @import("layout/constraint.zig").Layout;
pub const LayoutDirection = @import("layout/constraint.zig").Direction;

// Tree-sitter syntax highlighting
pub const grove = @import("grove");

// TOML parser
pub const zontom = @import("zontom");

// For compatibility with existing code
pub fn bufferedPrint() !void {
    const stdout_file = std.fs.File.stdout().writer();
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
