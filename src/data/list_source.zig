//! Generic list data source abstraction with async-friendly hooks
const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;

/// Range request for list data virtualization.
pub const Range = struct {
    start: usize = 0,
    count: usize,

    pub fn end(self: Range) usize {
        return self.start + self.count;
    }
};

/// Lifecycle state of a list-backed data source.
pub const State = enum {
    idle,
    loading,
    ready,
    exhausted,
    failed,
};

/// Events emitted by a list data source when data mutations occur.
pub fn Event(comptime Item: type) type {
    return union(enum) {
        reset,
        /// Items appended to the logical tail of the list.
        appended: struct {
            count: usize,
            items: []const Item,
        },
        /// A specific range was replaced with new items.
        replaced: struct {
            range: Range,
            items: []const Item,
        },
        /// A single item was updated in place.
        updated: struct {
            index: usize,
            item: Item,
        },
        /// A fatal error occurred. Data consumers should surface this state.
        failed: anyerror,
        /// The backing state changed (e.g. loading → ready).
        state: State,
    };
}

/// Observer callback invoked when the data source emits an event.
pub fn Observer(comptime Item: type) type {
    const EventType = Event(Item);
    return struct {
        context: ?*anyopaque = null,
        callback: *const fn (event: EventType, context: ?*anyopaque) void,

        pub fn notify(self: *const @This(), event: EventType) void {
            self.callback(event, self.context);
        }
    };
}

/// Virtualized list data source handle. Concrete implementations provide the vtable.
pub fn ListDataSource(comptime Item: type) type {
    return struct {
        context: *anyopaque,
        vtable: *const VTable,

        pub const VTable = struct {
            getState: *const fn (context: *anyopaque) State,
            len: *const fn (context: *anyopaque) usize,
            get: *const fn (context: *anyopaque, index: usize) ?Item,
            requestRange: *const fn (context: *anyopaque, requested_range: Range) anyerror!void,
            refresh: *const fn (context: *anyopaque) anyerror!void,
            subscribe: *const fn (context: *anyopaque, observer_ptr: *const Observer(Item)) void,
            unsubscribe: *const fn (context: *anyopaque, observer_ptr: *const Observer(Item)) void,
        };

        pub fn init(context: anytype, vtable: *const VTable) @This() {
            const info = @typeInfo(@TypeOf(context));
            switch (info) {
                .pointer => {},
                else => @compileError("ListDataSource context must be a pointer type"),
            }
            return .{
                .context = @ptrCast(context),
                .vtable = vtable,
            };
        }

        pub fn state(self: @This()) State {
            return self.vtable.getState(self.context);
        }

        pub fn len(self: @This()) usize {
            return self.vtable.len(self.context);
        }

        pub fn isEmpty(self: @This()) bool {
            return self.len() == 0;
        }

        pub fn get(self: @This(), index: usize) ?Item {
            return self.vtable.get(self.context, index);
        }

        pub fn requestRange(self: @This(), requested_range: Range) !void {
            return self.vtable.requestRange(self.context, requested_range);
        }

        pub fn refresh(self: @This()) !void {
            return self.vtable.refresh(self.context);
        }

        pub fn subscribe(self: @This(), observer_ptr: *const Observer(Item)) void {
            self.vtable.subscribe(self.context, observer_ptr);
        }

        pub fn unsubscribe(self: @This(), observer_ptr: *const Observer(Item)) void {
            self.vtable.unsubscribe(self.context, observer_ptr);
        }
    };
}

/// Helper to build read-only observers at compile time.
pub fn makeObserver(comptime Item: type, callback: *const fn (event: Event(Item), context: ?*anyopaque) void, context: ?*anyopaque) Observer(Item) {
    return Observer(Item){
        .context = context,
        .callback = callback,
    };
}

/// Convenience for constructing range requests.
pub fn range(start: usize, count: usize) Range {
    return Range{ .start = start, .count = count };
}

