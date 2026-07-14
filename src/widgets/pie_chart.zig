//! PieChart Widget - Proportional slice visualization
//! Renders categorical values as an elliptical pie filled with per-slice colors,
//! with an optional legend showing labels and percentages.

const std = @import("std");
const phantom = @import("../root.zig");
const Rect = phantom.Rect;
const Position = phantom.Position;
const Color = phantom.Color;
const Style = phantom.Style;
const Buffer = phantom.Buffer;
const Cell = phantom.Cell;

pub const Slice = struct {
    label: []const u8,
    value: f64,
    color: Color,
};

/// Configuration for PieChart widget
pub const PieChartConfig = struct {
    title: ?[]const u8 = null,
    show_legend: bool = true,
    show_percentage: bool = true,
    /// Character used to fill the pie body.
    fill_char: u21 = '█',
    title_style: Style = Style.default().withBold(),
    legend_style: Style = Style.default(),

    pub fn default() PieChartConfig {
        return .{};
    }
};

pub const Error = std.mem.Allocator.Error;

/// PieChart widget for proportional slice visualization
pub const PieChart = struct {
    allocator: std.mem.Allocator,
    slices: std.ArrayList(Slice),
    title: ?[]const u8,
    show_legend: bool,
    show_percentage: bool,
    fill_char: u21,
    title_style: Style,
    legend_style: Style,

    /// Initialize PieChart with config
    pub fn init(allocator: std.mem.Allocator, config: PieChartConfig) PieChart {
        return PieChart{
            .allocator = allocator,
            .slices = .empty,
            .title = config.title,
            .show_legend = config.show_legend,
            .show_percentage = config.show_percentage,
            .fill_char = config.fill_char,
            .title_style = config.title_style,
            .legend_style = config.legend_style,
        };
    }

    pub fn deinit(self: *PieChart) void {
        self.slices.deinit(self.allocator);
    }

    /// Add a slice to the pie
    pub fn addSlice(self: *PieChart, label: []const u8, value: f64, color: Color) !void {
        try self.slices.append(self.allocator, Slice{
            .label = label,
            .value = if (value < 0.0) 0.0 else value, // Defensive: no negative slices
            .color = color,
        });
    }

    /// Sum of all slice values
    fn total(self: *const PieChart) f64 {
        var sum: f64 = 0.0;
        for (self.slices.items) |slice| sum += slice.value;
        return sum;
    }

    /// Render the PieChart
    pub fn render(self: *PieChart, buffer: *Buffer, area: Rect) void {
        if (self.slices.items.len == 0) return;
        if (area.width < 6 or area.height < 3) return;

        const sum = self.total();
        if (sum <= 0.0) return;

        var render_area = area;

        // Render title if present
        if (self.title) |title| {
            const title_x = area.x + @divTrunc(area.width, 2) -
                @divTrunc(@as(u16, @intCast(title.len)), 2);
            buffer.writeText(title_x, area.y, title, self.title_style);
            render_area.y += 1;
            render_area.height = if (render_area.height > 1) render_area.height - 1 else 0;
        }

        // Reserve legend space on the right.
        var pie_area = render_area;
        if (self.show_legend) {
            const legend_width: u16 = 20;
            if (render_area.width > legend_width + 6) {
                pie_area.width = render_area.width - legend_width;
                self.drawLegend(buffer, .{
                    .x = render_area.x + pie_area.width,
                    .y = render_area.y,
                    .width = legend_width,
                    .height = render_area.height,
                }, sum);
            }
        }

        self.drawPie(buffer, pie_area, sum);
    }

    /// Draw the elliptical pie body, coloring each cell by the slice its angle
    /// falls into.
    fn drawPie(self: *const PieChart, buffer: *Buffer, area: Rect, sum: f64) void {
        if (area.width == 0 or area.height == 0) return;

        const center_x = @as(f64, @floatFromInt(area.x)) + @as(f64, @floatFromInt(area.width - 1)) / 2.0;
        const center_y = @as(f64, @floatFromInt(area.y)) + @as(f64, @floatFromInt(area.height - 1)) / 2.0;
        const radius_x = @as(f64, @floatFromInt(area.width)) / 2.0;
        const radius_y = @as(f64, @floatFromInt(area.height)) / 2.0;
        if (radius_x == 0.0 or radius_y == 0.0) return;

        const two_pi = std.math.tau;

        var y: u16 = area.y;
        while (y < area.y + area.height) : (y += 1) {
            var x: u16 = area.x;
            while (x < area.x + area.width) : (x += 1) {
                const nx = (@as(f64, @floatFromInt(x)) - center_x) / radius_x;
                const ny = (@as(f64, @floatFromInt(y)) - center_y) / radius_y;

                // Outside the unit ellipse => not part of the pie.
                if (nx * nx + ny * ny > 1.0) continue;

                // Angle in [0, 2pi), measured clockwise from the top so slices
                // read like a clock face.
                var angle = std.math.atan2(nx, -ny);
                if (angle < 0.0) angle += two_pi;
                const fraction = angle / two_pi;

                const color = self.sliceColorAt(fraction, sum);
                buffer.setCell(x, y, Cell.init(self.fill_char, Style.default().withFg(color)));
            }
        }
    }

    /// Find which slice a normalized angle fraction (0..1) belongs to.
    fn sliceColorAt(self: *const PieChart, fraction: f64, sum: f64) Color {
        var cumulative: f64 = 0.0;
        for (self.slices.items) |slice| {
            cumulative += slice.value / sum;
            if (fraction <= cumulative) return slice.color;
        }
        // Floating-point slack at the seam: fall back to the last slice.
        return self.slices.items[self.slices.items.len - 1].color;
    }

    /// Draw the legend: a colored swatch, label, and optional percentage.
    fn drawLegend(self: *const PieChart, buffer: *Buffer, area: Rect, sum: f64) void {
        var row: u16 = 0;
        for (self.slices.items) |slice| {
            if (row >= area.height) break;
            const y = area.y + row;

            // Color swatch.
            buffer.setCell(area.x, y, Cell.init('█', Style.default().withFg(slice.color)));

            // Label + percentage.
            const percent = slice.value / sum * 100.0;
            const text = if (self.show_percentage)
                std.fmt.allocPrint(self.allocator, "{s} {d:.0}%", .{ slice.label, percent }) catch {
                    row += 1;
                    continue;
                }
            else
                std.fmt.allocPrint(self.allocator, "{s}", .{slice.label}) catch {
                    row += 1;
                    continue;
                };
            defer self.allocator.free(text);

            buffer.writeText(area.x + 2, y, text, self.legend_style);
            row += 1;
        }
    }
};

