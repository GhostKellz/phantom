//! Calendar Widget - Month view with date selection
//! Supports event markers, keyboard navigation, and customizable styling

const std = @import("std");
const phantom = @import("../root.zig");
const Rect = phantom.Rect;
const Position = phantom.Position;
const Color = phantom.Color;
const Style = phantom.Style;
const Buffer = phantom.Buffer;
const Event = phantom.Event;
const Key = phantom.Key;

/// Calendar widget for date selection and display
pub const Calendar = struct {
    allocator: std.mem.Allocator,
    month: u8, // 1-12
    year: u32,
    selected_date: ?Date,
    events: std.AutoHashMap(Date, []const u8),
    first_day_of_week: FirstDay,
    show_week_numbers: bool,
    title_style: Style,
    weekday_style: Style,
    day_style: Style,
    selected_style: Style,
    today_style: Style,
    other_month_style: Style,
    event_marker: u21,

    pub const FirstDay = enum {
        sunday,
        monday,
    };

    pub const Date = struct {
        year: u32,
        month: u8,
        day: u8,

        pub fn equals(self: Date, other: Date) bool {
            return self.year == other.year and self.month == other.month and self.day == other.day;
        }

        pub fn hash(self: Date) u64 {
            return @as(u64, self.year) * 10000 + @as(u64, self.month) * 100 + @as(u64, self.day);
        }
    };

    /// Initialize Calendar
    pub fn init(allocator: std.mem.Allocator) Calendar {
        const now = std.time.timestamp();
        const epoch_day = @divFloor(now, 86400);
        const date = epochDayToDate(epoch_day);

        return Calendar{
            .allocator = allocator,
            .month = date.month,
            .year = date.year,
            .selected_date = date,
            .events = std.AutoHashMap(Date, []const u8).init(allocator),
            .first_day_of_week = .sunday,
            .show_week_numbers = false,
            .title_style = Style.default().withBold(),
            .weekday_style = Style.default().withFg(Color.cyan),
            .day_style = Style.default(),
            .selected_style = Style.default().withFg(Color.black).withBg(Color.cyan),
            .today_style = Style.default().withFg(Color.green).withBold(),
            .other_month_style = Style.default().withFg(Color.bright_black),
            .event_marker = '●',
        };
    }

    pub fn deinit(self: *Calendar) void {
        var iter = self.events.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.events.deinit();
    }

    /// Set the displayed month and year
    pub fn setMonth(self: *Calendar, year: u32, month: u8) void {
        self.year = year;
        self.month = @max(1, @min(month, 12));
    }

    /// Go to next month
    pub fn nextMonth(self: *Calendar) void {
        if (self.month == 12) {
            self.month = 1;
            self.year += 1;
        } else {
            self.month += 1;
        }
    }

    /// Go to previous month
    pub fn prevMonth(self: *Calendar) void {
        if (self.month == 1) {
            self.month = 12;
            self.year -= 1;
        } else {
            self.month -= 1;
        }
    }

    /// Select a date
    pub fn selectDate(self: *Calendar, date: Date) void {
        self.selected_date = date;
    }

    /// Add an event marker for a date
    pub fn addEvent(self: *Calendar, date: Date, description: []const u8) !void {
        const desc_copy = try self.allocator.dupe(u8, description);
        try self.events.put(date, desc_copy);
    }

    /// Check if a date has an event
    pub fn hasEvent(self: *const Calendar, date: Date) bool {
        return self.events.contains(date);
    }

    /// Get today's date
    pub fn getToday() Date {
        const now = std.time.timestamp();
        const epoch_day = @divFloor(now, 86400);
        return epochDayToDate(epoch_day);
    }

    /// Check if a date is today
    fn isToday(date: Date) bool {
        const today = getToday();
        return date.equals(today);
    }

    /// Get number of days in a month
    fn getDaysInMonth(year: u32, month: u8) u8 {
        return switch (month) {
            1, 3, 5, 7, 8, 10, 12 => 31,
            4, 6, 9, 11 => 30,
            2 => if (isLeapYear(year)) 29 else 28,
            else => 0,
        };
    }

    /// Check if a year is a leap year
    fn isLeapYear(year: u32) bool {
        return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
    }

    /// Get day of week for first day of month (0=Sunday, 6=Saturday)
    fn getFirstDayOfMonth(year: u32, month: u8) u8 {
        // Zeller's congruence algorithm
        const m: u32 = if (month < 3) month + 12 else month;
        const y: u32 = if (month < 3) year - 1 else year;
        const q: u32 = 1; // First day of month
        const k: u32 = y % 100;
        const j: u32 = y / 100;

        const h = (q + ((13 * (m + 1)) / 5) + k + (k / 4) + (j / 4) - (2 * j)) % 7;
        // Convert: 0=Saturday, 1=Sunday, etc. to 0=Sunday, 1=Monday, etc.
        return @intCast((h + 6) % 7);
    }

    /// Convert epoch day to date
    fn epochDayToDate(epoch_day: i64) Date {
        // Unix epoch is 1970-01-01 (Thursday)
        // Simple algorithm for demonstration
        var days_remaining = epoch_day;
        var year: u32 = 1970;

        while (true) {
            const days_in_year: i64 = if (isLeapYear(year)) 366 else 365;
            if (days_remaining < days_in_year) break;
            days_remaining -= days_in_year;
            year += 1;
        }

        var month: u8 = 1;
        while (month <= 12) : (month += 1) {
            const days_in_month = getDaysInMonth(year, month);
            if (days_remaining < days_in_month) break;
            days_remaining -= days_in_month;
        }

        const day: u8 = @intCast(days_remaining + 1);

        return Date{ .year = year, .month = month, .day = day };
    }

    /// Handle keyboard input
    pub fn handleEvent(self: *Calendar, event: Event) bool {
        if (event != .key) return false;

        const key = event.key;

        // Navigate months
        if (key.matches('n', .{ .ctrl = true }) or (key.code == .right and key.modifiers.ctrl)) {
            self.nextMonth();
            return true;
        }

        if (key.matches('p', .{ .ctrl = true }) or (key.code == .left and key.modifiers.ctrl)) {
            self.prevMonth();
            return true;
        }

        // Navigate days (if a date is selected)
        if (self.selected_date) |*date| {
            var changed = false;

            if (key.code == .up) {
                if (date.day > 7) {
                    date.day -= 7;
                    changed = true;
                }
            } else if (key.code == .down) {
                const days_in_month = getDaysInMonth(date.year, date.month);
                if (date.day + 7 <= days_in_month) {
                    date.day += 7;
                    changed = true;
                }
            } else if (key.code == .left) {
                if (date.day > 1) {
                    date.day -= 1;
                    changed = true;
                }
            } else if (key.code == .right) {
                const days_in_month = getDaysInMonth(date.year, date.month);
                if (date.day < days_in_month) {
                    date.day += 1;
                    changed = true;
                }
            }

            if (changed) {
                self.selected_date = date.*;
                return true;
            }
        }

        return false;
    }

    /// Render the Calendar
    pub fn render(self: *Calendar, buffer: *Buffer, area: Rect) void {
        if (area.height < 8 or area.width < 20) return;

        var current_y = area.y;

        // Render title (month and year)
        const month_names = [_][]const u8{
            "January", "February", "March",     "April",   "May",      "June",
            "July",    "August",   "September", "October", "November", "December",
        };

        const month_name = if (self.month >= 1 and self.month <= 12) month_names[self.month - 1] else "Unknown";
        const title = std.fmt.allocPrint(self.allocator, "{s} {d}", .{ month_name, self.year }) catch return;
        defer self.allocator.free(title);

        const title_x = area.x + @divTrunc(area.width, 2) - @divTrunc(@as(u16, @intCast(title.len)), 2);
        buffer.setString(title_x, current_y, title, self.title_style);
        current_y += 2;

        // Render weekday headers
        const weekdays = if (self.first_day_of_week == .sunday)
            [_][]const u8{ "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }
        else
            [_][]const u8{ "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" };

        var header_x = area.x + 1;
        for (weekdays) |weekday| {
            buffer.setString(header_x, current_y, weekday, self.weekday_style);
            header_x += 3;
        }
        current_y += 1;

        // Render days grid
        const first_weekday = getFirstDayOfMonth(self.year, self.month);
        const offset = if (self.first_day_of_week == .monday)
            if (first_weekday == 0) 6 else first_weekday - 1
        else
            first_weekday;

        const days_in_month = getDaysInMonth(self.year, self.month);

        var day: u8 = 1;
        var week: u8 = 0;

        while (week < 6 and current_y < area.y + area.height) : (week += 1) {
            var day_x = area.x;
            var weekday: u8 = 0;

            while (weekday < 7) : (weekday += 1) {
                const cell_idx = week * 7 + weekday;

                if (cell_idx >= offset and day <= days_in_month) {
                    const date = Date{ .year = self.year, .month = self.month, .day = day };

                    // Determine style
                    var style = self.day_style;
                    if (self.selected_date) |sel| {
                        if (date.equals(sel)) {
                            style = self.selected_style;
                        }
                    }
                    if (isToday(date) and style.bg == null) {
                        style = self.today_style;
                    }

                    // Render day number
                    const day_str = std.fmt.allocPrint(self.allocator, "{d:>2}", .{day}) catch break;
                    defer self.allocator.free(day_str);
                    buffer.setString(day_x + 1, current_y, day_str, style);

                    // Render event marker
                    if (self.hasEvent(date)) {
                        buffer.setCell(day_x, current_y, self.event_marker, Style.default().withFg(Color.red));
                    }

                    day += 1;
                }

                day_x += 3;
            }

            current_y += 1;
            if (day > days_in_month) break;
        }
    }
};

// Tests
test "Calendar initialization" {
    const testing = std.testing;

    var calendar = Calendar.init(testing.allocator);
    defer calendar.deinit();

    try testing.expect(calendar.month >= 1 and calendar.month <= 12);
    try testing.expect(calendar.year >= 1970);
}

test "Calendar days in month" {
    const testing = std.testing;

    try testing.expectEqual(@as(u8, 31), Calendar.getDaysInMonth(2024, 1)); // January
    try testing.expectEqual(@as(u8, 29), Calendar.getDaysInMonth(2024, 2)); // February (leap year)
    try testing.expectEqual(@as(u8, 28), Calendar.getDaysInMonth(2023, 2)); // February (non-leap)
    try testing.expectEqual(@as(u8, 30), Calendar.getDaysInMonth(2024, 4)); // April
}

test "Calendar leap year" {
    const testing = std.testing;

    try testing.expect(Calendar.isLeapYear(2024)); // Divisible by 4
    try testing.expect(!Calendar.isLeapYear(2023)); // Not divisible by 4
    try testing.expect(!Calendar.isLeapYear(1900)); // Divisible by 100 but not 400
    try testing.expect(Calendar.isLeapYear(2000)); // Divisible by 400
}

test "Calendar month navigation" {
    const testing = std.testing;

    var calendar = Calendar.init(testing.allocator);
    defer calendar.deinit();

    calendar.setMonth(2024, 6);
    try testing.expectEqual(@as(u8, 6), calendar.month);
    try testing.expectEqual(@as(u32, 2024), calendar.year);

    calendar.nextMonth();
    try testing.expectEqual(@as(u8, 7), calendar.month);

    calendar.prevMonth();
    try testing.expectEqual(@as(u8, 6), calendar.month);

    // Year boundary
    calendar.setMonth(2024, 12);
    calendar.nextMonth();
    try testing.expectEqual(@as(u8, 1), calendar.month);
    try testing.expectEqual(@as(u32, 2025), calendar.year);
}

test "Calendar event management" {
    const testing = std.testing;

    var calendar = Calendar.init(testing.allocator);
    defer calendar.deinit();

    const date = Calendar.Date{ .year = 2024, .month = 6, .day = 15 };
    try calendar.addEvent(date, "Test Event");

    try testing.expect(calendar.hasEvent(date));

    const other_date = Calendar.Date{ .year = 2024, .month = 6, .day = 16 };
    try testing.expect(!calendar.hasEvent(other_date));
}
