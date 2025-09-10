//! Text widget for displaying styled text
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Text alignment options
pub const Alignment = enum {
    left,
    center,
    right,
};

/// Text widget for displaying styled text
pub const Text = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    content: []const u8,
    text_style: Style,
    alignment: Alignment,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator, content: []const u8) !*Text {
        const text = try allocator.create(Text);
        text.* = Text{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .content = try allocator.dupe(u8, content),
            .text_style = Style.default(),
            .alignment = .left,
        };
        return text;
    }

    pub fn initWithStyle(allocator: std.mem.Allocator, content: []const u8, text_style: Style) !*Text {
        const text = try Text.init(allocator, content);
        text.text_style = text_style;
        return text;
    }

    pub fn setContent(self: *Text, content: []const u8) !void {
        self.allocator.free(self.content);
        self.content = try self.allocator.dupe(u8, content);
    }

    pub fn setStyle(self: *Text, text_style: Style) void {
        self.text_style = text_style;
    }

    pub fn setAlignment(self: *Text, alignment: Alignment) void {
        self.alignment = alignment;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Text = @fieldParentPtr("widget", widget);

        if (area.height == 0 or area.width == 0) return;

        // Calculate text position based on alignment
        const text_len = std.unicode.utf8CountCodepoints(self.content) catch self.content.len;

        const x_pos = switch (self.alignment) {
            .left => area.x,
            .center => area.x + @max(0, (area.width -| @as(u16, @intCast(text_len))) / 2),
            .right => area.x + @max(0, area.width -| @as(u16, @intCast(text_len))),
        };

        // Render text at calculated position
        buffer.writeText(x_pos, area.y, self.content, self.text_style);
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        _ = widget;
        _ = event;
        // Text widget doesn't handle events by default
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        _ = widget;
        _ = area;
        // Text widget doesn't need special resize handling
    }

    fn deinit(widget: *Widget) void {
        const self: *Text = @fieldParentPtr("widget", widget);
        self.allocator.free(self.content);
        self.allocator.destroy(self);
    }
};

test "Text widget creation" {
    const allocator = std.testing.allocator;

    const text = try Text.init(allocator, "Hello, World!");
    defer text.widget.deinit();

    try std.testing.expectEqualStrings("Hello, World!", text.content);
    try std.testing.expect(text.alignment == .left);
}

test "Text widget style setting" {
    const allocator = std.testing.allocator;

    const text = try Text.init(allocator, "Styled text");
    defer text.widget.deinit();

    const red_style = Style.default().withFg(style.Color.red);
    text.setStyle(red_style);

    try std.testing.expect(text.text_style.fg.? == style.Color.red);
}
