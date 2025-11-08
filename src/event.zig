//! Event system for Phantom TUI - keyboard, mouse, and system events
const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const types = @import("event/types.zig");

pub const Key = types.Key;
pub const MouseButton = types.MouseButton;
pub const Modifiers = types.Modifiers;
pub const MouseEvent = types.MouseEvent;
pub const SystemEvent = types.SystemEvent;
pub const Event = types.Event;
pub const EventHandler = types.EventHandler;
pub const keyEvent = types.keyEvent;
pub const charEvent = types.charEvent;
pub const mouseClickEvent = types.mouseClickEvent;
pub const mouseReleaseEvent = types.mouseReleaseEvent;
pub const resizeEvent = types.resizeEvent;

const event_queue_mod = @import("event/EventQueue.zig");
const EventQueue = event_queue_mod.EventQueue;
const EventPriority = event_queue_mod.EventPriority;
const zigzag_backend_mod = @import("event/ZigZagBackend.zig");
const ZigZagBackend = zigzag_backend_mod.ZigZagBackend;
const ZigZagBackendConfig = zigzag_backend_mod.Config;
const InputParser = @import("event/InputParser.zig").InputParser;
const phantom_config = @import("phantom_config");
const async_runtime = @import("async/runtime.zig");
const vxfw = @import("vxfw.zig");

