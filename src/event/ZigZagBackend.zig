//! ZigZag Event Loop Backend for Phantom
//! High-performance event loop using zigzag (io_uring/kqueue/IOCP)
//! Optional backend - can be enabled with -Devent_loop=zigzag

const std = @import("std");
const ArrayList = std.array_list.Managed;
const builtin = @import("builtin");
const posix = std.posix;
const zigzag = @import("zigzag");

const ZigZagCoalescingConfig = std.meta.Child(@FieldType(zigzag.Options, "coalescing"));
const types = @import("types.zig");
const vxfw = @import("../vxfw.zig");
const EventQueue = @import("EventQueue.zig").EventQueue;
const EventPriority = @import("EventQueue.zig").EventPriority;
const EventCoalescer = @import("EventCoalescer.zig").EventCoalescer;
const CoalescingConfig = @import("EventCoalescer.zig").CoalescingConfig;
const InputParser = @import("InputParser.zig").InputParser;

const Event = types.Event;

fn toZigZagCoalescing(config: CoalescingConfig) ZigZagCoalescingConfig {
    const debounce_ms = @max(config.resize_debounce_ms, config.mouse_move_debounce_ms);
    const bounded_debounce = if (debounce_ms == 0) @as(u32, 1) else debounce_ms;
    const batch_size: usize = if (config.coalesce_mouse_move) 64 else 16;

    return ZigZagCoalescingConfig{
        .coalesce_resize = config.coalesce_resize,
        .max_coalesce_time_ms = bounded_debounce,
        .max_batch_size = batch_size,
    };
}

pub const Config = struct {
    max_events: u16 = 1024,
    coalescing: CoalescingConfig = .{},
    frame_budget_ms: ?u32 = null,
};

