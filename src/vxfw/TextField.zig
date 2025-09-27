//! TextField - Single-line text input with cursor management
//! Enhanced text input widget with selection, cursor movement, and editing capabilities

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Style = style.Style;

const TextField = @This();

text_buffer: std.array_list.AlignedManaged(u8, null),
cursor_position: usize = 0,
scroll_offset: usize = 0,
selection_start: ?usize = null,
text_style: Style,
cursor_style: Style,
selection_style: Style,
placeholder_text: []const u8 = "",
placeholder_style: Style,
max_length: ?usize = null,

/// Create a TextField with initial text and styling
pub fn init(allocator: Allocator, initial_text: []const u8, text_style: Style) !TextField {
    var buffer = std.array_list.AlignedManaged(u8, null).init(allocator);
    try buffer.appendSlice(initial_text);

    return TextField{
        .text_buffer = buffer,
        .cursor_position = initial_text.len,
        .text_style = text_style,
        .cursor_style = text_style.withBg(.white).withFg(.black),
        .selection_style = text_style.withBg(.blue),
        .placeholder_style = text_style.withFg(.bright_black),
    };
}

/// Create an empty TextField with default styling
pub fn empty(allocator: Allocator) !TextField {
    return try init(allocator, "", Style.default());
}

/// Create a TextField with placeholder text
pub fn withPlaceholder(allocator: Allocator, placeholder: []const u8, text_style: Style) !TextField {
    var field = try init(allocator, "", text_style);
    field.placeholder_text = placeholder;
    return field;
}

/// Create a TextField with maximum length constraint
pub fn withMaxLength(allocator: Allocator, max_length: usize, text_style: Style) !TextField {
    var field = try init(allocator, "", text_style);
    field.max_length = max_length;
    return field;
}

pub fn deinit(self: *TextField) void {
    self.text_buffer.deinit();
}

/// Get the current text content
pub fn getText(self: *const TextField) []const u8 {
    return self.text_buffer.items;
}

/// Set the text content and reset cursor
pub fn setText(self: *TextField, text: []const u8) !void {
    self.text_buffer.clearRetainingCapacity();
    try self.text_buffer.appendSlice(text);
    self.cursor_position = text.len;
    self.selection_start = null;
    self.scroll_offset = 0;
}

/// Clear all text
pub fn clear(self: *TextField) void {
    self.text_buffer.clearRetainingCapacity();
    self.cursor_position = 0;
    self.selection_start = null;
    self.scroll_offset = 0;
}

/// Insert text at cursor position
pub fn insertText(self: *TextField, text: []const u8) !void {
    // Check max length constraint
    if (self.max_length) |max_len| {
        if (self.text_buffer.items.len + text.len > max_len) {
            return;
        }
    }

    // Delete selection if exists
    if (self.selection_start) |_| {
        try self.deleteSelection();
    }

    // Insert text at cursor
    try self.text_buffer.insertSlice(self.cursor_position, text);
    self.cursor_position += text.len;
}

/// Delete character at cursor (backspace)
pub fn backspace(self: *TextField) !void {
    if (self.selection_start) |_| {
        try self.deleteSelection();
    } else if (self.cursor_position > 0) {
        self.cursor_position -= 1;
        _ = self.text_buffer.orderedRemove(self.cursor_position);
    }
}

/// Delete character after cursor (delete key)
pub fn delete(self: *TextField) void {
    if (self.selection_start) |_| {
        self.deleteSelection() catch return;
    } else if (self.cursor_position < self.text_buffer.items.len) {
        _ = self.text_buffer.orderedRemove(self.cursor_position);
    }
}

/// Delete current selection
fn deleteSelection(self: *TextField) !void {
    if (self.selection_start) |sel_start| {
        const start = @min(self.cursor_position, sel_start);
        const end = @max(self.cursor_position, sel_start);

        // Remove selected text
        for (0..end - start) |_| {
            _ = self.text_buffer.orderedRemove(start);
        }

        self.cursor_position = start;
        self.selection_start = null;
    }
}

/// Move cursor to position
pub fn setCursorPosition(self: *TextField, position: usize) void {
    self.cursor_position = @min(position, self.text_buffer.items.len);
    self.selection_start = null;
}

/// Move cursor left
pub fn moveCursorLeft(self: *TextField, extend_selection: bool) void {
    if (extend_selection and self.selection_start == null) {
        self.selection_start = self.cursor_position;
    } else if (!extend_selection) {
        self.selection_start = null;
    }

    if (self.cursor_position > 0) {
        self.cursor_position -= 1;
    }
}

/// Move cursor right
pub fn moveCursorRight(self: *TextField, extend_selection: bool) void {
    if (extend_selection and self.selection_start == null) {
        self.selection_start = self.cursor_position;
    } else if (!extend_selection) {
        self.selection_start = null;
    }

    if (self.cursor_position < self.text_buffer.items.len) {
        self.cursor_position += 1;
    }
}

/// Move cursor to start of text
pub fn moveCursorHome(self: *TextField, extend_selection: bool) void {
    if (extend_selection and self.selection_start == null) {
        self.selection_start = self.cursor_position;
    } else if (!extend_selection) {
        self.selection_start = null;
    }

    self.cursor_position = 0;
}

/// Move cursor to end of text
pub fn moveCursorEnd(self: *TextField, extend_selection: bool) void {
    if (extend_selection and self.selection_start == null) {
        self.selection_start = self.cursor_position;
    } else if (!extend_selection) {
        self.selection_start = null;
    }

    self.cursor_position = self.text_buffer.items.len;
}

