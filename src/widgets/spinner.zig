//! Spinner widget for loading states and progress indication
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Spinner animation styles
pub const SpinnerStyle = enum {
    dots,           // ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏
    line,           // -\|/
    arrow,          // ←↖↑↗→↘↓↙
    box,            // ▖▘▝▗
    bounce,         // ⠁⠂⠄⡀⢀⠠⠐⠈
    arc,            // ◜◝◞◟
    circle,         // ◐◓◑◒
    braille,        // ⣾⣽⣻⢿⡿⣟⣯⣷
};

/// Spinner widget
pub const Spinner = struct {
    widget: Widget,
    allocator: std.mem.Allocator,

    /// Current frame
    frame: usize,

    /// Spinner style
    spinner_style: SpinnerStyle,

    /// Spinner color
    spinner_color: Style,

    /// Message to display next to spinner
    message: ?[]const u8,
    message_style: Style,

    /// Animation speed (frames per tick)
    speed: usize,
    tick_count: usize,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*Spinner {
        const spinner = try allocator.create(Spinner);
        spinner.* = Spinner{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .frame = 0,
            .spinner_style = .dots,
            .spinner_color = Style.default().withFg(style.Color.bright_cyan),
            .message = null,
            .message_style = Style.default(),
            .speed = 8, // Advance frame every 8 ticks
            .tick_count = 0,
        };
        return spinner;
    }

    pub fn setStyle(self: *Spinner, spinner_style: SpinnerStyle) void {
        self.spinner_style = spinner_style;
        self.frame = 0;
    }

    pub fn setMessage(self: *Spinner, message: []const u8) !void {
        if (self.message) |old| {
            self.allocator.free(old);
        }
        self.message = try self.allocator.dupe(u8, message);
    }

    pub fn clearMessage(self: *Spinner) void {
        if (self.message) |msg| {
            self.allocator.free(msg);
            self.message = null;
        }
    }

    pub fn tick(self: *Spinner) void {
        self.tick_count += 1;
        if (self.tick_count >= self.speed) {
            self.tick_count = 0;
            self.frame += 1;
            const frames = getFrames(self.spinner_style);
            if (self.frame >= frames.len) {
                self.frame = 0;
            }
        }
    }

    fn getFrames(spinner_style: SpinnerStyle) []const u21 {
        return switch (spinner_style) {
            .dots => &[_]u21{ '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' },
            .line => &[_]u21{ '-', '\\', '|', '/' },
            .arrow => &[_]u21{ '←', '↖', '↑', '↗', '→', '↘', '↓', '↙' },
            .box => &[_]u21{ '▖', '▘', '▝', '▗' },
            .bounce => &[_]u21{ '⠁', '⠂', '⠄', '⡀', '⢀', '⠠', '⠐', '⠈' },
            .arc => &[_]u21{ '◜', '◝', '◞', '◟' },
            .circle => &[_]u21{ '◐', '◓', '◑', '◒' },
            .braille => &[_]u21{ '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' },
        };
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Spinner = @fieldParentPtr("widget", widget);

        if (area.width == 0 or area.height == 0) return;

        // Get current frame character
        const frames = getFrames(self.spinner_style);
        const char = frames[self.frame % frames.len];

        // Render spinner
        buffer.setCell(area.x, area.y, Cell.init(char, self.spinner_color));

        // Render message if present
        if (self.message) |msg| {
            if (area.width >= 3 and msg.len > 0) {
                buffer.writeText(area.x + 2, area.y, msg, self.message_style);
            }
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Spinner = @fieldParentPtr("widget", widget);

        // Auto-tick on any event
        switch (event) {
            .tick => {
                self.tick();
                return true;
            },
            else => {},
        }

        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        _ = widget;
        _ = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *Spinner = @fieldParentPtr("widget", widget);

        if (self.message) |msg| {
            self.allocator.free(msg);
        }

        self.allocator.destroy(self);
    }
};

test "Spinner creation" {
    const allocator = std.testing.allocator;

    const spinner = try Spinner.init(allocator);
    defer spinner.widget.vtable.deinit(&spinner.widget);

    try std.testing.expect(spinner.frame == 0);
}

test "Spinner animation" {
    const allocator = std.testing.allocator;

    const spinner = try Spinner.init(allocator);
    defer spinner.widget.vtable.deinit(&spinner.widget);

    const initial_frame = spinner.frame;

    // Tick multiple times
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        spinner.tick();
    }

    try std.testing.expect(spinner.frame != initial_frame or spinner.speed > 10);
}
