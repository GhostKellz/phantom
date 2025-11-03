//! Gauge Widget - Visual progress/capacity indicators
//! Supports horizontal, vertical, circular, and semi-circular styles
//! Different from ProgressBar - focused on dashboard/metrics visualization

const std = @import("std");
const phantom = @import("../root.zig");
const Rect = phantom.Rect;
const Position = phantom.Position;
const Color = phantom.Color;
const Style = phantom.Style;
const Buffer = phantom.Buffer;
const Cell = phantom.Cell;

/// Gauge widget for visual metrics
pub const Gauge = struct {
    allocator: std.mem.Allocator,
    value: f64,
    max: f64,
    label: []const u8,
    style_type: GaugeStyle,
    use_unicode: bool,
    show_percentage: bool,
    show_value: bool,
    color: Color,
    bg_color: Color,
    label_style: Style,
    value_style: Style,

    pub const GaugeStyle = enum {
        horizontal,
        vertical,
        circular,
        semi_circular,
    };

    /// Initialize Gauge
    pub fn init(allocator: std.mem.Allocator, label: []const u8) Gauge {
        return Gauge{
            .allocator = allocator,
            .value = 0.0,
            .max = 100.0,
            .label = label,
            .style_type = .horizontal,
            .use_unicode = true,
            .show_percentage = true,
            .show_value = true,
            .color = Color.green,
            .bg_color = Color.bright_black,
            .label_style = Style.default(),
            .value_style = Style.default().withBold(),
        };
    }

    /// Set gauge value (builder pattern)
    pub fn setValue(self: *Gauge, value: f64) *Gauge {
        self.value = @max(0.0, @min(value, self.max));
        return self;
    }

    /// Set maximum value (builder pattern)
    pub fn setMax(self: *Gauge, max: f64) *Gauge {
        self.max = @max(1.0, max); // Defensive: minimum max of 1
        self.value = @min(self.value, self.max);
        return self;
    }

    /// Set gauge style (builder pattern)
    pub fn setStyle(self: *Gauge, style: GaugeStyle) *Gauge {
        self.style_type = style;
        return self;
    }

    /// Builder: Set color
    pub fn setColor(self: *Gauge, color: Color) *Gauge {
        self.color = color;
        return self;
    }

    /// Builder: Show/hide percentage
    pub fn setShowPercentage(self: *Gauge, show: bool) *Gauge {
        self.show_percentage = show;
        return self;
    }

    /// Builder: Show/hide value
    pub fn setShowValue(self: *Gauge, show: bool) *Gauge {
        self.show_value = show;
        return self;
    }

    /// Set color based on value thresholds
    pub fn setColorByThreshold(self: *Gauge) void {
        const percentage = (self.value / self.max) * 100.0;

        if (percentage < 50.0) {
            self.color = Color.green;
        } else if (percentage < 80.0) {
            self.color = Color.yellow;
        } else {
            self.color = Color.red;
        }
    }

    /// Get percentage
    pub fn getPercentage(self: *const Gauge) f64 {
        if (self.max == 0.0) return 0.0;
        return (self.value / self.max) * 100.0;
    }

    /// Render the Gauge
    pub fn render(self: *Gauge, buffer: *Buffer, area: Rect) void {
        // Defensive: Early exit for invalid conditions
        if (area.width == 0 or area.height == 0) return;

        switch (self.style_type) {
            .horizontal => self.renderHorizontal(buffer, area),
            .vertical => self.renderVertical(buffer, area),
            .circular => self.renderCircular(buffer, area),
            .semi_circular => self.renderSemiCircular(buffer, area),
        }
    }

    /// Render horizontal gauge
    fn renderHorizontal(self: *Gauge, buffer: *Buffer, area: Rect) void {
        if (area.height < 3) return;

        // Render label
        buffer.writeText(area.x, area.y, self.label, self.label_style);

        // Calculate gauge bar dimensions
        const bar_y = area.y + 1;
        const bar_width = area.width;
        const filled_width = @as(u16, @intFromFloat(@as(f64, @floatFromInt(bar_width)) * (self.value / self.max)));

        // Render filled portion
        const fill_style = Style.default().withFg(self.color);
        var x: u16 = 0;
        while (x < filled_width) : (x += 1) {
            const char: u21 = if (self.use_unicode) '█' else '#';
            buffer.setCell(area.x + x, bar_y, Cell.init(char, fill_style));
        }

        // Render empty portion
        const bg_style = Style.default().withFg(self.bg_color);
        while (x < bar_width) : (x += 1) {
            const char: u21 = if (self.use_unicode) '░' else '.';
            buffer.setCell(area.x + x, bar_y, Cell.init(char, bg_style));
        }

        // Render value/percentage
        if (area.height >= 3) {
            const value_y = area.y + 2;

            if (self.show_percentage) {
                const pct_str = std.fmt.allocPrint(self.allocator, "{d:.1}%", .{self.getPercentage()}) catch return;
                defer self.allocator.free(pct_str);
                buffer.writeText(area.x, value_y, pct_str, self.value_style);
            }

            if (self.show_value) {
                const val_str = std.fmt.allocPrint(self.allocator, "{d:.1}/{d:.1}", .{ self.value, self.max }) catch return;
                defer self.allocator.free(val_str);
                const val_x = area.x + area.width - @as(u16, @intCast(val_str.len));
                buffer.writeText(val_x, value_y, val_str, self.value_style);
            }
        }
    }

    /// Render vertical gauge
    fn renderVertical(self: *Gauge, buffer: *Buffer, area: Rect) void {
        if (area.width < 5) return;

        // Render label at top
        buffer.writeText(area.x, area.y, self.label, self.label_style);

        // Calculate gauge bar dimensions
        const bar_x = area.x + 1;
        const bar_height = if (area.height > 1) area.height - 1 else 0;
        const filled_height = @as(u16, @intFromFloat(@as(f64, @floatFromInt(bar_height)) * (self.value / self.max)));

        // Render from bottom up
        const bar_start_y = area.y + 1;

        // Render empty portion (top)
        const bg_style = Style.default().withFg(self.bg_color);
        var y: u16 = 0;
        while (y < bar_height - filled_height) : (y += 1) {
            const char: u21 = if (self.use_unicode) '░' else '.';
            buffer.setCell(bar_x, bar_start_y + y, Cell.init(char, bg_style));
        }

        // Render filled portion (bottom)
        const fill_style = Style.default().withFg(self.color);
        while (y < bar_height) : (y += 1) {
            const char: u21 = if (self.use_unicode) '█' else '#';
            buffer.setCell(bar_x, bar_start_y + y, Cell.init(char, fill_style));
        }

        // Render percentage on the right
        if (self.show_percentage and area.width >= 8) {
            const pct_str = std.fmt.allocPrint(self.allocator, "{d:.0}%", .{self.getPercentage()}) catch return;
            defer self.allocator.free(pct_str);
            const pct_y = area.y + @divTrunc(bar_height, 2);
            buffer.writeText(bar_x + 2, pct_y, pct_str, self.value_style);
        }
    }

    /// Render circular gauge (full circle)
    fn renderCircular(self: *Gauge, buffer: *Buffer, area: Rect) void {
        const center_x = area.x + @divTrunc(area.width, 2);
        const center_y = area.y + @divTrunc(area.height, 2);

        // Render label at center
        const label_x = center_x - @divTrunc(@as(u16, @intCast(self.label.len)), 2);
        buffer.writeText(label_x, center_y, self.label, self.label_style);

        // Render percentage below label
        if (self.show_percentage and area.height >= 3) {
            const pct_str = std.fmt.allocPrint(self.allocator, "{d:.1}%", .{self.getPercentage()}) catch return;
            defer self.allocator.free(pct_str);
            const pct_x = center_x - @divTrunc(@as(u16, @intCast(pct_str.len)), 2);
            buffer.writeText(pct_x, center_y + 1, pct_str, self.value_style);
        }

        // Render circle using Unicode characters
        if (!self.use_unicode) return;

        const percentage = self.getPercentage();
        const circle_char = self.getCircleChar(percentage);
        const style = Style.default().withFg(self.color);

        // Draw circle indicator at top
        buffer.setCell(center_x, area.y, Cell.init(circle_char, style));
    }

    /// Render semi-circular gauge (half circle)
    fn renderSemiCircular(self: *Gauge, buffer: *Buffer, area: Rect) void {
        const center_x = area.x + @divTrunc(area.width, 2);
        const bottom_y = area.y + area.height - 1;

        // Render label at center
        const label_x = center_x - @divTrunc(@as(u16, @intCast(self.label.len)), 2);
        buffer.writeText(label_x, bottom_y - 2, self.label, self.label_style);

        // Render percentage
        if (self.show_percentage) {
            const pct_str = std.fmt.allocPrint(self.allocator, "{d:.1}%", .{self.getPercentage()}) catch return;
            defer self.allocator.free(pct_str);
            const pct_x = center_x - @divTrunc(@as(u16, @intCast(pct_str.len)), 2);
            buffer.writeText(pct_x, bottom_y - 1, pct_str, self.value_style);
        }

        // Render arc using Unicode characters
        if (!self.use_unicode) return;

        const percentage = self.getPercentage();
        const segments = 7; // Number of segments in semi-circle

        const filled_segments = @as(u16, @intFromFloat(@as(f64, @floatFromInt(segments)) * (percentage / 100.0)));

        // Draw arc from left to right
        const arc_chars = [_]u21{ '╰', '─', '─', '┬', '─', '─', '╯' };
        const style = Style.default().withFg(self.color);
        const bg_style = Style.default().withFg(self.bg_color);

        for (0..segments) |i| {
            const char_x = center_x - 3 + @as(u16, @intCast(i));
            const char_style = if (i < filled_segments) style else bg_style;
            buffer.setCell(char_x, bottom_y, Cell.init(arc_chars[i], char_style));
        }
    }

    /// Get circle character based on percentage (for circular gauge)
    fn getCircleChar(self: *const Gauge, percentage: f64) u21 {
        _ = self;

        // Unicode circle filling characters
        if (percentage < 12.5) return '○'; // Empty
        if (percentage < 25.0) return '◔'; // 1/4
        if (percentage < 37.5) return '◑'; // 1/3
        if (percentage < 50.0) return '◕'; // 1/2
        if (percentage < 75.0) return '◕'; // 3/4
        return '●'; // Full
    }
};

