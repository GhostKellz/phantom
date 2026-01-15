//! Loop - Advanced event loop implementation for vxfw applications
//! Provides high-performance, feature-rich event loop with scheduling and lifecycle management

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const EventQueue = @import("EventQueue.zig").EventQueue;
const QueuedEvent = @import("EventQueue.zig").QueuedEvent;
const EventPriority = @import("EventQueue.zig").EventPriority;

const Allocator = std.mem.Allocator;

/// Advanced event loop for vxfw applications
pub const EventLoop = struct {
    allocator: Allocator,
    event_queue: EventQueue,
    root_widget: ?vxfw.Widget = null,
    is_running: bool = false,
    should_exit: bool = false,
    frame_rate_target: u32 = 60, // Target FPS
    frame_time_budget_ms: u32 = 16, // ~60 FPS (1000/60)

    // Performance metrics
    frame_count: u64 = 0,
    last_fps_time: i64 = 0,
    current_fps: f32 = 0.0,

    // Scheduling
    tick_scheduler: TickScheduler,
    timer_manager: TimerManager,

    // Lifecycle hooks
    pre_frame_hooks: std.array_list.AlignedManaged(FrameHook, null),
    post_frame_hooks: std.array_list.AlignedManaged(FrameHook, null),

    // Input handling
    input_processor: InputProcessor,

    // Rendering optimization
    needs_full_redraw: bool = true,
    last_render_time: i64 = 0,
    render_budget_ms: u32 = 12, // Leave 4ms for event processing

    // Timer for consistent timing
    timer: std.time.Timer,

    pub fn init(allocator: Allocator) !EventLoop {
        return EventLoop{
            .allocator = allocator,
            .event_queue = EventQueue.init(allocator),
            .tick_scheduler = TickScheduler.init(allocator),
            .timer_manager = TimerManager.init(allocator),
            .pre_frame_hooks = std.array_list.AlignedManaged(FrameHook, null).init(allocator),
            .post_frame_hooks = std.array_list.AlignedManaged(FrameHook, null).init(allocator),
            .input_processor = InputProcessor.init(allocator),
            .timer = try std.time.Timer.start(),
        };
    }

    pub fn deinit(self: *EventLoop) void {
        self.event_queue.deinit();
        self.tick_scheduler.deinit();
        self.timer_manager.deinit();
        self.pre_frame_hooks.deinit();
        self.post_frame_hooks.deinit();
        self.input_processor.deinit();
    }

    /// Set the root widget for the application
    pub fn setRootWidget(self: *EventLoop, widget: vxfw.Widget) void {
        self.root_widget = widget;
    }

    /// Set target frame rate
    pub fn setFrameRate(self: *EventLoop, fps: u32) void {
        self.frame_rate_target = fps;
        self.frame_time_budget_ms = if (fps > 0) 1000 / fps else 16;
        self.render_budget_ms = (self.frame_time_budget_ms * 3) / 4; // 75% for rendering
    }

    /// Add pre-frame hook
    pub fn addPreFrameHook(self: *EventLoop, hook: FrameHook) !void {
        try self.pre_frame_hooks.append(hook);
    }

    /// Add post-frame hook
    pub fn addPostFrameHook(self: *EventLoop, hook: FrameHook) !void {
        try self.post_frame_hooks.append(hook);
    }

    /// Schedule a tick event
    pub fn scheduleTick(self: *EventLoop, widget: vxfw.Widget, delay_ms: u32) !void {
        try self.tick_scheduler.schedule(widget, delay_ms, &self.timer);
    }

    /// Schedule a recurring timer
    pub fn scheduleTimer(self: *EventLoop, name: []const u8, interval_ms: u32, callback: TimerCallback) !void {
        try self.timer_manager.addTimer(name, interval_ms, callback, true);
    }

    /// Schedule a one-shot timer
    pub fn scheduleTimeout(self: *EventLoop, name: []const u8, delay_ms: u32, callback: TimerCallback) !void {
        try self.timer_manager.addTimer(name, delay_ms, callback, false);
    }

    /// Push an event to the queue
    pub fn pushEvent(self: *EventLoop, event: vxfw.Event) !void {
        const priority = EventPriority.fromEvent(event);
        try self.event_queue.pushEvent(event, priority);
    }

    /// Request a full redraw
    pub fn requestRedraw(self: *EventLoop) void {
        self.needs_full_redraw = true;
    }

    /// Run the event loop
    pub fn run(self: *EventLoop) !void {
        if (self.root_widget == null) {
            return LoopError.NoRootWidget;
        }

        self.is_running = true;
        defer self.is_running = false;

        // Initialize timing
        self.timer.reset();
        self.last_fps_time = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));

        // Send init event to root widget
        try self.pushEvent(vxfw.Event.init);

        while (!self.should_exit) {
            const frame_start = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));

            // Process frame
            try self.processFrame();

            // Calculate frame timing
            const frame_end = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));
            const frame_duration = frame_end - frame_start;

            // Sleep if we finished early
            if (frame_duration < self.frame_time_budget_ms) {
                const sleep_ms = self.frame_time_budget_ms - @as(u32, @intCast(frame_duration));
                const ts = std.c.timespec{ .sec = 0, .nsec = @intCast(sleep_ms * 1000000) };
                _ = std.c.nanosleep(&ts, null); // Convert to nanoseconds
            }

            // Update performance metrics
            self.updatePerformanceMetrics(frame_end);
        }
    }

    /// Stop the event loop
    pub fn stop(self: *EventLoop) void {
        self.should_exit = true;
        self.event_queue.shutdown();
    }

    /// Process a single frame
    fn processFrame(self: *EventLoop) !void {
        const frame_start = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));

        // Run pre-frame hooks
        for (self.pre_frame_hooks.items) |hook| {
            try hook.callback(self, hook.userdata);
        }

        // Process scheduled ticks
        try self.tick_scheduler.processTicks(&self.event_queue, &self.timer);

        // Process timers
        try self.timer_manager.processTimers();

        // Process events with time budget
        try self.processEvents(frame_start);

        // Render if needed
        if (self.shouldRender()) {
            try self.render();
            self.last_render_time = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));
        }

        // Run post-frame hooks
        for (self.post_frame_hooks.items) |hook| {
            try hook.callback(self, hook.userdata);
        }

        self.frame_count += 1;
    }

    /// Process events within time budget
    fn processEvents(self: *EventLoop, frame_start: i64) !void {
        const event_budget_ms = self.frame_time_budget_ms - self.render_budget_ms;

        while (true) {
            const elapsed = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms)) - frame_start;
            if (elapsed >= event_budget_ms) break;

            const event = self.event_queue.popEvent() orelse break;
            defer event.deinit(self.allocator);

            try self.processEvent(event.event);
        }
    }

    /// Process a single event
    fn processEvent(self: *EventLoop, event: vxfw.Event) !void {
        // Pre-process input events
        const processed_event = try self.input_processor.processEvent(event);

        // Handle system events
        switch (processed_event) {
            .winsize => |size| {
                // Handle window resize
                _ = size;
                self.requestRedraw();
            },
            .key_press => |key| {
                // Handle global key commands
                if (key.key == .escape and key.mods.ctrl) {
                    self.stop();
                    return;
                }
            },
            else => {},
        }

        // Send to root widget
        if (self.root_widget) |root| {
            const arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();

            const bounds = vxfw.Rect.init(0, 0, 80, 24); // Default size
            const ctx = vxfw.EventContext.init(processed_event, arena.allocator(), bounds);

            const commands = try root.handleEvent(ctx);
            defer arena.allocator().free(commands.items);

            // Process returned commands
            for (commands.items) |command| {
                try self.processCommand(command);
            }
        }
    }

    /// Process a command from widget
    fn processCommand(self: *EventLoop, command: vxfw.Command) !void {
        switch (command) {
            .tick => |tick| {
                const now = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));
                try self.tick_scheduler.schedule(tick.widget, @as(u32, @intCast(tick.deadline_ms - now)), &self.timer);
            },
            .request_focus => |widget| {
                // Focus management: Store focused widget for future keyboard routing
                // Currently, focus is handled implicitly by widget event handlers
                // Full tab-order and focus ring implementation planned for v0.9.0
                _ = widget;
                self.requestRedraw();
            },
            .queue_refresh => {
                self.requestRedraw();
            },
            .redraw => {
                self.requestRedraw();
            },
            else => {
                // Queue command for external processing
                try self.event_queue.pushCommand(command);
            },
        }
    }

    /// Check if rendering is needed
    fn shouldRender(self: *EventLoop) bool {
        if (self.needs_full_redraw) return true;

        // Render at target frame rate if needed
        const now = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));
        const elapsed = now - self.last_render_time;
        return elapsed >= self.frame_time_budget_ms;
    }

    /// Render the application
    fn render(self: *EventLoop) !void {
        if (self.root_widget) |root| {
            const arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();

            const size = vxfw.Size.init(80, 24); // Default size
            const ctx = vxfw.DrawContext.init(arena.allocator(), size, size, size);

            const surface = try root.draw(ctx);
            // Surface rendering: Requires terminal backend integration
            // Current implementation uses direct widget.render() calls in App.zig
            // Full surface-based rendering pipeline planned for v0.9.0
            _ = surface;

            self.needs_full_redraw = false;
        }
    }

    /// Update performance metrics
    fn updatePerformanceMetrics(self: *EventLoop, current_time: i64) void {
        const elapsed = current_time - self.last_fps_time;
        if (elapsed >= 1000) { // Update FPS every second
            self.current_fps = @as(f32, @floatFromInt(self.frame_count * 1000)) / @as(f32, @floatFromInt(elapsed));
            self.last_fps_time = current_time;
            self.frame_count = 0;
        }
    }

    /// Get current FPS
    pub fn getFPS(self: *const EventLoop) f32 {
        return self.current_fps;
    }

    /// Get performance statistics
    pub fn getStats(self: *const EventLoop) LoopStats {
        return LoopStats{
            .fps = self.current_fps,
            .frame_count = self.frame_count,
            .is_running = self.is_running,
            .queue_size = self.event_queue.size(),
            .command_queue_size = self.event_queue.commandSize(),
            .pending_ticks = self.tick_scheduler.getPendingCount(),
            .active_timers = self.timer_manager.getActiveCount(),
        };
    }
};

