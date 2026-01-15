//! Streaming adapters for Phantom list data sources.
//! Provides a channel-backed source that feeds data into the existing
//! `ListDataSource` abstraction so widgets can react to real-time updates.

const std = @import("std");
const zsync = @import("zsync");
const async = @import("../async/mod.zig");
const data = @import("list_source.zig");

/// Streaming list source that feeds items from a zsync channel into an
/// in-memory list. This is ideal for dashboards that need to reflect
/// real-time updates (logs, metrics, AI streaming tokens, etc.).
///
/// Items are copied into an internal `InMemoryListSource`, so callers should
/// prefer small value types or references. For large payloads provide handles
/// or indices instead of copying whole buffers.
pub fn StreamingListSource(comptime Item: type) type {
    const SourceType = data.ListDataSource(Item);
    const BaseType = data.InMemoryListSource(Item);
    const ChannelType = zsync.channels_mod.Channel(Item);

    return struct {
        const Self = @This();
        const ConsumerTaskHandle = async.TaskHandle(@TypeOf(consumeTask));

        /// Runtime configuration options.
        pub const Options = struct {
            /// Maximum buffered items in the channel before producers block.
            channel_capacity: usize = 128,
            /// Lifecycle state to broadcast when streaming starts.
            start_state: data.State = .loading,
        };

        allocator: std.mem.Allocator,
        runtime: *async.AsyncRuntime,
        base: BaseType,
        channel: ChannelType,
        running: std.atomic.Value(bool),
        consumer_task: ?ConsumerTaskHandle = null,
        options: Options,

        /// Initialize the streaming source. Call `start` after storing the struct
        /// at a stable memory location to begin consuming channel messages.
        pub fn init(
            allocator: std.mem.Allocator,
            runtime: *async.AsyncRuntime,
            options: Options,
        ) !Self {
            var channel = try ChannelType.init(allocator, options.channel_capacity);
            errdefer channel.deinit();

            return Self{
                .allocator = allocator,
                .runtime = runtime,
                .base = BaseType.init(allocator),
                .channel = channel,
                .running = std.atomic.Value(bool).init(false),
                .consumer_task = null,
                .options = options,
            };
        }

        /// Release resources. Automatically stops streaming if still active.
        pub fn deinit(self: *Self) void {
            self.stop();
            self.channel.deinit();
            self.base.deinit();
        }

        /// Access the `ListDataSource` handle backed by this streaming source.
        pub fn asListDataSource(self: *Self) SourceType {
            return self.base.asListDataSource();
        }

        /// Start consuming items from the channel. Safe to call multiple times.
        pub fn start(self: *Self) !void {
            if (self.running.swap(true, .acquire)) {
                return; // Already running
            }

            self.base.setState(self.options.start_state);

            const handle = try self.runtime.spawn(@TypeOf(consumeTask), .{self});
            self.consumer_task = handle;
        }

        /// Signal no more items will be produced. The consumer will drain the
        /// channel and transition into the exhausted state.
        pub fn finish(self: *Self) void {
            self.running.store(false, .release);
            self.channel.close();
        }

        /// Stop streaming and await the consumer task. Safe to call even if the
        /// stream never started.
        pub fn stop(self: *Self) void {
            self.finish();

            if (self.consumer_task) |*task| {
                defer self.consumer_task = null;

                var caught_err: ?anyerror = null;
                task.await() catch |err| {
                    caught_err = err;
                };
                task.deinit();

                if (caught_err) |err| {
                    std.log.err("streaming list source consumer failed: {s}", .{@errorName(err)});
                    self.base.fail(err);
                }
            }
        }

        /// Push a single item into the streaming pipeline.
        pub fn push(self: *Self, item: Item) !void {
            self.channel.send(item) catch |err| {
                return err;
            };
        }

        /// Push a batch of items into the pipeline.
        pub fn pushSlice(self: *Self, items: []const Item) !void {
            for (items) |item| {
                try self.push(item);
            }
        }

        /// Clear the accumulated items (without affecting the streaming task).
        pub fn clear(self: *Self) void {
            self.base.clear();
        }

        /// Replace current items immediately, bypassing the channel.
        pub fn setItems(self: *Self, items: []const Item) !void {
            try self.base.setItems(items);
        }

        /// Mark the source as failed and propagate the error to observers.
        pub fn fail(self: *Self, err: anyerror) void {
            self.base.fail(err);
            self.finish();
        }

        fn consumeTask(self: *Self) !void {
            defer {
                self.running.store(false, .release);
                if (self.base.state != .failed) {
                    self.base.setState(.exhausted);
                }
            }

            while (true) {
                const item = self.channel.recv() catch |err| switch (err) {
                    error.ChannelClosed => break,
                    else => {
                        self.base.fail(err);
                        return err;
                    },
                };

                const single = [_]Item{item};
                self.base.appendSlice(&single) catch |append_err| {
                    self.base.fail(append_err);
                    return append_err;
                };
            }
        }
    };
}

test "StreamingListSource processes pushed items" {
    const testing = std.testing;

    const Item = u32;
    const allocator = testing.allocator;

    var runtime = try async.AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    var stream = try StreamingListSource(Item).init(allocator, runtime, .{});
    defer stream.deinit();

    try stream.start();

    try stream.push(1);
    try stream.push(2);
    try stream.pushSlice(&[_]Item{ 3, 4 });

    const ts1 = std.c.timespec{ .sec = 0, .nsec = 25 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&ts1, null);

    const source = stream.asListDataSource();
    try testing.expectEqual(@as(usize, 4), source.len());
    try testing.expectEqual(@as(?Item, 1), source.get(0));
    try testing.expectEqual(@as(?Item, 4), source.get(3));

    stream.finish();
    const ts2 = std.c.timespec{ .sec = 0, .nsec = 5 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&ts2, null);
}
