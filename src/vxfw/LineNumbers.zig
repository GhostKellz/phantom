//! LineNumbers - Line number display for code/text views
//! Displays line numbers with customizable formatting and styling

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Style = style.Style;

const LineNumbers = @This();

start_line: u32 = 1,
total_lines: u32,
current_line: ?u32 = null,
number_style: Style,
current_line_style: Style,
padding: u8 = 1,

/// Create LineNumbers widget
pub fn init(total_lines: u32, number_style: Style) LineNumbers {
    return LineNumbers{
        .total_lines = total_lines,
        .number_style = number_style,
        .current_line_style = number_style.withBold(),
    };
}

/// Create LineNumbers with custom current line highlighting
pub fn withCurrentLine(total_lines: u32, current_line: u32, number_style: Style, current_line_style: Style) LineNumbers {
    return LineNumbers{
        .total_lines = total_lines,
        .current_line = current_line,
        .number_style = number_style,
        .current_line_style = current_line_style,
    };
}

/// Create LineNumbers with custom start line
pub fn withStartLine(start_line: u32, total_lines: u32, number_style: Style) LineNumbers {
    return LineNumbers{
        .start_line = start_line,
        .total_lines = total_lines,
        .number_style = number_style,
        .current_line_style = number_style.withBold(),
    };
}

/// Calculate the width needed for line numbers
pub fn getWidth(self: *const LineNumbers) u16 {
    const max_line = self.start_line + self.total_lines - 1;
    const digits = if (max_line == 0) 1 else std.math.log10_int(max_line) + 1;
    return @as(u16, @intCast(digits + self.padding * 2));
}

/// Get the widget interface for this LineNumbers
pub fn widget(self: *const LineNumbers) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const LineNumbers = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *const LineNumbers = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const LineNumbers, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const width = self.getWidth();
    const height = ctx.getHeight();

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(width, height)
    );

    // Fill background with line number style
    surface.fillRect(
        geometry.Rect.init(0, 0, width, height),
        ' ',
        self.number_style
    );

    // Draw line numbers
    const lines_to_draw = @min(height, self.total_lines);
    var y: u16 = 0;

    while (y < lines_to_draw) : (y += 1) {
        const line_number = self.start_line + y;
        const is_current = if (self.current_line) |current| line_number == current else false;

        // Format line number
        var line_buffer: [16]u8 = undefined;
        const line_text = std.fmt.bufPrint(&line_buffer, "{d}", .{line_number}) catch continue;

        // Calculate positioning (right-aligned with padding)
        const text_width = @as(u16, @intCast(line_text.len));
        const x_offset = if (text_width + self.padding <= width)
            width - text_width - self.padding
        else
            0;

        // Draw line number with appropriate style
        const line_style = if (is_current) self.current_line_style else self.number_style;
        _ = surface.writeText(x_offset, y, line_text, line_style);
    }

    return surface;
}

pub fn handleEvent(self: *const LineNumbers, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    // LineNumbers is typically read-only, but we could add click-to-jump functionality
    var commands = ctx.createCommandList();

    switch (ctx.event) {
        .mouse => |mouse| {
            if (ctx.isMouseEvent() != null and mouse.action == .press and mouse.button == .left) {
                // Calculate which line was clicked
                const local_pos = ctx.getLocalMousePosition() orelse return commands;
                const clicked_line = self.start_line + @as(u32, @intCast(local_pos.y));

                if (clicked_line <= self.start_line + self.total_lines - 1) {
                    // Could emit a custom command for line selection
                    // For now, just request redraw
                    try commands.append(.redraw);
                }
            }
        },
        else => {},
    }

    return commands;
}

/// Update the current line highlight
pub fn setCurrentLine(self: *LineNumbers, line: ?u32) void {
    self.current_line = line;
}

/// Update the total number of lines
pub fn setTotalLines(self: *LineNumbers, total: u32) void {
    self.total_lines = total;
}

/// Update the starting line number
pub fn setStartLine(self: *LineNumbers, start: u32) void {
    self.start_line = start;
}

test "LineNumbers width calculation" {
    const line_numbers = LineNumbers.init(99, Style.default());
    try std.testing.expectEqual(@as(u16, 4), line_numbers.getWidth()); // "99" + 2 padding = 4

    const large_numbers = LineNumbers.init(9999, Style.default());
    try std.testing.expectEqual(@as(u16, 6), large_numbers.getWidth()); // "9999" + 2 padding = 6
}

test "LineNumbers creation and basic functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const line_numbers = LineNumbers.withCurrentLine(50, 25, Style.default(), Style.default().withBold());

    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(6, 10),
        vxfw.DrawContext.SizeConstraints.fixed(6, 10),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try line_numbers.draw(ctx);

    // Test basic surface creation
    try std.testing.expectEqual(Size.init(6, 10), surface.size);
}

test "LineNumbers with custom start line" {
    const line_numbers = LineNumbers.withStartLine(100, 50, Style.default());
    try std.testing.expectEqual(@as(u32, 100), line_numbers.start_line);
    try std.testing.expectEqual(@as(u32, 50), line_numbers.total_lines);

    // Width should account for line 149 (100 + 50 - 1)
    try std.testing.expectEqual(@as(u16, 5), line_numbers.getWidth()); // "149" + 2 padding = 5
}