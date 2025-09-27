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
    _ = self; // TODO: Re-enable when we have proper mutable widget state
    var commands = ctx.createCommandList();

    // Handle scrolling with mouse wheel or arrow keys
    switch (ctx.event) {
        .mouse => |mouse| {
            if (ctx.isMouseEvent() != null) {
                switch (mouse.button) {
                    .wheel_up => {
                        // TODO: Make TextView properly mutable for scroll state
                        // For now, just signal redraw
                        try commands.append(.redraw);
                    },
                    .wheel_down => {
                        // TODO: Calculate max scroll based on content height
                        // TODO: Make TextView properly mutable for scroll state
                        try commands.append(.redraw);
                    },
                    else => {},
                }
            }
        },
        .key_press => |key| {
            if (ctx.has_focus) {
                switch (key.key) {
                    .up => {
                        // TODO: Make TextView properly mutable for scroll state
                        try commands.append(.redraw);
                    },
                    .down => {
                        // TODO: Make TextView properly mutable for scroll state
                        try commands.append(.redraw);
                    },
                    .page_up => {
                        // TODO: Make TextView properly mutable for scroll state
                        try commands.append(.redraw);
                    },
                    .page_down => {
                        // TODO: Make TextView properly mutable for scroll state
                        try commands.append(.redraw);
                    },
                    .home => {
                        // TODO: Make TextView properly mutable for scroll state
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