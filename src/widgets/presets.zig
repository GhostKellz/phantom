//! Widget Presets - Pre-configured widgets for common use cases
//! Makes it easy to create typical dashboard/monitoring/app widgets

const std = @import("std");
const phantom = @import("../root.zig");
const BarChart = @import("bar_chart.zig").BarChart;
const Chart = @import("chart.zig").Chart;
const Gauge = @import("gauge.zig").Gauge;
const Sparkline = @import("sparkline.zig").Sparkline;
const Color = phantom.Color;

/// Preset configurations for common widget types
pub const Presets = struct {
    /// Create a CPU usage gauge (0-100%)
    pub fn cpuGauge(allocator: std.mem.Allocator) Gauge {
        var gauge = Gauge.init(allocator, "CPU");
        _ = gauge.setStyle(.horizontal)
            .setColor(Color.blue)
            .setShowPercentage(true)
            .setShowValue(false);
        return gauge;
    }

    /// Create a memory usage gauge with color thresholds
    pub fn memoryGauge(allocator: std.mem.Allocator) Gauge {
        var gauge = Gauge.init(allocator, "Memory");
        _ = gauge.setStyle(.horizontal)
            .setShowPercentage(true)
            .setShowValue(true);
        return gauge;
    }

    /// Create a disk usage gauge (circular style)
    pub fn diskGauge(allocator: std.mem.Allocator, label: []const u8) Gauge {
        var gauge = Gauge.init(allocator, label);
        _ = gauge.setStyle(.circular)
            .setShowPercentage(true);
        return gauge;
    }

    /// Create a network throughput gauge
    pub fn networkGauge(allocator: std.mem.Allocator, label: []const u8) Gauge {
        var gauge = Gauge.init(allocator, label);
        _ = gauge.setStyle(.horizontal)
            .setColor(Color.green)
            .setShowValue(true);
        return gauge;
    }

    /// Create a time series line chart
    pub fn timeSeriesChart(allocator: std.mem.Allocator, title: []const u8) !Chart {
        var chart = try Chart.init(allocator, .{});
        _ = chart.setTitle(title)
            .setChartType(.line)
            .setShowGrid(true)
            .setShowLegend(true);
        return chart;
    }

    /// Create a scatter plot chart
    pub fn scatterChart(allocator: std.mem.Allocator, title: []const u8) !Chart {
        var chart = try Chart.init(allocator, .{});
        _ = chart.setTitle(title)
            .setChartType(.scatter)
            .setShowGrid(true)
            .setShowLegend(true);
        return chart;
    }

    /// Create a resource usage bar chart (CPU, Memory, Disk, Network)
    pub fn resourceBarChart(allocator: std.mem.Allocator) !BarChart {
        var chart = try BarChart.init(allocator, .{});
        _ = chart.setOrientation(.horizontal)
            .setShowValues(true)
            .setShowLabels(true)
            .setTitle("Resource Usage");
        return chart;
    }

    /// Create a comparison bar chart (vertical)
    pub fn comparisonBarChart(allocator: std.mem.Allocator, title: []const u8) !BarChart {
        var chart = try BarChart.init(allocator, .{});
        _ = chart.setOrientation(.vertical)
            .setShowValues(true)
            .setShowLabels(true)
            .setTitle(title)
            .setBarWidth(4)
            .setBarGap(1)
            .setGroupGap(2);
        return chart;
    }

    /// Create a sparkline for inline trend display
    pub fn inlineSparkline(allocator: std.mem.Allocator, data: []f64) Sparkline {
        var spark = Sparkline.init(allocator, data);
        spark.show_baseline = false;
        return spark;
    }

    /// Create a sparkline with baseline for status bars
    pub fn statusBarSparkline(allocator: std.mem.Allocator, data: []f64) Sparkline {
        var spark = Sparkline.init(allocator, data);
        spark.show_baseline = true;
        spark.setColor(Color.cyan);
        return spark;
    }
};

