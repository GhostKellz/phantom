//! Main application structure for Phantom TUI
const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const Buffer = @import("terminal.zig").Buffer;
const EventLoop = @import("event.zig").EventLoop;
const Event = @import("event.zig").Event;
const SystemEvent = @import("event.zig").SystemEvent;
const EventPriority = @import("event/mod.zig").EventPriority;
const vxfw = @import("vxfw.zig");
const geometry = @import("geometry.zig");
const style = @import("style.zig");
const widget_mod = @import("widget.zig");
const animation = @import("animation.zig");
const ArrayList = std.array_list.Managed;

const AutoHashMap = std.AutoHashMap;

const Size = geometry.Size;
const Rect = geometry.Rect;
const Style = style.Style;

// Re-export Widget from widget.zig
pub const Widget = widget_mod.Widget;
pub const SizeConstraints = widget_mod.SizeConstraints;

/// Application configuration
pub const AppConfig = struct {
    title: []const u8 = "Phantom App",
    tick_rate_ms: u64 = 16, // ~60 FPS
    mouse_enabled: bool = false,
    resize_enabled: bool = true,
    add_default_handler: bool = true, // Allow disabling default Escape/Ctrl+C quit
    enable_transitions: bool = true,
    transition_duration_ms: u64 = 180,
    transition_delay_ms: u64 = 0,
    transition_curve: animation.TransitionCurve = .ease,
    event_loop_config: EventLoop.Config = .{},
};

const WidgetTransitionState = struct {
    last_rect: ?Rect = null,
    active_transition: ?animation.TransitionId = null,
};