// Tests
test "PieChart init and addSlice" {
    const testing = std.testing;

    var pie = PieChart.init(testing.allocator, PieChartConfig.default());
    defer pie.deinit();

    try pie.addSlice("A", 30.0, Color.red);
    try pie.addSlice("B", 50.0, Color.green);
    try pie.addSlice("C", 20.0, Color.blue);

    try testing.expectEqual(@as(usize, 3), pie.slices.items.len);
    try testing.expectEqual(@as(f64, 100.0), pie.total());
}

test "PieChart rejects negative slice values" {
    const testing = std.testing;

    var pie = PieChart.init(testing.allocator, PieChartConfig.default());
    defer pie.deinit();

    try pie.addSlice("neg", -5.0, Color.red);
    try testing.expectEqual(@as(f64, 0.0), pie.slices.items[0].value);
}

test "PieChart renders colored cells" {
    const testing = std.testing;

    var pie = PieChart.init(testing.allocator, .{ .show_legend = false });
    defer pie.deinit();

    try pie.addSlice("A", 1.0, Color.red);
    try pie.addSlice("B", 1.0, Color.green);

    var buffer = try Buffer.init(testing.allocator, phantom.Size.init(20, 10));
    defer buffer.deinit();

    pie.render(&buffer, .{ .x = 0, .y = 0, .width = 20, .height = 10 });

    var filled: usize = 0;
    var y: u16 = 0;
    while (y < 10) : (y += 1) {
        var x: u16 = 0;
        while (x < 20) : (x += 1) {
            if (buffer.getCell(x, y)) |cell| {
                if (cell.char == '█') filled += 1;
            }
        }
    }
    try testing.expect(filled > 0);
}

test "PieChart empty renders nothing" {
    const testing = std.testing;

    var pie = PieChart.init(testing.allocator, PieChartConfig.default());
    defer pie.deinit();

    var buffer = try Buffer.init(testing.allocator, phantom.Size.init(20, 10));
    defer buffer.deinit();

    // Should not crash or draw with no slices.
    pie.render(&buffer, .{ .x = 0, .y = 0, .width = 20, .height = 10 });
}
