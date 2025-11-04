//! BarChart Widget - Data visualization with vertical/horizontal bars
//! Supports multiple datasets with grouping, value labels, and auto-scaling

const std = @import("std");
const phantom = @import("../root.zig");
const Rect = phantom.Rect;
const Position = phantom.Position;
const Color = phantom.Color;
const Style = phantom.Style;
const Buffer = phantom.Buffer;
const Cell = phantom.Cell;

pub const Orientation = enum {
    vertical,
    horizontal,
};

pub const Dataset = struct {
    label: []const u8,
    values: []f64,
    color: Color,
};

/// Configuration for BarChart widget
pub const BarChartConfig = struct {
    orientation: Orientation = .vertical,
    bar_width: usize = 3,
    bar_gap: usize = 1,
    group_gap: usize = 2,
    show_values: bool = true,
    show_labels: bool = true,
    max_value: ?f64 = null,
    title: ?[]const u8 = null,
    title_style: Style = Style.default().withBold(),
    label_style: Style = Style.default(),
    value_style: Style = Style.default(),

    pub fn default() BarChartConfig {
        return .{};
    }
};

/// Custom error types for BarChart
pub const Error = error{
    NoDatasets,
    InvalidBarWidth,
    InvalidMaxValue,
    DatasetSizeMismatch,
} || std.mem.Allocator.Error;