/// Main application structure
pub const App = struct {
    allocator: std.mem.Allocator,
    terminal: Terminal,
    event_loop: EventLoop,
    config: AppConfig,
    running: bool = false,
    needs_redraw: bool = true,

    // Widget storage
    widgets: ArrayList(*Widget),
    transition_manager: animation.TransitionManager,
    widget_transitions: AutoHashMap(*Widget, WidgetTransitionState),

    pub fn init(allocator: std.mem.Allocator, config: AppConfig) !App {
        const terminal = try Terminal.init(allocator);
        var loop_config = config.event_loop_config;
        loop_config.tick_interval_ms = config.tick_rate_ms;
        const event_loop = EventLoop.initWithConfig(allocator, loop_config);

        return App{
            .allocator = allocator,
            .terminal = terminal,
            .event_loop = event_loop,
            .config = config,
            .widgets = ArrayList(*Widget).init(allocator),
            .transition_manager = animation.TransitionManager.init(allocator),
            .widget_transitions = AutoHashMap(*Widget, WidgetTransitionState).init(allocator),
        };
    }

    pub fn deinit(self: *App) void {
        self.transition_manager.deinit();
        self.widget_transitions.deinit();
        self.widgets.deinit();
        self.event_loop.deinit();
        self.terminal.deinit();
    }

    /// Add a widget to the application
    pub fn addWidget(self: *App, widget: *Widget) !void {
        try self.widgets.append(widget);
        try self.widget_transitions.put(widget, WidgetTransitionState{});
        self.needs_redraw = true;
    }

    /// Remove a widget from the application
    pub fn removeWidget(self: *App, widget: *Widget) void {
        if (self.widget_transitions.fetchRemove(widget)) |entry| {
            if (entry.value.active_transition) |id| {
                self.transition_manager.release(id);
            }
        }

        for (self.widgets.items, 0..) |w, i| {
            if (w == widget) {
                _ = self.widgets.swapRemove(i);
                self.needs_redraw = true;
                return;
            }
        }
    }

    /// Run the application (blocking)
    pub fn run(self: *App) !void {
        try self.terminal.enableRawMode();
        defer self.terminal.disableRawMode() catch {};

        // Add default event handler if configured
        if (self.config.add_default_handler) {
            try self.event_loop.addHandler(appEventHandler);
            app_context = self;
        }

        // Trigger an initial resize so widgets receive layout information immediately.
        try self.event_loop.queueEvent(Event.fromSystem(SystemEvent.resize), null);

        self.running = true;
        try self.event_loop.run();
        try self.processPendingCommands();
    }

    /// Run the application without default event handlers
    /// Use this when you need full control over event handling (e.g., vim-style editors)
    pub fn runWithoutDefaults(self: *App) !void {
        try self.terminal.enableRawMode();
        defer self.terminal.disableRawMode() catch {};

        try self.event_loop.queueEvent(Event.fromSystem(SystemEvent.resize), null);

        self.running = true;
        try self.event_loop.run();
        try self.processPendingCommands();
    }

    /// Run the application asynchronously
    pub fn runAsync(self: *App) !void {
        // TODO: Implement with zsync
        try self.run();
    }

    /// Stop the application
    pub fn stop(self: *App) void {
        self.running = false;
        self.event_loop.stop();
    }

    /// Force a redraw on next tick
    pub fn invalidate(self: *App) void {
        self.needs_redraw = true;
    }

    /// Post an event to the application's event loop using automatic priority.
    pub fn postEvent(self: *App, event: Event) !void {
        try self.event_loop.queueEvent(event, null);
    }

    /// Post an event with an explicit priority override.
    pub fn postEventWithPriority(self: *App, event: Event, priority: EventPriority) !void {
        try self.event_loop.queueEvent(event, priority);
    }

    /// Handle window resize
    pub fn resize(self: *App, new_size: Size) !void {
        try self.terminal.resize(new_size);
        self.needs_redraw = true;

        // Notify widgets of resize
        for (self.widgets.items) |widget| {
            widget.resize(Rect.init(0, 0, new_size.width, new_size.height));
        }
    }

    /// Render all widgets to the terminal
    pub fn render(self: *App) !void {
        self.transition_manager.update();

        if (!self.needs_redraw and !self.transition_manager.hasActive()) return;

        try self.terminal.clear();
        const buffer = self.terminal.getBackBuffer();

        const area = Rect.init(0, 0, self.terminal.size.width, self.terminal.size.height);

        // If only one widget, give it the full area (most common case)
        if (self.widgets.items.len == 1) {
            const widget = self.widgets.items[0];
            const layout_rect = try self.resolveWidgetRect(widget, area);
            widget.render(buffer, layout_rect);
        } else if (self.widgets.items.len > 1) {
            // Multiple widgets: split area vertically (Ratatui-style default layout)
            const height_per_widget = area.height / @as(u16, @intCast(self.widgets.items.len));
            var current_y: u16 = area.y;

            for (self.widgets.items, 0..) |widget, i| {
                // Last widget gets remaining height to account for rounding
                const widget_height = if (i == self.widgets.items.len - 1)
                    area.height - (current_y - area.y)
                else
                    height_per_widget;

                const widget_area = Rect{
                    .x = area.x,
                    .y = current_y,
                    .width = area.width,
                    .height = widget_height,
                };

                const layout_rect = try self.resolveWidgetRect(widget, widget_area);
                widget.render(buffer, layout_rect);
                current_y += widget_height;
            }
        }

        try self.terminal.flush();
        self.needs_redraw = self.transition_manager.hasActive();
    }

    fn resolveWidgetRect(self: *App, widget: *Widget, target: Rect) !Rect {
        var entry = try self.widget_transitions.getOrPut(widget);
        if (!entry.found_existing) {
            entry.value_ptr.* = WidgetTransitionState{};
        }

        const transitions_enabled = self.config.enable_transitions;
        var state = entry.value_ptr;

        if (state.active_transition) |id| {
            if (self.transition_manager.get(id)) |transition| {
                if (transition.state == .completed or transition.state == .cancelled) {
                    self.transition_manager.release(id);
                    state.active_transition = null;
                } else if (transitions_enabled) {
                    if (transition.currentRect()) |rect| {
                        self.needs_redraw = true;
                        state.last_rect = target;
                        return rect;
                    }
                } else {
                    self.transition_manager.release(id);
                    state.active_transition = null;
                }
            } else {
                state.active_transition = null;
            }
        }

        if (!transitions_enabled) {
            state.last_rect = target;
            return target;
        }

        if (state.last_rect) |last_rect| {
            if (!rectEquals(last_rect, target)) {
                try self.startRectTransition(state, last_rect, target, .updating);
            }
        } else {
            const from_rect = Rect.init(target.x, target.y, target.width, 0);
            try self.startRectTransition(state, from_rect, target, .entering);
        }

        state.last_rect = target;

        if (state.active_transition) |id| {
            if (self.transition_manager.get(id)) |transition| {
                if (transition.state == .completed or transition.state == .cancelled) {
                    self.transition_manager.release(id);
                    state.active_transition = null;
                } else if (transition.currentRect()) |rect| {
                    self.needs_redraw = true;
                    return rect;
                }
            } else {
                state.active_transition = null;
            }
        }

        return target;
    }

    fn startRectTransition(
        self: *App,
        state: *WidgetTransitionState,
        from_rect: Rect,
        to_rect: Rect,
        phase: animation.TransitionPhase,
    ) !void {
        if (state.active_transition) |existing| {
            self.transition_manager.release(existing);
            state.active_transition = null;
        }

        const spec = animation.TransitionSpec{
            .duration_ms = self.config.transition_duration_ms,
            .delay_ms = self.config.transition_delay_ms,
            .curve = self.config.transition_curve,
            .phase = phase,
            .auto_remove = false,
        };

        const transition = try animation.Transitions.rectMorph(&self.transition_manager, from_rect, to_rect, spec);
        state.active_transition = transition.id;
        self.needs_redraw = true;
    }

    fn rectEquals(a: Rect, b: Rect) bool {
        return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height;
    }

    fn processPendingCommands(self: *App) !void {
        while (true) {
            const commands = try self.event_loop.drainCommands();
            defer self.event_loop.releaseCommands(commands);

            if (commands.len == 0) break;

            for (commands) |command| {
                try self.handleCommand(command);
            }
        }
    }

    fn handleCommand(self: *App, command: vxfw.Command) !void {
        switch (command) {
            .tick => |tick| {
                _ = tick;
                try self.event_loop.queueEvent(Event.fromTick(), null);
                self.invalidate();
            },
            .queue_refresh, .redraw => {
                self.invalidate();
            },
            .set_title => |title| {
                std.log.debug("App command set_title: {s}", .{title});
            },
            .copy_to_clipboard => |text| {
                std.log.debug("App command copy_to_clipboard received ({} bytes)", .{text.len});
            },
            .notify => |notify| {
                const title = notify.title orelse "";
                std.log.debug("App notification: {s}{s}{s}", .{
                    title,
                    if (title.len > 0) ": " else "",
                    notify.body,
                });
                self.invalidate();
            },
            .set_mouse_shape => |shape| {
                std.log.debug("App command set_mouse_shape: {}", .{shape});
            },
            .request_focus => |widget| {
                std.log.debug("App command request_focus received", .{});
                _ = widget;
            },
            .query_color => |kind| {
                std.log.debug("App command query_color: {}", .{kind});
            },
        }
    }
};

