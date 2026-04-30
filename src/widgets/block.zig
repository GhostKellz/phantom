//! Block widget for creating bordered containers
const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Style = style.Style;

pub const TitleAlignment = enum {
    left,
    center,
    right,
};

pub const Padding = struct {
    top: u16 = 0,
    right: u16 = 0,
    bottom: u16 = 0,
    left: u16 = 0,

    pub fn all(value: u16) Padding {
        return .{ .top = value, .right = value, .bottom = value, .left = value };
    }
};

/// Border style configuration
pub const BorderStyle = struct {
    top: u21 = '─',
    bottom: u21 = '─',
    left: u21 = '│',
    right: u21 = '│',
    top_left: u21 = '┌',
    top_right: u21 = '┐',
    bottom_left: u21 = '└',
    bottom_right: u21 = '┘',

    pub fn simple() BorderStyle {
        return BorderStyle{};
    }

    pub fn thick() BorderStyle {
        return BorderStyle{
            .top = '━',
            .bottom = '━',
            .left = '┃',
            .right = '┃',
            .top_left = '┏',
            .top_right = '┓',
            .bottom_left = '┗',
            .bottom_right = '┛',
        };
    }

    pub fn rounded() BorderStyle {
        return BorderStyle{
            .top_left = '╭',
            .top_right = '╮',
            .bottom_left = '╰',
            .bottom_right = '╯',
        };
    }
};

/// Block widget for creating bordered containers
pub const Block = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    title: ?[]const u8,
    border_style: ?BorderStyle,
    block_style: Style,
    inner_area: Rect,
    title_alignment: TitleAlignment = .left,
    padding: Padding = .{},

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*Block {
        const block = try allocator.create(Block);
        block.* = Block{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .title = null,
            .border_style = BorderStyle.simple(),
            .block_style = Style.default(),
            .inner_area = Rect.init(0, 0, 0, 0),
        };
        return block;
    }

    pub fn withTitle(self: *Block, title: []const u8) !void {
        try self.setTitle(title);
    }

    pub fn setTitle(self: *Block, title: []const u8) !void {
        if (self.title) |old_title| {
            self.allocator.free(old_title);
        }
        self.title = try self.allocator.dupe(u8, title);
    }

    pub fn withBorderStyle(self: *Block, border_style: BorderStyle) void {
        self.setBorderStyle(border_style);
    }

    pub fn setBorderStyle(self: *Block, border_style: BorderStyle) void {
        self.border_style = border_style;
    }

    pub fn withStyle(self: *Block, block_style: Style) void {
        self.setStyle(block_style);
    }

    pub fn setStyle(self: *Block, block_style: Style) void {
        self.block_style = block_style;
    }

    pub fn noBorder(self: *Block) void {
        self.border_style = null;
    }

    pub fn setTitleAlignment(self: *Block, alignment: TitleAlignment) void {
        self.title_alignment = alignment;
    }

    pub fn setPadding(self: *Block, padding: Padding) void {
        self.padding = padding;
    }

    pub fn getInnerArea(self: *const Block) Rect {
        return self.inner_area;
    }

    pub fn innerAreaFor(self: *const Block, area: Rect) Rect {
        var inner = area;

        if (self.border_style != null) {
            inner.x += 1;
            inner.y += 1;
            inner.width = inner.width -| 2;
            inner.height = inner.height -| 2;
        }

        inner.x += self.padding.left;
        inner.y += self.padding.top;
        inner.width = inner.width -| (self.padding.left + self.padding.right);
        inner.height = inner.height -| (self.padding.top + self.padding.bottom);
        return inner;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Block = @fieldParentPtr("widget", widget);

        if (area.width == 0 or area.height == 0) return;

        // Calculate inner area
        self.inner_area = self.innerAreaFor(area);

        // Fill background
        buffer.fill(area, Cell.withStyle(self.block_style));

        // Draw border if present
        if (self.border_style) |border| {
            self.drawBorder(buffer, area, border);
        }

        // Draw title if present
        if (self.title) |title| {
            const title_width: u16 = @intCast(@min(title.len, area.width));
            const title_x = switch (self.title_alignment) {
                .left => area.x + @min(@as(u16, 1), area.width),
                .center => area.x + (area.width -| title_width) / 2,
                .right => area.x + (area.width -| title_width) -| 1,
            };
            const title_y = area.y;
            buffer.writeText(title_x, title_y, title, self.block_style);
        }
    }

    fn drawBorder(self: *Block, buffer: *Buffer, area: Rect, border: BorderStyle) void {
        const style_cell = Cell.withStyle(self.block_style);

        // Draw corners
        buffer.setCell(area.x, area.y, Cell.init(border.top_left, style_cell.style));
        buffer.setCell(area.x + area.width - 1, area.y, Cell.init(border.top_right, style_cell.style));
        buffer.setCell(area.x, area.y + area.height - 1, Cell.init(border.bottom_left, style_cell.style));
        buffer.setCell(area.x + area.width - 1, area.y + area.height - 1, Cell.init(border.bottom_right, style_cell.style));

        // Draw horizontal borders
        var x = area.x + 1;
        while (x < area.x + area.width - 1) : (x += 1) {
            buffer.setCell(x, area.y, Cell.init(border.top, style_cell.style));
            buffer.setCell(x, area.y + area.height - 1, Cell.init(border.bottom, style_cell.style));
        }

        // Draw vertical borders
        var y = area.y + 1;
        while (y < area.y + area.height - 1) : (y += 1) {
            buffer.setCell(area.x, y, Cell.init(border.left, style_cell.style));
            buffer.setCell(area.x + area.width - 1, y, Cell.init(border.right, style_cell.style));
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        _ = widget;
        _ = event;
        // Block widget doesn't handle events by default
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *Block = @fieldParentPtr("widget", widget);

        // Update inner area based on new size
        self.inner_area = self.innerAreaFor(area);
    }

    fn deinit(widget: *Widget) void {
        const self: *Block = @fieldParentPtr("widget", widget);
        if (self.title) |title| {
            self.allocator.free(title);
        }
        self.allocator.destroy(self);
    }
};

test "Block widget creation" {
    const allocator = std.testing.allocator;

    const block = try Block.init(allocator);
    defer block.widget.deinit();

    try std.testing.expect(block.border_style != null);
    try std.testing.expect(block.title == null);
}

test "Block widget with title" {
    const allocator = std.testing.allocator;

    const block = try Block.init(allocator);
    defer block.widget.deinit();

    try block.withTitle("Test Block");
    try std.testing.expectEqualStrings("Test Block", block.title.?);
}