/// Tick scheduler for widget tick events
const TickScheduler = struct {
    allocator: Allocator,
    pending_ticks: std.PriorityQueue(ScheduledTick, void, ScheduledTick.lessThan),

    const ScheduledTick = struct {
        widget: vxfw.Widget,
        deadline_ms: i64,

        fn lessThan(context: void, a: ScheduledTick, b: ScheduledTick) std.math.Order {
            _ = context;
            return std.math.order(a.deadline_ms, b.deadline_ms);
        }
    };

    fn init(allocator: Allocator) TickScheduler {
        return TickScheduler{
            .allocator = allocator,
            .pending_ticks = std.PriorityQueue(ScheduledTick, void, ScheduledTick.lessThan).init(allocator, {}),
        };
    }

    fn deinit(self: *TickScheduler) void {
        self.pending_ticks.deinit();
    }

    fn schedule(self: *TickScheduler, widget: vxfw.Widget, delay_ms: u32, timer: *std.time.Timer) !void {
        const now = @as(i64, @intCast(timer.read() / std.time.ns_per_ms));
        const deadline = now + delay_ms;
        try self.pending_ticks.add(ScheduledTick{
            .widget = widget,
            .deadline_ms = deadline,
        });
    }

    fn processTicks(self: *TickScheduler, event_queue: *EventQueue, timer: *std.time.Timer) !void {
        const now = @as(i64, @intCast(timer.read() / std.time.ns_per_ms));

        while (self.pending_ticks.peek()) |tick| {
            if (tick.deadline_ms > now) break;

            _ = self.pending_ticks.remove();
            try event_queue.pushEvent(vxfw.Event.tick, .normal);
        }
    }

    fn getPendingCount(self: *const TickScheduler) usize {
        return self.pending_ticks.count();
    }
};