/// Global app context for event handler (simplified approach)
var app_context: ?*App = null;

/// Main application event handler
fn appEventHandler(event: Event) !bool {
    const app = app_context orelse return false;

    switch (event) {
        .key => |key| {
            switch (key) {
                .ctrl_c, .escape => {
                    app.stop();
                    try app.processPendingCommands();
                    return true;
                },
                else => {
                    // Forward to widgets
                    for (app.widgets.items) |widget| {
                        if (widget.handleEvent(event)) {
                            app.needs_redraw = true;
                            break;
                        }
                    }
                },
            }
        },
        .mouse => |mouse_event| {
            // Handle mouse events by dispatching to the focused widget
            app.needs_redraw = true;

            // Handle mouse events on widgets (simplified for now)
            for (app.widgets.items) |widget| {
                // Dispatch mouse event to all widgets for now
                _ = widget.handleEvent(Event.fromMouse(mouse_event));
            }
        },
        .system => |sys_event| {
            switch (sys_event) {
                .resize => {
                    // Get actual new terminal size using improved detection
                    const terminal = @import("terminal.zig");
                    const new_size = terminal.getTerminalSize() catch Size.init(80, 24);
                    try app.resize(new_size);
                },
                else => {},
            }
        },
        .tick => {
            // Update and render on each tick
            try app.render();
        },
    }

    try app.processPendingCommands();
    return false;
}

