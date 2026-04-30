//! Feature Showcase Demo - curated overview of the recommended Phantom path.

const std = @import("std");
const phantom = @import("phantom");

var global_app: *phantom.App = undefined;

const showcase_text =
    \\Phantom is strongest when you build around a small, composable core.
    \\
    \\Recommended path:
    \\  1. Start with phantom.App
    \\  2. Compose core widgets from phantom.widgets
    \\  3. Prefer phantom.layout.engine for new layout work
    \\  4. Add themes, dashboards, syntax highlighting, or terminal sessions only as needed
    \\
    \\Canonical demos:
    \\  - zig build demo-theme-gallery
    \\  - zig build demo-data-dashboard
    \\  - zig build demo-vxfw
    \\  - zig build -Dterminal-widget=true demo-terminal-session
    \\
    \\Supported surface:
    \\  - App, widgets, layout.engine
    \\  - themes and manifest loading
    \\  - data dashboards and async runtime helpers
    \\  - Grove-backed syntax highlighting
    \\
    \\Advanced surface:
    \\  - vxfw for lower-level widget control
    \\  - richer package/system/domain widgets where they fit your app
    \\
    \\Terminal path:
    \\  - PTY sessions are available behind -Dterminal-widget=true
    \\  - use the terminal demo as the reference integration path
    \\
    \\Press q or Ctrl+C to quit.
;

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