/// Async-aware event loop that can leverage the zigzag backend when available.
pub const EventLoop = struct {
    pub const BackendPreference = enum { auto, simple, zigzag };

    pub const Config = struct {
        backend: BackendPreference = .auto,
        tick_interval_ms: u64 = 16,
        frame_budget_ms: ?u32 = null,
        simple: SimpleBackend.Config = .{},
        zigzag: ZigZagBackendConfig = .{},
        trace_overruns: bool = false,
    };

    allocator: std.mem.Allocator,
    handlers: std.ArrayList(EventHandler),
    config: Config,
    tick_interval_ms: u64 = 16,
    tick_interval_ns: u64 = 16 * std.time.ns_per_ms,
    frame_budget_ns: u64 = 16 * std.time.ns_per_ms,
    running: bool = false,
    backend: Backend,
    last_tick_time_ns: u64 = 0,
    metrics: Metrics = .{},

    const Backend = union(enum) {
        simple: SimpleBackend,
        zigzag: *ZigZagBackend,
    };

    pub fn init(allocator: std.mem.Allocator) EventLoop {
        return EventLoop.initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: Config) EventLoop {
        const initial_frame_budget_ns = computeFrameBudgetNs(config, config.tick_interval_ms * std.time.ns_per_ms);

        var loop = EventLoop{
            .allocator = allocator,
            .handlers = std.ArrayList(EventHandler){},
            .config = config,
            .tick_interval_ms = config.tick_interval_ms,
            .tick_interval_ns = config.tick_interval_ms * std.time.ns_per_ms,
            .frame_budget_ns = initial_frame_budget_ns,
            .backend = undefined,
            .metrics = .{ .frame_budget_ns = initial_frame_budget_ns },
        };
        loop.backend = initBackend(allocator, config);
        loop.updateBackendTiming();
        return loop;
    }

    fn initBackend(allocator: std.mem.Allocator, config: Config) Backend {
        const preference = switch (config.backend) {
            .auto => if (phantom_config.use_zigzag_event_loop) BackendPreference.zigzag else BackendPreference.simple,
            else => config.backend,
        };

        if (preference == .zigzag) {
            if (ZigZagBackend.init(allocator, config.zigzag)) |backend_ptr| {
                return Backend{ .zigzag = backend_ptr };
            } else |err| {
                std.log.err("EventLoop: zigzag backend unavailable, using simple backend: {}", .{err});
            }
        }

        return Backend{ .simple = SimpleBackend.init(allocator, config.simple) };
    }

    pub fn deinit(self: *EventLoop) void {
        switch (self.backend) {
            .simple => |*backend| backend.deinit(),
            .zigzag => |backend| backend.deinit(),
        }
        self.handlers.deinit(self.allocator);
    }

    pub fn addHandler(self: *EventLoop, handler: EventHandler) !void {
        try self.handlers.append(self.allocator, handler);
    }

    pub fn removeHandler(self: *EventLoop, handler: EventHandler) void {
        for (self.handlers.items, 0..) |h, i| {
            if (h == handler) {
                _ = self.handlers.swapRemove(i);
                return;
            }
        }
    }

    pub fn backendKind(self: *const EventLoop) BackendPreference {
        return switch (self.backend) {
            .simple => .simple,
            .zigzag => .zigzag,
        };
    }

    pub fn frameBudgetNs(self: *const EventLoop) u64 {
        return self.frame_budget_ns;
    }

    pub fn getMetrics(self: *const EventLoop) Metrics {
        return self.metrics;
    }

    pub fn logMetrics(self: *EventLoop) void {
        const m = self.metrics;
        std.log.info(
            "EventLoop metrics frame_ns={d} budget_ns={d} queue_depth={d} commands={d} dropped={d} peak={d} over_budget={d}",
            .{
                m.last_frame_ns,
                m.frame_budget_ns,
                m.queue_depth,
                m.commands_pending,
                m.dropped_events,
                m.peak_queue_depth,
                m.frames_over_budget,
            },
        );
    }

    pub fn setTickInterval(self: *EventLoop, interval_ms: u64) void {
        self.config.tick_interval_ms = interval_ms;
        self.tick_interval_ms = interval_ms;
        self.tick_interval_ns = interval_ms * std.time.ns_per_ms;
        if (self.config.frame_budget_ms == null) {
            self.frame_budget_ns = computeFrameBudgetNs(self.config, self.tick_interval_ns);
        }
        self.metrics.frame_budget_ns = self.frame_budget_ns;
        self.updateBackendTiming();
    }

    pub fn setFrameBudget(self: *EventLoop, budget_ms: ?u32) void {
        self.config.frame_budget_ms = budget_ms;
        self.frame_budget_ns = computeFrameBudgetNs(self.config, self.tick_interval_ns);
        self.metrics.frame_budget_ns = self.frame_budget_ns;
        self.updateBackendTiming();
    }

    /// Queue an event for asynchronous processing.
    pub fn queueEvent(self: *EventLoop, event: Event, priority: ?EventPriority) !void {
        try self.backendPushEvent(event, priority);
    }

    /// Drain any pending backend commands. Caller must later call releaseCommands.
    pub fn drainCommands(self: *EventLoop) ![]vxfw.Command {
        return try self.backendPopCommands();
    }

    /// Release command slices obtained from drainCommands.
    pub fn releaseCommands(self: *EventLoop, commands: []vxfw.Command) void {
        if (commands.len == 0) return;
        event_queue_mod.destroyCommands(commands, self.allocator);
    }

    /// Start the event loop (blocking)
    pub fn run(self: *EventLoop) !void {
        self.running = true;
        defer self.running = false;

        var timer = try std.time.Timer.start();
        self.last_tick_time_ns = timer.read();

        while (self.running) {
            const frame_start_ns = timer.read();

            const had_backend_activity = try self.backendTick();

            var exit_requested = false;
            while (self.backendPopEvent()) |event| {
                if (try self.dispatchEvent(event)) {
                    exit_requested = true;
                    break;
                }
            }

            if (exit_requested or !self.running) break;

            const after_processing_ns = timer.read();
            const queue_stats = self.backendQueueStats();
            self.refreshMetrics(after_processing_ns - frame_start_ns, queue_stats);
            const tick_due = self.tick_interval_ns == 0 or after_processing_ns - self.last_tick_time_ns >= self.tick_interval_ns;

            if (tick_due) {
                self.last_tick_time_ns = after_processing_ns;
                if (try self.dispatchEvent(Event.fromTick())) {
                    break;
                }
                continue;
            }

            var sleep_ns: ?u64 = null;

            if (!had_backend_activity and self.tick_interval_ns > 0) {
                const elapsed_ns = after_processing_ns - self.last_tick_time_ns;
                if (elapsed_ns < self.tick_interval_ns) {
                    sleep_ns = self.tick_interval_ns - elapsed_ns;
                } else {
                    sleep_ns = 0;
                }
            }

            if (self.frame_budget_ns > 0) {
                const frame_elapsed_ns = after_processing_ns - frame_start_ns;
                if (frame_elapsed_ns < self.frame_budget_ns) {
                    const frame_remaining_ns = self.frame_budget_ns - frame_elapsed_ns;
                    sleep_ns = if (sleep_ns) |existing|
                        std.math.min(existing, frame_remaining_ns)
                    else
                        frame_remaining_ns;
                }
            }

            if (sleep_ns) |ns| {
                if (ns > 0) {
                    const sleep_sec = ns / std.time.ns_per_s;
                    const sleep_sub_ns = @as(u32, @intCast(ns % std.time.ns_per_s));
                    std.posix.nanosleep(sleep_sec, sleep_sub_ns) catch {};
                }
            }
        }
    }

    /// Start the event loop on an async runtime
    pub fn runAsync(self: *EventLoop) !void {
        const runtime = try async_runtime.startGlobal(self.allocator, .{});

        const Runner = struct {
            fn run(loop: *EventLoop) !void {
                try loop.run();
            }
        };

        var task = try runtime.spawn(@TypeOf(Runner.run), .{self});
        defer task.deinit();
        try task.await();
    }

    pub fn stop(self: *EventLoop) void {
        self.running = false;
        switch (self.backend) {
            .simple => |*backend| backend.stop(),
            .zigzag => |backend| backend.stop(),
        }
    }

    fn dispatchEvent(self: *EventLoop, event: Event) !bool {
        for (self.handlers.items) |handler| {
            if (try handler(event)) {
                return true;
            }
        }
        return false;
    }

    fn backendTick(self: *EventLoop) !bool {
        return switch (self.backend) {
            .simple => |*backend| try backend.tick(),
            .zigzag => |backend| try backend.tick(),
        };
    }

    fn backendPopEvent(self: *EventLoop) ?Event {
        return switch (self.backend) {
            .simple => |*backend| backend.popEvent(),
            .zigzag => |backend| backend.popEvent(),
        };
    }

    fn backendPopCommands(self: *EventLoop) ![]vxfw.Command {
        return switch (self.backend) {
            .simple => |*backend| try backend.popCommands(),
            .zigzag => |backend| try backend.popCommands(),
        };
    }

    fn backendQueueStats(self: *EventLoop) event_queue_mod.QueueStats {
        return switch (self.backend) {
            .simple => |*backend| backend.queueStats(),
            .zigzag => |backend| backend.queueStats(),
        };
    }

    fn backendPushEvent(self: *EventLoop, event: Event, priority: ?EventPriority) !void {
        switch (self.backend) {
            .simple => |*backend| {
                if (priority) |p| {
                    try backend.pushEvent(event, p);
                } else {
                    try backend.pushAuto(event);
                }
            },
            .zigzag => |backend| {
                if (priority) |p| {
                    try backend.pushEvent(event, p);
                } else {
                    try backend.pushAuto(event);
                }
            },
        }
    }

    fn updateBackendTiming(self: *EventLoop) void {
        switch (self.backend) {
            .simple => {},
            .zigzag => |backend| {
                if (self.config.frame_budget_ms) |budget_ms| {
                    backend.applyFrameBudget(budget_ms);
                } else {
                    const fps = if (self.tick_interval_ms == 0)
                        240
                    else blk: {
                        const divisor = @max(@as(u64, 1), self.tick_interval_ms);
                        const raw = @divTrunc(@as(u64, 1000), divisor);
                        break :blk @as(u32, @intCast(if (raw == 0) 1 else raw));
                    };
                    backend.setFrameRate(fps);
                    backend.applyFrameBudget(null);
                }
            },
        }
    }

    fn refreshMetrics(self: *EventLoop, frame_duration_ns: u64, stats: event_queue_mod.QueueStats) void {
        self.metrics.last_frame_ns = frame_duration_ns;
        self.metrics.frame_budget_ns = self.frame_budget_ns;
        self.metrics.queue_depth = stats.event_count;
        self.metrics.commands_pending = stats.command_count;
        self.metrics.dropped_events = stats.dropped_events;
        self.metrics.peak_queue_depth = stats.peak_event_count;

        if (self.frame_budget_ns > 0 and frame_duration_ns > self.frame_budget_ns) {
            self.metrics.frames_over_budget += 1;

            if (self.config.trace_overruns) {
                std.log.warn(
                    "EventLoop frame over budget (frame_ns={d}, budget_ns={d}, queue_depth={d}, dropped={d})",
                    .{ frame_duration_ns, self.frame_budget_ns, stats.event_count, stats.dropped_events },
                );
            }
        }
    }

    pub const Metrics = struct {
        last_frame_ns: u64 = 0,
        frame_budget_ns: u64 = 0,
        queue_depth: usize = 0,
        commands_pending: usize = 0,
        dropped_events: u64 = 0,
        peak_queue_depth: usize = 0,
        frames_over_budget: u64 = 0,
    };

    fn computeFrameBudgetNs(config: Config, tick_interval_ns: u64) u64 {
        return if (config.frame_budget_ms) |ms|
            @as(u64, ms) * std.time.ns_per_ms
        else
            tick_interval_ns;
    }
};

