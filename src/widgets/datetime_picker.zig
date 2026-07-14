//! DateTimePicker widget for selecting a date and/or time.
//! Keyboard: left/right (or tab) move between fields, up/down adjust the active
//! field, shift+up/down page by a larger step. Mouse: click a field to focus it,
//! wheel up/down adjust the focused field.

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

/// Which components of the value are shown and editable.
pub const Mode = enum {
    /// Only the date portion (YYYY-MM-DD).
    date,
    /// Only the time portion (HH:MM).
    time,
    /// Both date and time (YYYY-MM-DD HH:MM).
    datetime,
};

/// Editable field the cursor can rest on.
pub const Field = enum { year, month, day, hour, minute };

/// A plain-data date/time value. Not timezone-aware; purely a UI selection.
pub const DateTime = struct {
    year: u16 = 2026,
    month: u8 = 1, // 1-12
    day: u8 = 1, // 1-31 (clamped to month length)
    hour: u8 = 0, // 0-23
    minute: u8 = 0, // 0-59

    /// Number of days in this value's month, accounting for leap years.
    pub fn daysInMonth(self: DateTime) u8 {
        return daysIn(self.year, self.month);
    }

    fn isLeapYear(year: u16) bool {
        return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
    }

    fn daysIn(year: u16, month: u8) u8 {
        return switch (month) {
            1, 3, 5, 7, 8, 10, 12 => 31,
            4, 6, 9, 11 => 30,
            2 => if (isLeapYear(year)) @as(u8, 29) else 28,
            else => 31,
        };
    }

    /// Clamp the day so it never exceeds the current month's length.
    pub fn clampDay(self: *DateTime) void {
        const max_day = self.daysInMonth();
        if (self.day < 1) self.day = 1;
        if (self.day > max_day) self.day = max_day;
    }
};

