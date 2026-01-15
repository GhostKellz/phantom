//! Async Streaming Integration for Phantom
//! Provides zsync channel-based async streaming for widgets like StreamingText
//! Perfect for AI chat responses, log tailing, real-time data feeds, etc.

const std = @import("std");
const zsync = @import("zsync");
const async = @import("async/mod.zig");
const StreamingText = @import("widgets/streaming_text.zig").StreamingText;

/// Async stream consumer that feeds chunks to a StreamingText widget
pub const AsyncStreamConsumer = struct {
    allocator: std.mem.Allocator,
    widget: *StreamingText,
    channel: zsync.channels_mod.Channel([]const u8),
    runtime: *async.AsyncRuntime,
    running: std.atomic.Value(bool),
    consumer_task: ?ConsumerTaskHandle = null,

    const ConsumerTaskHandle = async.TaskHandle(@TypeOf(consumeTask));

    pub fn init(
        allocator: std.mem.Allocator,
        runtime: *async.AsyncRuntime,
        widget: *StreamingText,
    ) !*AsyncStreamConsumer {
        const self = try allocator.create(AsyncStreamConsumer);

        // Create unbounded channel for streaming chunks
        const channel = try zsync.channels_mod.Channel([]const u8).init(allocator, default_channel_capacity);

        self.* = AsyncStreamConsumer{
            .allocator = allocator,
            .widget = widget,
            .channel = channel,
            .runtime = runtime,
            .running = std.atomic.Value(bool).init(false),
            .consumer_task = null,
        };

        return self;
    }

    const default_channel_capacity: usize = 128;

    fn consumeTask(consumer: *AsyncStreamConsumer) !void {
        while (consumer.running.load(.acquire)) {
            const chunk = consumer.channel.recv() catch |err| switch (err) {
                error.ChannelClosed => break,
                else => return err,
            };

            try consumer.widget.addChunk(chunk);
            consumer.allocator.free(chunk);
        }

        consumer.widget.stopStreaming();
    }

    pub fn deinit(self: *AsyncStreamConsumer) void {
        self.stop();
        self.channel.deinit();
        self.allocator.destroy(self);
    }

    /// Start consuming chunks from the channel and feeding them to the widget
    pub fn start(self: *AsyncStreamConsumer) !void {
        if (self.running.swap(true, .acquire)) {
            return; // Already running
        }

        self.widget.startStreaming();

        const handle = try self.runtime.spawn(@TypeOf(consumeTask), .{self});
        self.consumer_task = handle;
    }

    /// Stop consuming (completes current chunk processing)
    pub fn stop(self: *AsyncStreamConsumer) void {
        self.running.store(false, .release);

        self.channel.close();

        if (self.consumer_task) |*task| {
            defer self.consumer_task = null;

            var caught_err: ?anyerror = null;
            task.await() catch |err| {
                caught_err = err;
            };
            task.deinit();

            if (caught_err) |err| {
                std.log.err("async stream consumer failed: {s}", .{@errorName(err)});
            }
        }
    }

    /// Send a chunk to the stream (producer side)
    /// The chunk will be copied, so the caller can free their buffer
    pub fn send(self: *AsyncStreamConsumer, chunk: []const u8) !void {
        // Duplicate the chunk so it can be freed after send
        const chunk_copy = try self.allocator.dupe(u8, chunk);
        self.channel.send(chunk_copy) catch |err| {
            self.allocator.free(chunk_copy);
            return err;
        };
    }

    /// Close the stream (no more chunks will be accepted)
    pub fn close(self: *AsyncStreamConsumer) void {
        self.channel.close();
    }
};

/// Async stream producer for simulating AI responses or other streaming data
pub const AsyncStreamProducer = struct {
    allocator: std.mem.Allocator,
    consumer: *AsyncStreamConsumer,
    delay_ms: u64,

    pub fn init(
        allocator: std.mem.Allocator,
        consumer: *AsyncStreamConsumer,
        delay_ms: u64,
    ) AsyncStreamProducer {
        return AsyncStreamProducer{
            .allocator = allocator,
            .consumer = consumer,
            .delay_ms = delay_ms,
        };
    }

    /// Stream text with simulated typing delay (character by character or word by word)
    pub fn streamText(self: *AsyncStreamProducer, text: []const u8, chunk_size: usize) !void {
        var i: usize = 0;
        while (i < text.len) {
            const end = @min(i + chunk_size, text.len);
            const chunk = text[i..end];

            try self.consumer.send(chunk);

            // Simulate network delay or typing speed
            const ts = std.c.timespec{ .sec = 0, .nsec = @intCast(self.delay_ms * std.time.ns_per_ms) };
            _ = std.c.nanosleep(&ts, null);

            i = end;
        }
    }

    /// Stream lines from a file (useful for log tailing)
    pub fn streamFile(self: *AsyncStreamProducer, file_path: []const u8) !void {
        const file = try std.Io.Dir.cwd().openFile(file_path, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        var reader = buf_reader.reader();

        var buffer: [4096]u8 = undefined;
        while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
            // Send line with newline
            var line_with_newline = try self.allocator.alloc(u8, line.len + 1);
            defer self.allocator.free(line_with_newline);

            @memcpy(line_with_newline[0..line.len], line);
            line_with_newline[line.len] = '\n';

            try self.consumer.send(line_with_newline);

            // Delay between lines
            const ts = std.c.timespec{ .sec = 0, .nsec = @intCast(self.delay_ms * std.time.ns_per_ms) };
            _ = std.c.nanosleep(&ts, null);
        }
    }

    /// Stream with custom generator function
    pub fn streamWithGenerator(
        self: *AsyncStreamProducer,
        comptime generator_fn: anytype,
        context: anytype,
    ) !void {
        while (try generator_fn(context)) |chunk| {
            try self.consumer.send(chunk);
            const ts = std.c.timespec{ .sec = 0, .nsec = @intCast(self.delay_ms * std.time.ns_per_ms) };
            _ = std.c.nanosleep(&ts, null);
        }
    }
};