pub const ZigZagBackend = struct {
    allocator: std.mem.Allocator,
    loop: zigzag.EventLoop,
    event_queue: EventQueue,
    coalescer: EventCoalescer,
    input_parser: InputParser,

    // Terminal file descriptors
    stdin_fd: std.posix.fd_t,
    stdin_watch: ?*zigzag.Watch = null,
    stdin_flags_original: ?usize = null,
    has_pending_input: bool = false,

    // Frame timing
    timer: std.time.Timer,
    frame_rate_target: u32 = 60,
    last_frame_time: u64 = 0,
    frame_budget_ms: u32 = 16, // ~60 FPS (1000/60)

    // Stop mechanism
    should_stop: bool = false,

    // Parse buffer for terminal input
    parse_buffer: [4096]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, config: Config) !*ZigZagBackend {
        const self = try allocator.create(ZigZagBackend);
        errdefer allocator.destroy(self);

        // Initialize zigzag loop with coalescing
        const coalescing_config: ?ZigZagCoalescingConfig = if (config.coalescing.coalesce_resize or config.coalescing.coalesce_mouse_move)
            toZigZagCoalescing(config.coalescing)
        else
            null;

        var loop = try zigzag.EventLoop.init(allocator, .{
            .max_events = config.max_events,
            .coalescing = coalescing_config,
        });
        errdefer loop.deinit();

        const initial_budget_ms: u32 = config.frame_budget_ms orelse 16;
        const initial_rate: u32 = if (config.frame_budget_ms) |ms|
            if (ms == 0) 0 else @max(@as(u32, @intCast(@divTrunc(1000, ms))), 1)
        else
            60;

        self.* = ZigZagBackend{
            .allocator = allocator,
            .loop = loop,
            .event_queue = EventQueue.init(allocator),
            .coalescer = EventCoalescer.initWithConfig(allocator, config.coalescing),
            .input_parser = InputParser.init(),
            .stdin_fd = posix.STDIN_FILENO,
            .timer = try std.time.Timer.start(),
            .frame_rate_target = initial_rate,
            .frame_budget_ms = initial_budget_ms,
        };

        self.configureStdinNonBlocking() catch |err| {
            std.log.warn("ZigZagBackend: failed to set non-blocking stdin: {}", .{err});
        };

        return self;
    }

    pub fn deinit(self: *ZigZagBackend) void {
        self.restoreStdinFlags();
        self.loop.deinit();
        self.event_queue.deinit();
        self.coalescer.deinit();
        self.allocator.destroy(self);
    }

    /// Register stdin for reading terminal input
    pub fn registerStdin(self: *ZigZagBackend) !void {
        // Add stdin to zigzag event loop
        const watch = try self.loop.addFd(
            self.stdin_fd,
            .{ .read = true },
            stdinCallback,
            self,
        );
        self.stdin_watch = watch;
    }

    /// Unregister stdin
    pub fn unregisterStdin(self: *ZigZagBackend) void {
        if (self.stdin_watch) |watch| {
            self.loop.removeFd(watch);
            self.stdin_watch = null;
        }
    }

    /// Run one iteration of the event loop
    pub fn tick(self: *ZigZagBackend) !bool {
        const frame_start = self.timer.read() / std.time.ns_per_ms;

        // Poll zigzag for I/O events
        var zigzag_events: [64]zigzag.Event = undefined;
        const timeout_ms = self.calculatePollTimeout(frame_start);
        const count = try self.loop.poll(&zigzag_events, timeout_ms);

        var had_activity = count > 0;

        // Flush any pending coalesced events
        var pending_events = ArrayList(Event).init(self.allocator);
        defer pending_events.deinit();
        try self.coalescer.flushPending(&pending_events);

        if (pending_events.items.len > 0) {
            had_activity = true;
        }

        // Add flushed events to queue
        for (pending_events.items) |event| {
            try self.event_queue.pushAuto(event);
        }

        const flush_activity = try self.input_parser.flushPending(&self.event_queue, &self.coalescer, self.timer.read());
        if (flush_activity) had_activity = true;

        if (self.has_pending_input) {
            had_activity = true;
            self.has_pending_input = false;
        }

        return had_activity or !self.event_queue.isEmpty();
    }

    /// Run the event loop until stopped
    pub fn run(self: *ZigZagBackend) !void {
        try self.registerStdin();
        defer self.unregisterStdin();

        self.last_frame_time = self.timer.read() / std.time.ns_per_ms;

        while (!self.should_stop) {
            const frame_start = self.timer.read() / std.time.ns_per_ms;

            _ = try self.tick();

            // Frame timing - maintain target FPS
            const frame_end = self.timer.read() / std.time.ns_per_ms;
            const frame_duration = frame_end - frame_start;

            if (frame_duration < self.frame_budget_ms) {
                const sleep_ms = self.frame_budget_ms - @as(u32, @intCast(frame_duration));
                std.posix.nanosleep(0, sleep_ms * std.time.ns_per_ms);
            }

            self.last_frame_time = frame_end;
        }
    }

    /// Stop the event loop
    pub fn stop(self: *ZigZagBackend) void {
        self.should_stop = true;
        self.event_queue.shutdown();
    }

    /// Push an event into the backend queue with an explicit priority
    pub fn pushEvent(self: *ZigZagBackend, event: Event, priority: EventPriority) !void {
        try self.event_queue.pushEvent(event, priority);
    }

    /// Push an event using automatic priority classification
    pub fn pushAuto(self: *ZigZagBackend, event: Event) !void {
        try self.event_queue.pushAuto(event);
    }

    /// Get next event from queue
    pub fn popEvent(self: *ZigZagBackend) ?Event {
        if (self.event_queue.popEvent()) |queued| {
            return queued.event;
        }
        return null;
    }

    /// Set target frame rate
    pub fn setFrameRate(self: *ZigZagBackend, fps: u32) void {
        self.frame_rate_target = fps;
        self.frame_budget_ms = if (fps > 0)
            @max(@as(u32, @intCast(@divTrunc(1000, fps))), 1)
        else
            0;
    }

    /// Apply an explicit frame budget override (null to fall back to frame rate)
    pub fn applyFrameBudget(self: *ZigZagBackend, budget_ms: ?u32) void {
        if (budget_ms) |ms| {
            self.frame_budget_ms = ms;
        } else if (self.frame_rate_target > 0) {
            self.frame_budget_ms = @max(@as(u32, @intCast(@divTrunc(1000, self.frame_rate_target))), 1);
        } else {
            self.frame_budget_ms = 0;
        }
    }

    /// Calculate poll timeout based on frame budget
    fn calculatePollTimeout(self: *ZigZagBackend, frame_start: u64) u32 {
        const elapsed = (self.timer.read() / std.time.ns_per_ms) - frame_start;
        if (elapsed >= self.frame_budget_ms) return 0; // Poll immediately
        return @intCast(self.frame_budget_ms - @as(u32, @intCast(elapsed)));
    }

    /// Callback for stdin read events
    fn stdinCallback(watch: *const zigzag.Watch, event: zigzag.Event) void {
        const self: *ZigZagBackend = @ptrCast(@alignCast(watch.user_data.?));

        if (event.type == .read_ready) {
            self.parseTerminalInput() catch |err| {
                std.log.err("Failed to parse terminal input: {}", .{err});
            };
        }
    }

    /// Parse terminal input into Phantom events
    /// For now, simplified - just reads raw input and converts to char events
    /// TODO: Use proper ANSI parser when terminal/Parser.zig API is clarified
    fn parseTerminalInput(self: *ZigZagBackend) !void {
        if (builtin.os.tag == .windows) return;

        var had_activity = false;

        while (true) {
            const bytes_read = posix.read(self.stdin_fd, &self.parse_buffer) catch |err| switch (err) {
                error.Interrupted => continue,
                error.WouldBlock => break,
                error.OperationAborted => break,
                else => return err,
            };

            if (bytes_read == 0) break;

            const now_ns = self.timer.read();
            const produced = try self.input_parser.feedBytes(&self.event_queue, &self.coalescer, self.parse_buffer[0..bytes_read], now_ns);
            had_activity = had_activity or produced;
        }

        if (had_activity) {
            self.has_pending_input = true;
        }
    }

    pub fn popCommands(self: *ZigZagBackend) ![]vxfw.Command {
        return try self.event_queue.popCommands();
    }

    pub fn queueStats(self: *ZigZagBackend) @import("EventQueue.zig").QueueStats {
        return self.event_queue.getStats();
    }

    fn configureStdinNonBlocking(self: *ZigZagBackend) !void {
        if (builtin.os.tag == .windows) return;

        const flags = try posix.fcntl(self.stdin_fd, posix.F.GETFL, 0);
        self.stdin_flags_original = @intCast(flags);

        const non_block: usize = 1 << @bitOffsetOf(posix.O, "NONBLOCK");
        _ = try posix.fcntl(self.stdin_fd, posix.F.SETFL, flags | non_block);
    }

    fn restoreStdinFlags(self: *ZigZagBackend) void {
        if (builtin.os.tag == .windows) return;

        if (self.stdin_flags_original) |flags| {
            const result = posix.fcntl(self.stdin_fd, posix.F.SETFL, flags) catch |err| {
                std.log.warn("ZigZagBackend: failed to restore stdin flags: {}", .{err});
                return;
            };
            _ = result;
        }
    }
};

