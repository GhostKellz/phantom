//! Chart Widget - Line and scatter plots for data visualization
//! Supports multiple datasets, axes, legends, and grid lines
//! Uses Bresenham algorithm for line drawing

const std = @import("std");
const ArrayList = std.array_list.Managed;
const phantom = @import("../root.zig");
const Rect = phantom.Rect;
const Position = phantom.Position;
const Color = phantom.Color;
const Style = phantom.Style;
const Buffer = phantom.Buffer;
const Cell = phantom.Cell;

pub const ChartType = enum {
    line,
    scatter,
    both,
};

const ChartPoint = struct {
    x: f64,
    y: f64,
};
pub const Point = ChartPoint;

const ChartDataset = struct {
    label: []const u8,
    points: []Point,
    color: Color,
    marker: u21, // Unicode character for scatter points
};
pub const Dataset = ChartDataset;

pub const Axis = struct {
    label: []const u8,
    min: f64,
    max: f64,
    auto_scale: bool,

    pub fn init(label: []const u8) Axis {
        return Axis{
            .label = label,
            .min = 0.0,
            .max = 1.0,
            .auto_scale = true,
        };
    }
};

/// Configuration for Chart widget
pub const ChartConfig = struct {
    x_axis_label: []const u8 = "X",
    y_axis_label: []const u8 = "Y",
    chart_type: ChartType = .line,
    show_legend: bool = true,
    show_grid: bool = true,
    title: ?[]const u8 = null,
    title_style: Style = Style.default().withBold(),
    axis_style: Style = Style.default(),
    grid_style: Style = Style.default().withFg(Color.bright_black),

    pub fn default() ChartConfig {
        return .{};
    }
};

/// Custom error types for Chart
pub const Error = error{
    NoDatasets,
    InvalidAxisRange,
    InvalidDataPoint,
} || std.mem.Allocator.Error;

