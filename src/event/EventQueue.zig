//! EventQueue - Event queue management for efficient event processing
//! Provides thread-safe event queuing and processing for the vxfw framework

const std = @import("std");
const vxfw = @import("../vxfw.zig");

const Allocator = std.mem.Allocator;

/// Thread-safe event queue for managing UI events
pub const EventQueue = struct {
    allocator: Allocator,
    events: std.array_list.AlignedManaged(QueuedEvent, null),
    commands: std.array_list.AlignedManaged(vxfw.Command, null),
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    is_shutdown: bool = false,
    max_queue_size: usize = 10000,
    dropped_events: u64 = 0,

    pub fn init(allocator: Allocator) EventQueue {
        return EventQueue{
            .allocator = allocator,
            .events = std.array_list.AlignedManaged(QueuedEvent, null).init(allocator),
            .commands = std.array_list.AlignedManaged(vxfw.Command, null).init(allocator),
        };
    }

    pub fn deinit(self: *EventQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up queued events
        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.events.deinit();

        // Clean up commands
        for (self.commands.items) |*command| {
            command.deinit(self.allocator);
        }
        self.commands.deinit();
    }

    /// Push an event to the queue
    pub fn pushEvent(self: *EventQueue, event: vxfw.Event, priority: EventPriority) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_shutdown) return;

        // Check queue size limit
        if (self.events.items.len >= self.max_queue_size) {
            // Drop oldest non-critical event
            if (self.dropOldestEvent()) {
                self.dropped_events += 1;
            } else {
                return EventQueueError.QueueFull;
            }
        }

        const queued_event = QueuedEvent{
            .event = try event.clone(self.allocator),
            .priority = priority,
            .timestamp = std.time.milliTimestamp(),
        };

        // Insert in priority order
        try self.insertByPriority(queued_event);

        // Notify waiting threads
        self.condition.signal();
    }

    /// Pop the highest priority event from the queue
    pub fn popEvent(self: *EventQueue) ?QueuedEvent {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.events.items.len == 0) return null;

        return self.events.orderedRemove(0);
    }

    /// Wait for an event (blocking)
    pub fn waitForEvent(self: *EventQueue, timeout_ms: ?u32) ?QueuedEvent {
        self.mutex.lock();
        defer self.mutex.unlock();

        const deadline = if (timeout_ms) |ms|
            std.time.milliTimestamp() + ms
        else
            null;

        while (self.events.items.len == 0 and !self.is_shutdown) {
            if (deadline) |d| {
                const now = std.time.milliTimestamp();
                if (now >= d) break;

                const remaining_ms = @as(u32, @intCast(d - now));
                self.condition.timedWait(&self.mutex, remaining_ms * 1000000) catch break;
            } else {
                self.condition.wait(&self.mutex);
            }
        }

        if (self.events.items.len > 0) {
            return self.events.orderedRemove(0);
        }

        return null;
    }

    /// Push a command to the command queue
    pub fn pushCommand(self: *EventQueue, command: vxfw.Command) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_shutdown) return;

        try self.commands.append(try command.clone(self.allocator));
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
        return self.events.items.len == 0 and self.commands.items.len == 0;
    }

    /// Get queue size
    pub fn size(self: *EventQueue) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.events.items.len;
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

        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.events.clearRetainingCapacity();

        for (self.commands.items) |*command| {
            command.deinit(self.allocator);
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
            .event_count = self.events.items.len,
            .command_count = self.commands.items.len,
            .dropped_events = self.dropped_events,
            .is_shutdown = self.is_shutdown,
        };
    }

    /// Insert event maintaining priority order
    fn insertByPriority(self: *EventQueue, event: QueuedEvent) !void {
        const priority_value = @intFromEnum(event.priority);

        // Find insertion point
        var insert_index: usize = 0;
        for (self.events.items, 0..) |existing, i| {
            if (@intFromEnum(existing.priority) > priority_value) {
                insert_index = i;
                break;
            }
            insert_index = i + 1;
        }

        try self.events.insert(insert_index, event);
    }

    /// Drop the oldest non-critical event
    fn dropOldestEvent(self: *EventQueue) bool {
        // Find oldest non-critical event
        var oldest_index: ?usize = null;
        var oldest_time: i64 = std.math.maxInt(i64);

        for (self.events.items, 0..) |event, i| {
            if (event.priority != .critical and event.timestamp < oldest_time) {
                oldest_time = event.timestamp;
                oldest_index = i;
            }
        }

        if (oldest_index) |index| {
            var event = self.events.orderedRemove(index);
            event.deinit(self.allocator);
            return true;
        }

        return false;
    }
};

/// Queued event with priority and timestamp
pub const QueuedEvent = struct {
    event: vxfw.Event,
    priority: EventPriority,
    timestamp: i64,

    pub fn deinit(self: *QueuedEvent, allocator: Allocator) void {
        self.event.deinit(allocator);
    }
};

/// Event priority levels
pub const EventPriority = enum(u8) {
    critical = 0,  // System events, shutdown
    high = 1,      // User input, focus changes
    normal = 2,    // Redraws, ticks
    low = 3,       // Background updates
    idle = 4,      // Cleanup, statistics

    pub fn fromEvent(event: vxfw.Event) EventPriority {
        return switch (event) {
            .key_press, .key_release, .mouse => .high,
            .focus_in, .focus_out => .high,
            .paste_start, .paste_end, .paste => .high,
            .winsize => .critical,
            .tick => .normal,
            .init => .critical,
            .mouse_enter, .mouse_leave => .normal,
            .color_report, .color_scheme => .low,
            .user => .normal,
        };
    }
};