/// Interactive date/time picker.
pub const DateTimePicker = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    value: DateTime,
    mode: Mode,
    active: Field,
    is_focused: bool = false,
    min_year: u16 = 1970,
    max_year: u16 = 2200,

    normal_style: Style,
    active_style: Style,
    label_style: Style,

    area: Rect = Rect.init(0, 0, 0, 0),
    // Screen column ranges of each rendered field, for mouse hit-testing.
    field_spans: [5]Span = .{ .{}, .{}, .{}, .{}, .{} },

    const Span = struct { start: u16 = 0, end: u16 = 0, field: Field = .year, active: bool = false };

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*DateTimePicker {
        return initWith(allocator, .datetime, .{});
    }

    pub fn initWith(allocator: std.mem.Allocator, mode: Mode, value: DateTime) !*DateTimePicker {
        const self = try allocator.create(DateTimePicker);
        var v = value;
        v.clampDay();
        self.* = DateTimePicker{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .value = v,
            .mode = mode,
            .active = firstField(mode),
            .normal_style = Style.default(),
            .active_style = Style.default().withBg(style.Color.blue).withBold(),
            .label_style = Style.default().withFg(style.Color.bright_black),
        };
        return self;
    }

    fn firstField(mode: Mode) Field {
        return switch (mode) {
            .date, .datetime => .year,
            .time => .hour,
        };
    }

    /// Ordered list of fields visible for the current mode.
    fn fields(self: *const DateTimePicker) []const Field {
        const date_fields = &[_]Field{ .year, .month, .day };
        const time_fields = &[_]Field{ .hour, .minute };
        const all_fields = &[_]Field{ .year, .month, .day, .hour, .minute };
        return switch (self.mode) {
            .date => date_fields,
            .time => time_fields,
            .datetime => all_fields,
        };
    }

    pub fn setValue(self: *DateTimePicker, value: DateTime) void {
        self.value = value;
        self.value.clampDay();
    }

    pub fn getValue(self: *const DateTimePicker) DateTime {
        return self.value;
    }

    pub fn setFocused(self: *DateTimePicker, focused: bool) void {
        self.is_focused = focused;
    }

    /// Move the cursor to the next/previous visible field.
    fn moveField(self: *DateTimePicker, forward: bool) void {
        const fs = self.fields();
        var idx: usize = 0;
        for (fs, 0..) |f, i| {
            if (f == self.active) idx = i;
        }
        if (forward) {
            idx = (idx + 1) % fs.len;
        } else {
            idx = if (idx == 0) fs.len - 1 else idx - 1;
        }
        self.active = fs[idx];
    }

    /// Increment/decrement the active field by `step`, wrapping each unit.
    fn adjust(self: *DateTimePicker, step: i32) void {
        switch (self.active) {
            .year => {
                const y = @as(i32, self.value.year) + step;
                const lo = @as(i32, self.min_year);
                const hi = @as(i32, self.max_year);
                self.value.year = @intCast(std.math.clamp(y, lo, hi));
                self.value.clampDay();
            },
            .month => {
                self.value.month = wrap(self.value.month, step, 1, 12);
                self.value.clampDay();
            },
            .day => {
                self.value.day = wrap(self.value.day, step, 1, self.value.daysInMonth());
            },
            .hour => self.value.hour = wrap(self.value.hour, step, 0, 23),
            .minute => self.value.minute = wrap(self.value.minute, step, 0, 59),
        }
    }

    /// Wrap `current + step` into the inclusive range [lo, hi].
    fn wrap(current: u8, step: i32, lo: u8, hi: u8) u8 {
        const span = @as(i32, hi) - @as(i32, lo) + 1;
        var v = @as(i32, current) + step - @as(i32, lo);
        v = @mod(v, span);
        if (v < 0) v += span;
        return @intCast(v + @as(i32, lo));
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *DateTimePicker = @fieldParentPtr("widget", widget);
        self.area = area;
        if (area.width == 0 or area.height == 0) return;

        buffer.fill(area, Cell.withStyle(self.normal_style));

        var x = area.x;
        const y = area.y;
        var span_count: usize = 0;

        const show_date = self.mode == .date or self.mode == .datetime;
        const show_time = self.mode == .time or self.mode == .datetime;

        if (show_date) {
            x = self.drawField(buffer, x, y, .year, 4, &span_count);
            x = self.drawSep(buffer, x, y, '-');
            x = self.drawField(buffer, x, y, .month, 2, &span_count);
            x = self.drawSep(buffer, x, y, '-');
            x = self.drawField(buffer, x, y, .day, 2, &span_count);
        }
        if (show_date and show_time) {
            x = self.drawSep(buffer, x, y, ' ');
        }
        if (show_time) {
            x = self.drawField(buffer, x, y, .hour, 2, &span_count);
            x = self.drawSep(buffer, x, y, ':');
            x = self.drawField(buffer, x, y, .minute, 2, &span_count);
        }
    }

    fn fieldValue(self: *const DateTimePicker, field: Field) u16 {
        return switch (field) {
            .year => self.value.year,
            .month => self.value.month,
            .day => self.value.day,
            .hour => self.value.hour,
            .minute => self.value.minute,
        };
    }

    fn drawField(self: *DateTimePicker, buffer: *Buffer, x: u16, y: u16, field: Field, width: u8, span_count: *usize) u16 {
        const is_active = self.active == field;
        const cell_style = if (is_active and self.is_focused) self.active_style else self.normal_style;

        var buf: [8]u8 = undefined;
        const text = if (width == 4)
            std.fmt.bufPrint(&buf, "{d:0>4}", .{self.fieldValue(field)}) catch "????"
        else
            std.fmt.bufPrint(&buf, "{d:0>2}", .{self.fieldValue(field)}) catch "??";

        buffer.writeText(x, y, text, cell_style);

        const end = x + @as(u16, @intCast(text.len));
        if (span_count.* < self.field_spans.len) {
            self.field_spans[span_count.*] = .{ .start = x, .end = end, .field = field, .active = true };
            span_count.* += 1;
        }
        return end;
    }

    fn drawSep(self: *DateTimePicker, buffer: *Buffer, x: u16, y: u16, ch: u21) u16 {
        buffer.setCell(x, y, Cell.init(ch, self.label_style));
        return x + 1;
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *DateTimePicker = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key| {
                if (!self.is_focused) return false;
                switch (key) {
                    .left => {
                        self.moveField(false);
                        return true;
                    },
                    .right, .tab => {
                        self.moveField(true);
                        return true;
                    },
                    .up => {
                        self.adjust(1);
                        return true;
                    },
                    .down => {
                        self.adjust(-1);
                        return true;
                    },
                    .page_up => {
                        self.adjust(10);
                        return true;
                    },
                    .page_down => {
                        self.adjust(-10);
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
                            for (self.field_spans) |span| {
                                if (!span.active) continue;
                                if (pos.x >= span.start and pos.x < span.end) {
                                    self.active = span.field;
                                    return true;
                                }
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
        const self: *DateTimePicker = @fieldParentPtr("widget", widget);
        self.area = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *DateTimePicker = @fieldParentPtr("widget", widget);
        self.allocator.destroy(self);
    }
};

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

const testing = std.testing;
const phantom = @import("../root.zig");

test "DateTimePicker leap year day count" {
    var dt = DateTime{ .year = 2024, .month = 2, .day = 1 };
    try testing.expectEqual(@as(u8, 29), dt.daysInMonth());
    dt.year = 2023;
    try testing.expectEqual(@as(u8, 28), dt.daysInMonth());
    dt.year = 2000;
    try testing.expectEqual(@as(u8, 29), dt.daysInMonth());
    dt.year = 1900;
    try testing.expectEqual(@as(u8, 28), dt.daysInMonth());
}

test "DateTimePicker clampDay shrinks day to month length" {
    var dt = DateTime{ .year = 2023, .month = 1, .day = 31 };
    dt.month = 2;
    dt.clampDay();
    try testing.expectEqual(@as(u8, 28), dt.day);
}

test "DateTimePicker field navigation cycles" {
    const picker = try DateTimePicker.init(testing.allocator);
    defer picker.widget.deinit();

    try testing.expectEqual(Field.year, picker.active);
    picker.moveField(true);
    try testing.expectEqual(Field.month, picker.active);
    picker.moveField(false);
    try testing.expectEqual(Field.year, picker.active);
    picker.moveField(false); // wrap to last field
    try testing.expectEqual(Field.minute, picker.active);
}

test "DateTimePicker adjust wraps units" {
    const picker = try DateTimePicker.init(testing.allocator);
    defer picker.widget.deinit();

    picker.setValue(.{ .year = 2026, .month = 12, .day = 31, .hour = 23, .minute = 59 });

    picker.active = .minute;
    picker.adjust(1);
    try testing.expectEqual(@as(u8, 0), picker.value.minute);

    picker.active = .hour;
    picker.adjust(1);
    try testing.expectEqual(@as(u8, 0), picker.value.hour);

    picker.active = .month;
    picker.adjust(1);
    try testing.expectEqual(@as(u8, 1), picker.value.month);
}

test "DateTimePicker year respects bounds" {
    const picker = try DateTimePicker.init(testing.allocator);
    defer picker.widget.deinit();
    picker.setValue(.{ .year = 1970 });
    picker.active = .year;
    picker.adjust(-5);
    try testing.expectEqual(@as(u16, 1970), picker.value.year);
}

test "DateTimePicker keyboard event adjusts active field" {
    const picker = try DateTimePicker.init(testing.allocator);
    defer picker.widget.deinit();
    picker.setFocused(true);
    picker.setValue(.{ .year = 2026, .month = 6, .day = 15 });

    picker.active = .month;
    _ = picker.widget.handleEvent(Event{ .key = .up });
    try testing.expectEqual(@as(u8, 7), picker.value.month);
    _ = picker.widget.handleEvent(Event{ .key = .down });
    try testing.expectEqual(@as(u8, 6), picker.value.month);
}

test "DateTimePicker renders date fields" {
    const picker = try DateTimePicker.init(testing.allocator);
    defer picker.widget.deinit();
    picker.setValue(.{ .year = 2026, .month = 7, .day = 4, .hour = 9, .minute = 30 });

    var buffer = try Buffer.init(testing.allocator, phantom.Size.init(40, 3));
    defer buffer.deinit();

    picker.widget.render(&buffer, Rect.init(0, 0, 40, 1));

    // First cell should be the leading '2' of the year.
    const cell = buffer.getCell(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, '2'), cell.?.char);
}

test "DateTimePicker time mode starts on hour" {
    const picker = try DateTimePicker.initWith(testing.allocator, .time, .{});
    defer picker.widget.deinit();
    try testing.expectEqual(Field.hour, picker.active);
    const fs = picker.fields();
    try testing.expectEqual(@as(usize, 2), fs.len);
}
