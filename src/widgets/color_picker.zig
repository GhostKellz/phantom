//! ColorPicker widget for choosing an RGB color.
//! Keyboard: left/right (or tab) move between R/G/B channels, up/down adjust the
//! active channel by 1, page_up/page_down adjust by 16. Mouse: click a channel
//! bar to focus it and jump the value to the clicked position; wheel up/down
//! adjust the focused channel.

const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const Key = @import("../event.zig").Key;
const MouseEvent = @import("../event.zig").MouseEvent;
const MouseButton = @import("../event.zig").MouseButton;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Style = style.Style;
const Color = style.Color;

/// The three editable channels.
pub const Channel = enum { red, green, blue };

/// Interactive RGB color picker.
pub const ColorPicker = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    red: u8 = 128,
    green: u8 = 128,
    blue: u8 = 128,
    active: Channel = .red,
    is_focused: bool = false,

    label_style: Style,
    active_label_style: Style,

    area: Rect = Rect.init(0, 0, 0, 0),
    // Screen row + bar span for each channel, recorded during render for mouse
    // hit-testing. Index order matches Channel: red, green, blue.
    bar_rows: [3]BarRow = .{ .{}, .{}, .{} },

    const BarRow = struct { y: u16 = 0, start: u16 = 0, width: u16 = 0 };

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*ColorPicker {
        return initWith(allocator, 128, 128, 128);
    }

    pub fn initWith(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) !*ColorPicker {
        const self = try allocator.create(ColorPicker);
        self.* = ColorPicker{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .red = r,
            .green = g,
            .blue = b,
            .label_style = Style.default().withFg(style.Color.bright_black),
            .active_label_style = Style.default().withFg(style.Color.white).withBold(),
        };
        return self;
    }

    /// The currently selected color as a true-color RGB value.
    pub fn color(self: *const ColorPicker) Color {
        return Color.fromRgb(self.red, self.green, self.blue);
    }

    pub fn setColor(self: *ColorPicker, r: u8, g: u8, b: u8) void {
        self.red = r;
        self.green = g;
        self.blue = b;
    }

    pub fn setFocused(self: *ColorPicker, focused: bool) void {
        self.is_focused = focused;
    }

    fn channelPtr(self: *ColorPicker, ch: Channel) *u8 {
        return switch (ch) {
            .red => &self.red,
            .green => &self.green,
            .blue => &self.blue,
        };
    }

    fn channelValue(self: *const ColorPicker, ch: Channel) u8 {
        return switch (ch) {
            .red => self.red,
            .green => self.green,
            .blue => self.blue,
        };
    }

    fn moveChannel(self: *ColorPicker, forward: bool) void {
        const order = [_]Channel{ .red, .green, .blue };
        var idx: usize = 0;
        for (order, 0..) |c, i| {
            if (c == self.active) idx = i;
        }
        if (forward) {
            idx = (idx + 1) % order.len;
        } else {
            idx = if (idx == 0) order.len - 1 else idx - 1;
        }
        self.active = order[idx];
    }

    /// Adjust the active channel by `step`, saturating at 0 and 255.
    fn adjust(self: *ColorPicker, step: i32) void {
        const ptr = self.channelPtr(self.active);
        const v = std.math.clamp(@as(i32, ptr.*) + step, 0, 255);
        ptr.* = @intCast(v);
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *ColorPicker = @fieldParentPtr("widget", widget);
        self.area = area;
        if (area.width == 0 or area.height == 0) return;

        buffer.fill(area, Cell.withStyle(Style.default()));

        const channels = [_]Channel{ .red, .green, .blue };
        const swatch_width: u16 = 4;
        // Leave room on the left for the "R " label and on the right for the
        // swatch preview plus its separating space.
        const label_w: u16 = 2;
        const value_w: u16 = 4; // " 255"
        const reserved: u16 = label_w + value_w + swatch_width + 1;
        const bar_width: u16 = if (area.width > reserved) area.width - reserved else 0;

        for (channels, 0..) |ch, i| {
            const y = area.y + @as(u16, @intCast(i));
            if (y >= area.y + area.height) break;

            const is_active = self.active == ch and self.is_focused;
            const label_style = if (is_active) self.active_label_style else self.label_style;

            const label: u21 = switch (ch) {
                .red => 'R',
                .green => 'G',
                .blue => 'B',
            };
            buffer.setCell(area.x, y, Cell.init(label, label_style));

            const bar_x = area.x + label_w;
            const value = self.channelValue(ch);
            const filled: u16 = if (bar_width == 0) 0 else @intCast((@as(u32, value) * bar_width) / 255);

            const bar_color: Color = switch (ch) {
                .red => Color.fromRgb(value, 0, 0),
                .green => Color.fromRgb(0, value, 0),
                .blue => Color.fromRgb(0, 0, value),
            };
            const bar_style = Style.default().withFg(bar_color);

            var bx: u16 = 0;
            while (bx < bar_width) : (bx += 1) {
                const ch_glyph: u21 = if (bx < filled) '█' else '░';
                buffer.setCell(bar_x + bx, y, Cell.init(ch_glyph, bar_style));
            }

            // Numeric value after the bar.
            var vbuf: [4]u8 = undefined;
            const vtext = std.fmt.bufPrint(&vbuf, " {d:>3}", .{value}) catch " ???";
            buffer.writeText(bar_x + bar_width, y, vtext, label_style);

            self.bar_rows[i] = .{ .y = y, .start = bar_x, .width = bar_width };
        }

        // Swatch preview on the right side, spanning all three rows.
        const swatch_x = area.x + area.width - swatch_width;
        const swatch_style = Style.default().withBg(self.color());
        var sy: u16 = area.y;
        while (sy < area.y + @min(@as(u16, 3), area.height)) : (sy += 1) {
            var sx: u16 = 0;
            while (sx < swatch_width) : (sx += 1) {
                buffer.setCell(swatch_x + sx, sy, Cell.init(' ', swatch_style));
            }
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *ColorPicker = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key| {
                if (!self.is_focused) return false;
                switch (key) {
                    .up => {
                        self.moveChannel(false);
                        return true;
                    },
                    .down => {
                        self.moveChannel(true);
                        return true;
                    },
                    .tab => {
                        self.moveChannel(true);
                        return true;
                    },
                    .left => {
                        self.adjust(-1);
                        return true;
                    },
                    .right => {
                        self.adjust(1);
                        return true;
                    },
                    .page_up => {
                        self.adjust(16);
                        return true;
                    },
                    .page_down => {
                        self.adjust(-16);
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                const pos = mouse.position;
                const in_bounds = pos.x >= self.area.x and pos.x < self.area.x + self.area.width and
                    pos.y >= self.area.y and pos.y < self.area.y + self.area.height;
                if (!in_bounds) return false;

                switch (mouse.button) {
                    .left => {
                        if (mouse.pressed) {
                            self.is_focused = true;
                            for (self.bar_rows, 0..) |row, i| {
                                if (pos.y != row.y or row.width == 0) continue;
                                self.active = @enumFromInt(i);
                                if (pos.x >= row.start and pos.x < row.start + row.width) {
                                    const rel = pos.x - row.start;
                                    const v = (@as(u32, rel) * 255) / (row.width - 1);
                                    self.channelPtr(self.active).* = @intCast(@min(v, 255));
                                }
                                return true;
                            }
                            return true;
                        }
                    },
                    .wheel_up => {
                        self.adjust(1);
                        return true;
                    },
                    .wheel_down => {
                        self.adjust(-1);
                        return true;
                    },
                    else => {},
                }
            },
            else => {},
        }
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *ColorPicker = @fieldParentPtr("widget", widget);
        self.area = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *ColorPicker = @fieldParentPtr("widget", widget);
        self.allocator.destroy(self);
    }
};

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

const testing = std.testing;
const phantom = @import("../root.zig");

test "ColorPicker returns rgb color" {
    const picker = try ColorPicker.initWith(testing.allocator, 10, 20, 30);
    defer picker.widget.deinit();

    const c = picker.color();
    try testing.expect(c == .rgb);
    try testing.expectEqual(@as(u8, 10), c.rgb.r);
    try testing.expectEqual(@as(u8, 20), c.rgb.g);
    try testing.expectEqual(@as(u8, 30), c.rgb.b);
}

test "ColorPicker channel navigation cycles" {
    const picker = try ColorPicker.init(testing.allocator);
    defer picker.widget.deinit();

    try testing.expectEqual(Channel.red, picker.active);
    picker.moveChannel(true);
    try testing.expectEqual(Channel.green, picker.active);
    picker.moveChannel(true);
    try testing.expectEqual(Channel.blue, picker.active);
    picker.moveChannel(true);
    try testing.expectEqual(Channel.red, picker.active);
}

test "ColorPicker adjust saturates" {
    const picker = try ColorPicker.initWith(testing.allocator, 250, 5, 0);
    defer picker.widget.deinit();

    picker.active = .red;
    picker.adjust(16);
    try testing.expectEqual(@as(u8, 255), picker.red);

    picker.active = .blue;
    picker.adjust(-16);
    try testing.expectEqual(@as(u8, 0), picker.blue);
}

test "ColorPicker keyboard adjusts active channel" {
    const picker = try ColorPicker.initWith(testing.allocator, 100, 100, 100);
    defer picker.widget.deinit();
    picker.setFocused(true);

    picker.active = .green;
    _ = picker.widget.handleEvent(Event{ .key = .right });
    try testing.expectEqual(@as(u8, 101), picker.green);
    _ = picker.widget.handleEvent(Event{ .key = .left });
    try testing.expectEqual(@as(u8, 100), picker.green);
}

test "ColorPicker ignores keys when unfocused" {
    const picker = try ColorPicker.initWith(testing.allocator, 100, 100, 100);
    defer picker.widget.deinit();

    const consumed = picker.widget.handleEvent(Event{ .key = .right });
    try testing.expect(!consumed);
    try testing.expectEqual(@as(u8, 100), picker.red);
}

test "ColorPicker renders channel labels" {
    const picker = try ColorPicker.initWith(testing.allocator, 255, 0, 0);
    defer picker.widget.deinit();

    var buffer = try Buffer.init(testing.allocator, phantom.Size.init(30, 4));
    defer buffer.deinit();

    picker.widget.render(&buffer, Rect.init(0, 0, 30, 3));

    try testing.expectEqual(@as(u21, 'R'), buffer.getCell(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'G'), buffer.getCell(0, 1).?.char);
    try testing.expectEqual(@as(u21, 'B'), buffer.getCell(0, 2).?.char);
}
