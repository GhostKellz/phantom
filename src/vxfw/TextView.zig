//! TextView - Multi-line text display widget with word wrapping support
//! Handles Unicode text, word wrapping, and scrolling

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Style = style.Style;

const TextView = @This();

text: []const u8,
text_style: Style,
wrap_mode: WrapMode,
scroll_offset: u16 = 0,

pub const WrapMode = enum {
    /// No wrapping - text extends beyond widget bounds
    none,
    /// Wrap at word boundaries when possible
    word,
    /// Wrap at any character boundary
    character,
};

/// Create a TextView with the given text and style
pub fn init(text: []const u8, text_style: Style, wrap_mode: WrapMode) TextView {
    return TextView{
        .text = text,
        .text_style = text_style,
        .wrap_mode = wrap_mode,
    };
}

/// Create a TextView with default styling
pub fn simple(text: []const u8) TextView {
    return init(text, Style.default(), .word);
}

/// Get the widget interface for this TextView
pub fn widget(self: *const TextView) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const TextView = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *TextView = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const TextView, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const available_width = ctx.getWidth();
    const available_height = ctx.getHeight();

    // Create surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(available_width, available_height)
    );

    // Split text into lines based on wrap mode
    const lines = try self.wrapText(ctx.arena, available_width);
    defer ctx.arena.free(lines);

    // Draw visible lines starting from scroll offset
    var y: u16 = 0;
    var line_index = self.scroll_offset;

    while (y < available_height and line_index < lines.len) : (line_index += 1) {
        const line = lines[line_index];
        _ = surface.writeText(0, y, line, self.text_style);
        y += 1;
    }

    return surface;
}

pub fn handleEvent(self: *TextView, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    // The viewport size comes from the bounds assigned during layout; it lets us
    // clamp scrolling so the last line can't be scrolled above the viewport.
    const view_width = ctx.bounds.width;
    const view_height = ctx.bounds.height;

    switch (ctx.event) {
        .mouse => |mouse| {
            if (ctx.isMouseEvent() != null) {
                const delta: ?i32 = switch (mouse.button) {
                    .wheel_up => -3,
                    .wheel_down => 3,
                    else => null,
                };
                if (delta) |d| {
                    const max = try self.maxScroll(ctx.arena, view_width, view_height);
                    self.applyScroll(d, max);
                    try commands.append(.redraw);
                }
            }
        },
        .key_press => |key| {
            if (ctx.has_focus) {
                const page: i32 = @max(1, @as(i32, view_height) - 1);
                const max = try self.maxScroll(ctx.arena, view_width, view_height);
                switch (key.key) {
                    .up => {
                        self.applyScroll(-1, max);
                        try commands.append(.redraw);
                    },
                    .down => {
                        self.applyScroll(1, max);
                        try commands.append(.redraw);
                    },
                    .page_up => {
                        self.applyScroll(-page, max);
                        try commands.append(.redraw);
                    },
                    .page_down => {
                        self.applyScroll(page, max);
                        try commands.append(.redraw);
                    },
                    .home => {
                        self.scroll_offset = 0;
                        try commands.append(.redraw);
                    },
                    .end => {
                        self.scroll_offset = max;
                        try commands.append(.redraw);
                    },
                    else => {},
                }
            }
        },
        else => {},
    }

    return commands;
}

/// Maximum first-line index that still fills the viewport, i.e. the largest
/// value `scroll_offset` may take without scrolling past the content.
fn maxScroll(self: *const TextView, arena: Allocator, width: u16, height: u16) Allocator.Error!u16 {
    if (width == 0 or height == 0) return 0;
    const lines = try self.wrapText(arena, width);
    defer arena.free(lines);
    if (lines.len <= height) return 0;
    return @intCast(lines.len - height);
}

/// Apply a signed scroll delta, clamped to `[0, max]`.
fn applyScroll(self: *TextView, delta: i32, max: u16) void {
    const next = std.math.clamp(@as(i32, self.scroll_offset) + delta, 0, @as(i32, max));
    self.scroll_offset = @intCast(next);
}

/// Split text into lines based on the wrap mode and available width
fn wrapText(self: *const TextView, allocator: Allocator, width: u16) ![][]const u8 {
    var lines = std.array_list.AlignedManaged([]const u8, null).init(allocator);

    if (width == 0) {
        return lines.toOwnedSlice();
    }

    switch (self.wrap_mode) {
        .none => {
            // Split only on existing newlines
            var iterator = std.mem.splitScalar(u8, self.text, '\n');
            while (iterator.next()) |line| {
                try lines.append(line);
            }
        },
        .word => {
            try self.wrapAtWords(allocator, &lines, width);
        },
        .character => {
            try self.wrapAtCharacters(allocator, &lines, width);
        },
    }

    return lines.toOwnedSlice();
}