/// Simple in-memory list source that drives `ListDataSource` via a backing slice.
pub fn InMemoryListSource(comptime Item: type) type {
    return struct {
        const Self = @This();
        const SourceType = ListDataSource(Item);
        const ObserverType = Observer(Item);

        /// Domain-specific errors emitted by mutation helpers.
        pub const Error = error{
            OutOfRange,
            CountMismatch,
        };

        allocator: std.mem.Allocator,
        state: State = .idle,
        items: ArrayListUnmanaged(Item) = .{},
        observers: ArrayListUnmanaged(ObserverType) = .{},

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
            self.observers.deinit(self.allocator);
        }

        /// Returns a `ListDataSource` handle backed by this instance.
        pub fn asListDataSource(self: *Self) SourceType {
            return SourceType.init(self, &Self.vtable);
        }

        /// Removes all items and signals observers to reset.
        pub fn clear(self: *Self) void {
            self.items.clearRetainingCapacity();
            self.emit(.reset);
            self.ensureState(.idle);
        }

        /// Replaces the entire data set with `data`, emitting reset and appended events.
        pub fn setItems(self: *Self, data: []const Item) !void {
            self.items.clearRetainingCapacity();
            try self.items.appendSlice(self.allocator, data);
            self.emit(.reset);
            self.ensureState(.ready);
            if (data.len != 0) {
                self.emit(.{ .appended = .{ .count = data.len, .items = self.items.items } });
            }
        }

        /// Appends the provided items to the tail, emitting an appended event.
        pub fn appendSlice(self: *Self, data: []const Item) !void {
            if (data.len == 0) return;
            const start_index = self.items.items.len;
            try self.items.appendSlice(self.allocator, data);
            self.ensureState(.ready);
            self.emit(.{ .appended = .{ .count = data.len, .items = self.items.items[start_index..] } });
        }

        /// Replaces the given range with `data` (lengths must match).
        pub fn replaceRange(self: *Self, requested: Range, data: []const Item) Error!void {
            if (requested.end() > self.items.items.len) return error.OutOfRange;
            if (requested.count != data.len) return error.CountMismatch;

            std.mem.copyForwards(Item, self.items.items[requested.start..requested.end()], data);
            self.emit(.{ .replaced = .{ .range = requested, .items = self.items.items[requested.start..requested.end()] } });
        }

        /// Updates a single index in-place and emits an updated event.
        pub fn update(self: *Self, index: usize, value: Item) Error!void {
            if (index >= self.items.items.len) return error.OutOfRange;
            self.items.items[index] = value;
            self.emit(.{ .updated = .{ .index = index, .item = value } });
        }

        /// Emits a failed event and transitions into the failed state.
        pub fn fail(self: *Self, err: anyerror) void {
            self.emit(.{ .failed = err });
            self.ensureState(.failed);
        }

        /// Force the internal state machine to a new state and emit notification.
        pub fn setState(self: *Self, new_state: State) void {
            self.ensureState(new_state);
        }

        const vtable = SourceType.VTable{
            .getState = Self.getState,
            .len = Self.len,
            .get = Self.get,
            .requestRange = Self.requestRange,
            .refresh = Self.refresh,
            .subscribe = Self.subscribe,
            .unsubscribe = Self.unsubscribe,
        };

        fn getState(context: *anyopaque) State {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            return self.state;
        }

        fn len(context: *anyopaque) usize {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            return self.items.items.len;
        }

        fn get(context: *anyopaque, index: usize) ?Item {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            if (index >= self.items.items.len) return null;
            return self.items.items[index];
        }

        fn requestRange(context: *anyopaque, requested_range: Range) anyerror!void {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            if (requested_range.end() > self.items.items.len) {
                return error.OutOfRange;
            }
            return;
        }

        fn refresh(context: *anyopaque) anyerror!void {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            self.ensureState(.ready);
            return;
        }

        fn subscribe(context: *anyopaque, observer_ptr: *const ObserverType) void {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            if (self.findObserverIndex(observer_ptr.*)) |idx| {
                const stored = &self.observers.items[idx];
                self.replayObserver(stored);
                return;
            }
            self.observers.append(self.allocator, observer_ptr.*) catch |err| {
                std.log.err("Failed to register observer: {}", .{err});
                return; // Fail silently - observer won't receive updates
            };
            const stored = &self.observers.items[self.observers.items.len - 1];
            self.replayObserver(stored);
        }

        fn unsubscribe(context: *anyopaque, observer_ptr: *const ObserverType) void {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            if (self.findObserverIndex(observer_ptr.*)) |idx| {
                _ = self.observers.swapRemove(idx);
            }
        }

        fn findObserverIndex(self: *Self, needle: ObserverType) ?usize {
            var i: usize = 0;
            while (i < self.observers.items.len) : (i += 1) {
                if (self.observers.items[i].callback == needle.callback and self.observers.items[i].context == needle.context) {
                    return i;
                }
            }
            return null;
        }

        fn emit(self: *Self, event: Event(Item)) void {
            var i: usize = 0;
            while (i < self.observers.items.len) : (i += 1) {
                self.observers.items[i].notify(event);
            }
        }

        fn replayObserver(self: *Self, observer_ref: *const ObserverType) void {
            observer_ref.notify(.reset);
            if (self.items.items.len != 0) {
                observer_ref.notify(.{ .appended = .{ .count = self.items.items.len, .items = self.items.items } });
            }
            observer_ref.notify(.{ .state = self.state });
        }

        fn ensureState(self: *Self, new_state: State) void {
            if (self.state != new_state) {
                self.state = new_state;
                self.emit(.{ .state = self.state });
            }
        }
    };
}

