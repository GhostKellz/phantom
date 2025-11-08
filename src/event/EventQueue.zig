//! EventQueue - Event queue management for efficient event processing
//! Provides thread-safe event queuing and processing for the vxfw framework

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const event_types = @import("types.zig");

const Allocator = std.mem.Allocator;
const Event = event_types.Event;
const SystemEvent = event_types.SystemEvent;

/// Event priority levels used for scheduling
pub const EventPriority = enum(u8) {
    critical = 0, // System events, shutdown
    high = 1, // User input, focus changes
    normal = 2, // Redraws, ticks
    low = 3, // Background updates
    idle = 4, // Cleanup, statistics

    pub fn fromEvent(event: Event) EventPriority {
        return switch (event) {
            .key => .high,
            .mouse => .high,
            .system => |sys| switch (sys) {
                .resize => .critical,
                .focus_gained, .focus_lost => .high,
                .suspended, .resumed => .low,
            },
            .tick => .normal,
        };
    }
};

const priority_order = [_]EventPriority{ .critical, .high, .normal, .low, .idle };
const priority_count = priority_order.len;

fn priorityIndex(priority: EventPriority) usize {
    return switch (priority) {
        .critical => 0,
        .high => 1,
        .normal => 2,
        .low => 3,
        .idle => 4,
    };
}