/// Wrap text at word boundaries
fn wrapAtWords(self: *const TextView, allocator: Allocator, lines: *std.array_list.AlignedManaged([]const u8, null), width: u16) !void {
    var line_iterator = std.mem.splitScalar(u8, self.text, '\n');

    while (line_iterator.next()) |paragraph| {
        if (paragraph.len == 0) {
            try lines.append("");
            continue;
        }

        var current_line = std.array_list.AlignedManaged(u8, null).init(allocator);
        defer current_line.deinit();

        var word_iterator = std.mem.tokenizeAny(u8, paragraph, " \t");
        var first_word = true;

        while (word_iterator.next()) |word| {
            const space_needed = if (first_word) word.len else current_line.items.len + 1 + word.len;

            if (space_needed <= width) {
                // Word fits on current line
                if (!first_word) {
                    try current_line.append(' ');
                }
                try current_line.appendSlice(word);
                first_word = false;
            } else {
                // Word doesn't fit, start new line
                if (current_line.items.len > 0) {
                    try lines.append(try allocator.dupe(u8, current_line.items));
                    current_line.clearRetainingCapacity();
                }

                // If word itself is too long, wrap at character boundary
                if (word.len > width) {
                    var word_start: usize = 0;
                    while (word_start < word.len) {
                        const chunk_end = @min(word_start + width, word.len);
                        try lines.append(try allocator.dupe(u8, word[word_start..chunk_end]));
                        word_start = chunk_end;
                    }
                } else {
                    try current_line.appendSlice(word);
                }
                first_word = false;
            }
        }

        // Add remaining content as last line
        if (current_line.items.len > 0) {
            try lines.append(try allocator.dupe(u8, current_line.items));
        }
    }
}

/// Wrap text at character boundaries
fn wrapAtCharacters(self: *const TextView, allocator: Allocator, lines: *std.array_list.AlignedManaged([]const u8, null), width: u16) !void {
    var line_iterator = std.mem.splitScalar(u8, self.text, '\n');

    while (line_iterator.next()) |paragraph| {
        if (paragraph.len == 0) {
            try lines.append("");
            continue;
        }

        var start: usize = 0;
        while (start < paragraph.len) {
            const end = @min(start + width, paragraph.len);
            try lines.append(try allocator.dupe(u8, paragraph[start..end]));
            start = end;
        }
    }
}

test "TextView scrolls on key events and clamps to content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // 10 single-char lines, no wrapping; viewport is 5 wide x 4 tall.
    var tv = TextView.init("0\n1\n2\n3\n4\n5\n6\n7\n8\n9", Style.default(), .none);
    const view = geometry.Rect.init(0, 0, 5, 4);
    // max scroll = 10 lines - 4 rows = 6.

    const sendKey = struct {
        fn call(t: *TextView, alloc: Allocator, bounds: geometry.Rect, k: vxfw.Key.KeyType) !void {
            const ev = vxfw.Event{ .key_press = .{ .key = k } };
            const ctx = vxfw.EventContext.withFocus(ev, alloc, bounds, true, true);
            _ = try t.handleEvent(ctx);
        }
    }.call;

    try sendKey(&tv, a, view, .down);
    try std.testing.expectEqual(@as(u16, 1), tv.scroll_offset);

    try sendKey(&tv, a, view, .end);
    try std.testing.expectEqual(@as(u16, 6), tv.scroll_offset);

    // Already at the bottom: further down is clamped.
    try sendKey(&tv, a, view, .down);
    try std.testing.expectEqual(@as(u16, 6), tv.scroll_offset);

    // page_up moves by (height - 1) = 3.
    try sendKey(&tv, a, view, .page_up);
    try std.testing.expectEqual(@as(u16, 3), tv.scroll_offset);

    try sendKey(&tv, a, view, .home);
    try std.testing.expectEqual(@as(u16, 0), tv.scroll_offset);

    // Already at the top: further up is clamped.
    try sendKey(&tv, a, view, .up);
    try std.testing.expectEqual(@as(u16, 0), tv.scroll_offset);
}

test "TextView creation and basic functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const text_view = TextView.simple("Hello, World!\nThis is a test.");

    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(20, 5),
        vxfw.DrawContext.SizeConstraints.fixed(20, 5),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try text_view.draw(ctx);

    // Test basic surface creation
    try std.testing.expectEqual(Size.init(20, 5), surface.size);
}

test "TextView word wrapping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const text_view = TextView.init(
        "This is a very long line that should wrap at word boundaries",
        Style.default(),
        .word
    );

    const lines = try text_view.wrapText(arena.allocator(), 20);

    // Should have multiple lines due to wrapping
    try std.testing.expect(lines.len > 1);

    // First line should fit within width
    try std.testing.expect(lines[0].len <= 20);
}

test "TextView character wrapping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const text_view = TextView.init(
        "Supercalifragilisticexpialidocious",
        Style.default(),
        .character
    );

    const lines = try text_view.wrapText(arena.allocator(), 10);

    // Should wrap the long word into multiple lines
    try std.testing.expect(lines.len > 1);

    // Each line should be exactly 10 characters (except possibly the last)
    for (lines[0..lines.len-1]) |line| {
        try std.testing.expectEqual(@as(usize, 10), line.len);
    }
}