/// Timer manager for recurring and one-shot timers
const TimerManager = struct {
    allocator: Allocator,
    timers: std.array_list.AlignedManaged(Timer, null),
    timer: std.time.Timer,

    const Timer = struct {
        name: []u8,
        interval_ms: u32,
        last_fire: i64,
        callback: TimerCallback,
        recurring: bool,
        active: bool = true,
    };

    fn init(allocator: Allocator) TimerManager {
        return TimerManager{
            .allocator = allocator,
            .timers = std.array_list.AlignedManaged(Timer, null).init(allocator),
            .timer = std.time.Timer.start() catch unreachable,
        };
    }

    fn deinit(self: *TimerManager) void {
        for (self.timers.items) |*timer| {
            self.allocator.free(timer.name);
        }
        self.timers.deinit();
    }

    fn addTimer(self: *TimerManager, name: []const u8, interval_ms: u32, callback: TimerCallback, recurring: bool) !void {
        const now = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));
        const timer = Timer{
            .name = try self.allocator.dupe(u8, name),
            .interval_ms = interval_ms,
            .last_fire = now,
            .callback = callback,
            .recurring = recurring,
        };
        try self.timers.append(timer);
    }

    fn processTimers(self: *TimerManager) !void {
        const now = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));

        var i: usize = 0;
        while (i < self.timers.items.len) {
            const timer = &self.timers.items[i];

            if (!timer.active) {
                self.allocator.free(timer.name);
                _ = self.timers.orderedRemove(i);
                continue;
            }

            if (now - timer.last_fire >= timer.interval_ms) {
                try timer.callback.fire();
                timer.last_fire = now;

                if (!timer.recurring) {
                    timer.active = false;
                }
            }

            i += 1;
        }
    }

    fn removeTimer(self: *TimerManager, name: []const u8) void {
        for (self.timers.items) |*timer| {
            if (std.mem.eql(u8, timer.name, name)) {
                timer.active = false;
                break;
            }
        }
    }

    fn getActiveCount(self: *const TimerManager) usize {
        var count: usize = 0;
        for (self.timers.items) |timer| {
            if (timer.active) count += 1;
        }
        return count;
    }
};