// Tests cover generic behaviour using a test harness implementation.
test "ListDataSource vtable contract" {
    const Item = usize;
    const ObserverType = Observer(Item);
    const SourceType = ListDataSource(Item);

    const Harness = struct {
        const Self = @This();

        state: State = .idle,
        allocator: std.mem.Allocator,
        items: ArrayListUnmanaged(Item) = .{},
        observers: ArrayListUnmanaged(ObserverType) = .{},

        fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
            self.observers.deinit(self.allocator);
        }

        fn getState(context: *anyopaque) State {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            return self.state;
        }

        fn len(context: *anyopaque) usize {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            return self.items.items.len;
        }

        fn get(context: *anyopaque, index: usize) ?Item {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            if (index >= self.items.items.len) return null;
            return self.items.items[index];
        }

        fn requestRange(context: *anyopaque, requested: Range) anyerror!void {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            if (requested.end() > self.items.items.len) {
                return error.OutOfRange;
            }
        }

        fn refresh(context: *anyopaque) anyerror!void {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            if (self.state == .failed) {
                return error.RefreshFailed;
            }
            self.state = .loading;
            return;
        }

        fn subscribe(context: *anyopaque, observer_ptr: *const ObserverType) void {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            self.observers.append(self.allocator, observer_ptr.*) catch |err| {
                std.log.err("Failed to register observer: {}", .{err});
                return;
            };
        }

        fn unsubscribe(context: *anyopaque, observer_ptr: *const ObserverType) void {
            const self = @as(*Self, @ptrCast(@alignCast(context)));
            var i: usize = 0;
            while (i < self.observers.items.len) : (i += 1) {
                if (self.observers.items[i].callback == observer_ptr.callback and self.observers.items[i].context == observer_ptr.context) {
                    _ = self.observers.swapRemove(i);
                    return;
                }
            }
        }
    };

    var harness = Harness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.items.appendSlice(harness.allocator, &[_]Item{ 1, 2, 3 });
    harness.state = .ready;

    const vtable = SourceType.VTable{
        .getState = Harness.getState,
        .len = Harness.len,
        .get = Harness.get,
        .requestRange = Harness.requestRange,
        .refresh = Harness.refresh,
        .subscribe = Harness.subscribe,
        .unsubscribe = Harness.unsubscribe,
    };

    var source = SourceType.init(&harness, &vtable);

    try std.testing.expect(source.state() == .ready);
    try std.testing.expect(source.len() == 3);
    try std.testing.expect(source.get(1).? == 2);
    try std.testing.expect(source.get(100) == null);

    var observer_fired = false;
    const ObserverImpl = struct {
        fn onEvent(event: Event(Item), ctx: ?*anyopaque) void {
            _ = event;
            const flag_ptr = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag_ptr.* = true;
        }
    };

    var test_observer = makeObserver(Item, ObserverImpl.onEvent, &observer_fired);
    source.subscribe(&test_observer);
    try std.testing.expect(harness.observers.items.len == 1);

    source.unsubscribe(&test_observer);
    try std.testing.expect(harness.observers.items.len == 0);

    try std.testing.expectError(error.OutOfRange, source.requestRange(range(0, 10)));

    try source.refresh();
    try std.testing.expect(harness.state == .loading);
}

