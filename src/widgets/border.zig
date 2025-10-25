//! Border widget for wrapping other widgets with decorative borders
//! Perfect for floating windows, dialogs, panels, etc.
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Border style presets
pub const BorderStyle = enum {
    single,       // ┌─┐│└┘
    double,       // ╔═╗║╚╝
    rounded,      // ╭─╮│╰╯
    thick,        // ┏━┓┃┗┛
    ascii,        // +-+||++
    none,         // No border
};

/// Border characters for each style
const BorderChars = struct {
    top_left: u21,
    top: u21,
    top_right: u21,
    left: u21,
    right: u21,
    bottom_left: u21,
    bottom: u21,
    bottom_right: u21,

    fn forStyle(border_style: BorderStyle) BorderChars {
        return switch (border_style) {
            .single => BorderChars{
                .top_left = '┌',
                .top = '─',
                .top_right = '┐',
                .left = '│',
                .right = '│',
                .bottom_left = '└',
                .bottom = '─',
                .bottom_right = '┘',
            },
            .double => BorderChars{
                .top_left = '╔',
                .top = '═',
                .top_right = '╗',
                .left = '║',
                .right = '║',
                .bottom_left = '╚',
                .bottom = '═',
                .bottom_right = '╝',
            },
            .rounded => BorderChars{
                .top_left = '╭',
                .top = '─',
                .top_right = '╮',
                .left = '│',
                .right = '│',
                .bottom_left = '╰',
                .bottom = '─',
                .bottom_right = '╯',
            },
            .thick => BorderChars{
                .top_left = '┏',
                .top = '━',
                .top_right = '┓',
                .left = '┃',
                .right = '┃',
                .bottom_left = '┗',
                .bottom = '━',
                .bottom_right = '┛',
            },
            .ascii => BorderChars{
                .top_left = '+',
                .top = '-',
                .top_right = '+',
                .left = '|',
                .right = '|',
                .bottom_left = '+',
                .bottom = '-',
                .bottom_right = '+',
            },
            .none => BorderChars{
                .top_left = ' ',
                .top = ' ',
                .top_right = ' ',
                .left = ' ',
                .right = ' ',
                .bottom_left = ' ',
                .bottom = ' ',
                .bottom_right = ' ',
            },
        };
    }
};

/// Border widget wrapper
pub const Border = struct {
    widget: Widget,
    allocator: std.mem.Allocator,

    /// Child widget
    child: ?*Widget,

    /// Border style
    border_style: BorderStyle,
    border_color: Style,

    /// Title (optional)
    title: ?[]const u8,
    title_style: Style,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*Border {
        const border = try allocator.create(Border);
        border.* = Border{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .child = null,
            .border_style = .single,
            .border_color = Style.default().withFg(style.Color.white),
            .title = null,
            .title_style = Style.default().withFg(style.Color.bright_cyan).withBold(),
        };
        return border;
    }

    pub fn setChild(self: *Border, child: *Widget) void {
        self.child = child;
    }

    pub fn setBorderStyle(self: *Border, border_style: BorderStyle) void {
        self.border_style = border_style;
    }

    pub fn setTitle(self: *Border, title: []const u8) !void {
        if (self.title) |old| {
            self.allocator.free(old);
        }
        self.title = try self.allocator.dupe(u8, title);
    }

    pub fn clearTitle(self: *Border) void {
        if (self.title) |title| {
            self.allocator.free(title);
            self.title = null;
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Border = @fieldParentPtr("widget", widget);

        if (area.width < 2 or area.height < 2) return;

        const chars = BorderChars.forStyle(self.border_style);

        // Draw top border
        buffer.setCell(area.x, area.y, Cell.init(chars.top_left, self.border_color));
        var x: u16 = area.x + 1;
        while (x < area.x + area.width - 1) : (x += 1) {
            buffer.setCell(x, area.y, Cell.init(chars.top, self.border_color));
        }
        buffer.setCell(area.x + area.width - 1, area.y, Cell.init(chars.top_right, self.border_color));

        // Draw title if present
        if (self.title) |title| {
            const title_x = area.x + 2;
            if (title_x + title.len < area.x + area.width - 2) {
                buffer.writeText(title_x, area.y, title, self.title_style);
            }
        }

        // Draw left and right borders
        var y: u16 = area.y + 1;
        while (y < area.y + area.height - 1) : (y += 1) {
            buffer.setCell(area.x, y, Cell.init(chars.left, self.border_color));
            buffer.setCell(area.x + area.width - 1, y, Cell.init(chars.right, self.border_color));
        }

        // Draw bottom border
        buffer.setCell(area.x, area.y + area.height - 1, Cell.init(chars.bottom_left, self.border_color));
        x = area.x + 1;
        while (x < area.x + area.width - 1) : (x += 1) {
            buffer.setCell(x, area.y + area.height - 1, Cell.init(chars.bottom, self.border_color));
        }
        buffer.setCell(area.x + area.width - 1, area.y + area.height - 1, Cell.init(chars.bottom_right, self.border_color));

        // Render child in inner area
        if (self.child) |child| {
            if (area.width >= 2 and area.height >= 2) {
                const inner_area = Rect.init(
                    area.x + 1,
                    area.y + 1,
                    area.width - 2,
                    area.height - 2,
                );
                child.vtable.render(child, buffer, inner_area);
            }
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Border = @fieldParentPtr("widget", widget);

        // Forward events to child
        if (self.child) |child| {
            return child.vtable.handleEvent(child, event);
        }

        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *Border = @fieldParentPtr("widget", widget);

        // Resize child to inner area
        if (self.child) |child| {
            if (area.width >= 2 and area.height >= 2) {
                const inner_area = Rect.init(
                    area.x + 1,
                    area.y + 1,
                    area.width - 2,
                    area.height - 2,
                );
                child.vtable.resize(child, inner_area);
            }
        }
    }

    fn deinit(widget: *Widget) void {
        const self: *Border = @fieldParentPtr("widget", widget);

        if (self.title) |title| {
            self.allocator.free(title);
        }

        self.allocator.destroy(self);
    }
};

test "Border creation" {
    const allocator = std.testing.allocator;

    const border = try Border.init(allocator);
    defer border.widget.vtable.deinit(&border.widget);

    try std.testing.expect(border.border_style == .single);
}
