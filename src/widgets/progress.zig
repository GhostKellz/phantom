//! Progress bar widget for showing progress/completion
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const emoji = @import("../emoji.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Progress bar widget for showing progress/completion
pub const ProgressBar = struct {
    widget: Widget,
    allocator: std.mem.Allocator,

    // Progress state
    value: f64 = 0.0,
    max_value: f64 = 100.0,

    // Text labels
    label: ?[]const u8 = null,
    show_percentage: bool = true,
    show_value: bool = false,
    show_emoji: bool = true,
    show_eta: bool = false,

    // Timing for ETA calculation
    start_time: i64 = 0,

    // Styling
    bar_style: Style,
    fill_style: Style,
    text_style: Style,
    progress_style: emoji.ProgressStyle = .blocks,

    // Characters
    fill_char: u21 = '█',
    empty_char: u21 = '░',

    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*ProgressBar {
        const progress = try allocator.create(ProgressBar);
        progress.* = ProgressBar{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .bar_style = Style.default(),
            .fill_style = Style.default().withFg(style.Color.green),
            .text_style = Style.default(),
            .start_time = std.time.milliTimestamp(),
        };
        return progress;
    }

    pub fn setValue(self: *ProgressBar, value: f64) void {
        self.value = @max(0.0, @min(value, self.max_value));
    }

    pub fn setMaxValue(self: *ProgressBar, max_value: f64) void {
        self.max_value = @max(0.0, max_value);
        self.value = @max(0.0, @min(self.value, self.max_value));
    }

    pub fn setPercentage(self: *ProgressBar, percentage: f64) void {
        self.setValue(percentage * self.max_value / 100.0);
    }

    pub fn getPercentage(self: *const ProgressBar) f64 {
        if (self.max_value == 0.0) return 0.0;
        return (self.value / self.max_value) * 100.0;
    }

    pub fn getETA(self: *const ProgressBar) i64 {
        if (self.value <= 0.0) return -1; // Unknown

        const elapsed = std.time.milliTimestamp() - self.start_time;
        const progress_ratio = self.value / self.max_value;

        if (progress_ratio <= 0.0) return -1;

        const total_estimated = @as(f64, @floatFromInt(elapsed)) / progress_ratio;
        const remaining = total_estimated - @as(f64, @floatFromInt(elapsed));

        return @as(i64, @intFromFloat(@max(0.0, remaining)));
    }

    pub fn setProgressStyle(self: *ProgressBar, progress_style: emoji.ProgressStyle) void {
        self.progress_style = progress_style;
        self.fill_char = progress_style.getFilledChar();
        self.empty_char = progress_style.getEmptyChar();
    }

    pub fn setShowPercentage(self: *ProgressBar, show: bool) void {
        self.show_percentage = show;
    }

    pub fn setShowValue(self: *ProgressBar, show: bool) void {
        self.show_value = show;
    }

    pub fn setShowEmoji(self: *ProgressBar, show: bool) void {
        self.show_emoji = show;
    }

    pub fn setShowETA(self: *ProgressBar, show: bool) void {
        self.show_eta = show;
    }

    pub fn setBarStyle(self: *ProgressBar, bar_style: Style) void {
        self.bar_style = bar_style;
    }

    pub fn setFillStyle(self: *ProgressBar, fill_style: Style) void {
        self.fill_style = fill_style;
    }

    pub fn setTextStyle(self: *ProgressBar, text_style: Style) void {
        self.text_style = text_style;
    }

    pub fn setFillChar(self: *ProgressBar, fill_char: u21) void {
        self.fill_char = fill_char;
    }

    pub fn setEmptyChar(self: *ProgressBar, empty_char: u21) void {
        self.empty_char = empty_char;
    }

    pub fn increment(self: *ProgressBar, amount: f64) void {
        self.setValue(self.value + amount);
    }

    pub fn decrement(self: *ProgressBar, amount: f64) void {
        self.setValue(self.value - amount);
    }

    pub fn reset(self: *ProgressBar) void {
        self.value = 0.0;
    }

    pub fn complete(self: *ProgressBar) void {
        self.value = self.max_value;
    }

    pub fn isComplete(self: *const ProgressBar) bool {
        return self.value >= self.max_value;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *ProgressBar = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;

        // Calculate progress percentage
        const percentage = self.getPercentage();

        // Calculate bar area (leave space for text if needed)
        var bar_area = area;
        var text_area: ?Rect = null;

        if (self.label != null or self.show_percentage or self.show_value) {
            if (area.height >= 2) {
                // Text on top, bar below
                text_area = Rect.init(area.x, area.y, area.width, 1);
                bar_area = Rect.init(area.x, area.y + 1, area.width, area.height - 1);
            } else {
                // Text and bar on same line (bar gets priority)
                if (area.width > 10) {
                    text_area = Rect.init(area.x, area.y, 10, 1);
                    bar_area = Rect.init(area.x + 10, area.y, area.width - 10, 1);
                }
            }
        }

        // Render text
        if (text_area) |text_rect| {
            // Clear text area
            buffer.fill(text_rect, Cell.withStyle(self.text_style));

            // Build text string
            var text_buffer = std.ArrayList(u8).initCapacity(self.allocator, 32) catch return;
            defer text_buffer.deinit(self.allocator);

            if (self.label) |label| {
                text_buffer.appendSlice(self.allocator, label) catch {};
                if (self.show_percentage or self.show_value) {
                    text_buffer.appendSlice(self.allocator, " ") catch {};
                }
            }

            if (self.show_percentage) {
                const percentage_str = std.fmt.allocPrint(self.allocator, "{d:.1}%", .{percentage}) catch "";
                defer self.allocator.free(percentage_str);
                text_buffer.appendSlice(self.allocator, percentage_str) catch {};
            }

            if (self.show_value) {
                if (self.show_percentage) {
                    text_buffer.appendSlice(self.allocator, " ") catch {};
                }
                const value_str = std.fmt.allocPrint(self.allocator, "({d:.1}/{d:.1})", .{ self.value, self.max_value }) catch "";
                defer self.allocator.free(value_str);
                text_buffer.appendSlice(self.allocator, value_str) catch {};
            }

            // Render text
            const text_len = @min(text_buffer.items.len, text_rect.width);
            if (text_len > 0) {
                buffer.writeText(text_rect.x, text_rect.y, text_buffer.items[0..text_len], self.text_style);
            }
        }

        // Render progress bar
        if (bar_area.width > 0 and bar_area.height > 0) {
            // Calculate fill width
            const fill_width = if (self.max_value > 0.0)
                @as(u16, @intFromFloat(@round((self.value / self.max_value) * @as(f64, @floatFromInt(bar_area.width)))))
            else
                0;

            // Fill progress bar
            var y = bar_area.y;
            while (y < bar_area.y + bar_area.height) : (y += 1) {
                var x = bar_area.x;
                while (x < bar_area.x + bar_area.width) : (x += 1) {
                    const char = if (x < bar_area.x + fill_width) self.fill_char else self.empty_char;
                    const cell_style = if (x < bar_area.x + fill_width) self.fill_style else self.bar_style;
                    buffer.setCell(x, y, Cell.init(char, cell_style));
                }
            }
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        _ = widget;
        _ = event;
        // Progress bar doesn't handle events by default
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *ProgressBar = @fieldParentPtr("widget", widget);
        self.area = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *ProgressBar = @fieldParentPtr("widget", widget);
        if (self.label) |label| {
            self.allocator.free(label);
        }
        self.allocator.destroy(self);
    }
};

test "ProgressBar widget creation" {
    const allocator = std.testing.allocator;

    const progress = try ProgressBar.init(allocator);
    defer progress.widget.deinit();

    try std.testing.expect(progress.value == 0.0);
    try std.testing.expect(progress.max_value == 100.0);
    try std.testing.expect(progress.getPercentage() == 0.0);
}

test "ProgressBar widget value management" {
    const allocator = std.testing.allocator;

    const progress = try ProgressBar.init(allocator);
    defer progress.widget.deinit();

    progress.setValue(50.0);
    try std.testing.expect(progress.value == 50.0);
    try std.testing.expect(progress.getPercentage() == 50.0);

    progress.setPercentage(75.0);
    try std.testing.expect(progress.value == 75.0);
    try std.testing.expect(progress.getPercentage() == 75.0);

    progress.increment(10.0);
    try std.testing.expect(progress.value == 85.0);

    progress.decrement(5.0);
    try std.testing.expect(progress.value == 80.0);

    progress.complete();
    try std.testing.expect(progress.isComplete());
    try std.testing.expect(progress.value == 100.0);

    progress.reset();
    try std.testing.expect(progress.value == 0.0);
    try std.testing.expect(!progress.isComplete());
}