/// Chart widget for line and scatter plots
pub const Chart = struct {
    pub const Point = ChartPoint;
    pub const Dataset = ChartDataset;
    allocator: std.mem.Allocator,
    datasets: ArrayList(ChartDataset),
    x_axis: Axis,
    y_axis: Axis,
    chart_type: ChartType,
    show_legend: bool,
    show_grid: bool,
    title: ?[]const u8,
    title_style: Style,
    axis_style: Style,
    grid_style: Style,

    /// Initialize Chart with config
    pub fn init(allocator: std.mem.Allocator, config: ChartConfig) Error!Chart {
        return Chart{
            .allocator = allocator,
            .datasets = ArrayList(ChartDataset).init(allocator),
            .x_axis = Axis.init(config.x_axis_label),
            .y_axis = Axis.init(config.y_axis_label),
            .chart_type = config.chart_type,
            .show_legend = config.show_legend,
            .show_grid = config.show_grid,
            .title = config.title,
            .title_style = config.title_style,
            .axis_style = config.axis_style,
            .grid_style = config.grid_style,
        };
    }

    /// Builder pattern for complex chart construction
    pub const Builder = struct {
        allocator: std.mem.Allocator,
        config: ChartConfig,
        datasets_list: ArrayList(ChartDataset),

        pub fn init(allocator: std.mem.Allocator) Builder {
            return .{
                .allocator = allocator,
                .config = ChartConfig.default(),
                .datasets_list = ArrayList(ChartDataset).init(allocator),
            };
        }

        pub fn setTitle(self: *Builder, title: []const u8) *Builder {
            self.config.title = title;
            return self;
        }

        pub fn setXAxisLabel(self: *Builder, label: []const u8) *Builder {
            self.config.x_axis_label = label;
            return self;
        }

        pub fn setYAxisLabel(self: *Builder, label: []const u8) *Builder {
            self.config.y_axis_label = label;
            return self;
        }

        pub fn setChartType(self: *Builder, chart_type: ChartType) *Builder {
            self.config.chart_type = chart_type;
            return self;
        }

        pub fn setShowLegend(self: *Builder, show: bool) *Builder {
            self.config.show_legend = show;
            return self;
        }

        pub fn setShowGrid(self: *Builder, show: bool) *Builder {
            self.config.show_grid = show;
            return self;
        }

        pub fn addDataset(self: *Builder, label: []const u8, points: []ChartPoint, color: Color, marker: u21) Error!*Builder {
            try self.datasets_list.append(ChartDataset{
                .label = label,
                .points = points,
                .color = color,
                .marker = marker,
            });
            return self;
        }

        pub fn build(self: *Builder) Error!Chart {
            var chart = try Chart.init(self.allocator, self.config);

            // Transfer datasets
            chart.datasets = self.datasets_list;
            self.datasets_list = ArrayList(ChartDataset).init(self.allocator); // Reset builder list

            // Auto-scale axes if needed
            if (chart.x_axis.auto_scale or chart.y_axis.auto_scale) {
                chart.calculateAxisBounds();
            }

            return chart;
        }

        pub fn deinit(self: *Builder) void {
            self.datasets_list.deinit();
        }
    };

    /// Create a builder for fluent API
    pub fn builder(allocator: std.mem.Allocator) Builder {
        return Builder.init(allocator);
    }

    pub fn deinit(self: *Chart) void {
        self.datasets.deinit();
    }

    /// Add a dataset to the chart
    pub fn addDataset(self: *Chart, label: []const u8, points: []ChartPoint, color: Color, marker: u21) !void {
        try self.datasets.append(ChartDataset{
            .label = label,
            .points = points,
            .color = color,
            .marker = marker,
        });

        // Auto-scale axes if enabled
        if (self.x_axis.auto_scale or self.y_axis.auto_scale) {
            self.calculateAxisBounds();
        }
    }

    /// Set X axis properties (builder pattern)
    pub fn setXAxis(self: *Chart, label: []const u8, min: f64, max: f64) *Chart {
        self.x_axis.label = label;
        self.x_axis.min = @min(min, max); // Defensive: ensure min <= max
        self.x_axis.max = @max(min, max);
        self.x_axis.auto_scale = false;
        return self;
    }

    /// Set Y axis properties (builder pattern)
    pub fn setYAxis(self: *Chart, label: []const u8, min: f64, max: f64) *Chart {
        self.y_axis.label = label;
        self.y_axis.min = @min(min, max); // Defensive: ensure min <= max
        self.y_axis.max = @max(min, max);
        self.y_axis.auto_scale = false;
        return self;
    }

    /// Set chart type (builder pattern)
    pub fn setChartType(self: *Chart, chart_type: ChartType) *Chart {
        self.chart_type = chart_type;
        return self;
    }

    /// Set title (builder pattern)
    pub fn setTitle(self: *Chart, title: []const u8) *Chart {
        self.title = title;
        return self;
    }

    /// Builder: Show/hide legend
    pub fn setShowLegend(self: *Chart, show: bool) *Chart {
        self.show_legend = show;
        return self;
    }

    /// Builder: Show/hide grid
    pub fn setShowGrid(self: *Chart, show: bool) *Chart {
        self.show_grid = show;
        return self;
    }

    /// Calculate axis bounds from data
    fn calculateAxisBounds(self: *Chart) void {
        if (self.datasets.items.len == 0) return;

        var x_min: f64 = std.math.floatMax(f64);
        var x_max: f64 = std.math.floatMin(f64);
        var y_min: f64 = std.math.floatMax(f64);
        var y_max: f64 = std.math.floatMin(f64);

        for (self.datasets.items) |dataset| {
            for (dataset.points) |point| {
                if (point.x < x_min) x_min = point.x;
                if (point.x > x_max) x_max = point.x;
                if (point.y < y_min) y_min = point.y;
                if (point.y > y_max) y_max = point.y;
            }
        }

        if (self.x_axis.auto_scale) {
            self.x_axis.min = x_min;
            self.x_axis.max = x_max;
        }

        if (self.y_axis.auto_scale) {
            self.y_axis.min = y_min;
            self.y_axis.max = y_max;
        }
    }

    /// Render the Chart
    pub fn render(self: *Chart, buffer: *Buffer, area: Rect) void {
        // Defensive: Early exit for invalid conditions
        if (self.datasets.items.len == 0) return;
        if (area.width < 15 or area.height < 8) return; // Need minimum space for axes

        var render_area = area;

        // Render title if present
        if (self.title) |title| {
            const title_pos = Position{
                .x = area.x + @divTrunc(area.width, 2) - @divTrunc(@as(u16, @intCast(title.len)), 2),
                .y = area.y,
            };
            buffer.writeText(title_pos.x, title_pos.y, title, self.title_style);
            render_area.y += 1;
            render_area.height = if (render_area.height > 1) render_area.height - 1 else 0;
        }

        // Reserve space for axes
        const y_axis_width: u16 = 8; // Space for Y axis labels
        const x_axis_height: u16 = 2; // Space for X axis

        if (render_area.width <= y_axis_width or render_area.height <= x_axis_height) return;

        const chart_area = Rect{
            .x = render_area.x + y_axis_width,
            .y = render_area.y,
            .width = render_area.width - y_axis_width,
            .height = render_area.height - x_axis_height,
        };

        // Draw axes
        self.drawAxes(buffer, render_area, chart_area);

        // Draw grid if enabled
        if (self.show_grid) {
            self.drawGrid(buffer, chart_area);
        }

        // Draw datasets
        for (self.datasets.items) |dataset| {
            self.drawDataset(buffer, chart_area, dataset);
        }

        // Draw legend if enabled
        if (self.show_legend) {
            self.drawLegend(buffer, area);
        }
    }

    /// Draw X and Y axes
    fn drawAxes(self: *Chart, buffer: *Buffer, area: Rect, chart_area: Rect) void {
        // Y axis line
        var y: u16 = chart_area.y;
        while (y < chart_area.y + chart_area.height) : (y += 1) {
            buffer.setCell(chart_area.x - 1, y, Cell.init('│', self.axis_style));
        }

        // X axis line
        var x: u16 = chart_area.x;
        while (x < chart_area.x + chart_area.width) : (x += 1) {
            buffer.setCell(x, chart_area.y + chart_area.height, Cell.init('─', self.axis_style));
        }

        // Corner
        buffer.setCell(chart_area.x - 1, chart_area.y + chart_area.height, Cell.init('└', self.axis_style));

        // Y axis label and bounds
        const y_label_x = area.x;
        const y_label_y = chart_area.y + @divTrunc(chart_area.height, 2);
        buffer.writeText(y_label_x, y_label_y, self.y_axis.label, self.axis_style);

        // Y min/max
        const y_max_str = std.fmt.allocPrint(self.allocator, "{d:.1}", .{self.y_axis.max}) catch return;
        defer self.allocator.free(y_max_str);
        buffer.writeText(area.x, chart_area.y, y_max_str, self.axis_style);

        const y_min_str = std.fmt.allocPrint(self.allocator, "{d:.1}", .{self.y_axis.min}) catch return;
        defer self.allocator.free(y_min_str);
        buffer.writeText(area.x, chart_area.y + chart_area.height - 1, y_min_str, self.axis_style);

        // X axis label and bounds
        const x_label_x = chart_area.x + @divTrunc(chart_area.width, 2) - @divTrunc(@as(u16, @intCast(self.x_axis.label.len)), 2);
        const x_label_y = chart_area.y + chart_area.height + 1;
        buffer.writeText(x_label_x, x_label_y, self.x_axis.label, self.axis_style);

        // X min/max
        const x_min_str = std.fmt.allocPrint(self.allocator, "{d:.1}", .{self.x_axis.min}) catch return;
        defer self.allocator.free(x_min_str);
        buffer.writeText(chart_area.x, x_label_y, x_min_str, self.axis_style);

        const x_max_str = std.fmt.allocPrint(self.allocator, "{d:.1}", .{self.x_axis.max}) catch return;
        defer self.allocator.free(x_max_str);
        const x_max_x = chart_area.x + chart_area.width - @as(u16, @intCast(x_max_str.len));
        buffer.writeText(x_max_x, x_label_y, x_max_str, self.axis_style);
    }

    /// Draw grid lines
    fn drawGrid(self: *Chart, buffer: *Buffer, area: Rect) void {
        // Vertical grid lines (every 1/4 of width)
        const grid_spacing_x = @divTrunc(area.width, 4);
        if (grid_spacing_x > 0) {
            var i: u16 = 1;
            while (i < 4) : (i += 1) {
                const x = area.x + i * grid_spacing_x;
                var y = area.y;
                while (y < area.y + area.height) : (y += 1) {
                    buffer.setCell(x, y, Cell.init('┆', self.grid_style));
                }
            }
        }

        // Horizontal grid lines (every 1/4 of height)
        const grid_spacing_y = @divTrunc(area.height, 4);
        if (grid_spacing_y > 0) {
            var i: u16 = 1;
            while (i < 4) : (i += 1) {
                const y = area.y + i * grid_spacing_y;
                var x = area.x;
                while (x < area.x + area.width) : (x += 1) {
                    buffer.setCell(x, y, Cell.init('┄', self.grid_style));
                }
            }
        }
    }

    /// Draw a dataset (line or scatter or both)
    fn drawDataset(self: *Chart, buffer: *Buffer, area: Rect, dataset: ChartDataset) void {
        if (dataset.points.len == 0) return;

        const style = Style.default().withFg(dataset.color);

        // Convert data points to screen coordinates
        var screen_points = ArrayList(struct { x: u16, y: u16 }).init(self.allocator);
        defer screen_points.deinit();

        for (dataset.points) |point| {
            const screen_x = self.mapToScreenX(point.x, area);
            const screen_y = self.mapToScreenY(point.y, area);
            screen_points.append(.{ .x = screen_x, .y = screen_y }) catch continue;
        }

        // Draw scatter points
        if (self.chart_type == .scatter or self.chart_type == .both) {
            for (screen_points.items) |sp| {
                buffer.setCell(sp.x, sp.y, Cell.init(dataset.marker, style));
            }
        }

        // Draw lines connecting points
        if (self.chart_type == .line or self.chart_type == .both) {
            for (0..screen_points.items.len - 1) |i| {
                const p1 = screen_points.items[i];
                const p2 = screen_points.items[i + 1];
                self.drawLine(buffer, p1.x, p1.y, p2.x, p2.y, style);
            }
        }
    }

    /// Map data X coordinate to screen X coordinate
    fn mapToScreenX(self: *const Chart, data_x: f64, area: Rect) u16 {
        const range = self.x_axis.max - self.x_axis.min;
        if (range == 0.0) return area.x;

        const normalized = (data_x - self.x_axis.min) / range;
        const screen_x = area.x + @as(u16, @intFromFloat(normalized * @as(f64, @floatFromInt(area.width - 1))));
        return @min(screen_x, area.x + area.width - 1);
    }

    /// Map data Y coordinate to screen Y coordinate (inverted)
    fn mapToScreenY(self: *const Chart, data_y: f64, area: Rect) u16 {
        const range = self.y_axis.max - self.y_axis.min;
        if (range == 0.0) return area.y;

        const normalized = (data_y - self.y_axis.min) / range;
        // Invert Y axis (screen Y grows downward)
        const screen_y = area.y + area.height - 1 - @as(u16, @intFromFloat(normalized * @as(f64, @floatFromInt(area.height - 1))));
        return @max(area.y, @min(screen_y, area.y + area.height - 1));
    }

    /// Draw a line using Bresenham's algorithm
    fn drawLine(self: *Chart, buffer: *Buffer, x0: u16, y0: u16, x1: u16, y1: u16, style: Style) void {
        _ = self;

        var x: i32 = @intCast(x0);
        var y: i32 = @intCast(y0);
        const x_end: i32 = @intCast(x1);
        const y_end: i32 = @intCast(y1);

        const dx: i32 = @intCast(@abs(x_end - x));
        const dy: i32 = @intCast(@abs(y_end - y));
        const sx: i32 = if (x < x_end) 1 else -1;
        const sy: i32 = if (y < y_end) 1 else -1;
        var err: i32 = dx - dy;

        while (true) {
            buffer.setCell(@intCast(x), @intCast(y), Cell.init('·', style));

            if (x == x_end and y == y_end) break;

            const e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x += sx;
            }
            if (e2 < dx) {
                err += dx;
                y += sy;
            }
        }
    }

    /// Draw legend
    fn drawLegend(self: *Chart, buffer: *Buffer, area: Rect) void {
        const legend_x = area.x + area.width - 20;
        var legend_y = area.y + 2;

        for (self.datasets.items) |dataset| {
            const style = Style.default().withFg(dataset.color);

            // Marker
            buffer.setCell(legend_x, legend_y, Cell.init(dataset.marker, style));

            // Label
            const label_x = legend_x + 2;
            buffer.writeText(label_x, legend_y, dataset.label, Style.default());

            legend_y += 1;
        }
    }
};