/// Thread-safe event queue for managing UI events
pub const EventQueue = struct {
    allocator: Allocator,
    queues: [priority_count]std.array_list.AlignedManaged(QueuedEvent, null),
    commands: std.array_list.AlignedManaged(vxfw.Command, null),
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    is_shutdown: bool = false,
    max_queue_size: usize = 10000,
    dropped_events: u64 = 0,
    total_events: usize = 0,
    peak_events: usize = 0,

    pub fn init(allocator: Allocator) EventQueue {
        var queues_init: [priority_count]std.array_list.AlignedManaged(QueuedEvent, null) = undefined;
        inline for (&queues_init) |*subqueue| {
            subqueue.* = std.array_list.AlignedManaged(QueuedEvent, null).init(allocator);
        }

        return EventQueue{
            .allocator = allocator,
            .queues = queues_init,
            .commands = std.array_list.AlignedManaged(vxfw.Command, null).init(allocator),
        };
    }

    pub fn deinit(self: *EventQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up queued events
        inline for (&self.queues) |*queue| {
            for (queue.items) |*event| {
                event.deinit(self.allocator);
            }
            queue.deinit();
        }

        // Clean up commands
        for (self.commands.items) |*command| {
            CommandCloneExt.deinit(command.*, self.allocator);
        }
        self.commands.deinit();
    }

    /// Push an event to the queue
    pub fn pushEvent(self: *EventQueue, event: Event, priority: EventPriority) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_shutdown) return;

        // Check queue size limit
        if (self.total_events >= self.max_queue_size) {
            // Drop oldest non-critical event
            if (self.dropOldestEvent()) {
                self.dropped_events += 1;
            } else {
                return EventQueueError.QueueFull;
            }
        }

        const queued_event = QueuedEvent{
            .event = event,
            .priority = priority,
            .timestamp = std.time.milliTimestamp(),
        };

        try self.pushIntoSubqueue(queued_event);

        // Notify waiting threads
        self.condition.signal();
    }

    /// Push an event with automatically derived priority
    pub fn pushAuto(self: *EventQueue, event: Event) !void {
        try self.pushEvent(event, EventPriority.fromEvent(event));
    }

    /// Pop the highest priority event from the queue
    pub fn popEvent(self: *EventQueue) ?QueuedEvent {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.popEventUnlocked();
    }

    /// Wait for an event (blocking)
    pub fn waitForEvent(self: *EventQueue, timeout_ms: ?u32) ?QueuedEvent {
        self.mutex.lock();
        defer self.mutex.unlock();

        const deadline = if (timeout_ms) |ms|
            std.time.milliTimestamp() + ms
        else
            null;

        while (self.total_events == 0 and !self.is_shutdown) {
            if (deadline) |d| {
                const now = std.time.milliTimestamp();
                if (now >= d) break;

                const remaining_ms = @as(u32, @intCast(d - now));
                self.condition.timedWait(&self.mutex, remaining_ms * 1000000) catch break;
            } else {
                self.condition.wait(&self.mutex);
            }
        }

        return self.popEventUnlocked();
    }

    /// Push a command to the command queue
    pub fn pushCommand(self: *EventQueue, command: vxfw.Command) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_shutdown) return;

            try self.commands.append(try CommandCloneExt.clone(command, self.allocator));
        self.condition.signal();
    }

    /// Pop all commands from the queue
    pub fn popCommands(self: *EventQueue) ![]vxfw.Command {
        self.mutex.lock();
        defer self.mutex.unlock();

        const commands = try self.commands.toOwnedSlice();
        self.commands = std.array_list.AlignedManaged(vxfw.Command, null).init(self.allocator);
        return commands;
    }

    /// Check if queue is empty
    pub fn isEmpty(self: *EventQueue) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.total_events == 0 and self.commands.items.len == 0;
    }

    /// Get queue size
    pub fn size(self: *EventQueue) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.total_events;
    }

    /// Get command queue size
    pub fn commandSize(self: *EventQueue) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.commands.items.len;
    }

    /// Clear all events and commands
    pub fn clear(self: *EventQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        inline for (&self.queues) |*queue| {
            for (queue.items) |*event| {
                event.deinit(self.allocator);
            }
            queue.clearRetainingCapacity();
        }
        self.total_events = 0;
        self.peak_events = 0;

        for (self.commands.items) |*command| {
            CommandCloneExt.deinit(command.*, self.allocator);
        }
        self.commands.clearRetainingCapacity();
    }

    /// Shutdown the queue
    pub fn shutdown(self: *EventQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.is_shutdown = true;
        self.condition.broadcast();
    }

    /// Get statistics
    pub fn getStats(self: *EventQueue) QueueStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return QueueStats{
            .event_count = self.total_events,
            .command_count = self.commands.items.len,
            .dropped_events = self.dropped_events,
            .is_shutdown = self.is_shutdown,
            .peak_event_count = self.peak_events,
        };
    }

    /// Drop the oldest non-critical event
    fn dropOldestEvent(self: *EventQueue) bool {
        var best_priority: ?usize = null;
        var best_index: ?usize = null;
        var best_timestamp: i64 = std.math.maxInt(i64);

        inline for (priority_order, 0..) |priority, p_idx| {
            if (priority == .critical) continue;
            const queue = &self.queues[p_idx];
            for (queue.items, 0..) |event, i| {
                if (event.timestamp < best_timestamp) {
                    best_timestamp = event.timestamp;
                    best_priority = p_idx;
                    best_index = i;
                }
            }
        }

        if (best_priority) |p_idx| {
            var event = self.queues[p_idx].orderedRemove(best_index.?);
            event.deinit(self.allocator);
            self.total_events -= 1;
            return true;
        }

        return false;
    }

    fn pushIntoSubqueue(self: *EventQueue, event: QueuedEvent) !void {
        const idx = priorityIndex(event.priority);
        self.queues[idx].append(event) catch |err| {
            var cleanup = event;
            cleanup.deinit(self.allocator);
            return err;
        };
        self.total_events += 1;
        if (self.total_events > self.peak_events) {
            self.peak_events = self.total_events;
        }
    }

    fn popEventUnlocked(self: *EventQueue) ?QueuedEvent {
        inline for (priority_order) |priority| {
            const idx = priorityIndex(priority);
            if (self.queues[idx].items.len > 0) {
                const event = self.queues[idx].orderedRemove(0);
                self.total_events -= 1;
                return event;
            }
        }
        return null;
    }
};

