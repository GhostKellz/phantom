//! RichText widget for formatted text with inline styles
//! Supports markdown-like formatting: **bold**, *italic*, `code`, colors, etc.
const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Style = style.Style;
const Color = style.Color;

/// Text span with specific style
pub const TextSpan = struct {
    text: []const u8,
    style: Style,
};

/// Rich text formatting options
pub const Format = enum {
    normal,
    bold,
    italic,
    underline,
    code,
    strikethrough,
};

/// RichText widget with inline formatting
pub const RichText = struct {
    widget: Widget,
    allocator: std.mem.Allocator,

    /// Text spans
    spans: std.ArrayList(TextSpan),

    /// Base style
    base_style: Style,

    /// Word wrap
    word_wrap: bool,

    /// Alignment
    alignment: enum { left, center, right },

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*RichText {
        const text = try allocator.create(RichText);
        text.* = RichText{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .spans = .{},
            .base_style = Style.default(),
            .word_wrap = true,
            .alignment = .left,
        };
        return text;
    }

    pub fn addSpan(self: *RichText, text: []const u8, span_style: Style) !void {
        const owned_text = try self.allocator.dupe(u8, text);
        try self.spans.append(self.allocator, TextSpan{ .text = owned_text, .style = span_style });
    }

    pub fn addText(self: *RichText, text: []const u8) !void {
        try self.addSpan(text, self.base_style);
    }

    pub fn addBold(self: *RichText, text: []const u8) !void {
        try self.addSpan(text, self.base_style.withBold());
    }

    pub fn addItalic(self: *RichText, text: []const u8) !void {
        try self.addSpan(text, self.base_style.withItalic());
    }

    pub fn addUnderline(self: *RichText, text: []const u8) !void {
        try self.addSpan(text, self.base_style.withUnderline());
    }

    pub fn addCode(self: *RichText, text: []const u8) !void {
        const code_style = Style.default()
            .withFg(Color.bright_cyan)
            .withBg(Color.bright_black);
        try self.addSpan(text, code_style);
    }

    pub fn addColored(self: *RichText, text: []const u8, color: Color) !void {
        try self.addSpan(text, self.base_style.withFg(color));
    }

    pub fn addNewline(self: *RichText) !void {
        try self.addText("\n");
    }

    /// Parse markdown-style text
    pub fn parseMarkdown(self: *RichText, markdown: []const u8) !void {
        var i: usize = 0;
        var current_text: std.ArrayList(u8) = .{};
        defer current_text.deinit(self.allocator);

        while (i < markdown.len) {
            // Check for formatting markers
            if (i + 2 < markdown.len and markdown[i] == '*' and markdown[i + 1] == '*') {
                // Bold: **text**
                if (current_text.items.len > 0) {
                    try self.addText(current_text.items);
                    current_text.clearRetainingCapacity();
                }

                i += 2;
                const start = i;
                while (i + 1 < markdown.len) : (i += 1) {
                    if (markdown[i] == '*' and markdown[i + 1] == '*') {
                        try self.addBold(markdown[start..i]);
                        i += 2;
                        break;
                    }
                }
            } else if (markdown[i] == '*') {
                // Italic: *text*
                if (current_text.items.len > 0) {
                    try self.addText(current_text.items);
                    current_text.clearRetainingCapacity();
                }

                i += 1;
                const start = i;
                while (i < markdown.len and markdown[i] != '*') : (i += 1) {}
                if (i < markdown.len) {
                    try self.addItalic(markdown[start..i]);
                    i += 1;
                }
            } else if (markdown[i] == '`') {
                // Code: `text`
                if (current_text.items.len > 0) {
                    try self.addText(current_text.items);
                    current_text.clearRetainingCapacity();
                }

                i += 1;
                const start = i;
                while (i < markdown.len and markdown[i] != '`') : (i += 1) {}
                if (i < markdown.len) {
                    try self.addCode(markdown[start..i]);
                    i += 1;
                }
            } else {
                // Regular text
                try current_text.append(self.allocator, markdown[i]);
                i += 1;
            }
        }

        // Add remaining text
        if (current_text.items.len > 0) {
            try self.addText(current_text.items);
        }
    }

    pub fn clear(self: *RichText) void {
        for (self.spans.items) |span| {
            self.allocator.free(span.text);
        }
        self.spans.clearRetainingCapacity();
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *RichText = @fieldParentPtr("widget", widget);

        if (area.width == 0 or area.height == 0) return;

        var x: u16 = area.x;
        var y: u16 = area.y;

        for (self.spans.items) |span| {
            var span_i: usize = 0;
            while (span_i < span.text.len) {
                const c = span.text[span_i];

                // Handle newline
                if (c == '\n') {
                    x = area.x;
                    y += 1;
                    if (y >= area.y + area.height) return; // Out of bounds
                    span_i += 1;
                    continue;
                }

                // Handle word wrap
                if (self.word_wrap and x >= area.x + area.width) {
                    x = area.x;
                    y += 1;
                    if (y >= area.y + area.height) return; // Out of bounds
                }

                // Render character
                buffer.setCell(x, y, Cell.init(c, span.style));
                x += 1;
                span_i += 1;
            }
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        _ = widget;
        _ = event;
        return false; // RichText is non-interactive
    }

    fn resize(widget: *Widget, area: Rect) void {
        _ = widget;
        _ = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *RichText = @fieldParentPtr("widget", widget);

        for (self.spans.items) |span| {
            self.allocator.free(span.text);
        }

        self.spans.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

test "RichText creation" {
    const allocator = std.testing.allocator;

    const text = try RichText.init(allocator);
    defer text.widget.vtable.deinit(&text.widget);

    try std.testing.expect(text.spans.items.len == 0);
}

test "RichText markdown parsing" {
    const allocator = std.testing.allocator;

    const text = try RichText.init(allocator);
    defer text.widget.vtable.deinit(&text.widget);

    try text.parseMarkdown("Normal **bold** *italic* `code` text");

    try std.testing.expect(text.spans.items.len >= 4);
}