/// Pre-configured dashboard layouts using constraints
pub const DashboardLayouts = struct {
    /// Classic dashboard: header, 2-column body, footer
    /// Returns: [header, left_panel, right_panel, footer]
    pub fn classic(allocator: std.mem.Allocator, area: phantom.Rect) ![]phantom.Rect {
        // Vertical split: header, body, footer
        const vertical = phantom.ConstraintLayout.init(.vertical, &[_]phantom.Constraint{
            .{ .length = 3 }, // Header
            .{ .fill = 1 }, // Body
            .{ .length = 1 }, // Footer
        });
        const v_areas = try vertical.split(allocator, area);

        // Horizontal split for body: left panel, right panel
        const horizontal = phantom.ConstraintLayout.init(.horizontal, &[_]phantom.Constraint{
            .{ .percentage = 60 }, // Left panel (main content)
            .{ .percentage = 40 }, // Right panel (sidebar)
        });
        const h_areas = try horizontal.split(allocator, v_areas[1]);

        // Combine results
        var result = try allocator.alloc(phantom.Rect, 4);
        result[0] = v_areas[0]; // Header
        result[1] = h_areas[0]; // Left panel
        result[2] = h_areas[1]; // Right panel
        result[3] = v_areas[2]; // Footer

        allocator.free(v_areas);
        allocator.free(h_areas);

        return result;
    }

    /// Monitoring dashboard: title, 4-panel grid, status bar
    /// Returns: [title, top_left, top_right, bottom_left, bottom_right, status]
    pub fn monitoring(allocator: std.mem.Allocator, area: phantom.Rect) ![]phantom.Rect {
        // Vertical: title, grid, status
        const vertical = phantom.ConstraintLayout.init(.vertical, &[_]phantom.Constraint{
            .{ .length = 2 }, // Title
            .{ .fill = 1 }, // Grid area
            .{ .length = 1 }, // Status
        });
        const v_areas = try vertical.split(allocator, area);

        // Split grid into top and bottom rows
        const grid_vert = phantom.ConstraintLayout.init(.vertical, &[_]phantom.Constraint{
            .{ .percentage = 50 }, // Top row
            .{ .percentage = 50 }, // Bottom row
        });
        const grid_v = try grid_vert.split(allocator, v_areas[1]);

        // Split top row
        const top_horiz = phantom.ConstraintLayout.init(.horizontal, &[_]phantom.Constraint{
            .{ .percentage = 50 },
            .{ .percentage = 50 },
        });
        const top = try top_horiz.split(allocator, grid_v[0]);

        // Split bottom row
        const bottom_horiz = phantom.ConstraintLayout.init(.horizontal, &[_]phantom.Constraint{
            .{ .percentage = 50 },
            .{ .percentage = 50 },
        });
        const bottom = try bottom_horiz.split(allocator, grid_v[1]);

        // Combine results
        var result = try allocator.alloc(phantom.Rect, 6);
        result[0] = v_areas[0]; // Title
        result[1] = top[0]; // Top left
        result[2] = top[1]; // Top right
        result[3] = bottom[0]; // Bottom left
        result[4] = bottom[1]; // Bottom right
        result[5] = v_areas[2]; // Status

        allocator.free(v_areas);
        allocator.free(grid_v);
        allocator.free(top);
        allocator.free(bottom);

        return result;
    }

    /// Chat/AI interface: header, messages, input
    /// Returns: [header, messages_area, input_area]
    pub fn chatInterface(allocator: std.mem.Allocator, area: phantom.Rect) ![]phantom.Rect {
        const layout = phantom.ConstraintLayout.init(.vertical, &[_]phantom.Constraint{
            .{ .length = 3 }, // Header (title, model info)
            .{ .fill = 1 }, // Messages area (scrollable)
            .{ .length = 3 }, // Input area
        });
        return layout.split(allocator, area);
    }

    /// Editor layout: title, editor, status line
    /// Returns: [title, editor_area, status_line]
    pub fn editorLayout(allocator: std.mem.Allocator, area: phantom.Rect) ![]phantom.Rect {
        const layout = phantom.ConstraintLayout.init(.vertical, &[_]phantom.Constraint{
            .{ .length = 1 }, // Title
            .{ .fill = 1 }, // Editor
            .{ .length = 2 }, // Status line
        });
        return layout.split(allocator, area);
    }
};

// Tests
test "Presets CPU gauge" {
    const testing = std.testing;

    const gauge = Presets.cpuGauge(testing.allocator);
    try testing.expectEqualStrings("CPU", gauge.label);
    try testing.expectEqual(Gauge.GaugeStyle.horizontal, gauge.style_type);
    try testing.expect(gauge.show_percentage);
}

test "Presets time series chart" {
    const testing = std.testing;

    var chart = Presets.timeSeriesChart(testing.allocator, "Test");
    defer chart.deinit();

    try testing.expectEqual(Chart.ChartType.line, chart.chart_type);
    try testing.expect(chart.show_grid);
    try testing.expect(chart.show_legend);
}

test "DashboardLayouts classic" {
    const testing = std.testing;

    const area = phantom.Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    const areas = try DashboardLayouts.classic(testing.allocator, area);
    defer testing.allocator.free(areas);

    try testing.expectEqual(@as(usize, 4), areas.len);
    // Header should be 3 lines
    try testing.expectEqual(@as(u16, 3), areas[0].height);
    // Footer should be 1 line
    try testing.expectEqual(@as(u16, 1), areas[3].height);
}

test "DashboardLayouts chat interface" {
    const testing = std.testing;

    const area = phantom.Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const areas = try DashboardLayouts.chatInterface(testing.allocator, area);
    defer testing.allocator.free(areas);

    try testing.expectEqual(@as(usize, 3), areas.len);
    // Header: 3 lines
    try testing.expectEqual(@as(u16, 3), areas[0].height);
    // Input: 3 lines
    try testing.expectEqual(@as(u16, 3), areas[2].height);
    // Messages: remaining (should be 18 lines)
    try testing.expect(areas[1].height >= 18);
}
