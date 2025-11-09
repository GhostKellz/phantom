//! Data dashboard demo showcasing data-bound widgets.
const std = @import("std");
const phantom = @import("phantom");

const Item = []const u8;
const SourceType = phantom.data.InMemoryListSource(Item);
const DataListView = phantom.widgets.DataListView(Item);
const DataStateIndicator = phantom.widgets.DataStateIndicator(Item);
const DataBadge = phantom.widgets.DataBadge(Item);
const DataEventOverlay = phantom.widgets.DataEventOverlay(Item);
const ListViewConfig = phantom.widgets.ListViewConfig;
const Container = phantom.widgets.Container;

const Tasks = [_][]const u8{
    "Gather metrics",
    "Connect upstream",
    "Normalize streams",
    "Aggregate results",
    "Compute insights",
    "Publish dashboard",
};

const DemoError = error{NetworkGlitch};

var global_source: *SourceType = undefined;
var global_app: *phantom.App = undefined;

const DashboardState = struct {
    tick: usize = 0,
    emitted: usize = 0,
    injecting_failure: bool = false,
};

var dashboard_state = DashboardState{};

fn onTick() !void {
    dashboard_state.tick += 1;

    if (dashboard_state.injecting_failure and dashboard_state.tick % 4 == 0) {
        global_source.clear();
        global_source.setState(.loading);
        dashboard_state.injecting_failure = false;
        dashboard_state.emitted = 0;
        return;
    }

    if (dashboard_state.tick % 6 == 1 and dashboard_state.emitted < Tasks.len) {
        global_source.setState(.loading);
        return;
    }

    if (dashboard_state.tick % 6 == 3 and dashboard_state.emitted < Tasks.len) {
        try global_source.appendSlice(Tasks[dashboard_state.emitted .. dashboard_state.emitted + 1]);
        dashboard_state.emitted += 1;
        if (dashboard_state.emitted == Tasks.len) {
            global_source.setState(.exhausted);
        } else {
            global_source.setState(.ready);
        }
        return;
    }

    if (dashboard_state.tick == 18 and !dashboard_state.injecting_failure) {
        global_source.fail(DemoError.NetworkGlitch);
        dashboard_state.injecting_failure = true;
    }
}

fn handleEvent(event: phantom.Event) !bool {
    switch (event) {
        .tick => {
            try onTick();
            try global_app.render();
            return false;
        },
        .key => |key| {
            if (key.isChar('q') or key == .ctrl_c) {
                global_app.stop();
                return true;
            }
        },
        else => {},
    }
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var source = SourceType.init(allocator);
    defer source.deinit();
    global_source = &source;

    global_source.setState(.loading);

    const handle = source.asListDataSource();

    const list_adapter = DataListView.adapters.text();
    const list_config = ListViewConfig{ .viewport_height = 10 };
    var list_widget = try DataListView.init(allocator, handle, list_adapter, list_config, .{
        .virtualization = .{ .window_size = 40, .preload = 10 },
    });

    var indicator = try DataStateIndicator.init(allocator, handle, .{});

    var badge = try DataBadge.init(allocator, handle, .{});

    var overlay = try DataEventOverlay.init(allocator, handle, .{ .max_entries = 12 });

    var header = try Container.init(allocator, .horizontal);
    header.setGap(2);
    try header.addChild(&indicator.widget);
    try header.addChild(&badge.widget);

    var layout = try Container.init(allocator, .vertical);
    layout.setGap(1);
    layout.setPadding(1);
    try layout.addChildWithFlex(&header.widget, 1);
    try layout.addChildWithFlex(&list_widget.widget, 4);
    try layout.addChildWithFlex(&overlay.widget, 2);

    var app = try phantom.App.init(allocator, .{
        .title = "Phantom Data Dashboard Demo",
        .tick_rate_ms = 300,
        .mouse_enabled = false,
        .add_default_handler = false,
    });
    defer app.deinit();

    global_app = &app;

    try app.addWidget(&layout.widget);
    try app.event_loop.addHandler(handleEvent);

    try app.run();
}