const SimpleBackend = struct {
    pub const Config = struct {};

    allocator: std.mem.Allocator,
    queue: EventQueue,
    input_parser: InputParser,
    stdin_fd: std.posix.fd_t,
    stdin_flags_original: ?usize = null,
    read_buffer: [1024]u8 = undefined,
    timer: std.time.Timer,

    fn init(allocator: std.mem.Allocator, config: Config) SimpleBackend {
        _ = config;
        var backend = SimpleBackend{
            .allocator = allocator,
            .queue = EventQueue.init(allocator),
            .input_parser = InputParser.init(),
            .stdin_fd = posix.STDIN_FILENO,
            .timer = std.time.Timer.start() catch unreachable,
        };
        backend.configureStdinNonBlocking() catch |err| {
            std.log.warn("SimpleBackend: failed to set non-blocking stdin: {}", .{err});
        };
        return backend;
    }

    fn deinit(self: *SimpleBackend) void {
        self.restoreStdinFlags();
        self.queue.deinit();
    }

    fn tick(self: *SimpleBackend) !bool {
        var had_input = false;
        had_input = self.pollInput() catch |err| blk: {
            std.log.err("SimpleBackend: input poll error: {}", .{err});
            break :blk false;
        };

        const now_ns = self.timer.read();
        const flushed = self.input_parser.flushPending(&self.queue, null, now_ns) catch |err| blk: {
            std.log.err("SimpleBackend: flush error: {}", .{err});
            break :blk false;
        };

        return had_input or flushed or !self.queue.isEmpty();
    }

    fn popEvent(self: *SimpleBackend) ?Event {
        if (self.queue.popEvent()) |queued| {
            return queued.event;
        }
        return null;
    }

    fn popCommands(self: *SimpleBackend) ![]vxfw.Command {
        return try self.queue.popCommands();
    }

    fn queueStats(self: *SimpleBackend) event_queue_mod.QueueStats {
        return self.queue.getStats();
    }

    fn pushEvent(self: *SimpleBackend, event: Event, priority: EventPriority) !void {
        try self.queue.pushEvent(event, priority);
    }

    fn pushAuto(self: *SimpleBackend, event: Event) !void {
        try self.queue.pushAuto(event);
    }

    fn stop(self: *SimpleBackend) void {
        self.queue.shutdown();
    }

    fn pollInput(self: *SimpleBackend) !bool {
        if (builtin.os.tag == .windows) return false;

        var had_activity = false;

        while (true) {
            const bytes_read = posix.read(self.stdin_fd, &self.read_buffer) catch |err| switch (err) {
                error.Interrupted => continue,
                error.WouldBlock => break,
                error.OperationAborted => break,
                else => return err,
            };

            if (bytes_read == 0) break;

            const now_ns = self.timer.read();
            const produced = try self.input_parser.feedBytes(&self.queue, null, self.read_buffer[0..bytes_read], now_ns);
            had_activity = had_activity or produced;
        }

        return had_activity;
    }

    fn configureStdinNonBlocking(self: *SimpleBackend) !void {
        if (builtin.os.tag == .windows) return;

        const flags = try posix.fcntl(self.stdin_fd, posix.F.GETFL, 0);
        self.stdin_flags_original = @intCast(flags);

        const non_block: usize = @intCast(@intFromEnum(posix.O.NONBLOCK));
        try posix.fcntl(self.stdin_fd, posix.F.SETFL, flags | non_block);
    }

    fn restoreStdinFlags(self: *SimpleBackend) void {
        if (builtin.os.tag == .windows) return;

        if (self.stdin_flags_original) |flags| {
            const result = posix.fcntl(self.stdin_fd, posix.F.SETFL, flags) catch |err| {
                std.log.warn("SimpleBackend: failed to restore stdin flags: {}", .{err});
                return;
            };
            _ = result;
        }
    }
};