/// Get the widget interface for this TextField
pub fn widget(self: *const TextField) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const TextField = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *TextField = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const TextField, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const width = ctx.getWidth();
    const height = @max(ctx.getHeight(), 1);

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(width, height)
    );

    // Fill background
    surface.fillRect(
        geometry.Rect.init(0, 0, width, height),
        ' ',
        self.text_style
    );

    // Determine what text to show
    const display_text = if (self.text_buffer.items.len == 0)
        self.placeholder_text
    else
        self.text_buffer.items;

    if (display_text.len == 0) {
        return surface;
    }

    // Calculate visible range based on scroll offset and cursor position
    const visible_start = self.scroll_offset;
    const visible_end = @min(display_text.len, visible_start + width);

    if (visible_start >= display_text.len) {
        return surface;
    }

    const visible_text = display_text[visible_start..visible_end];

    // Draw selection background if exists
    if (self.selection_start) |sel_start| {
        const sel_min = @min(self.cursor_position, sel_start);
        const sel_max = @max(self.cursor_position, sel_start);

        if (sel_max > visible_start and sel_min < visible_end) {
            const sel_start_visual = if (sel_min > visible_start) sel_min - visible_start else 0;
            const sel_end_visual = if (sel_max < visible_end) sel_max - visible_start else visible_text.len;

            surface.fillRect(
                geometry.Rect.init(@intCast(sel_start_visual), 0, @intCast(sel_end_visual - sel_start_visual), 1),
                ' ',
                self.selection_style
            );
        }
    }

    // Draw text
    const text_style = if (self.text_buffer.items.len == 0) self.placeholder_style else self.text_style;
    _ = surface.writeText(0, 0, visible_text, text_style);

    // Draw cursor if within visible range
    if (self.cursor_position >= visible_start and self.cursor_position <= visible_end) {
        const cursor_x = self.cursor_position - visible_start;
        if (cursor_x < width) {
            const cursor_char = if (self.cursor_position < self.text_buffer.items.len)
                @as(u21, @intCast(self.text_buffer.items[self.cursor_position]))
            else
                ' ';

            _ = surface.setCell(@intCast(cursor_x), 0, cursor_char, self.cursor_style);
        }
    }

    return surface;
}

pub fn handleEvent(self: *TextField, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    switch (ctx.event) {
        .key_press => |key| {
            if (ctx.has_focus) {
                const shift_pressed = key.modifiers.shift;

                switch (key.key) {
                    .left => {
                        self.moveCursorLeft(shift_pressed);
                        try commands.append(.redraw);
                    },
                    .right => {
                        self.moveCursorRight(shift_pressed);
                        try commands.append(.redraw);
                    },
                    .home => {
                        self.moveCursorHome(shift_pressed);
                        try commands.append(.redraw);
                    },
                    .end => {
                        self.moveCursorEnd(shift_pressed);
                        try commands.append(.redraw);
                    },
                    .backspace => {
                        self.backspace() catch {};
                        try commands.append(.redraw);
                    },
                    .delete => {
                        self.delete();
                        try commands.append(.redraw);
                    },
                    .enter => {
                        // Could emit a custom "submit" command
                        try commands.append(.redraw);
                    },
                    else => {
                        // Handle printable characters
                        if (key.codepoint) |cp| {
                            if (cp >= 32 and cp < 127) { // Basic ASCII printable range
                                var char_buf: [4]u8 = undefined;
                                if (std.unicode.utf8Encode(cp, &char_buf)) |len| {
                                    self.insertText(char_buf[0..len]) catch {};
                                    try commands.append(.redraw);
                                } else |_| {
                                    // Ignore invalid codepoint
                                }
                            }
                        }
                    },
                }
            }
        },
        .mouse => |mouse| {
            if (ctx.isMouseEvent() != null and mouse.action == .press and mouse.button == .left) {
                // Click to position cursor
                if (ctx.getLocalMousePosition()) |local_pos| {
                    const clicked_x = @as(usize, @intCast(local_pos.x));
                    const new_cursor_pos = @min(self.scroll_offset + clicked_x, self.text_buffer.items.len);
                    self.setCursorPosition(new_cursor_pos);
                    try commands.append(.redraw);
                }
            }
        },
        else => {},
    }

    return commands;
}

test "TextField creation and basic operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var field = try TextField.init(arena.allocator(), "Hello", Style.default());
    defer field.deinit();

    // Test initial state
    try std.testing.expectEqualStrings("Hello", field.getText());
    try std.testing.expectEqual(@as(usize, 5), field.cursor_position);

    // Test text insertion
    try field.insertText(" World");
    try std.testing.expectEqualStrings("Hello World", field.getText());

    // Test cursor movement
    field.setCursorPosition(5);
    try field.insertText("!");
    try std.testing.expectEqualStrings("Hello! World", field.getText());
}

test "TextField cursor movement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var field = try TextField.init(arena.allocator(), "Test", Style.default());
    defer field.deinit();

    // Test cursor movement
    field.moveCursorLeft(false);
    try std.testing.expectEqual(@as(usize, 3), field.cursor_position);

    field.moveCursorHome(false);
    try std.testing.expectEqual(@as(usize, 0), field.cursor_position);

    field.moveCursorEnd(false);
    try std.testing.expectEqual(@as(usize, 4), field.cursor_position);
}