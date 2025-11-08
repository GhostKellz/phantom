//! Widget Lifecycle Management - Handles widget initialization, focus, ticks, and cleanup
//! Provides a centralized system for managing widget states and lifecycle events

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");

const Allocator = std.mem.Allocator;
const Rect = geometry.Rect;

const WidgetLifecycle = @This();

/// Widget lifecycle states
pub const LifecycleState = enum {
    uninitialized,
    initialized,
    focused,
    blurred,
    destroyed,
};

/// Widget lifecycle event types
pub const LifecycleEvent = union(enum) {
    init: InitEvent,
    focus_gained: FocusEvent,
    focus_lost: FocusEvent,
    tick: TickEvent,
    resize: ResizeEvent,
    destroy: DestroyEvent,
};

/// Initialization event data
pub const InitEvent = struct {
    initial_bounds: Rect,
    allocator: Allocator,
};

/// Focus event data
pub const FocusEvent = struct {
    previous_widget: ?vxfw.Widget = null,
    reason: FocusReason = .user_action,

    pub const FocusReason = enum {
        user_action,
        tab_navigation,
        mouse_click,
        programmatic,
    };
};

/// Timer tick event data
pub const TickEvent = struct {
    timestamp_ms: i64,
    delta_ms: u32,
    tick_id: u32,
};

/// Resize event data
pub const ResizeEvent = struct {
    old_bounds: Rect,
    new_bounds: Rect,
};

/// Destruction event data
pub const DestroyEvent = struct {
    reason: DestroyReason = .parent_destroyed,

    pub const DestroyReason = enum {
        parent_destroyed,
        explicitly_removed,
        app_shutdown,
    };
};

