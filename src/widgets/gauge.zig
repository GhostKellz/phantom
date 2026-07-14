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
    /// Number of discrete cells for the `segmented` style.
    segments: u16,
    /// Optional highlighted target band for the `range` style.
    range_low: ?f64,
    range_high: ?f64,
    /// Percentage thresholds used when `threshold_coloring` is enabled.
    warning_threshold: f64,
    critical_threshold: f64,
    /// When true, the fill color is derived from warning/critical thresholds
    /// instead of the fixed `color`.
    threshold_coloring: bool,

    pub const GaugeStyle = enum {
        horizontal,
        vertical,
        circular,
        semi_circular,
        /// Vertical bulb-and-tube thermometer.
        thermometer,
        /// Discrete on/off segment bar (LED-style).
        segmented,
        /// Horizontal track with an optional target band and a value marker.
        range,
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
            .segments = 10,
            .range_low = null,
            .range_high = null,
            .warning_threshold = 80.0,
            .critical_threshold = 95.0,
            .threshold_coloring = false,
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

    /// Builder: number of segments for the segmented style.
    pub fn setSegments(self: *Gauge, count: u16) *Gauge {
        self.segments = @max(1, count);
        return self;
    }

    /// Builder: highlighted target band for the range style.
    pub fn setRange(self: *Gauge, low: f64, high: f64) *Gauge {
        self.range_low = @min(low, high);
        self.range_high = @max(low, high);
        return self;
    }

    /// Builder: warning/critical percentage thresholds (0..100).
    pub fn setThresholds(self: *Gauge, warning: f64, critical: f64) *Gauge {
        self.warning_threshold = warning;
        self.critical_threshold = critical;
        return self;
    }

    /// Builder: derive the fill color from the configured thresholds.
    pub fn setThresholdColoring(self: *Gauge, enabled: bool) *Gauge {
        self.threshold_coloring = enabled;
        return self;
    }

    /// Color implied by the current percentage against the thresholds.
    fn thresholdColor(self: *const Gauge) Color {
        const pct = self.getPercentage();
        if (pct >= self.critical_threshold) return Color.red;
        if (pct >= self.warning_threshold) return Color.yellow;
        return Color.green;
    }

    /// The color the fill should use, honoring threshold coloring when enabled.
    fn effectiveColor(self: *const Gauge) Color {
        return if (self.threshold_coloring) self.thresholdColor() else self.color;
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
            .thermometer => self.renderThermometer(buffer, area),
            .segmented => self.renderSegmented(buffer, area),
            .range => self.renderRange(buffer, area),
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
        const fill_style = Style.default().withFg(self.effectiveColor());
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
        const fill_style = Style.default().withFg(self.effectiveColor());
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

    /// Render vertical bulb-and-tube thermometer
    fn renderThermometer(self: *Gauge, buffer: *Buffer, area: Rect) void {
        if (area.height < 4 or area.width < 3) return;

        const fill_style = Style.default().withFg(self.effectiveColor());
        const bg_style = Style.default().withFg(self.bg_color);
        const center_x = area.x + @divTrunc(area.width, 2);

        // Label at top.
        const label_x = center_x - @divTrunc(@as(u16, @intCast(self.label.len)), 2);
        buffer.writeText(label_x, area.y, self.label, self.label_style);

        // Tube runs from just below the label down to the row above the bulb.
        const bulb_y = area.y + area.height - 1;
        const tube_top = area.y + 1;
        const tube_height = bulb_y - tube_top;
        if (tube_height == 0) return;

        const filled = @as(u16, @intFromFloat(@as(f64, @floatFromInt(tube_height)) * (self.value / self.max)));

        var row: u16 = 0;
        while (row < tube_height) : (row += 1) {
            const y = tube_top + row;
            const from_bottom = tube_height - row; // 1 (bottom) .. tube_height (top)
            const is_filled = from_bottom <= filled;
            const char: u21 = if (is_filled)
                (if (self.use_unicode) '█' else '#')
            else
                (if (self.use_unicode) '░' else '.');
            buffer.setCell(center_x, y, Cell.init(char, if (is_filled) fill_style else bg_style));
        }

        // Bulb is always shown in the fill color.
        const bulb_char: u21 = if (self.use_unicode) '●' else 'O';
        buffer.setCell(center_x, bulb_y, Cell.init(bulb_char, fill_style));

        // Percentage beside the bulb.
        if (self.show_percentage and area.width >= 6) {
            const pct = std.fmt.allocPrint(self.allocator, "{d:.0}%", .{self.getPercentage()}) catch return;
            defer self.allocator.free(pct);
            buffer.writeText(center_x + 2, bulb_y, pct, self.value_style);
        }
    }

    /// Render a discrete segmented (LED-style) bar
    fn renderSegmented(self: *Gauge, buffer: *Buffer, area: Rect) void {
        if (area.height < 2) return;

        const fill_style = Style.default().withFg(self.effectiveColor());
        const bg_style = Style.default().withFg(self.bg_color);

        buffer.writeText(area.x, area.y, self.label, self.label_style);
        const bar_y = area.y + 1;

        const seg_count = @max(1, self.segments);
        const filled_segments = @as(u16, @intFromFloat(@as(f64, @floatFromInt(seg_count)) * (self.value / self.max)));
        const seg_width = @max(1, @divTrunc(area.width, seg_count));

        var i: u16 = 0;
        while (i < seg_count) : (i += 1) {
            const seg_x = area.x + i * seg_width;
            if (seg_x >= area.x + area.width) break;

            const on = i < filled_segments;
            const st = if (on) fill_style else bg_style;
            const char: u21 = if (self.use_unicode)
                (if (on) '█' else '▁')
            else
                (if (on) '#' else '_');

            // Body of the segment; leave the trailing column as a gap when wide.
            const body = if (seg_width > 1) seg_width - 1 else 1;
            var c: u16 = 0;
            while (c < body and seg_x + c < area.x + area.width) : (c += 1) {
                buffer.setCell(seg_x + c, bar_y, Cell.init(char, st));
            }
        }

        if (self.show_percentage and area.height >= 3) {
            const pct = std.fmt.allocPrint(self.allocator, "{d:.0}%", .{self.getPercentage()}) catch return;
            defer self.allocator.free(pct);
            buffer.writeText(area.x, area.y + 2, pct, self.value_style);
        }
    }

    /// Render a horizontal track with an optional target band and value marker
    fn renderRange(self: *Gauge, buffer: *Buffer, area: Rect) void {
        if (area.height < 2 or area.width < 2) return;

        buffer.writeText(area.x, area.y, self.label, self.label_style);
        const bar_y = area.y + 1;
        const bar_width = area.width;
        const last = bar_width - 1;

        const bg_style = Style.default().withFg(self.bg_color);
        const band_style = Style.default().withFg(Color.blue);
        const marker_style = Style.default().withFg(self.effectiveColor());

        // Baseline track.
        var x: u16 = 0;
        while (x < bar_width) : (x += 1) {
            const char: u21 = if (self.use_unicode) '─' else '-';
            buffer.setCell(area.x + x, bar_y, Cell.init(char, bg_style));
        }

        // Highlighted target band, if configured.
        if (self.range_low != null and self.range_high != null) {
            const low_frac = @max(0.0, @min(1.0, self.range_low.? / self.max));
            const high_frac = @max(0.0, @min(1.0, self.range_high.? / self.max));
            const low_x = @as(u16, @intFromFloat(@as(f64, @floatFromInt(last)) * low_frac));
            const high_x = @as(u16, @intFromFloat(@as(f64, @floatFromInt(last)) * high_frac));
            var bx = low_x;
            while (bx <= high_x and bx < bar_width) : (bx += 1) {
                const char: u21 = if (self.use_unicode) '━' else '=';
                buffer.setCell(area.x + bx, bar_y, Cell.init(char, band_style));
            }
        }

        // Value marker.
        const val_frac = @max(0.0, @min(1.0, self.value / self.max));
        const marker_x = @as(u16, @intFromFloat(@as(f64, @floatFromInt(last)) * val_frac));
        const marker_char: u21 = if (self.use_unicode) '▼' else 'v';
        buffer.setCell(area.x + marker_x, bar_y, Cell.init(marker_char, marker_style));

        if (self.show_value and area.height >= 3) {
            const val_str = std.fmt.allocPrint(self.allocator, "{d:.1}/{d:.1}", .{ self.value, self.max }) catch return;
            defer self.allocator.free(val_str);
            buffer.writeText(area.x, area.y + 2, val_str, self.value_style);
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
    _ = gauge.setValue(75.0);

    try testing.expectEqual(@as(f64, 75.0), gauge.value);
    try testing.expectEqual(@as(f64, 75.0), gauge.getPercentage());
}

test "Gauge value clamping" {
    const testing = std.testing;

    var gauge = Gauge.init(testing.allocator, "Test");
    _ = gauge.setMax(50.0);
    _ = gauge.setValue(100.0); // Should clamp to 50.0

    try testing.expectEqual(@as(f64, 50.0), gauge.value);
    try testing.expectEqual(@as(f64, 100.0), gauge.getPercentage());
}

test "Gauge color by threshold" {
    const testing = std.testing;

    var gauge = Gauge.init(testing.allocator, "Disk");

    // Low usage - green
    _ = gauge.setValue(30.0);
    gauge.setColorByThreshold();
    try testing.expectEqual(Color.green, gauge.color);

    // Medium usage - yellow
    _ = gauge.setValue(60.0);
    gauge.setColorByThreshold();
    try testing.expectEqual(Color.yellow, gauge.color);

    // High usage - red
    _ = gauge.setValue(90.0);
    gauge.setColorByThreshold();
    try testing.expectEqual(Color.red, gauge.color);
}

test "Gauge percentage calculation" {
    const testing = std.testing;

    var gauge = Gauge.init(testing.allocator, "Test");
    _ = gauge.setMax(200.0);
    _ = gauge.setValue(50.0);

    try testing.expectEqual(@as(f64, 25.0), gauge.getPercentage());
}

test "Gauge threshold coloring" {
    const testing = std.testing;

    var gauge = Gauge.init(testing.allocator, "CPU");
    _ = gauge.setThresholdColoring(true).setThresholds(70.0, 90.0);

    _ = gauge.setValue(50.0);
    try testing.expectEqual(Color.green, gauge.effectiveColor());

    _ = gauge.setValue(75.0);
    try testing.expectEqual(Color.yellow, gauge.effectiveColor());

    _ = gauge.setValue(95.0);
    try testing.expectEqual(Color.red, gauge.effectiveColor());
}

test "Gauge effectiveColor honors fixed color when threshold coloring off" {
    const testing = std.testing;

    var gauge = Gauge.init(testing.allocator, "Mem");
    _ = gauge.setColor(Color.magenta).setValue(99.0);
    try testing.expectEqual(Color.magenta, gauge.effectiveColor());
}

test "Gauge thermometer renders without crashing" {
    const testing = std.testing;

    var gauge = Gauge.init(testing.allocator, "Temp");
    _ = gauge.setStyle(.thermometer).setValue(60.0);

    var buffer = try Buffer.init(testing.allocator, phantom.Size.init(12, 10));
    defer buffer.deinit();
    gauge.render(&buffer, .{ .x = 0, .y = 0, .width = 12, .height = 10 });

    // Some fill cell should exist in the tube/bulb column.
    var filled: usize = 0;
    var y: u16 = 0;
    while (y < 10) : (y += 1) {
        var x: u16 = 0;
        while (x < 12) : (x += 1) {
            if (buffer.getCell(x, y)) |cell| {
                if (cell.char == '█' or cell.char == '●') filled += 1;
            }
        }
    }
    try testing.expect(filled > 0);
}

test "Gauge segmented lights the right number of segments" {
    const testing = std.testing;

    var gauge = Gauge.init(testing.allocator, "Load");
    _ = gauge.setStyle(.segmented).setSegments(10).setValue(50.0);

    var buffer = try Buffer.init(testing.allocator, phantom.Size.init(20, 3));
    defer buffer.deinit();
    gauge.render(&buffer, .{ .x = 0, .y = 0, .width = 20, .height = 3 });

    // 50% of 10 segments == 5 lit segments; each lit segment draws a '█'.
    var lit: usize = 0;
    var x: u16 = 0;
    while (x < 20) : (x += 1) {
        if (buffer.getCell(x, 1)) |cell| {
            if (cell.char == '█') lit += 1;
        }
    }
    try testing.expectEqual(@as(usize, 5), lit);
}

test "Gauge range renders band and marker" {
    const testing = std.testing;

    var gauge = Gauge.init(testing.allocator, "Signal");
    _ = gauge.setStyle(.range).setRange(20.0, 40.0).setValue(80.0);

    var buffer = try Buffer.init(testing.allocator, phantom.Size.init(20, 3));
    defer buffer.deinit();
    gauge.render(&buffer, .{ .x = 0, .y = 0, .width = 20, .height = 3 });

    var band: usize = 0;
    var marker: usize = 0;
    var x: u16 = 0;
    while (x < 20) : (x += 1) {
        if (buffer.getCell(x, 1)) |cell| {
            if (cell.char == '━') band += 1;
            if (cell.char == '▼') marker += 1;
        }
    }
    try testing.expect(band > 0);
    try testing.expectEqual(@as(usize, 1), marker);
}