/// Queue statistics
pub const QueueStats = struct {
    event_count: usize,
    command_count: usize,
    dropped_events: u64,
    is_shutdown: bool,
};

/// Event queue errors
pub const EventQueueError = error{
    QueueFull,
    Shutdown,
    InvalidEvent,
};

/// Event filter for processing
pub const EventFilter = struct {
    filter_fn: *const fn (vxfw.Event) bool,
    name: []const u8,

    pub fn init(name: []const u8, filter_fn: *const fn (vxfw.Event) bool) EventFilter {
        return EventFilter{
            .filter_fn = filter_fn,
            .name = name,
        };
    }

    pub fn matches(self: EventFilter, event: vxfw.Event) bool {
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

        var i: usize = 0;
        while (i < queue.events.items.len) {
            const event = &queue.events.items[i];

            // Check if event matches any filter
            var matches = false;
            for (self.filters.items) |filter| {
                if (filter.matches(event.event)) {
                    matches = true;
                    break;
                }
            }

            if (matches) {
                return queue.events.orderedRemove(i);
            }
            i += 1;
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

// Extension methods for vxfw.Event and vxfw.Command
const EventExtensions = struct {
    fn cloneEvent(event: vxfw.Event, allocator: Allocator) !vxfw.Event {
        return switch (event) {
            .key_press => |key| vxfw.Event{ .key_press = key },
            .key_release => |key| vxfw.Event{ .key_release = key },
            .mouse => |mouse| vxfw.Event{ .mouse = mouse },
            .focus_in => vxfw.Event.focus_in,
            .focus_out => vxfw.Event.focus_out,
            .paste_start => vxfw.Event.paste_start,
            .paste_end => vxfw.Event.paste_end,
            .paste => |data| vxfw.Event{ .paste = try allocator.dupe(u8, data) },
            .color_report => |report| vxfw.Event{ .color_report = report },
            .color_scheme => |scheme| vxfw.Event{ .color_scheme = scheme },
            .winsize => |size| vxfw.Event{ .winsize = size },
            .tick => vxfw.Event.tick,
            .init => vxfw.Event.init,
            .mouse_enter => vxfw.Event.mouse_enter,
            .mouse_leave => vxfw.Event.mouse_leave,
            .user => |user| vxfw.Event{ .user = .{
                .name = try allocator.dupe(u8, user.name),
                .data = user.data,
            } },
        };
    }

    fn deinitEvent(event: vxfw.Event, allocator: Allocator) void {
        switch (event) {
            .paste => |data| allocator.free(data),
            .user => |user| allocator.free(user.name),
            else => {},
        }
    }

    fn cloneCommand(command: vxfw.Command, allocator: Allocator) !vxfw.Command {
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

    fn deinitCommand(command: vxfw.Command, allocator: Allocator) void {
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

// Add clone and deinit methods to Event and Command
pub const EventCloneExt = struct {
    pub fn clone(event: vxfw.Event, allocator: Allocator) !vxfw.Event {
        return EventExtensions.cloneEvent(event, allocator);
    }

    pub fn deinit(event: vxfw.Event, allocator: Allocator) void {
        EventExtensions.deinitEvent(event, allocator);
    }
};

pub const CommandCloneExt = struct {
    pub fn clone(command: vxfw.Command, allocator: Allocator) !vxfw.Command {
        return EventExtensions.cloneCommand(command, allocator);
    }

    pub fn deinit(command: vxfw.Command, allocator: Allocator) void {
        EventExtensions.deinitCommand(command, allocator);
    }
};

test "EventQueue basic operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var queue = EventQueue.init(arena.allocator());
    defer queue.deinit();

    // Test pushing and popping events
    try queue.pushEvent(vxfw.Event.tick, .normal);
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
    try queue.pushEvent(vxfw.Event.tick, .normal);
    try queue.pushEvent(vxfw.Event.focus_in, .high);
    try queue.pushEvent(vxfw.Event.init, .critical);

    // Should pop in priority order (critical first)
    const first = queue.popEvent().?;
    try std.testing.expectEqual(vxfw.Event.init, first.event);
    first.deinit(arena.allocator());

    const second = queue.popEvent().?;
    try std.testing.expectEqual(vxfw.Event.focus_in, second.event);
    second.deinit(arena.allocator());

    const third = queue.popEvent().?;
    try std.testing.expectEqual(vxfw.Event.tick, third.event);
    third.deinit(arena.allocator());
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
        fn filterKeyEvents(event: vxfw.Event) bool {
            return event == .key_press or event == .key_release;
        }
    }.filterKeyEvents);

    try filtered.addFilter(key_filter);

    // Add mixed events
    const key_event = vxfw.Event{ .key_press = .{ .key = .enter } };
    try queue.pushEvent(key_event, .high);
    try queue.pushEvent(vxfw.Event.tick, .normal);

    // Should only get key event
    const filtered_event = filtered.popFilteredEvent().?;
    try std.testing.expectEqual(vxfw.Event.key_press, filtered_event.event);
    filtered_event.deinit(arena.allocator());

    // Tick event should still be in queue
    try std.testing.expectEqual(@as(usize, 1), queue.size());
}