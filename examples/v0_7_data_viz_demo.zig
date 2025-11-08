//! Phantom v0.7.0 Data Visualization Demo
//! Showcases all new Ratatui-parity features:
//! - BarChart, Chart, Gauge, Sparkline, Calendar, Canvas
//! - Constraint-based layouts
//! - Builder patterns and presets
//! - Perfect reference for Zeke TUI development!

const std = @import("std");
const phantom = @import("phantom");

const DemoState = struct {
    frame: u64 = 0,
    cpu_usage: f64 = 45.0,
    memory_usage: f64 = 67.0,
    disk_usage: f64 = 82.0,
    network_in: f64 = 1.5, // MB/s
    network_out: f64 = 0.8, // MB/s

    // Time series data for chart
    metrics_history: [20]f64 = undefined,

    // Initialize with some sample data
    pub fn init() DemoState {
        var demo_state = DemoState{};
        for (&demo_state.metrics_history, 0..) |*m, i| {
            m.* = @as(f64, @floatFromInt(i)) * 2.0 + 10.0;
        }
        return demo_state;
    }

    // Update values each frame (simulated live data)
    pub fn update(self: *DemoState) void {
        self.frame += 1;

        // Simulate fluctuating metrics
        const t = @as(f64, @floatFromInt(self.frame)) * 0.1;
        self.cpu_usage = 45.0 + @sin(t) * 20.0;
        self.memory_usage = 67.0 + @cos(t * 0.5) * 15.0;
        self.disk_usage = 82.0; // Static
        self.network_in = 1.5 + @sin(t * 2.0) * 0.5;
        self.network_out = 0.8 + @cos(t * 1.5) * 0.3;

        // Shift history
        for (1..self.metrics_history.len) |i| {
            self.metrics_history[i - 1] = self.metrics_history[i];
        }
        self.metrics_history[self.metrics_history.len - 1] = self.cpu_usage;
    }
};

// Global state for event handler
var global_state: *DemoState = undefined;
var global_app: *phantom.App = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Phantom app
    var app = try phantom.App.init(allocator, .{
        .title = "Phantom v0.7.0 - Data Visualization Demo",
        .tick_rate_ms = 100, // 10 FPS for smooth updates
        .mouse_enabled = true,
        .add_default_handler = false, // We'll handle events manually
    });
    defer app.deinit();

    var demo_state = DemoState.init();
    global_state = &demo_state;
    global_app = &app;

    // Event handler
    try app.event_loop.addHandler(struct {
        fn handle(event: phantom.Event) !bool {
            if (event == .key) {
                const key = event.key;
                // Quit on 'q' or Ctrl+C
                if (key.isChar('q') or key == .ctrl_c) {
                    global_app.stop();
                    return true; // Exit
                }
            } else if (event == .tick) {
                // Render on each tick
                try renderFrame();
            }
            return false;
        }
    }.handle);

    // Run the app
    try app.run();
}

fn renderFrame() !void {
    // Update simulation
    global_state.update();

    const buffer = global_app.terminal.getBackBuffer();
    const area = phantom.Rect.init(0, 0, global_app.terminal.size.width, global_app.terminal.size.height);

    // Clear buffer
    try global_app.terminal.clear();

    // Use monitoring dashboard layout
    const layout_areas = try phantom.widgets.DashboardLayouts.monitoring(buffer.allocator, area);
    defer buffer.allocator.free(layout_areas);

    // Title area
    renderTitle(buffer, layout_areas[0]);

    // Top-left: Resource bar chart
    try renderResourceBarChart(buffer, layout_areas[1]);

    // Top-right: Gauges
    try renderGauges(buffer, layout_areas[2]);

    // Bottom-left: Time series chart
    try renderTimeSeriesChart(buffer, layout_areas[3]);

    // Bottom-right: Canvas demo
    try renderCanvasDemo(buffer, layout_areas[4]);

    // Status bar with sparklines
    try renderStatusBar(buffer, layout_areas[5]);

    // Flush to screen
    try global_app.terminal.flush();
}

fn renderTitle(buffer: *phantom.Buffer, area: phantom.Rect) void {
    const title = "🎨 Phantom v0.7.0 - Ratatui Parity Demo | Press 'q' to quit";
    const title_style = phantom.Style.default().withFg(phantom.Color.cyan).withBold();
    const x = area.x + @divTrunc(area.width, 2) - @divTrunc(@as(u16, @intCast(title.len)), 2);
    buffer.writeText(x, area.y, title, title_style);
}

