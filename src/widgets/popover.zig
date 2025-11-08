//! Popover widget for contextual help or menus.
const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const SizeConstraints = @import("../widget.zig").SizeConstraints;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const Event = @import("../event.zig").Event;
const Key = @import("../event.zig").Key;

const Rect = geometry.Rect;
const Style = style.Style;

pub const Popover = struct {
    pub const Config = struct {
        padding: u8 = 1,
        background_style: Style = Style.default().withBg(style.Color.black).withFg(style.Color.white),
        border_style: Style = Style.default().withFg(style.Color.bright_white),
        title_style: Style = Style.default().withFg(style.Color.bright_cyan).withBold(),
        content_style: Style = Style.default().withFg(style.Color.white),
        close_on_escape: bool = true,
        draw_border: bool = true,
    };

    pub const Error = std.mem.Allocator.Error;

    widget: Widget,
    allocator: std.mem.Allocator,
    config: Config,
    title: ?[]u8 = null,
    body_lines: std.ArrayList([]u8),
    visible: bool = false,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
        .getConstraints = getConstraints,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !*Popover {
        const self = try allocator.create(Popover);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .config = config,
            .body_lines = std.ArrayList([]u8).init(allocator),
        };
        return self;
    }

    pub fn setTitle(self: *Popover, maybe_title: ?[]const u8) Error!void {
        if (self.title) |existing| {
            self.allocator.free(existing);
            self.title = null;
        }
        if (maybe_title) |title_text| {
            const owned = try self.allocator.dupe(u8, title_text);
            self.title = owned;
        }
    }

    pub fn setBodyLines(self: *Popover, lines: []const []const u8) Error!void {
        self.clearLines();
        for (lines) |line| {
            const copy = try self.allocator.dupe(u8, line);
            try self.body_lines.append(copy);
        }
    }

    pub fn setBodyText(self: *Popover, text: []const u8) Error!void {
        self.clearLines();
        var splitter = std.mem.splitScalar(u8, text, '\n');
        while (splitter.next()) |line| {
            const copy = try self.allocator.dupe(u8, line);
            try self.body_lines.append(copy);
        }
    }

    pub fn show(self: *Popover) void {
        self.visible = true;
    }

    pub fn hide(self: *Popover) void {
        self.visible = false;
    }

    pub fn toggle(self: *Popover) void {
        self.visible = !self.visible;
    }

    fn clearLines(self: *Popover) void {
        for (self.body_lines.items) |line| {
            self.allocator.free(line);
        }
        self.body_lines.clearRetainingCapacity();
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Popover = @fieldParentPtr("widget", widget);
        if (!self.visible or area.width == 0 or area.height == 0) return;

        buffer.fill(area, Cell.init(' ', self.config.background_style));
        if (self.config.draw_border) {
            self.drawBorder(buffer, area);
        }

        const content_rect = shrink(area, self.config.padding);
        if (content_rect.width == 0 or content_rect.height == 0) return;

        var line_y = content_rect.y;
        if (self.title) |title_text| {
            self.writeLimited(buffer, content_rect.x, line_y, content_rect.x + content_rect.width, title_text, self.config.title_style);
            line_y += 1;
        }

        for (self.body_lines.items) |line| {
            if (line_y >= content_rect.y + content_rect.height) break;
            self.writeLimited(buffer, content_rect.x, line_y, content_rect.x + content_rect.width, line, self.config.content_style);
            line_y += 1;
        }
    }

    fn drawBorder(self: *Popover, buffer: *Buffer, area: Rect) void {
        if (area.width < 2 or area.height < 2) return;
        const left = area.x;
        const right = area.x + area.width - 1;
        const top = area.y;
        const bottom = area.y + area.height - 1;
        const border_style = self.config.border_style;

        buffer.setCell(left, top, Cell.init('┌', border_style));
        buffer.setCell(right, top, Cell.init('┐', border_style));
        buffer.setCell(left, bottom, Cell.init('└', border_style));
        buffer.setCell(right, bottom, Cell.init('┘', border_style));

        var x = left + 1;
        while (x < right) : (x += 1) {
            buffer.setCell(x, top, Cell.init('─', border_style));
            buffer.setCell(x, bottom, Cell.init('─', border_style));
        }

        var y = top + 1;
        while (y < bottom) : (y += 1) {
            buffer.setCell(left, y, Cell.init('│', border_style));
            buffer.setCell(right, y, Cell.init('│', border_style));
        }
    }

    fn shrink(area: Rect, padding: u8) Rect {
        const pad_u16: u16 = padding;
        const double_pad = pad_u16 * 2;
        if (area.width <= double_pad or area.height <= double_pad) {
            return Rect.init(area.x, area.y, 0, 0);
        }
        return Rect.init(
            area.x + pad_u16,
            area.y + pad_u16,
            area.width - double_pad,
            area.height - double_pad,
        );
    }

    fn writeLimited(self: *const Popover, buffer: *Buffer, x: u16, y: u16, end_x: u16, text: []const u8, text_style: Style) void {
        _ = self;
        if (text.len == 0 or x >= end_x) return;
        const available = end_x - x;
        if (available == 0) return;
        const chunk = @min(@as(usize, available), text.len);
        buffer.writeText(x, y, text[0..chunk], text_style);
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Popover = @fieldParentPtr("widget", widget);
        switch (event) {
            .key => |key| {
                if (self.visible and self.config.close_on_escape and key == .escape) {
                    self.visible = false;
                    return true;
                }
            },
            else => {},
        }
        return false;
    }

    fn getConstraints(widget: *Widget) SizeConstraints {
        const self: *Popover = @fieldParentPtr("widget", widget);
        _ = self;
        return SizeConstraints.unconstrained();
    }

    fn deinit(widget: *Widget) void {
        const self: *Popover = @fieldParentPtr("widget", widget);
        if (self.title) |t| {
            self.allocator.free(t);
        }
        self.clearLines();
        self.body_lines.deinit();
        self.allocator.destroy(self);
    }
};

const testing = std.testing;

fn makeBuffer(width: u16, height: u16) !Buffer {
    return try Buffer.init(testing.allocator, geometry.Size.init(width, height));
}

test "Popover sets title and content" {
    var popover = try Popover.init(testing.allocator, .{});
    defer popover.widget.deinit();

    try popover.setTitle("Help");
    try popover.setBodyText("Line 1\nLine 2");
    popover.show();

    var buffer = try makeBuffer(20, 6);
    defer buffer.deinit();

    popover.widget.render(&buffer, Rect.init(0, 0, 20, 6));
    const title_cell = buffer.getCell(1, 1) orelse return error.TestUnexpectedResult;
    try testing.expect(title_cell.char != ' ');

    popover.hide();
    try testing.expect(!popover.visible);
}

test "Popover closes on escape" {
    var popover = try Popover.init(testing.allocator, .{ .close_on_escape = true });
    defer popover.widget.deinit();
    popover.show();
    _ = popover.widget.handleEvent(Event.fromKey(.escape));
    try testing.expect(!popover.visible);
}