// Example event handler used in tests and demos
fn echoHandler(event: Event) !bool {
    switch (event) {
        .key => |key| {
            switch (key) {
                .char => |c| std.debug.print("Key: {c}\n", .{c}),
                .ctrl_c => {
                    std.debug.print("Ctrl+C pressed, exiting\n", .{});
                    return true;
                },
                else => std.debug.print("Special key pressed\n", .{}),
            }
        },
        .mouse => |mouse| {
            std.debug.print(
                "Mouse {} at ({}, {})\n",
                .{ if (mouse.pressed) "press" else "release", mouse.position.x, mouse.position.y },
            );
        },
        .system => |sys| {
            std.debug.print("System event: {}\n", .{sys});
        },
        .tick => {},
    }
    return false;
}

var queue_event_flag = std.atomic.Value(bool).init(false);

fn queueEventHandler(event: Event) !bool {
    switch (event) {
        .system => |sys| {
            if (sys == .resize) {
                queue_event_flag.store(true, .release);
                return true;
            }
        },
        else => {},
    }
    return false;
}

test "EventLoop basic operations" {
    const allocator = std.testing.allocator;
    var event_loop = EventLoop.init(allocator);
    defer event_loop.deinit();

    try event_loop.addHandler(echoHandler);
    try std.testing.expect(event_loop.handlers.items.len == 1);

    event_loop.removeHandler(echoHandler);
    try std.testing.expect(event_loop.handlers.items.len == 0);
}