fn renderResourceBarChart(buffer: *phantom.Buffer, area: phantom.Rect) !void {
    var chart = phantom.widgets.Presets.resourceBarChart(buffer.allocator);
    defer chart.deinit();

    const values = [_]f64{ global_state.cpu_usage, global_state.memory_usage, global_state.disk_usage, global_state.network_in * 10, global_state.network_out * 10 };
    try chart.addDataset("Usage", @constCast(&values), phantom.Color.green);

    chart.render(buffer, area);
}

fn renderGauges(buffer: *phantom.Buffer, area: phantom.Rect) !void {
    // Split into 3 rows for 3 gauges
    const layout = phantom.ConstraintLayout.init(.vertical, &[_]phantom.Constraint{
        .{ .percentage = 33 },
        .{ .percentage = 33 },
        .{ .percentage = 34 },
    });
    const gauge_areas = try layout.split(buffer.allocator, area);
    defer buffer.allocator.free(gauge_areas);

    // CPU gauge
    var cpu_gauge = phantom.widgets.Presets.cpuGauge(buffer.allocator);
    _ = cpu_gauge.setValue(global_state.cpu_usage).setColorByThreshold();
    cpu_gauge.render(buffer, gauge_areas[0]);

    // Memory gauge
    var mem_gauge = phantom.widgets.Presets.memoryGauge(buffer.allocator);
    _ = mem_gauge.setValue(global_state.memory_usage).setColorByThreshold();
    mem_gauge.render(buffer, gauge_areas[1]);

    // Disk gauge (circular)
    var disk_gauge = phantom.widgets.Presets.diskGauge(buffer.allocator, "Disk");
    _ = disk_gauge.setValue(global_state.disk_usage).setColorByThreshold();
    disk_gauge.render(buffer, gauge_areas[2]);
}

fn renderTimeSeriesChart(buffer: *phantom.Buffer, area: phantom.Rect) !void {
    var chart = phantom.widgets.Presets.timeSeriesChart(buffer.allocator, "CPU History");
    defer chart.deinit();

    // Convert history to points
    var points = try buffer.allocator.alloc(phantom.widgets.Chart.Point, global_state.metrics_history.len);
    defer buffer.allocator.free(points);

    for (global_state.metrics_history, 0..) |val, i| {
        points[i] = .{ .x = @floatFromInt(i), .y = val };
    }

    try chart.addDataset("CPU %", points, phantom.Color.blue, '●');
    chart.render(buffer, area);
}

fn renderCanvasDemo(buffer: *phantom.Buffer, area: phantom.Rect) !void {
    var canvas = try phantom.widgets.Canvas.init(buffer.allocator, .{ .width = 40, .height = 20 });
    defer canvas.deinit();

    // Draw some shapes
    const t = @as(f64, @floatFromInt(global_state.frame)) * 0.1;

    // Animated circle
    const cx = 20.0 + @sin(t) * 10.0;
    const cy = 10.0 + @cos(t * 0.7) * 5.0;
    try canvas.drawCircle(cx, cy, 3.0, phantom.Color.red);

    // Static rectangle
    try canvas.drawRect(5.0, 5.0, 10.0, 8.0, phantom.Color.green);

    // Diagonal line
    try canvas.drawLine(0.0, 0.0, 40.0, 20.0, phantom.Color.yellow);

    // Text label
    try canvas.drawText(15.0, 2.0, "Canvas", phantom.Style.default().withFg(phantom.Color.cyan));

    canvas.render(buffer, area);
}

fn renderStatusBar(buffer: *phantom.Buffer, area: phantom.Rect) !void {
    // Show frame counter and sparklines
    const status = try std.fmt.allocPrint(buffer.allocator, "Frame: {d} | CPU Trend:", .{global_state.frame});
    defer buffer.allocator.free(status);

    buffer.writeText(area.x, area.y, status, phantom.Style.default().withFg(phantom.Color.bright_black));

    // Sparkline showing recent CPU history
    var spark = phantom.widgets.Presets.statusBarSparkline(buffer.allocator, @constCast(&global_state.metrics_history));
    const spark_area = phantom.Rect{ .x = area.x + @as(u16, @intCast(status.len)) + 2, .y = area.y, .width = area.width - @as(u16, @intCast(status.len)) - 2, .height = 1 };
    spark.render(buffer, spark_area);
}