/// Queued event with priority and timestamp
pub const QueuedEvent = struct {
    event: Event,
    priority: EventPriority,
    timestamp: i64,

    pub fn deinit(self: *QueuedEvent, allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// Queue statistics
pub const QueueStats = struct {
    event_count: usize,
    command_count: usize,
    dropped_events: u64,
    is_shutdown: bool,
    peak_event_count: usize,
};

/// Event queue errors
pub const EventQueueError = error{
    QueueFull,
    Shutdown,
    InvalidEvent,
};

/// Event filter for processing
pub const EventFilter = struct {
    filter_fn: *const fn (Event) bool,
    name: []const u8,

    pub fn init(name: []const u8, filter_fn: *const fn (Event) bool) EventFilter {
        return EventFilter{
            .filter_fn = filter_fn,
            .name = name,
        };
    }

    pub fn matches(self: EventFilter, event: Event) bool {
        return self.filter_fn(event);
    }
};

/// Filtered event queue
pub const FilteredEventQueue = struct {
    queue: *EventQueue,
    filters: std.array_list.AlignedManaged(EventFilter, null),
    allocator: Allocator,

    pub fn init(allocator: Allocator, queue: *EventQueue) FilteredEventQueue {
        return FilteredEventQueue{
            .queue = queue,
            .filters = std.array_list.AlignedManaged(EventFilter, null).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FilteredEventQueue) void {
        self.filters.deinit();
    }

    /// Add event filter
    pub fn addFilter(self: *FilteredEventQueue, filter: EventFilter) !void {
        try self.filters.append(filter);
    }

    /// Remove event filter
    pub fn removeFilter(self: *FilteredEventQueue, name: []const u8) void {
        var i: usize = 0;
        while (i < self.filters.items.len) {
            if (std.mem.eql(u8, self.filters.items[i].name, name)) {
                _ = self.filters.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Pop event that matches any filter
    pub fn popFilteredEvent(self: *FilteredEventQueue) ?QueuedEvent {
        const queue = self.queue;
        queue.mutex.lock();
        defer queue.mutex.unlock();

        inline for (priority_order) |priority| {
            const idx = priorityIndex(priority);
            var i: usize = 0;
            while (i < queue.queues[idx].items.len) {
                const event = &queue.queues[idx].items[i];

                var matches = false;
                for (self.filters.items) |filter| {
                    if (filter.matches(event.event)) {
                        matches = true;
                        break;
                    }
                }

                if (matches) {
                    const removed = queue.queues[idx].orderedRemove(i);
                    queue.total_events -= 1;
                    return removed;
                }
                i += 1;
            }
        }

        return null;
    }
};

/// Event processor for batch processing
pub const EventProcessor = struct {
    queue: *EventQueue,
    allocator: Allocator,
    batch_size: usize = 100,
    processing_time_ms: u32 = 16, // ~60 FPS

    pub fn init(allocator: Allocator, queue: *EventQueue) EventProcessor {
        return EventProcessor{
            .queue = queue,
            .allocator = allocator,
        };
    }

    /// Process events in batches
    pub fn processBatch(self: *EventProcessor, handler: *const fn ([]QueuedEvent) anyerror!void) !void {
        const start_time = std.time.milliTimestamp();
        var events = std.array_list.AlignedManaged(QueuedEvent, null).init(self.allocator);
        defer events.deinit();

        while (events.items.len < self.batch_size) {
            const elapsed = std.time.milliTimestamp() - start_time;
            if (elapsed >= self.processing_time_ms) break;

            if (self.queue.popEvent()) |event| {
                try events.append(event);
            } else {
                break;
            }
        }

        if (events.items.len > 0) {
            try handler(events.items);

            // Clean up events
            for (events.items) |*event| {
                event.deinit(self.allocator);
            }
        }
    }
};

pub const CommandCloneExt = struct {
    pub fn clone(command: vxfw.Command, allocator: Allocator) !vxfw.Command {
        return switch (command) {
            .tick => |tick| vxfw.Command{ .tick = tick },
            .set_mouse_shape => |shape| vxfw.Command{ .set_mouse_shape = shape },
            .request_focus => |widget| vxfw.Command{ .request_focus = widget },
            .copy_to_clipboard => |text| vxfw.Command{ .copy_to_clipboard = try allocator.dupe(u8, text) },
            .set_title => |title| vxfw.Command{ .set_title = try allocator.dupe(u8, title) },
            .queue_refresh => vxfw.Command.queue_refresh,
            .notify => |notify| vxfw.Command{ .notify = .{
                .title = if (notify.title) |t| try allocator.dupe(u8, t) else null,
                .body = try allocator.dupe(u8, notify.body),
            } },
            .query_color => |color| vxfw.Command{ .query_color = color },
            .redraw => vxfw.Command.redraw,
        };
    }

    pub fn deinit(command: vxfw.Command, allocator: Allocator) void {
        switch (command) {
            .copy_to_clipboard => |text| allocator.free(text),
            .set_title => |title| allocator.free(title),
            .notify => |notify| {
                if (notify.title) |title| allocator.free(title);
                allocator.free(notify.body);
            },
            else => {},
        }
    }
};

pub fn destroyCommands(commands: []vxfw.Command, allocator: Allocator) void {
    for (commands) |command| {
        CommandCloneExt.deinit(command, allocator);
    }
    allocator.free(commands);
}

test "EventQueue basic operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var queue = EventQueue.init(arena.allocator());
    defer queue.deinit();

    // Test pushing and popping events
    try queue.pushEvent(Event.fromTick(), .normal);
    try std.testing.expect(!queue.isEmpty());
    try std.testing.expectEqual(@as(usize, 1), queue.size());

    const event = queue.popEvent();
    try std.testing.expect(event != null);
    try std.testing.expect(queue.isEmpty());
}

test "EventQueue priority ordering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var queue = EventQueue.init(arena.allocator());
    defer queue.deinit();

    // Push events in reverse priority order
    try queue.pushEvent(Event.fromTick(), .normal);
    try queue.pushEvent(Event.fromSystem(SystemEvent.focus_gained), .high);
    try queue.pushEvent(Event.fromSystem(SystemEvent.resize), .critical);

    // Should pop in priority order (critical first)
    const first = queue.popEvent().?;
    try std.testing.expect(first.event == .system);
    try std.testing.expectEqual(SystemEvent.resize, first.event.system);
    first.deinit(arena.allocator());

    const second = queue.popEvent().?;
    try std.testing.expect(second.event == .system);
    try std.testing.expectEqual(SystemEvent.focus_gained, second.event.system);
    second.deinit(arena.allocator());

    const third = queue.popEvent().?;
    try std.testing.expect(third.event == .tick);
    third.deinit(arena.allocator());
}

test "EventQueue pushAuto infers priority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var queue = EventQueue.init(arena.allocator());
    defer queue.deinit();

    try queue.pushEvent(Event.fromTick(), .normal);
    try queue.pushAuto(Event.fromSystem(SystemEvent.focus_gained));

    const first = queue.popEvent().?;
    try std.testing.expectEqual(EventPriority.high, first.priority);
    first.deinit(arena.allocator());

    const second = queue.popEvent().?;
    try std.testing.expect(second.event == .tick);
    second.deinit(arena.allocator());
}

test "EventFilter functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var queue = EventQueue.init(arena.allocator());
    defer queue.deinit();

    var filtered = FilteredEventQueue.init(arena.allocator(), &queue);
    defer filtered.deinit();

    // Add filter for key events only
    const key_filter = EventFilter.init("keys", struct {
        fn filterKeyEvents(event: Event) bool {
            return event == .key;
        }
    }.filterKeyEvents);

    try filtered.addFilter(key_filter);

    // Add mixed events
    const key_event = Event.fromKey(event_types.Key.enter);
    try queue.pushEvent(key_event, .high);
    try queue.pushEvent(Event.fromTick(), .normal);

    // Should only get key event
    const filtered_event = filtered.popFilteredEvent().?;
    try std.testing.expect(filtered_event.event == .key);
    filtered_event.deinit(arena.allocator());

    // Tick event should still be in queue
    try std.testing.expectEqual(@as(usize, 1), queue.size());
}