test "EventLoop respects backend preference" {
    const allocator = std.testing.allocator;
    var event_loop = EventLoop.initWithConfig(allocator, .{ .backend = .simple });
    defer event_loop.deinit();

    try std.testing.expectEqual(EventLoop.BackendPreference.simple, event_loop.backendKind());
}

test "EventLoop frame budget override" {
    const allocator = std.testing.allocator;
    var event_loop = EventLoop.initWithConfig(allocator, .{ .frame_budget_ms = 20 });
    defer event_loop.deinit();

    try std.testing.expectEqual(@as(u64, 20) * std.time.ns_per_ms, event_loop.frameBudgetNs());

    event_loop.setFrameBudget(null);
    try std.testing.expectEqual(
        event_loop.tick_interval_ns,
        event_loop.frameBudgetNs(),
    );
}

test "EventLoop processes queued events" {
    const allocator = std.testing.allocator;
    var event_loop = EventLoop.init(allocator);
    defer event_loop.deinit();

    queue_event_flag.store(false, .release);

    try event_loop.addHandler(queueEventHandler);

    try event_loop.queueEvent(Event.fromSystem(SystemEvent.resize), null);
    try event_loop.run();

    try std.testing.expect(queue_event_flag.load(.acquire));

    const metrics = event_loop.getMetrics();
    try std.testing.expectEqual(@as(usize, 0), metrics.queue_depth);
    try std.testing.expect(metrics.peak_queue_depth >= 1);
}
