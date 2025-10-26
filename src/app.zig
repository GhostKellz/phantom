//! Main application structure for Phantom TUI
const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const EventLoop = @import("event.zig").EventLoop;
const Event = @import("event.zig").Event;
const geometry = @import("geometry.zig");
const style = @import("style.zig");
const widget_mod = @import("widget.zig");

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
    widgets: std.ArrayList(*Widget),

    pub fn init(allocator: std.mem.Allocator, config: AppConfig) !App {
        const terminal = try Terminal.init(allocator);
        var event_loop = EventLoop.init(allocator);

        event_loop.setTickInterval(config.tick_rate_ms);

        return App{
            .allocator = allocator,
            .terminal = terminal,
            .event_loop = event_loop,
            .config = config,
            .widgets = .{},
        };
    }

    pub fn deinit(self: *App) void {
        self.widgets.deinit(self.allocator);
        self.event_loop.deinit();
        self.terminal.deinit();
    }

    /// Add a widget to the application
    pub fn addWidget(self: *App, widget: *Widget) !void {
        try self.widgets.append(self.allocator, widget);
        self.needs_redraw = true;
    }

    /// Remove a widget from the application
    pub fn removeWidget(self: *App, widget: *Widget) void {
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

        // Add app event handler
        try self.event_loop.addHandler(appEventHandler);

        // Set up context for event handler (simplified)
        app_context = self;

        self.running = true;
        try self.event_loop.run();
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
        if (!self.needs_redraw) return;

        try self.terminal.clear();
        const buffer = self.terminal.getBackBuffer();

        // Calculate layout and render widgets
        const area = Rect.init(0, 0, self.terminal.size.width, self.terminal.size.height);

        for (self.widgets.items) |widget| {
            widget.render(buffer, area);
        }

        try self.terminal.flush();
        self.needs_redraw = false;
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

    return false;
}

test "App initialization" {
    const allocator = std.testing.allocator;

    var app = try App.init(allocator, AppConfig{});
    defer app.deinit();

    try std.testing.expect(!app.running);
    try std.testing.expect(app.needs_redraw);
}