/// Widget lifecycle manager - tracks multiple widgets
pub const LifecycleManager = struct {
    allocator: Allocator,
    widgets: std.array_list.AlignedManaged(ManagedWidget, null),
    focused_widget: ?vxfw.Widget = null,
    next_tick_id: u32 = 1,
    tick_timers: std.array_list.AlignedManaged(TickTimer, null),
    timer: std.time.Timer,

    const ManagedWidget = struct {
        widget: vxfw.Widget,
        state: LifecycleState = .uninitialized,
        bounds: Rect = Rect.init(0, 0, 0, 0),
        can_focus: bool = false,
        tick_interval_ms: ?u32 = null,
        last_tick_ms: i64 = 0,
    };

    const TickTimer = struct {
        widget: vxfw.Widget,
        tick_id: u32,
        interval_ms: u32,
        last_fire_ms: i64,
    };

    pub fn init(allocator: Allocator) !LifecycleManager {
        return LifecycleManager{
            .allocator = allocator,
            .widgets = std.array_list.AlignedManaged(ManagedWidget, null).init(allocator),
            .tick_timers = std.array_list.AlignedManaged(TickTimer, null).init(allocator),
            .timer = try std.time.Timer.start(),
        };
    }

    pub fn deinit(self: *LifecycleManager) void {
        // Destroy all widgets before cleanup
        for (self.widgets.items) |*managed| {
            self.destroyWidget(managed.widget, .app_shutdown) catch {};
        }
        self.widgets.deinit();
        self.tick_timers.deinit();
    }

    /// Register a widget with the lifecycle manager
    pub fn registerWidget(
        self: *LifecycleManager,
        widget: vxfw.Widget,
        initial_bounds: Rect,
        can_focus: bool
    ) !void {
        const managed = ManagedWidget{
            .widget = widget,
            .state = .uninitialized,
            .bounds = initial_bounds,
            .can_focus = can_focus,
        };
        try self.widgets.append(self.allocator, managed);
    }

    /// Initialize a widget (sends init lifecycle event)
    pub fn initializeWidget(
        self: *LifecycleManager,
        widget: vxfw.Widget,
        bounds: Rect
    ) !void {
        if (self.findManagedWidget(widget)) |managed| {
            if (managed.state == .uninitialized) {
                managed.state = .initialized;
                managed.bounds = bounds;

                const init_event = LifecycleEvent{
                    .init = InitEvent{
                        .initial_bounds = bounds,
                        .allocator = self.allocator,
                    },
                };

                try self.sendLifecycleEvent(widget, init_event);
            }
        }
    }

    /// Set focus to a specific widget
    pub fn setFocus(self: *LifecycleManager, widget: ?vxfw.Widget) !void {
        const previous_widget = self.focused_widget;

        // Send focus lost event to previous widget
        if (previous_widget) |prev| {
            if (self.findManagedWidget(prev)) |managed| {
                if (managed.state == .focused) {
                    managed.state = .initialized;

                    const focus_lost_event = LifecycleEvent{
                        .focus_lost = FocusEvent{
                            .previous_widget = widget,
                            .reason = .user_action,
                        },
                    };

                    try self.sendLifecycleEvent(prev, focus_lost_event);
                }
            }
        }

        self.focused_widget = widget;

        // Send focus gained event to new widget
        if (widget) |new_widget| {
            if (self.findManagedWidget(new_widget)) |managed| {
                if (managed.can_focus and managed.state == .initialized) {
                    managed.state = .focused;

                    const focus_gained_event = LifecycleEvent{
                        .focus_gained = FocusEvent{
                            .previous_widget = previous_widget,
                            .reason = .user_action,
                        },
                    };

                    try self.sendLifecycleEvent(new_widget, focus_gained_event);
                }
            }
        }
    }

    /// Schedule periodic tick events for a widget
    pub fn scheduleTickEvents(
        self: *LifecycleManager,
        widget: vxfw.Widget,
        interval_ms: u32
    ) !u32 {
        const tick_id = self.next_tick_id;
        self.next_tick_id += 1;

        const timer = TickTimer{
            .widget = widget,
            .tick_id = tick_id,
            .interval_ms = interval_ms,
            .last_fire_ms = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms)),
        };

        try self.tick_timers.append(self.allocator, timer);

        // Update managed widget tick interval
        if (self.findManagedWidget(widget)) |managed| {
            managed.tick_interval_ms = interval_ms;
        }

        return tick_id;
    }

    /// Process tick events and send to widgets that need them
    pub fn processTicks(self: *LifecycleManager) !void {
        const now_ms = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));

        for (self.tick_timers.items) |*timer| {
            if (now_ms - timer.last_fire_ms >= timer.interval_ms) {
                const delta_ms: u32 = @intCast(now_ms - timer.last_fire_ms);
                timer.last_fire_ms = now_ms;

                const tick_event = LifecycleEvent{
                    .tick = TickEvent{
                        .timestamp_ms = now_ms,
                        .delta_ms = delta_ms,
                        .tick_id = timer.tick_id,
                    },
                };

                try self.sendLifecycleEvent(timer.widget, tick_event);
            }
        }
    }

    /// Resize a widget (sends resize lifecycle event)
    pub fn resizeWidget(
        self: *LifecycleManager,
        widget: vxfw.Widget,
        new_bounds: Rect
    ) !void {
        if (self.findManagedWidget(widget)) |managed| {
            const old_bounds = managed.bounds;
            managed.bounds = new_bounds;

            const resize_event = LifecycleEvent{
                .resize = ResizeEvent{
                    .old_bounds = old_bounds,
                    .new_bounds = new_bounds,
                },
            };

            try self.sendLifecycleEvent(widget, resize_event);
        }
    }

    /// Destroy a widget (sends destroy lifecycle event and removes from management)
    pub fn destroyWidget(
        self: *LifecycleManager,
        widget: vxfw.Widget,
        reason: DestroyEvent.DestroyReason
    ) !void {
        // Remove focus if this widget has it
        if (self.focused_widget) |focused| {
            if (std.meta.eql(focused, widget)) {
                try self.setFocus(null);
            }
        }

        // Send destroy event
        const destroy_event = LifecycleEvent{
            .destroy = DestroyEvent{ .reason = reason },
        };
        try self.sendLifecycleEvent(widget, destroy_event);

        // Remove from managed widgets
        for (self.widgets.items, 0..) |managed, i| {
            if (std.meta.eql(managed.widget, widget)) {
                _ = self.widgets.swapRemove(i);
                break;
            }
        }

        // Remove any tick timers for this widget
        var i: usize = 0;
        while (i < self.tick_timers.items.len) {
            if (std.meta.eql(self.tick_timers.items[i].widget, widget)) {
                _ = self.tick_timers.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Get the current focus state
    pub fn getFocusedWidget(self: *const LifecycleManager) ?vxfw.Widget {
        return self.focused_widget;
    }

    /// Check if a widget has focus
    pub fn hasFocus(self: *const LifecycleManager, widget: vxfw.Widget) bool {
        if (self.focused_widget) |focused| {
            return std.meta.eql(focused, widget);
        }
        return false;
    }

    /// Find a managed widget by widget reference
    fn findManagedWidget(self: *LifecycleManager, widget: vxfw.Widget) ?*ManagedWidget {
        for (self.widgets.items) |*managed| {
            if (std.meta.eql(managed.widget, widget)) {
                return managed;
            }
        }
        return null;
    }

    /// Send a lifecycle event to a widget
    fn sendLifecycleEvent(
        self: *LifecycleManager,
        widget: vxfw.Widget,
        event: LifecycleEvent
    ) !void {
        // Convert lifecycle event to vxfw.Event and send to widget
        const vxfw_event = switch (event) {
            .init => vxfw.Event.init,
            .tick => vxfw.Event.tick,
            .focus_gained => vxfw.Event.focus_in,
            .focus_lost => vxfw.Event.focus_out,
            .resize => vxfw.Event{ .winsize = event.resize.new_bounds.size() },
            .destroy => vxfw.Event.focus_out, // No specific destroy event in vxfw.Event
        };

        // Create event context for the widget
        const bounds = if (self.findManagedWidget(widget)) |managed| managed.bounds else Rect.init(0, 0, 0, 0);
        const event_ctx = vxfw.EventContext.init(
            vxfw_event,
            self.allocator,
            bounds
        );

        // Send event to widget
        const commands = try widget.handleEvent(event_ctx);

        // Process any commands returned by the widget
        for (commands.items) |command| {
            try self.processCommand(widget, command);
        }
    }

    /// Process commands returned by widgets
    fn processCommand(
        self: *LifecycleManager,
        widget: vxfw.Widget,
        command: vxfw.Command
    ) !void {
        switch (command) {
            .request_focus => |focus_widget| {
                try self.setFocus(focus_widget);
            },
            .tick => |tick| {
                // Schedule a one-time tick event
                const delay: u32 = @intCast(@max(0, tick.deadline_ms - @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms))));
                _ = try self.scheduleTickEvents(tick.widget, delay);
            },
            else => {
                // Other commands would be handled by the application layer
                _ = widget; // Suppress unused variable warning
            },
        }
    }
};

