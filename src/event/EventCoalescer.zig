//! Event Coalescer
//! Reduces event spam by coalescing similar events (resize, mouse moves)
//! Critical for responsive TUI applications during window resize

const std = @import("std");
const Event = @import("../event.zig").Event;
const ArrayList = std.array_list.Managed;
const EventQueue = @import("EventQueue.zig").EventQueue;
const geometry = @import("../geometry.zig");
const Position = geometry.Position;

pub const CoalescingConfig = struct {
    /// Debounce time for resize events (ms)
    resize_debounce_ms: u32 = 50,

    /// Debounce time for mouse move events (ms)
    mouse_move_debounce_ms: u32 = 16, // ~60 FPS

    /// Enable coalescing for resize events
    coalesce_resize: bool = true,

    /// Enable coalescing for mouse move events
    coalesce_mouse_move: bool = true,
};

pub const EventCoalescer = struct {
    allocator: std.mem.Allocator,
    config: CoalescingConfig,

    // Coalescing state
    timer: std.time.Timer,
    last_resize_time: ?u64 = null,
    last_resize_event: ?Event = null,

    last_mouse_move_time: ?u64 = null,
    last_mouse_move_pos: ?Position = null,
    last_mouse_move_event: ?Event = null,

    pub fn init(allocator: std.mem.Allocator) EventCoalescer {
        return EventCoalescer{
            .allocator = allocator,
            .config = CoalescingConfig{},
            .timer = std.time.Timer.start() catch unreachable,
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: CoalescingConfig) EventCoalescer {
        return EventCoalescer{
            .allocator = allocator,
            .config = config,
            .timer = std.time.Timer.start() catch unreachable,
        };
    }

    pub fn deinit(self: *EventCoalescer) void {
        _ = self;
    }

    /// Process a single event, returning whether it should be dispatched now
    /// If the event is coalesced, it's stored internally and will be dispatched later
    pub fn processEvent(self: *EventCoalescer, event: Event) CoalesceResult {
        const now = self.timer.read() / std.time.ns_per_ms;

        switch (event) {
            .system => |sys| {
                if (sys == .resize and self.config.coalesce_resize) {
                    return self.handleResizeEvent(event, now);
                }
            },
            .mouse => |mouse_event| {
                // Coalesce mouse move events (not clicks)
                if (!mouse_event.pressed and self.config.coalesce_mouse_move) {
                    return self.handleMouseMoveEvent(event, mouse_event.position, now);
                }
            },
            else => {},
        }

        // Event not coalesced, dispatch immediately
        return .{ .dispatch_now = event };
    }

    /// Flush any pending coalesced events that have passed their debounce time
    pub fn flushPending(self: *EventCoalescer, events: *ArrayList(Event)) !void {
        const now = self.timer.read() / std.time.ns_per_ms;

        // Flush resize event if debounce time elapsed
        if (self.last_resize_event) |event| {
            if (self.last_resize_time) |last_time| {
                if (now - last_time >= self.config.resize_debounce_ms) {
                    try events.append(event);
                    self.last_resize_event = null;
                    self.last_resize_time = null;
                }
            }
        }

        // Flush mouse move event if debounce time elapsed
        if (self.last_mouse_move_event) |event| {
            if (self.last_mouse_move_time) |last_time| {
                if (now - last_time >= self.config.mouse_move_debounce_ms) {
                    try events.append(event);
                    self.last_mouse_move_event = null;
                    self.last_mouse_move_time = null;
                    self.last_mouse_move_pos = null;
                }
            }
        }
    }

    /// Get statistics about coalesced events
    pub fn getStats(self: *const EventCoalescer) CoalescingStats {
        return CoalescingStats{
            .pending_resize = self.last_resize_event != null,
            .pending_mouse_move = self.last_mouse_move_event != null,
        };
    }

    fn handleResizeEvent(self: *EventCoalescer, event: Event, now: u64) CoalesceResult {
        // Store the latest resize event
        self.last_resize_event = event;
        self.last_resize_time = now;
        return .coalesced;
    }

    fn handleMouseMoveEvent(self: *EventCoalescer, event: Event, pos: Position, now: u64) CoalesceResult {
        // If this is a different position, update the stored event
        if (self.last_mouse_move_pos == null or
            !std.meta.eql(self.last_mouse_move_pos.?, pos))
        {
            self.last_mouse_move_event = event;
            self.last_mouse_move_pos = pos;
            self.last_mouse_move_time = now;
        }
        return .coalesced;
    }
};

pub const CoalesceResult = union(enum) {
    /// Event should be dispatched immediately
    dispatch_now: Event,

    /// Event was coalesced and stored for later
    coalesced: void,
};

pub const CoalescingStats = struct {
    pending_resize: bool,
    pending_mouse_move: bool,

    pub fn hasPending(self: CoalescingStats) bool {
        return self.pending_resize or self.pending_mouse_move;
    }
};

// Tests
test "EventCoalescer resize coalescing" {
    const testing = std.testing;
    var coalescer = EventCoalescer.init(testing.allocator);
    defer coalescer.deinit();

    coalescer.config.resize_debounce_ms = 50;

    // First resize event
    const resize1 = Event{ .system = .resize };
    const result1 = coalescer.processEvent(resize1);
    try testing.expect(result1 == .coalesced);

    // Second resize event immediately after
    const resize2 = Event{ .system = .resize };
    const result2 = coalescer.processEvent(resize2);
    try testing.expect(result2 == .coalesced);

    // Should have only one pending resize
    const stats = coalescer.getStats();
    try testing.expect(stats.pending_resize);

    // Flush pending events
    var events = ArrayList(Event).init(testing.allocator);
    defer events.deinit();

    // Wait for debounce time
    const ts1 = std.c.timespec{ .sec = 0, .nsec = 60 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&ts1, null);

    try coalescer.flushPending(&events);

    // Should have exactly one resize event
    try testing.expectEqual(@as(usize, 1), events.items.len);
    try testing.expect(events.items[0].system == .resize);
}

test "EventCoalescer mouse move coalescing" {
    const testing = std.testing;
    var coalescer = EventCoalescer.init(testing.allocator);
    defer coalescer.deinit();

    coalescer.config.mouse_move_debounce_ms = 16;

    const MouseEvent = @import("../event.zig").MouseEvent;

    // Multiple mouse move events to different positions
    const pos1 = Position{ .x = 10, .y = 10 };
    const pos2 = Position{ .x = 15, .y = 15 };
    const pos3 = Position{ .x = 20, .y = 20 };

    const mouse1 = Event{ .mouse = MouseEvent{
        .button = .left,
        .position = pos1,
        .pressed = false,
    } };
    const mouse2 = Event{ .mouse = MouseEvent{
        .button = .left,
        .position = pos2,
        .pressed = false,
    } };
    const mouse3 = Event{ .mouse = MouseEvent{
        .button = .left,
        .position = pos3,
        .pressed = false,
    } };

    _ = coalescer.processEvent(mouse1);
    _ = coalescer.processEvent(mouse2);
    _ = coalescer.processEvent(mouse3);

    const stats = coalescer.getStats();
    try testing.expect(stats.pending_mouse_move);

    // Flush after debounce time
    var events = ArrayList(Event).init(testing.allocator);
    defer events.deinit();

    const ts2 = std.c.timespec{ .sec = 0, .nsec = 20 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&ts2, null);
    try coalescer.flushPending(&events);

    // Should have only the last mouse position
    try testing.expectEqual(@as(usize, 1), events.items.len);
    try testing.expectEqual(pos3, events.items[0].mouse.position);
}

test "EventCoalescer non-coalesced events pass through" {
    const testing = std.testing;
    var coalescer = EventCoalescer.init(testing.allocator);
    defer coalescer.deinit();

    // Keyboard events should not be coalesced
    const key_event = Event{ .key = .enter };
    const result = coalescer.processEvent(key_event);

    try testing.expect(result == .dispatch_now);
    try testing.expect(result.dispatch_now.key == .enter);
}