// Tests
test "Gauge initialization" {
    const testing = std.testing;

    const gauge = Gauge.init(testing.allocator, "CPU");

    try testing.expectEqual(@as(f64, 0.0), gauge.value);
    try testing.expectEqual(@as(f64, 100.0), gauge.max);
    try testing.expectEqualStrings("CPU", gauge.label);
    try testing.expect(gauge.show_percentage);
}

test "Gauge set value" {
    const testing = std.testing;

    var gauge = Gauge.init(testing.allocator, "Memory");
    gauge.setValue(75.0);

    try testing.expectEqual(@as(f64, 75.0), gauge.value);
    try testing.expectEqual(@as(f64, 75.0), gauge.getPercentage());
}

test "Gauge value clamping" {
    const testing = std.testing;

    var gauge = Gauge.init(testing.allocator, "Test");
    gauge.setMax(50.0);
    gauge.setValue(100.0); // Should clamp to 50.0

    try testing.expectEqual(@as(f64, 50.0), gauge.value);
    try testing.expectEqual(@as(f64, 100.0), gauge.getPercentage());
}

test "Gauge color by threshold" {
    const testing = std.testing;

    var gauge = Gauge.init(testing.allocator, "Disk");

    // Low usage - green
    gauge.setValue(30.0);
    gauge.setColorByThreshold();
    try testing.expectEqual(Color.green, gauge.color);

    // Medium usage - yellow
    gauge.setValue(60.0);
    gauge.setColorByThreshold();
    try testing.expectEqual(Color.yellow, gauge.color);

    // High usage - red
    gauge.setValue(90.0);
    gauge.setColorByThreshold();
    try testing.expectEqual(Color.red, gauge.color);
}

test "Gauge percentage calculation" {
    const testing = std.testing;

    var gauge = Gauge.init(testing.allocator, "Test");
    gauge.setMax(200.0);
    gauge.setValue(50.0);

    try testing.expectEqual(@as(f64, 25.0), gauge.getPercentage());
}