const TestWidget = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    render_calls: usize = 0,
    last_resize: ?Rect = null,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = null,
        .resize = resize,
        .getConstraints = null,
    };

    pub fn init(allocator: std.mem.Allocator) !*TestWidget {
        const self = try allocator.create(TestWidget);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
        };
        return self;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        _ = buffer;
        _ = area;
        const self: *TestWidget = @fieldParentPtr("widget", widget);
        self.render_calls += 1;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *TestWidget = @fieldParentPtr("widget", widget);
        self.last_resize = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *TestWidget = @fieldParentPtr("widget", widget);
        self.allocator.destroy(self);
    }
};

test "App initialization" {
    const allocator = std.testing.allocator;

    var app = try App.init(allocator, AppConfig{});
    defer app.deinit();

    try std.testing.expect(!app.running);
    try std.testing.expect(app.needs_redraw);
}

test "App handleCommand marks redraw" {
    const allocator = std.testing.allocator;

    var app = try App.init(allocator, AppConfig{});
    defer app.deinit();

    app.needs_redraw = false;
    try app.handleCommand(vxfw.Command.redraw);
    try std.testing.expect(app.needs_redraw);
}

test "App addWidget registers widget" {
    const allocator = std.testing.allocator;

    var app = try App.init(allocator, AppConfig{});
    defer app.deinit();

    const widget = try TestWidget.init(allocator);
    defer widget.widget.deinit();

    app.needs_redraw = false;
    try app.addWidget(&widget.widget);

    try std.testing.expectEqual(@as(usize, 1), app.widgets.items.len);
    try std.testing.expect(app.needs_redraw);
    try std.testing.expect(app.widget_transitions.contains(&widget.widget));

    app.removeWidget(&widget.widget);
}

test "App removeWidget clears state" {
    const allocator = std.testing.allocator;

    var app = try App.init(allocator, AppConfig{});
    defer app.deinit();

    const widget = try TestWidget.init(allocator);
    defer widget.widget.deinit();

    try app.addWidget(&widget.widget);
    try std.testing.expect(app.widget_transitions.contains(&widget.widget));

    app.needs_redraw = false;
    app.removeWidget(&widget.widget);

    try std.testing.expectEqual(@as(usize, 0), app.widgets.items.len);
    try std.testing.expect(app.needs_redraw);
    try std.testing.expect(!app.widget_transitions.contains(&widget.widget));

    app.needs_redraw = false;
    app.removeWidget(&widget.widget);
    try std.testing.expect(!app.needs_redraw);
}

test "App resize notifies widgets" {
    const allocator = std.testing.allocator;

    var app = try App.init(allocator, AppConfig{});
    defer app.deinit();

    const widget = try TestWidget.init(allocator);
    defer widget.widget.deinit();

    try app.addWidget(&widget.widget);

    widget.last_resize = null;
    app.needs_redraw = false;

    const new_size = Size.init(120, 40);
    try app.resize(new_size);

    try std.testing.expect(app.needs_redraw);
    try std.testing.expect(widget.last_resize != null);
    const expected_rect = Rect.init(0, 0, new_size.width, new_size.height);
    try std.testing.expectEqual(expected_rect, widget.last_resize.?);

    app.removeWidget(&widget.widget);
}