/// BarChart widget for data visualization
pub const BarChart = struct {
    allocator: std.mem.Allocator,
    datasets: std.ArrayList(Dataset),
    orientation: Orientation,
    bar_width: usize,
    bar_gap: usize,
    group_gap: usize,
    show_values: bool,
    show_labels: bool,
    max_value: ?f64,
    title: ?[]const u8,
    title_style: Style,
    label_style: Style,
    value_style: Style,

    /// Initialize BarChart with config
    pub fn init(allocator: std.mem.Allocator, config: BarChartConfig) Error!BarChart {
        if (config.bar_width == 0) return Error.InvalidBarWidth;
        if (config.max_value) |max| {
            if (max <= 0.0) return Error.InvalidMaxValue;
        }

        return BarChart{
            .allocator = allocator,
            .datasets = .{},
            .orientation = config.orientation,
            .bar_width = config.bar_width,
            .bar_gap = config.bar_gap,
            .group_gap = config.group_gap,
            .show_values = config.show_values,
            .show_labels = config.show_labels,
            .max_value = config.max_value,
            .title = config.title,
            .title_style = config.title_style,
            .label_style = config.label_style,
            .value_style = config.value_style,
        };
    }

    /// Builder pattern for complex bar chart construction
    pub const Builder = struct {
        allocator: std.mem.Allocator,
        config: BarChartConfig,
        datasets_list: std.ArrayList(Dataset),

        pub fn init(allocator: std.mem.Allocator) Builder {
            return .{
                .allocator = allocator,
                .config = BarChartConfig.default(),
                .datasets_list = .{},
            };
        }

        pub fn setTitle(self: *Builder, title: []const u8) *Builder {
            self.config.title = title;
            return self;
        }

        pub fn setOrientation(self: *Builder, orientation: Orientation) *Builder {
            self.config.orientation = orientation;
            return self;
        }

        pub fn setBarWidth(self: *Builder, width: usize) *Builder {
            self.config.bar_width = @max(1, width);
            return self;
        }

        pub fn setBarGap(self: *Builder, gap: usize) *Builder {
            self.config.bar_gap = gap;
            return self;
        }

        pub fn setGroupGap(self: *Builder, gap: usize) *Builder {
            self.config.group_gap = gap;
            return self;
        }

        pub fn setShowValues(self: *Builder, show: bool) *Builder {
            self.config.show_values = show;
            return self;
        }

        pub fn setShowLabels(self: *Builder, show: bool) *Builder {
            self.config.show_labels = show;
            return self;
        }

        pub fn setMaxValue(self: *Builder, max: ?f64) *Builder {
            self.config.max_value = max;
            return self;
        }

        pub fn addDataset(self: *Builder, label: []const u8, values: []f64, color: Color) Error!*Builder {
            try self.datasets_list.append(self.allocator, Dataset{
                .label = label,
                .values = values,
                .color = color,
            });
            return self;
        }

        pub fn build(self: *Builder) Error!BarChart {
            var chart = try BarChart.init(self.allocator, self.config);
            chart.datasets = self.datasets_list;
            self.datasets_list = .{}; // Clear to avoid double-free
            return chart;
        }

        pub fn deinit(self: *Builder) void {
            self.datasets_list.deinit(self.allocator);
        }
    };

    /// Create a builder for fluent API
    pub fn builder(allocator: std.mem.Allocator) Builder {
        return Builder.init(allocator);
    }

    pub fn deinit(self: *BarChart) void {
        self.datasets.deinit(self.allocator);
    }

    /// Add a dataset to the chart
    pub fn addDataset(self: *BarChart, label: []const u8, values: []f64, color: Color) !void {
        try self.datasets.append(self.allocator, Dataset{
            .label = label,
            .values = values,
            .color = color,
        });
    }

    /// Set chart orientation (builder pattern)
    pub fn setOrientation(self: *BarChart, orientation: Orientation) *BarChart {
        self.orientation = orientation;
        return self;
    }

    /// Set bar width (builder pattern)
    pub fn setBarWidth(self: *BarChart, width: usize) *BarChart {
        self.bar_width = @max(1, width); // Defensive: minimum width of 1
        return self;
    }

    /// Set whether to show values on bars (builder pattern)
    pub fn setShowValues(self: *BarChart, show: bool) *BarChart {
        self.show_values = show;
        return self;
    }

    /// Set whether to show labels (builder pattern)
    pub fn setShowLabels(self: *BarChart, show: bool) *BarChart {
        self.show_labels = show;
        return self;
    }

    /// Set title (builder pattern)
    pub fn setTitle(self: *BarChart, title: []const u8) *BarChart {
        self.title = title;
        return self;
    }

    /// Set maximum value for scaling (builder pattern)
    pub fn setMaxValue(self: *BarChart, max: ?f64) *BarChart {
        if (max) |m| {
            self.max_value = if (m > 0.0) m else null; // Defensive: reject invalid max
        } else {
            self.max_value = null;
        }
        return self;
    }

    /// Builder: Set bar gap (builder pattern)
    pub fn setBarGap(self: *BarChart, gap: usize) *BarChart {
        self.bar_gap = gap;
        return self;
    }

    /// Builder: Set group gap (builder pattern)
    pub fn setGroupGap(self: *BarChart, gap: usize) *BarChart {
        self.group_gap = gap;
        return self;
    }

    /// Calculate the maximum value across all datasets
    fn calculateMaxValue(self: *const BarChart) f64 {
        if (self.max_value) |max| return max;

        var max: f64 = 0.0;
        for (self.datasets.items) |dataset| {
            for (dataset.values) |value| {
                if (value > max) max = value;
            }
        }

        // Add 10% headroom
        return max * 1.1;
    }

    /// Render the BarChart
    pub fn render(self: *BarChart, buffer: *Buffer, area: Rect) void {
        // Defensive: Early exit for invalid conditions
        if (self.datasets.items.len == 0) return;
        if (area.width < 3 or area.height < 3) return; // Need minimum space

        var render_area = area;

        // Render title if present
        if (self.title) |title| {
            const title_pos = Position{
                .x = area.x + (area.width / 2) - @as(u16, @intCast(@divTrunc(title.len, 2))),
                .y = area.y,
            };
            buffer.writeText(title_pos.x, title_pos.y, title, self.title_style);
            render_area.y += 1;
            render_area.height -= 1;
        }

        // Calculate dimensions
        const max_val = self.calculateMaxValue();
        if (max_val == 0.0) return;

        const num_groups = if (self.datasets.items.len > 0) self.datasets.items[0].values.len else 0;
        if (num_groups == 0) return;

        const num_datasets = self.datasets.items.len;

        if (self.orientation == .vertical) {
            self.renderVertical(buffer, render_area, max_val, num_groups, num_datasets);
        } else {
            self.renderHorizontal(buffer, render_area, max_val, num_groups, num_datasets);
        }
    }

    /// Render vertical bars
    fn renderVertical(self: *BarChart, buffer: *Buffer, area: Rect, max_val: f64, num_groups: usize, num_datasets: usize) void {
        // Reserve space for labels at bottom
        const label_height: u16 = if (self.show_labels) 1 else 0;
        const chart_height = if (area.height > label_height) area.height - label_height else 1;

        // Calculate bar positions
        const total_bar_width = num_datasets * self.bar_width + (num_datasets - 1) * self.bar_gap;
        const total_width = num_groups * (total_bar_width + self.group_gap) - self.group_gap;

        if (total_width > area.width) return; // Not enough space

        const start_x = area.x + @divTrunc(area.width - @as(u16, @intCast(total_width)), 2);

        // Render each group
        for (0..num_groups) |group_idx| {
            const group_x = start_x + @as(u16, @intCast(group_idx * (total_bar_width + self.group_gap)));

            // Render bars in this group
            for (self.datasets.items, 0..) |dataset, dataset_idx| {
                if (group_idx >= dataset.values.len) continue;

                const value = dataset.values[group_idx];
                const bar_height = @as(u16, @intFromFloat(@as(f64, @floatFromInt(chart_height)) * (value / max_val)));

                const bar_x = group_x + @as(u16, @intCast(dataset_idx * (self.bar_width + self.bar_gap)));
                const bar_y = area.y + chart_height - bar_height;

                // Draw bar using block characters
                self.renderVerticalBar(buffer, bar_x, bar_y, self.bar_width, bar_height, dataset.color);

                // Show value on top of bar
                if (self.show_values and bar_height > 0) {
                    const value_str = std.fmt.allocPrint(self.allocator, "{d:.1}", .{value}) catch continue;
                    defer self.allocator.free(value_str);

                    const value_x = bar_x + @divTrunc(@as(u16, @intCast(self.bar_width)), 2) -
                        @divTrunc(@as(u16, @intCast(value_str.len)), 2);
                    const value_y = if (bar_y > area.y) bar_y - 1 else bar_y;

                    buffer.writeText(value_x, value_y, value_str, self.value_style);
                }
            }

            // Show group label at bottom
            if (self.show_labels) {
                // Use first dataset's label or group index
                const label = std.fmt.allocPrint(self.allocator, "{d}", .{group_idx}) catch continue;
                defer self.allocator.free(label);

                const label_x = group_x + @divTrunc(@as(u16, @intCast(total_bar_width)), 2) -
                    @divTrunc(@as(u16, @intCast(label.len)), 2);
                const label_y = area.y + chart_height;

                buffer.writeText(label_x, label_y, label, self.label_style);
            }
        }
    }

    /// Render horizontal bars
    fn renderHorizontal(self: *BarChart, buffer: *Buffer, area: Rect, max_val: f64, num_groups: usize, num_datasets: usize) void {
        // Reserve space for labels on left
        const label_width: u16 = if (self.show_labels) 10 else 0;
        const chart_width = if (area.width > label_width) area.width - label_width else 1;

        // Calculate bar positions
        const bar_height_total = num_datasets * 1 + (num_datasets - 1) * self.bar_gap;
        const total_height = num_groups * (bar_height_total + self.group_gap) - self.group_gap;

        if (total_height > area.height) return; // Not enough space

        const start_y = area.y + @divTrunc(area.height - @as(u16, @intCast(total_height)), 2);

        // Render each group
        for (0..num_groups) |group_idx| {
            const group_y = start_y + @as(u16, @intCast(group_idx * (bar_height_total + self.group_gap)));

            // Render bars in this group
            for (self.datasets.items, 0..) |dataset, dataset_idx| {
                if (group_idx >= dataset.values.len) continue;

                const value = dataset.values[group_idx];
                const bar_width = @as(u16, @intFromFloat(@as(f64, @floatFromInt(chart_width)) * (value / max_val)));

                const bar_x = area.x + label_width;
                const bar_y = group_y + @as(u16, @intCast(dataset_idx * (1 + self.bar_gap)));

                // Draw horizontal bar
                self.renderHorizontalBar(buffer, bar_x, bar_y, bar_width, dataset.color);

                // Show value at end of bar
                if (self.show_values and bar_width > 0) {
                    const value_str = std.fmt.allocPrint(self.allocator, "{d:.1}", .{value}) catch continue;
                    defer self.allocator.free(value_str);

                    const value_x = bar_x + bar_width + 1;
                    if (value_x + value_str.len < area.x + area.width) {
                        buffer.writeText(@intCast(value_x), bar_y, value_str, self.value_style);
                    }
                }
            }

            // Show group label on left
            if (self.show_labels) {
                const label = std.fmt.allocPrint(self.allocator, "{d}", .{group_idx}) catch continue;
                defer self.allocator.free(label);

                const label_x = area.x;
                const label_y = group_y + @divTrunc(@as(u16, @intCast(bar_height_total)), 2);

                buffer.writeText(label_x, label_y, label, self.label_style);
            }
        }
    }

    /// Render a vertical bar using block characters
    fn renderVerticalBar(self: *BarChart, buffer: *Buffer, x: u16, y: u16, width: usize, height: u16, color: Color) void {
        _ = self;
        const style = Style.default().withFg(color);

        // Fill bar with block characters
        var row: u16 = 0;
        while (row < height) : (row += 1) {
            var col: u16 = 0;
            while (col < width) : (col += 1) {
                buffer.setCell(x + col, y + row, Cell.init('█', style));
            }
        }
    }

    /// Render a horizontal bar using block characters
    fn renderHorizontalBar(self: *BarChart, buffer: *Buffer, x: u16, y: u16, width: u16, color: Color) void {
        _ = self;
        const style = Style.default().withFg(color);

        var col: u16 = 0;
        while (col < width) : (col += 1) {
            buffer.setCell(x + col, y, Cell.init('█', style));
        }
    }
};

