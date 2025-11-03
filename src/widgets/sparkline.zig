//! Sparkline Widget - Compact trend visualization
//! Minimal chrome, single line height, perfect for inline metrics
//! Uses Unicode block characters: ▁▂▃▄▅▆▇█

const std = @import("std");
const phantom = @import("../root.zig");
const Rect = phantom.Rect;
const Color = phantom.Color;
const Style = phantom.Style;
const Buffer = phantom.Buffer;
const Cell = phantom.Cell;

/// Sparkline widget for compact trend visualization
pub const Sparkline = struct {
    allocator: std.mem.Allocator,
    data: []f64,
    max_value: ?f64,
    style: Style,
    show_baseline: bool,
    baseline_char: u21,

    /// Initialize Sparkline
    pub fn init(allocator: std.mem.Allocator, data: []f64) Sparkline {
        return Sparkline{
            .allocator = allocator,
            .data = data,
            .max_value = null,
            .style = Style.default(),
            .show_baseline = false,
            .baseline_char = '─',
        };
    }

    /// Set data
    pub fn setData(self: *Sparkline, data: []f64) void {
        self.data = data;
    }

    /// Set maximum value for scaling (auto-calculate if null)
    pub fn setMaxValue(self: *Sparkline, max: ?f64) void {
        self.max_value = max;
    }

    /// Set style
    pub fn setStyle(self: *Sparkline, style: Style) void {
        self.style = style;
    }

    /// Set color
    pub fn setColor(self: *Sparkline, color: Color) void {
        self.style = self.style.withFg(color);
    }

    /// Calculate maximum value from data
    fn calculateMaxValue(self: *const Sparkline) f64 {
        if (self.max_value) |max| return max;
        if (self.data.len == 0) return 1.0;

        var max: f64 = 0.0;
        for (self.data) |value| {
            if (value > max) max = value;
        }

        return if (max == 0.0) 1.0 else max;
    }

    /// Get sparkline character for value
    fn getSparkChar(self: *const Sparkline, value: f64, max_val: f64) u21 {
        _ = self;

        if (max_val == 0.0 or value <= 0.0) return ' ';

        const normalized = value / max_val;
        const level = @as(u8, @intFromFloat(normalized * 8.0));

        // Unicode block characters from empty to full
        return switch (level) {
            0 => ' ',  // Empty
            1 => '▁', // 1/8
            2 => '▂', // 2/8
            3 => '▃', // 3/8
            4 => '▄', // 4/8
            5 => '▅', // 5/8
            6 => '▆', // 6/8
            7 => '▇', // 7/8
            else => '█', // Full
        };
    }

    /// Render the Sparkline
    pub fn render(self: *Sparkline, buffer: *Buffer, area: Rect) void {
        if (self.data.len == 0 or area.width == 0) return;

        const max_val = self.calculateMaxValue();
        const y = area.y;

        // If we have more data points than width, sample evenly
        if (self.data.len <= area.width) {
            // Render all data points
            for (self.data, 0..) |value, i| {
                if (i >= area.width) break;

                const char = self.getSparkChar(value, max_val);
                buffer.setCell(area.x + @as(u16, @intCast(i)), y, Cell.init(char, self.style));
            }

            // Fill remaining space with baseline if enabled
            if (self.show_baseline) {
                var x = @as(u16, @intCast(self.data.len));
                while (x < area.width) : (x += 1) {
                    buffer.setCell(area.x + x, y, Cell.init(self.baseline_char, self.style));
                }
            }
        } else {
            // Sample data to fit width
            const sample_rate = @as(f64, @floatFromInt(self.data.len)) / @as(f64, @floatFromInt(area.width));

            var x: u16 = 0;
            while (x < area.width) : (x += 1) {
                const data_idx = @as(usize, @intFromFloat(@as(f64, @floatFromInt(x)) * sample_rate));
                if (data_idx >= self.data.len) break;

                const value = self.data[data_idx];
                const char = self.getSparkChar(value, max_val);
                buffer.setCell(area.x + x, y, Cell.init(char, self.style));
            }
        }
    }

    /// Render with value at the end
    pub fn renderWithValue(self: *Sparkline, buffer: *Buffer, area: Rect) void {
        if (self.data.len == 0) return;

        // Reserve space for value (e.g., " 123.4")
        const value_width: u16 = 8;
        if (area.width <= value_width) {
            self.render(buffer, area);
            return;
        }

        const sparkline_area = Rect{
            .x = area.x,
            .y = area.y,
            .width = area.width - value_width,
            .height = area.height,
        };

        self.render(buffer, sparkline_area);

        // Render current value
        const current_value = self.data[self.data.len - 1];
        const value_str = std.fmt.allocPrint(self.allocator, " {d:.1}", .{current_value}) catch return;
        defer self.allocator.free(value_str);

        const value_x = area.x + area.width - @as(u16, @intCast(value_str.len));
        buffer.writeText(value_x, area.y, value_str, self.style.withBold());
    }

    /// Create a sparkline from a sliding window of data
    pub fn fromWindow(allocator: std.mem.Allocator, full_data: []const f64, window_size: usize) !Sparkline {
        const start = if (full_data.len > window_size) full_data.len - window_size else 0;
        const window_data = full_data[start..];

        const data_copy = try allocator.dupe(f64, window_data);
        return Sparkline.init(allocator, data_copy);
    }
};

