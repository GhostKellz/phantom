//! Border - Border decoration widget
//! Draws decorative borders around child widgets with various styles

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Rect = geometry.Rect;
const Style = style.Style;

const Border = @This();

child: ?vxfw.Widget,
border_style: BorderStyle,
line_style: Style,

pub const BorderStyle = enum {
    /// No border
    none,
    /// Simple ASCII border using +, -, | characters
    ascii,
    /// Single-line Unicode box drawing characters
    single,
    /// Double-line Unicode box drawing characters
    double,
    /// Thick Unicode box drawing characters
    thick,
    /// Rounded corner Unicode box drawing characters
    rounded,
    /// Dashed Unicode box drawing characters
    dashed,
};

pub const BorderChars = struct {
    top_left: u21,
    top_right: u21,
    bottom_left: u21,
    bottom_right: u21,
    horizontal: u21,
    vertical: u21,
};

/// Get border characters for a given style
pub fn getBorderChars(border_style: BorderStyle) BorderChars {
    return switch (border_style) {
        .none => unreachable,
        .ascii => BorderChars{
            .top_left = '+',
            .top_right = '+',
            .bottom_left = '+',
            .bottom_right = '+',
            .horizontal = '-',
            .vertical = '|',
        },
        .single => BorderChars{
            .top_left = '┌',
            .top_right = '┐',
            .bottom_left = '└',
            .bottom_right = '┘',
            .horizontal = '─',
            .vertical = '│',
        },
        .double => BorderChars{
            .top_left = '╔',
            .top_right = '╗',
            .bottom_left = '╚',
            .bottom_right = '╝',
            .horizontal = '═',
            .vertical = '║',
        },
        .thick => BorderChars{
            .top_left = '┏',
            .top_right = '┓',
            .bottom_left = '┗',
            .bottom_right = '┛',
            .horizontal = '━',
            .vertical = '┃',
        },
        .rounded => BorderChars{
            .top_left = '╭',
            .top_right = '╮',
            .bottom_left = '╰',
            .bottom_right = '╯',
            .horizontal = '─',
            .vertical = '│',
        },
        .dashed => BorderChars{
            .top_left = '┌',
            .top_right = '┐',
            .bottom_left = '└',
            .bottom_right = '┘',
            .horizontal = '╌',
            .vertical = '╎',
        },
    };
}

/// Create a Border with a child widget
pub fn init(child: ?vxfw.Widget, border_style: BorderStyle, line_style: Style) Border {
    return Border{
        .child = child,
        .border_style = border_style,
        .line_style = line_style,
    };
}

/// Create a Border with default styling
pub fn simple(child: ?vxfw.Widget, border_style: BorderStyle) Border {
    return init(child, border_style, Style.default());
}

/// Create a Border with a specific color
pub fn withColor(child: ?vxfw.Widget, border_style: BorderStyle, color: style.Color) Border {
    return init(child, border_style, Style.default().withFg(color));
}

/// Get the widget interface for this Border
pub fn widget(self: *const Border) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const Border = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *const Border = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const Border, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const available_width = ctx.getWidth();
    const available_height = ctx.getHeight();

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(available_width, available_height)
    );

    // If no border style, just render child directly
    if (self.border_style == .none) {
        if (self.child) |child_widget| {
            const child_surface = try child_widget.draw(ctx);
            const child_subsurface = vxfw.SubSurface.init(Point{ .x = 0, .y = 0 }, child_surface);
            try surface.addChild(child_subsurface);
        }
        return surface;
    }

    // Need at least 3x3 to draw a border
    if (available_width < 3 or available_height < 3) {
        return surface;
    }

    // Draw the border
    const chars = getBorderChars(self.border_style);

    // Draw corners
    _ = surface.setCell(0, 0, chars.top_left, self.line_style);
    _ = surface.setCell(available_width - 1, 0, chars.top_right, self.line_style);
    _ = surface.setCell(0, available_height - 1, chars.bottom_left, self.line_style);
    _ = surface.setCell(available_width - 1, available_height - 1, chars.bottom_right, self.line_style);

    // Draw horizontal borders
    var x: u16 = 1;
    while (x < available_width - 1) : (x += 1) {
        _ = surface.setCell(x, 0, chars.horizontal, self.line_style);
        _ = surface.setCell(x, available_height - 1, chars.horizontal, self.line_style);
    }

    // Draw vertical borders
    var y: u16 = 1;
    while (y < available_height - 1) : (y += 1) {
        _ = surface.setCell(0, y, chars.vertical, self.line_style);
        _ = surface.setCell(available_width - 1, y, chars.vertical, self.line_style);
    }

    // Render child widget inside the border
    if (self.child) |child_widget| {
        const inner_width = available_width - 2;
        const inner_height = available_height - 2;

        if (inner_width > 0 and inner_height > 0) {
            const child_ctx = ctx.withConstraints(
                Size.init(inner_width, inner_height),
                vxfw.DrawContext.SizeConstraints.init(inner_width, inner_height)
            );

            const child_surface = try child_widget.draw(child_ctx);
            const child_subsurface = vxfw.SubSurface.init(Point{ .x = 1, .y = 1 }, child_surface);
            try surface.addChild(child_subsurface);
        }
    }

    return surface;
}

pub fn handleEvent(self: *const Border, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    // Forward events to child, adjusting coordinates for border offset
    if (self.child) |child_widget| {
        // Create child context with adjusted bounds for border
        const adjusted_ctx = if (self.border_style != .none) blk: {
            const border_offset = Point{ .x = 1, .y = 1 };
            const adjusted_bounds = Rect.init(
                ctx.bounds.x + border_offset.x,
                ctx.bounds.y + border_offset.y,
                ctx.bounds.width - 2,
                ctx.bounds.height - 2
            );
            break :blk vxfw.EventContext.init(ctx.event, ctx.arena, adjusted_bounds);
        } else ctx;

        const child_commands = try child_widget.handleEvent(adjusted_ctx);
        for (child_commands.items) |cmd| {
            try commands.append(cmd);
        }
    }

    return commands;
}

test "Border creation and rendering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const border = Border.simple(null, .single);

    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(10, 5),
        vxfw.DrawContext.SizeConstraints.fixed(10, 5),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try border.draw(ctx);

    // Test basic surface creation
    try std.testing.expectEqual(Size.init(10, 5), surface.size);

    // Test corner characters
    try std.testing.expectEqual(@as(u21, '┌'), surface.getCell(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, '┐'), surface.getCell(9, 0).?.char);
    try std.testing.expectEqual(@as(u21, '└'), surface.getCell(0, 4).?.char);
    try std.testing.expectEqual(@as(u21, '┘'), surface.getCell(9, 4).?.char);
}

test "Border styles" {
    // Test ASCII border chars
    const ascii_chars = getBorderChars(.ascii);
    try std.testing.expectEqual(@as(u21, '+'), ascii_chars.top_left);
    try std.testing.expectEqual(@as(u21, '-'), ascii_chars.horizontal);
    try std.testing.expectEqual(@as(u21, '|'), ascii_chars.vertical);

    // Test Unicode single border chars
    const single_chars = getBorderChars(.single);
    try std.testing.expectEqual(@as(u21, '┌'), single_chars.top_left);
    try std.testing.expectEqual(@as(u21, '─'), single_chars.horizontal);
    try std.testing.expectEqual(@as(u21, '│'), single_chars.vertical);
}