// Tests
test "BarChart initialization with config" {
    const testing = std.testing;

    var chart = try BarChart.init(testing.allocator, BarChartConfig.default());
    defer chart.deinit();

    try testing.expectEqual(Orientation.vertical, chart.orientation);
    try testing.expectEqual(@as(usize, 3), chart.bar_width);
    try testing.expect(chart.show_values);
    try testing.expect(chart.show_labels);
}

test "BarChart builder pattern" {
    const testing = std.testing;

    const values = [_]f64{ 10.0, 20.0, 30.0 };

    var builder = BarChart.builder(testing.allocator);
    defer builder.deinit();

    _ = builder.setTitle("CPU Usage")
        .setOrientation(.horizontal)
        .setBarWidth(5)
        .setShowValues(true);

    _ = try builder.addDataset("Series 1", &values, Color.blue);

    var chart = try builder.build();
    defer chart.deinit();

    try testing.expectEqual(@as(usize, 1), chart.datasets.items.len);
    try testing.expectEqual(Orientation.horizontal, chart.orientation);
    try testing.expectEqual(@as(usize, 5), chart.bar_width);
}

test "BarChart add dataset" {
    const testing = std.testing;

    var chart = try BarChart.init(testing.allocator, BarChartConfig.default());
    defer chart.deinit();

    const values = [_]f64{ 10.0, 20.0, 30.0 };
    try chart.addDataset("Test", &values, Color.red);

    try testing.expectEqual(@as(usize, 1), chart.datasets.items.len);
    try testing.expectEqualStrings("Test", chart.datasets.items[0].label);
}

