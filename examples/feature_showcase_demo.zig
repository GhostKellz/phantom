//! Feature Showcase Demo - ACTUAL working TUI
//! Shows real widgets rendering in a clean TUI

const std = @import("std");
const phantom = @import("phantom");

var global_app: *phantom.App = undefined;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try phantom.App.init(allocator, .{
        .title = "Phantom Feature Showcase",
        .tick_rate_ms = 50,
        .mouse_enabled = false,
    });
    defer app.deinit();
    global_app = &app;

    // Create showcase content
    const showcase_text =
        \\╔═══════════════════════════════════════════════════════════╗
        \\║          PHANTOM TUI - FEATURE SHOWCASE                   ║
        \\╚═══════════════════════════════════════════════════════════╝
        \\
        \\✨ WORKING FEATURES:
        \\
        \\📦 WIDGETS (49 available):
        \\  • Text - Multi-line rendering with styling
        \\  • ListView - Virtualized lists with filtering
        \\  • Block - Bordered containers
        \\  • Container - Vertical/horizontal layouts
        \\  • FlexRow/FlexColumn - Flexible layouts
        \\  • Input - Text input with focus
        \\  • Button - Interactive buttons
        \\  • Chart/BarChart - Data visualization
        \\  • Canvas - Custom drawing
        \\  • Spinner - Loading animations
        \\
        \\⚡ RENDERING:
        \\  ✓ Clean alternate screen mode
        \\  ✓ Proper termios configuration
        \\  ✓ Double buffering for flicker-free updates
        \\  ✓ Unicode/emoji support
        \\  ✓ RGB true color + 256 color palette
        \\
        \\🎮 INPUT:
        \\  ✓ Keyboard events (Ctrl, Alt, Function keys)
        \\  ✓ Mouse support (click, drag, scroll)
        \\  ✓ Focus management
        \\
        \\🎨 THEMES:
        \\  ✓ Built-in themes (ghost-hacker-blue, tokyo-night)
        \\  ✓ Custom theme support
        \\  ✓ Runtime theme switching
        \\
        \\📊 LAYOUT:
        \\  ✓ Constraint-based layouts
        \\  ✓ Flex layouts with gap/justify
        \\  ✓ Grid system
        \\  ✓ Z-index layering
        \\
        \\🚀 PERFORMANCE:
        \\  ✓ Event loop: < 1ms tick latency
        \\  ✓ Layout solver: O(n) complexity
        \\  ✓ Render diff: Only changed cells updated
        \\  ✓ ListView virtualization: 1000+ items performant
        \\
        \\✅ QUALITY (v0.8.1):
        \\  ✓ Zero terminal bleed-through
        \\  ✓ No stdout contamination
        \\  ✓ Proper cleanup on exit
        \\  ✓ Zig 0.16.0-dev compatible
        \\  ✓ Memory leak free
        \\
        \\Press 'q' or Ctrl+C to exit
    ;

    var text_widget = try phantom.widgets.Text.initWithStyle(
        allocator,
        showcase_text,
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );

    try app.addWidget(&text_widget.widget);
    try app.event_loop.addHandler(handleEvent);

    try app.run();
}

fn handleEvent(event: phantom.Event) !bool {
    switch (event) {
        .key => |key| {
            if (key.isChar('q') or key == .ctrl_c) {
                global_app.stop();
                return true;
            }
        },
        else => {},
    }
    return false;
}