// Tests
test "ZigZagBackend initialization" {
    const testing = std.testing;
    var backend = try ZigZagBackend.init(testing.allocator, .{});
    defer backend.deinit();

    try testing.expect(!backend.should_stop);
    try testing.expectEqual(@as(u32, 60), backend.frame_rate_target);
    try testing.expectEqual(@as(u32, 16), backend.frame_budget_ms);
}

test "ZigZagBackend frame rate setting" {
    const testing = std.testing;
    var backend = try ZigZagBackend.init(testing.allocator, .{});
    defer backend.deinit();

    backend.setFrameRate(120);
    try testing.expectEqual(@as(u32, 120), backend.frame_rate_target);
    try testing.expectEqual(@as(u32, 8), backend.frame_budget_ms); // 1000/120 ≈ 8

    backend.setFrameRate(30);
    try testing.expectEqual(@as(u32, 30), backend.frame_rate_target);
    try testing.expectEqual(@as(u32, 33), backend.frame_budget_ms); // 1000/30 ≈ 33
}

test "ZigZagBackend apply custom frame budget" {
    const testing = std.testing;
    var backend = try ZigZagBackend.init(testing.allocator, .{});
    defer backend.deinit();

    backend.applyFrameBudget(12);
    try testing.expectEqual(@as(u32, 12), backend.frame_budget_ms);

    backend.applyFrameBudget(null);
    try testing.expectEqual(@as(u32, 16), backend.frame_budget_ms);
}