test "Widget lifecycle management" {
    var lifecycle = try LifecycleManager.init(std.testing.allocator);
    defer lifecycle.deinit();

    // Create a test widget
    const TestWidget = struct {
        value: u32,

        const Self = @This();

        pub fn widget(self: *Self) vxfw.Widget {
            return .{
                .userdata = self,
                .drawFn = drawFn,
                .eventHandlerFn = handleEvent,
            };
        }

        fn drawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
            _ = ptr;
            return vxfw.Surface.initArena(ctx.arena, undefined, ctx.min);
        }

        fn handleEvent(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
            _ = ptr;
            return vxfw.CommandList.init(ctx.arena);
        }
    };

    var test_widget = TestWidget{ .value = 42 };
    const widget = test_widget.widget();

    const bounds = Rect.init(10, 10, 50, 20);

    // Test widget registration and initialization
    try lifecycle.registerWidget(widget, bounds, true);
    try lifecycle.initializeWidget(widget, bounds);

    // Test focus management
    try lifecycle.setFocus(widget);
    try std.testing.expect(lifecycle.hasFocus(widget));

    try lifecycle.setFocus(null);
    try std.testing.expect(!lifecycle.hasFocus(widget));

    // Test tick scheduling
    const tick_id = try lifecycle.scheduleTickEvents(widget, 100);
    try std.testing.expect(tick_id > 0);

    // Test widget destruction
    try lifecycle.destroyWidget(widget, .explicitly_removed);
    try std.testing.expect(!lifecycle.hasFocus(widget));
}