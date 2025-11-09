//! Grim Editor - Tokyo Night themed with syntax highlighting
//! Demonstrates colorful IDE-quality rendering like nvim
const std = @import("std");
const phantom = @import("phantom");

var global_app: *phantom.App = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try phantom.App.init(allocator, .{
        .title = "Grim Editor - Tokyo Night",
        .tick_rate_ms = 50,
        .mouse_enabled = false,
    });
    defer app.deinit();
    global_app = &app;

    // File path (cyan - brighter)
    const filepath = try phantom.widgets.Text.initWithStyle(
        allocator,
        "◆src/animation.zig",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&filepath.widget);

    // Line 1: Comment (blue-gray, italic)
    const line1 = try phantom.widgets.Text.initWithStyle(
        allocator,
        "◆ 1  //! Animation system for Phantom TUI",
        phantom.Style.default().withFg(phantom.Color.blue).withItalic(),
    );
    try app.addWidget(&line1.widget);

    // Line 2: imports - bright cyan
    const line2 = try phantom.widgets.Text.initWithStyle(
        allocator,
        "◆ 2  const std = @import(\"std\");",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line2.widget);

    const line3 = try phantom.widgets.Text.initWithStyle(
        allocator,
        "  3  const ArrayList = std.array_list.Managed;",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line3.widget);

    const line4 = try phantom.widgets.Text.initWithStyle(
        allocator,
        "◆ 4  const geometry = @import(\"geometry.zig\");",
        phantom.Style.default().withFg(phantom.Color.bright_green),
    );
    try app.addWidget(&line4.widget);

    const line5 = try phantom.widgets.Text.initWithStyle(
        allocator,
        "  5  const style = @import(\"style.zig\");",
        phantom.Style.default().withFg(phantom.Color.bright_green),
    );
    try app.addWidget(&line5.widget);

    // Blank line
    const line6 = try phantom.widgets.Text.initWithStyle(
        allocator,
        "  6",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&line6.widget);

    // Type aliases - cyan/teal
    const line7 = try phantom.widgets.Text.initWithStyle(
        allocator,
        "  7  const Position = geometry.Position;",
        phantom.Style.default().withFg(phantom.Color.bright_cyan), // teal/mint
    );
    try app.addWidget(&line7.widget);

    const line8 = try phantom.widgets.Text.initWithStyle(
        allocator,
        "  8  const Size = geometry.Size;",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line8.widget);

    const line9 = try phantom.widgets.Text.initWithStyle(
        allocator,
        "  9  const Rect = geometry.Rect;",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line9.widget);

    const line10 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 10  const Style = style.Style;",
        phantom.Style.default().withFg(phantom.Color.bright_cyan), // cyan
    );
    try app.addWidget(&line10.widget);

    const line11 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 11  const Color = style.Color;",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line11.widget);

    const line12 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 12",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&line12.widget);

    // pub const - purple/magenta keywords
    const line13 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 13  pub const TimelineId = u64;",
        phantom.Style.default().withFg(phantom.Color.bright_magenta), // purple
    );
    try app.addWidget(&line13.widget);

    const line14 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 14  pub const TransitionId = u64;",
        phantom.Style.default().withFg(phantom.Color.bright_magenta),
    );
    try app.addWidget(&line14.widget);

    const line15 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 15",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&line15.widget);

    // enum - orange/yellow
    const line16 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 16  pub const TransitionPhase = enum { entering, updating, exiting };",
        phantom.Style.default().withFg(phantom.Color.bright_yellow), // orange
    );
    try app.addWidget(&line16.widget);

    const line17 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 17",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&line17.widget);

    // union - purple
    const line18 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 18  pub const TransitionEvent = union(enum) {",
        phantom.Style.default().withFg(phantom.Color.bright_magenta),
    );
    try app.addWidget(&line18.widget);

    // Fields - green/teal
    const line19 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 19      started: TransitionPhase,",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line19.widget);

    const line20 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 20      finished: TransitionPhase,",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line20.widget);

    const line21 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 21      cancelled,",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line21.widget);

    const line22 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 22  };",
        phantom.Style.default().withFg(phantom.Color.white),
    );
    try app.addWidget(&line22.widget);

    const line23 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 23",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&line23.widget);

    // More enum - orange
    const line24 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 24  pub const TransitionCurve = enum {",
        phantom.Style.default().withFg(phantom.Color.bright_yellow),
    );
    try app.addWidget(&line24.widget);

    const line25 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 25      linear,",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line25.widget);

    const line26 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 26      ease,",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line26.widget);

    const line27 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 27      ease_in,",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line27.widget);

    const line28 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 28      ease_out,",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line28.widget);

    const line29 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 29      ease_in_out,",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line29.widget);

    const line30 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 30      custom,",
        phantom.Style.default().withFg(phantom.Color.bright_cyan),
    );
    try app.addWidget(&line30.widget);

    const line31 = try phantom.widgets.Text.initWithStyle(
        allocator,
        " 31  };",
        phantom.Style.default().withFg(phantom.Color.white),
    );
    try app.addWidget(&line31.widget);

    // Separator
    const separator = try phantom.widgets.Text.initWithStyle(
        allocator,
        "────────────────────────────────────────────────────────────────────────",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&separator.widget);

    // Status bar (Tokyo Night blue bg)
    const status_bar = try phantom.widgets.Text.initWithStyle(
        allocator,
        " NORMAL  src/animation.zig                              zig utf-8  31/159  1│36",
        phantom.Style.default()
            .withBg(phantom.Color.blue)
            .withFg(phantom.Color.bright_cyan)
            .withBold(),
    );
    try app.addWidget(&status_bar.widget);

    // Help (gray)
    const help = try phantom.widgets.Text.initWithStyle(
        allocator,
        "i:INSERT v:VISUAL /:SEARCH  h/j/k/l:navigate  q:quit  ESC:normal",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&help.widget);

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