test "InMemoryListSource emits event payloads" {
    const Item = usize;
    const EventType = Event(Item);
    const Source = InMemoryListSource(Item);

    const allocator = std.testing.allocator;
    var source = Source.init(allocator);
    defer source.deinit();

    var handle = source.asListDataSource();
    try std.testing.expect(handle.state() == .idle);
    try std.testing.expect(handle.isEmpty());

    const EventLog = struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        entries: ArrayListUnmanaged(EventType) = .{},

        fn append(self: *Self, event: EventType) void {
            self.entries.append(self.allocator, event) catch unreachable;
        }

        fn clear(self: *Self) void {
            self.entries.clearRetainingCapacity();
        }

        fn deinit(self: *Self) void {
            self.entries.deinit(self.allocator);
        }
    };

    var event_log = EventLog{ .allocator = allocator };
    defer event_log.deinit();

    const ObserverHarness = struct {
        fn onEvent(event: EventType, ctx: ?*anyopaque) void {
            const log = @as(*EventLog, @ptrCast(@alignCast(ctx.?)));
            log.append(event);
        }
    };

    var observer = makeObserver(Item, ObserverHarness.onEvent, &event_log);
    handle.subscribe(&observer);

    try std.testing.expectEqual(@as(usize, 2), event_log.entries.items.len);
    try std.testing.expect(event_log.entries.items[0] == .reset);
    try std.testing.expect(event_log.entries.items[1] == .state);
    try std.testing.expect(event_log.entries.items[1].state == .idle);
    event_log.clear();

    try source.setItems(&[_]Item{ 1, 2, 3 });
    try std.testing.expectEqual(@as(usize, 3), handle.len());
    try std.testing.expectEqual(@as(?Item, 2), handle.get(1));

    try std.testing.expectEqual(@as(usize, 3), event_log.entries.items.len);
    try std.testing.expect(event_log.entries.items[0] == .reset);
    try std.testing.expect(event_log.entries.items[1] == .state);
    try std.testing.expect(event_log.entries.items[1].state == .ready);
    try std.testing.expect(event_log.entries.items[2] == .appended);
    try std.testing.expectEqual(@as(usize, 3), event_log.entries.items[2].appended.count);
    try std.testing.expect(std.mem.eql(Item, event_log.entries.items[2].appended.items, &[_]Item{ 1, 2, 3 }));
    event_log.clear();

    try source.appendSlice(&[_]Item{ 4, 5 });
    try std.testing.expectEqual(@as(usize, 5), handle.len());
    try std.testing.expectEqual(@as(usize, 1), event_log.entries.items.len);
    try std.testing.expect(event_log.entries.items[0] == .appended);
    try std.testing.expectEqual(@as(usize, 2), event_log.entries.items[0].appended.count);
    try std.testing.expect(std.mem.eql(Item, event_log.entries.items[0].appended.items, &[_]Item{ 4, 5 }));
    event_log.clear();

    try source.update(1, 20);
    try std.testing.expectEqual(@as(?Item, 20), handle.get(1));
    try std.testing.expectEqual(@as(usize, 1), event_log.entries.items.len);
    try std.testing.expect(event_log.entries.items[0] == .updated);
    try std.testing.expectEqual(@as(usize, 1), event_log.entries.items[0].updated.index);
    try std.testing.expectEqual(@as(Item, 20), event_log.entries.items[0].updated.item);
    event_log.clear();

    try source.replaceRange(range(2, 2), &[_]Item{ 30, 40 });
    try std.testing.expectEqual(@as(?Item, 30), handle.get(2));
    try std.testing.expectEqual(@as(usize, 1), event_log.entries.items.len);
    try std.testing.expect(event_log.entries.items[0] == .replaced);
    try std.testing.expectEqual(@as(usize, 2), event_log.entries.items[0].replaced.range.count);
    try std.testing.expect(std.mem.eql(Item, event_log.entries.items[0].replaced.items, &[_]Item{ 30, 40 }));
    event_log.clear();

    try std.testing.expectError(Source.Error.CountMismatch, source.replaceRange(range(0, 2), &[_]Item{1}));
    try std.testing.expectEqual(@as(usize, 0), event_log.entries.items.len);

    try std.testing.expectError(error.OutOfRange, handle.requestRange(range(10, 1)));

    try std.testing.expectError(Source.Error.OutOfRange, source.update(99, 999));

    const sample_error = error.DataSourceFailure;
    source.fail(sample_error);
    try std.testing.expectEqual(@as(usize, 2), event_log.entries.items.len);
    try std.testing.expect(event_log.entries.items[0] == .failed);
    try std.testing.expect(event_log.entries.items[0].failed == sample_error);
    try std.testing.expect(event_log.entries.items[1] == .state);
    try std.testing.expect(event_log.entries.items[1].state == .failed);
    event_log.clear();

    source.clear();
    try std.testing.expectEqual(@as(usize, 0), handle.len());
    try std.testing.expect(handle.state() == .idle);
    try std.testing.expectEqual(@as(usize, 2), event_log.entries.items.len);
    try std.testing.expect(event_log.entries.items[0] == .reset);
    try std.testing.expect(event_log.entries.items[1] == .state);
    try std.testing.expect(event_log.entries.items[1].state == .idle);

    handle.unsubscribe(&observer);
    try std.testing.expectEqual(@as(usize, 0), source.observers.items.len);
}