// Tests
test "Sparkline initialization" {
    const testing = std.testing;

    const data = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const sparkline = Sparkline.init(testing.allocator, @constCast(&data));

    try testing.expectEqual(@as(usize, 5), sparkline.data.len);
    try testing.expect(sparkline.max_value == null);
}

test "Sparkline calculate max value" {
    const testing = std.testing;

    const data = [_]f64{ 1.0, 5.0, 3.0, 8.0, 2.0 };
    var sparkline = Sparkline.init(testing.allocator, @constCast(&data));

    const max = sparkline.calculateMaxValue();
    try testing.expectEqual(@as(f64, 8.0), max);
}

test "Sparkline with explicit max value" {
    const testing = std.testing;

    const data = [_]f64{ 1.0, 2.0, 3.0 };
    var sparkline = Sparkline.init(testing.allocator, @constCast(&data));
    sparkline.setMaxValue(10.0);

    const max = sparkline.calculateMaxValue();
    try testing.expectEqual(@as(f64, 10.0), max);
}

test "Sparkline character mapping" {
    const testing = std.testing;

    const data = [_]f64{0.0};
    var sparkline = Sparkline.init(testing.allocator, @constCast(&data));

    // Test character levels
    try testing.expectEqual(@as(u21, ' '), sparkline.getSparkChar(0.0, 10.0));
    try testing.expectEqual(@as(u21, '▁'), sparkline.getSparkChar(1.0, 10.0));
    try testing.expectEqual(@as(u21, '▄'), sparkline.getSparkChar(5.0, 10.0));
    try testing.expectEqual(@as(u21, '█'), sparkline.getSparkChar(10.0, 10.0));
}

test "Sparkline from window" {
    const testing = std.testing;

    const full_data = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0 };
    const sparkline = try Sparkline.fromWindow(testing.allocator, &full_data, 3);
    defer testing.allocator.free(sparkline.data);

    // Should get last 3 values: [6.0, 7.0, 8.0]
    try testing.expectEqual(@as(usize, 3), sparkline.data.len);
    try testing.expectEqual(@as(f64, 6.0), sparkline.data[0]);
    try testing.expectEqual(@as(f64, 7.0), sparkline.data[1]);
    try testing.expectEqual(@as(f64, 8.0), sparkline.data[2]);
}

test "Sparkline empty data" {
    const testing = std.testing;

    var data = [_]f64{};
    var sparkline = Sparkline.init(testing.allocator, &data);

    const max = sparkline.calculateMaxValue();
    try testing.expectEqual(@as(f64, 1.0), max); // Default to 1.0 for empty data
}