// Tests
test "Chart initialization with config" {
    const testing = std.testing;

    var chart = try Chart.init(testing.allocator, ChartConfig.default());
    defer chart.deinit();

    try testing.expectEqual(ChartType.line, chart.chart_type);
    try testing.expect(chart.show_legend);
    try testing.expect(chart.show_grid);
}

test "Chart builder pattern" {
    const testing = std.testing;

    const points = [_]Point{
        .{ .x = 0.0, .y = 0.0 },
        .{ .x = 1.0, .y = 10.0 },
        .{ .x = 2.0, .y = 5.0 },
    };

    var builder = Chart.builder(testing.allocator);
    defer builder.deinit();

    _ = builder.setTitle("Test Chart")
        .setXAxisLabel("Time")
        .setYAxisLabel("Value")
        .setChartType(.both)
        .setShowLegend(true);

    _ = try builder.addDataset("Series 1", &points, Color.red, '●');

    var chart = try builder.build();
    defer chart.deinit();

    try testing.expectEqual(@as(usize, 1), chart.datasets.items.len);
    try testing.expectEqual(ChartType.both, chart.chart_type);
    try testing.expectEqualStrings("Test Chart", chart.title.?);
}

test "Chart add dataset with auto-scale" {
    const testing = std.testing;

    var chart = try Chart.init(testing.allocator, ChartConfig.default());
    defer chart.deinit();

    const points = [_]Point{
        .{ .x = 0.0, .y = 0.0 },
        .{ .x = 1.0, .y = 10.0 },
        .{ .x = 2.0, .y = 5.0 },
    };

    try chart.addDataset("Test", &points, Color.red, '●');

    try testing.expectEqual(@as(usize, 1), chart.datasets.items.len);
    try testing.expect(chart.x_axis.min <= 0.0);
    try testing.expect(chart.x_axis.max >= 2.0);
    try testing.expect(chart.y_axis.min <= 0.0);
    try testing.expect(chart.y_axis.max >= 10.0);
}

test "Chart coordinate mapping" {
    const testing = std.testing;

    var chart = try Chart.init(testing.allocator, ChartConfig.default());
    defer chart.deinit();

    _ = chart.setXAxis("X", 0.0, 10.0);
    _ = chart.setYAxis("Y", 0.0, 100.0);

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    // Map middle values
    const screen_x = chart.mapToScreenX(5.0, area);
    const screen_y = chart.mapToScreenY(50.0, area);

    try testing.expect(screen_x >= 45 and screen_x <= 55); // Should be near middle
    try testing.expect(screen_y >= 20 and screen_y <= 30); // Should be near middle
}