/// Input processor for handling and transforming input events
const InputProcessor = struct {
    allocator: Allocator,
    key_repeat_delay_ms: u32 = 500,
    key_repeat_rate_ms: u32 = 50,
    last_key_time: i64 = 0,
    last_key: ?vxfw.Key = null,
    timer: std.time.Timer,

    fn init(allocator: Allocator) InputProcessor {
        return InputProcessor{
            .allocator = allocator,
            .timer = std.time.Timer.start() catch unreachable,
        };
    }

    fn deinit(self: *InputProcessor) void {
        _ = self;
    }

    fn processEvent(self: *InputProcessor, event: vxfw.Event) !vxfw.Event {
        switch (event) {
            .key_press => |key| {
                const now = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));

                // Handle key repeat
                if (self.last_key) |last| {
                    if (std.meta.eql(last.key, key.key) and std.meta.eql(last.mods, key.mods)) {
                        const elapsed = now - self.last_key_time;
                        if (elapsed < self.key_repeat_delay_ms) {
                            // Ignore rapid repeats within delay period
                            return event;
                        }
                    }
                }

                self.last_key = key;
                self.last_key_time = now;
            },
            else => {},
        }

        return event;
    }
};

/// Frame hook for custom processing
pub const FrameHook = struct {
    callback: *const fn (*EventLoop, ?*anyopaque) anyerror!void,
    userdata: ?*anyopaque = null,

    pub fn init(callback: *const fn (*EventLoop, ?*anyopaque) anyerror!void, userdata: ?*anyopaque) FrameHook {
        return FrameHook{
            .callback = callback,
            .userdata = userdata,
        };
    }
};

/// Timer callback interface
pub const TimerCallback = struct {
    fire_fn: *const fn (*TimerCallback) anyerror!void,
    userdata: ?*anyopaque = null,

    pub fn init(fire_fn: *const fn (*TimerCallback) anyerror!void, userdata: ?*anyopaque) TimerCallback {
        return TimerCallback{
            .fire_fn = fire_fn,
            .userdata = userdata,
        };
    }

    pub fn fire(self: *TimerCallback) !void {
        try self.fire_fn(self);
    }
};

/// Performance statistics
pub const LoopStats = struct {
    fps: f32,
    frame_count: u64,
    is_running: bool,
    queue_size: usize,
    command_queue_size: usize,
    pending_ticks: usize,
    active_timers: usize,
};

/// Loop errors
pub const LoopError = error{
    NoRootWidget,
    InvalidFrameRate,
    SchedulingError,
};

test "EventLoop basic functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var loop = try EventLoop.init(arena.allocator());
    defer loop.deinit();

    // Test initial state
    try std.testing.expect(!loop.is_running);
    try std.testing.expectEqual(@as(u32, 60), loop.frame_rate_target);
    try std.testing.expectEqual(@as(f32, 0.0), loop.getFPS());

    // Test frame rate setting
    loop.setFrameRate(30);
    try std.testing.expectEqual(@as(u32, 30), loop.frame_rate_target);
    try std.testing.expectEqual(@as(u32, 33), loop.frame_time_budget_ms); // 1000/30 ≈ 33
}

test "TickScheduler functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var scheduler = TickScheduler.init(arena.allocator());
    defer scheduler.deinit();

    const dummy_widget = vxfw.Widget{
        .userdata = undefined,
        .drawFn = undefined,
    };

    // Test scheduling
    try scheduler.schedule(dummy_widget, 100);
    try std.testing.expectEqual(@as(usize, 1), scheduler.getPendingCount());
}

test "TimerManager functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var manager = TimerManager.init(arena.allocator());
    defer manager.deinit();

    const test_callback = TimerCallback.init(struct {
        fn testTimerFire(callback: *TimerCallback) !void {
            _ = callback;
            // Test timer fired
        }
    }.testTimerFire, null);

    try manager.addTimer("test", 100, test_callback, false);
    try std.testing.expectEqual(@as(usize, 1), manager.getActiveCount());
}