/// Example: Simulate AI chat response streaming
pub fn simulateAIChatResponse(
    allocator: std.mem.Allocator,
    runtime: *async.AsyncRuntime,
    widget: *StreamingText,
) !*AsyncStreamConsumer {
    const consumer = try AsyncStreamConsumer.init(allocator, runtime, widget);
    try consumer.start();

    // Spawn a producer task to simulate AI response
    const ProducerTask = struct {
        fn produce(alloc: std.mem.Allocator, cons: *AsyncStreamConsumer) !void {
            const ai_response =
                \\Here's a comprehensive analysis of the async runtime patterns in Zig:
                \\
                \\1. **Event Loop Architecture**
                \\   - Single-threaded event loop with io_uring on Linux
                \\   - Cross-platform support with epoll/kqueue/IOCP
                \\   - Zero-cost abstractions for async operations
                \\
                \\2. **Structured Concurrency**
                \\   - Nursery pattern for safe task spawning
                \\   - Automatic cleanup on scope exit
                \\   - Error propagation through task boundaries
                \\
                \\3. **Channel-based Communication**
                \\   - Bounded and unbounded channels
                \\   - Type-safe message passing
                \\   - Select-like primitives for multiplexing
                \\
                \\This approach provides both safety and performance! 🚀
            ;

            var producer = AsyncStreamProducer.init(alloc, cons, 30); // 30ms between chunks

            // Stream word by word for realistic typing effect
            try producer.streamText(ai_response, 1); // Character by character

            cons.close();
        }
    };

    const ProducerHandle = async.TaskHandle(@TypeOf(ProducerTask.produce));
    const handle = try runtime.spawn(@TypeOf(ProducerTask.produce), .{ allocator, consumer });

    const HandleCleanup = struct {
        fn run(alloc: std.mem.Allocator, ptr: *ProducerHandle) !void {
            defer alloc.destroy(ptr);
            var h = ptr.*;

            var caught_err: ?anyerror = null;
            h.await() catch |err| {
                caught_err = err;
            };
            h.deinit();

            if (caught_err) |err| {
                std.log.err("async AI producer failed: {s}", .{@errorName(err)});
            }
        }
    };

    const handle_ptr = allocator.create(ProducerHandle) catch |alloc_err| {
        var cleanup = handle;
        var caught_err: ?anyerror = null;
        cleanup.await() catch |err| {
            caught_err = err;
        };
        cleanup.deinit();

        if (caught_err) |err| {
            std.log.err("async AI producer failed during setup: {s}", .{@errorName(err)});
        }

        return alloc_err;
    };
    handle_ptr.* = handle;

    _ = runtime.spawn(@TypeOf(HandleCleanup.run), .{ allocator, handle_ptr }) catch |spawn_err| {
        const cleanup_ptr = handle_ptr;
        defer allocator.destroy(cleanup_ptr);

        var cleanup = cleanup_ptr.*;
        var caught_err: ?anyerror = null;
        cleanup.await() catch |err| {
            caught_err = err;
        };
        cleanup.deinit();

        if (caught_err) |err| {
            std.log.err("async AI producer failed during setup: {s}", .{@errorName(err)});
        }

        return spawn_err;
    };

    return consumer;
}

// Tests
test "AsyncStreamConsumer basic operation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create runtime
    var rt = try async.AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer rt.deinit();

    try rt.start();
    defer rt.shutdown();

    // Create widget
    var widget = try @import("widgets/streaming_text.zig").StreamingText.init(allocator);
    defer widget.deinit();

    // Create consumer
    var consumer = try AsyncStreamConsumer.init(allocator, rt, widget);
    defer consumer.deinit();

    // Start consuming
    try consumer.start();

    // Send some chunks
    try consumer.send("Hello ");
    try consumer.send("World!");

    // Give consumer time to process
    const ts_wait = std.c.timespec{ .sec = 0, .nsec = 50 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&ts_wait, null);

    // Stop
    consumer.stop();

    // Verify text was received
    const text = widget.getText();
    try testing.expect(std.mem.indexOf(u8, text, "Hello") != null);
    try testing.expect(std.mem.indexOf(u8, text, "World") != null);
}