test "BarChart calculate max value" {
    const testing = std.testing;

    var chart = try BarChart.init(testing.allocator, BarChartConfig.default());
    defer chart.deinit();

    const values1 = [_]f64{ 10.0, 20.0, 30.0 };
    const values2 = [_]f64{ 15.0, 25.0, 35.0 };

    try chart.addDataset("Dataset 1", &values1, Color.red);
    try chart.addDataset("Dataset 2", &values2, Color.blue);

    const max = chart.calculateMaxValue();
    try testing.expect(max >= 35.0); // Should be 35 * 1.1 = 38.5
    try testing.expect(max <= 40.0);
}

test "BarChart with explicit max value" {
    const testing = std.testing;

    const config = BarChartConfig{
        .max_value = 100.0,
    };

    var chart = try BarChart.init(testing.allocator, config);
    defer chart.deinit();

    const values = [_]f64{ 10.0, 20.0, 30.0 };
    try chart.addDataset("Test", &values, Color.red);

    const max = chart.calculateMaxValue();
    try testing.expectEqual(@as(f64, 100.0), max);
}

test "BarChart error validation" {
    const testing = std.testing;

    // Test invalid bar width
    const bad_config = BarChartConfig{
        .bar_width = 0,
    };

    const result = BarChart.init(testing.allocator, bad_config);
    try testing.expectError(Error.InvalidBarWidth, result);
}
