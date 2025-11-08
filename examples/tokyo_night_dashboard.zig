//! Tokyo Night Theme Dashboard
//! Professional themed TUI demonstrating theming capabilities
//! Shows system stats with Tokyo Night color scheme

const std = @import("std");
const phantom = @import("phantom");

const TokyoNight = struct {
    bg: phantom.Color = .{ .rgb = .{ .r = 26, .g = 27, .b = 38 } },
    fg: phantom.Color = .{ .rgb = .{ .r = 169, .g = 177, .b = 214 } },
    cyan: phantom.Color = .{ .rgb = .{ .r = 125, .g = 207, .b = 255 } },
    green: phantom.Color = .{ .rgb = .{ .r = 158, .g = 206, .b = 106 } },
    yellow: phantom.Color = .{ .rgb = .{ .r = 224, .g = 175, .b = 104 } },
    red: phantom.Color = .{ .rgb = .{ .r = 247, .g = 118, .b = 142 } },
    purple: phantom.Color = .{ .rgb = .{ .r = 187, .g = 154, .b = 247 } },
    blue: phantom.Color = .{ .rgb = .{ .r = 122, .g = 162, .b = 247 } },
};

const DashboardState = struct {
    frame: u64 = 0,
    theme: TokyoNight = .{},

    cpu_usage: f64 = 45.0,
    mem_usage: f64 = 67.0,
    disk_usage: f64 = 52.0,
    net_in: f64 = 1.2,
    net_out: f64 = 0.8,

    pub fn update(self: *DashboardState) void {
        self.frame += 1;
        const t = @as(f64, @floatFromInt(self.frame)) * 0.05;
        self.cpu_usage = 45.0 + @sin(t) * 15.0;
        self.mem_usage = 67.0 + @cos(t * 0.7) * 10.0;
        self.net_in = 1.2 + @sin(t * 1.5) * 0.6;
        self.net_out = 0.8 + @cos(t * 1.2) * 0.4;
    }
};

var state: *DashboardState = undefined;
var app: *phantom.App = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    state = try allocator.create(DashboardState);
    defer allocator.destroy(state);
    state.* = .{};

    var phantom_app = try phantom.App.init(allocator, .{
        .title = "Tokyo Night Dashboard",
        .tick_rate_ms = 100,
        .mouse_enabled = true,
        .add_default_handler = false,
    });
    defer phantom_app.deinit();
    app = &phantom_app;

    try app.event_loop.addHandler(handleEvent);
    try app.run();
}

fn handleEvent(event: phantom.Event) !bool {
    if (event == .key) {
        const key = event.key;
        if (key == .ctrl_c or key.isChar('q')) {
            app.stop();
            return true;
        }
    } else if (event == .tick) {
        try renderDashboard();
    }
    return false;
}

fn renderDashboard() !void {
    state.update();

    const buffer = app.terminal.getBackBuffer();
    const area = phantom.Rect.init(0, 0, app.terminal.size.width, app.terminal.size.height);

    try app.terminal.clear();

    const layout = try phantom.widgets.DashboardLayouts.monitoring(buffer.allocator, area);
    defer buffer.allocator.free(layout);

    renderTitle(buffer, layout[0]);
    try renderGauges(buffer, layout[1]);
    renderStatus(buffer, layout[5]);

    try app.terminal.flush();
}

fn renderTitle(buffer: *phantom.Buffer, area: phantom.Rect) void {
    const title = "Tokyo Night System Monitor";
    const style = phantom.Style.default()
        .withFg(state.theme.purple)
        .withBold();

    const x = area.x + @divTrunc(area.width, 2) - @divTrunc(@as(u16, @intCast(title.len)), 2);
    buffer.writeText(x, area.y, title, style);
}

fn renderGauges(buffer: *phantom.Buffer, area: phantom.Rect) !void {
    const weights = [_]phantom.layout.engine.WeightSpec{
        .{ .weight = 1.0 },
        .{ .weight = 1.0 },
        .{ .weight = 1.0 },
    };
    const gauge_areas = try phantom.layout.engine.splitColumn(buffer.allocator, area, &weights);
    defer buffer.allocator.free(gauge_areas);

    var cpu_gauge = phantom.widgets.Presets.cpuGauge(buffer.allocator);
    _ = cpu_gauge.setValue(state.cpu_usage);
    cpu_gauge.gauge_color = state.theme.cyan;
    cpu_gauge.render(buffer, gauge_areas[0]);

    var mem_gauge = phantom.widgets.Presets.memoryGauge(buffer.allocator);
    _ = mem_gauge.setValue(state.mem_usage);
    mem_gauge.gauge_color = state.theme.green;
    mem_gauge.render(buffer, gauge_areas[1]);

    var disk_gauge = phantom.widgets.Presets.diskGauge(buffer.allocator, "Disk");
    _ = disk_gauge.setValue(state.disk_usage);
    disk_gauge.gauge_color = state.theme.yellow;
    disk_gauge.render(buffer, gauge_areas[2]);
}

fn renderStatus(buffer: *phantom.Buffer, area: phantom.Rect) void {
    const status_style = phantom.Style.default().withFg(state.theme.fg);

    const status = std.fmt.allocPrint(
        buffer.allocator,
        "Network: IN {d:.2} MB/s  OUT {d:.2} MB/s | Press 'q' to quit",
        .{ state.net_in, state.net_out }
    ) catch return;
    defer buffer.allocator.free(status);

    buffer.writeText(area.x, area.y, status, status_style);
}
