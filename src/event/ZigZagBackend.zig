//! ZigZag Event Loop Backend for Phantom
//! High-performance event loop using zigzag (io_uring/kqueue/IOCP)
//! Optional backend - can be enabled with -Devent_loop=zigzag

const std = @import("std");
const zigzag = @import("zigzag");
const phantom = @import("../root.zig");
const EventQueue = @import("EventQueue.zig").EventQueue;
const EventPriority = @import("EventQueue.zig").EventPriority;
const EventCoalescer = @import("EventCoalescer.zig").EventCoalescer;
const CoalescingConfig = @import("EventCoalescer.zig").CoalescingConfig;

pub const ZigZagBackend = struct {
    allocator: std.mem.Allocator,
    loop: zigzag.EventLoop,
    event_queue: EventQueue,
    coalescer: EventCoalescer,

    // Terminal file descriptors
    stdin_fd: std.posix.fd_t,
    stdin_watch: ?*zigzag.Watch = null,

    // Frame timing
    frame_rate_target: u32 = 60,
    last_frame_time: i64 = 0,
    frame_budget_ms: u32 = 16, // ~60 FPS (1000/60)

    // Stop mechanism
    should_stop: bool = false,

    // Parse buffer for terminal input
    parse_buffer: [4096]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator) !*ZigZagBackend {
        const self = try allocator.create(ZigZagBackend);
        errdefer allocator.destroy(self);

        // Initialize zigzag loop with coalescing
        var loop = try zigzag.EventLoop.init(allocator, .{
            .max_events = 1024,
            .coalescing = CoalescingConfig{
                .resize_debounce_ms = 50,
                .mouse_move_debounce_ms = 16,
                .coalesce_resize = true,
                .coalesce_mouse_move = true,
            },
        });
        errdefer loop.deinit();

        self.* = ZigZagBackend{
            .allocator = allocator,
            .loop = loop,
            .event_queue = EventQueue.init(allocator),
            .coalescer = EventCoalescer.init(allocator),
            .stdin_fd = std.posix.STDIN_FILENO,
        };

        return self;
    }

    pub fn deinit(self: *ZigZagBackend) void {
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
        const frame_start = std.time.milliTimestamp();

        // Poll zigzag for I/O events
        var zigzag_events: [64]zigzag.Event = undefined;
        const timeout_ms = self.calculatePollTimeout(frame_start);
        const count = try self.loop.poll(&zigzag_events, timeout_ms);

        // zigzag events are automatically processed via callbacks
        // We just need to check if we got any events
        const had_events = count > 0;

        // Flush any pending coalesced events
        var pending_events = std.ArrayList(phantom.Event).init(self.allocator);
        defer pending_events.deinit();
        try self.coalescer.flushPending(&pending_events);

        // Add flushed events to queue
        for (pending_events.items) |event| {
            try self.event_queue.pushAuto(event);
        }

        return had_events or !self.event_queue.isEmpty();
    }

    /// Run the event loop until stopped
    pub fn run(self: *ZigZagBackend) !void {
        try self.registerStdin();
        defer self.unregisterStdin();

        self.last_frame_time = std.time.milliTimestamp();

        while (!self.should_stop) {
            const frame_start = std.time.milliTimestamp();

            _ = try self.tick();

            // Frame timing - maintain target FPS
            const frame_end = std.time.milliTimestamp();
            const frame_duration = frame_end - frame_start;

            if (frame_duration < self.frame_budget_ms) {
                const sleep_ms = self.frame_budget_ms - @as(u32, @intCast(frame_duration));
                std.time.sleep(sleep_ms * std.time.ns_per_ms);
            }

            self.last_frame_time = frame_end;
        }
    }

    /// Stop the event loop
    pub fn stop(self: *ZigZagBackend) void {
        self.should_stop = true;
        self.event_queue.shutdown();
    }

    /// Get next event from queue
    pub fn popEvent(self: *ZigZagBackend) ?phantom.Event {
        if (self.event_queue.popEvent()) |queued| {
            return queued.event;
        }
        return null;
    }

    /// Set target frame rate
    pub fn setFrameRate(self: *ZigZagBackend, fps: u32) void {
        self.frame_rate_target = fps;
        self.frame_budget_ms = if (fps > 0) 1000 / fps else 16;
    }

    /// Calculate poll timeout based on frame budget
    fn calculatePollTimeout(self: *ZigZagBackend, frame_start: i64) u32 {
        const elapsed = std.time.milliTimestamp() - frame_start;
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
        const bytes_read = try std.posix.read(self.stdin_fd, &self.parse_buffer);
        if (bytes_read == 0) return; // EOF

        // Simplified parsing - convert bytes to char events
        // In production, use terminal/Parser.zig for full ANSI sequence parsing
        var i: usize = 0;
        while (i < bytes_read) : (i += 1) {
            const byte = self.parse_buffer[i];

            // Create basic event from byte
            const event = if (byte == 0x03) // Ctrl+C
                phantom.Event{ .key = .ctrl_c }
            else if (byte == 0x1B) // ESC
                phantom.Event{ .key = .escape }
            else if (byte == 0x0A or byte == 0x0D) // Enter
                phantom.Event{ .key = .enter }
            else if (byte == 0x08 or byte == 0x7F) // Backspace/Delete
                phantom.Event{ .key = .backspace }
            else if (byte == 0x09) // Tab
                phantom.Event{ .key = .tab }
            else if (byte >= 0x20 and byte < 0x7F) // Printable ASCII
                phantom.Event{ .key = phantom.Key{ .char = byte } }
            else
                continue; // Skip other control characters for now

            // Coalesce event if needed
            const coalesce_result = self.coalescer.processEvent(event);
            switch (coalesce_result) {
                .dispatch_now => |e| {
                    try self.event_queue.pushAuto(e);
                },
                .coalesced => {
                    // Event stored for later dispatch
                },
            }
        }
    }
};

// Tests
test "ZigZagBackend initialization" {
    const testing = std.testing;
    var backend = try ZigZagBackend.init(testing.allocator);
    defer backend.deinit();

    try testing.expect(!backend.should_stop);
    try testing.expectEqual(@as(u32, 60), backend.frame_rate_target);
    try testing.expectEqual(@as(u32, 16), backend.frame_budget_ms);
}

test "ZigZagBackend frame rate setting" {
    const testing = std.testing;
    var backend = try ZigZagBackend.init(testing.allocator);
    defer backend.deinit();

    backend.setFrameRate(120);
    try testing.expectEqual(@as(u32, 120), backend.frame_rate_target);
    try testing.expectEqual(@as(u32, 8), backend.frame_budget_ms); // 1000/120 ≈ 8

    backend.setFrameRate(30);
    try testing.expectEqual(@as(u32, 30), backend.frame_rate_target);
    try testing.expectEqual(@as(u32, 33), backend.frame_budget_ms); // 1000/30 ≈ 33
}
