//! Async Runtime Integration for Phantom TUI
//! Provides non-blocking operations using zsync async runtime
//! Essential for LSP operations (Grim) and AI streaming (Zeke)

const std = @import("std");
const zsync = @import("zsync");
const phantom = @import("../root.zig");

/// Async runtime configuration
pub const Config = struct {
    /// Number of worker threads (0 = auto-detect CPU count)
    worker_threads: u32 = 0,

    /// Enable debug logging
    debug_logging: bool = false,

    /// Max concurrent tasks
    max_tasks: u32 = 1024,
};

/// Async runtime for non-blocking operations
pub const AsyncRuntime = struct {
    allocator: std.mem.Allocator,
    runtime: *zsync.Runtime,
    config: Config,
    running: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: Config) !*AsyncRuntime {
        const self = try allocator.create(AsyncRuntime);
        errdefer allocator.destroy(self);

        // Initialize zsync runtime
        const worker_count = if (config.worker_threads == 0)
            @as(u32, @intCast(try std.Thread.getCpuCount()))
        else
            config.worker_threads;

        const runtime_config = zsync.Config{
            .worker_threads = worker_count,
            .enable_diagnostics = config.debug_logging,
        };

        const runtime = try zsync.Runtime.init(allocator, runtime_config);
        errdefer runtime.deinit();

        self.* = AsyncRuntime{
            .allocator = allocator,
            .runtime = runtime,
            .config = config,
        };

        return self;
    }

    pub fn deinit(self: *AsyncRuntime) void {
        if (self.running) {
            self.shutdown();
        }
        self.runtime.deinit();
        self.allocator.destroy(self);
    }

    /// Start the async runtime
    pub fn start(self: *AsyncRuntime) !void {
        if (self.running) return error.AlreadyRunning;
        try self.runtime.start();
        self.running = true;
    }

    /// Shutdown the async runtime gracefully
    pub fn shutdown(self: *AsyncRuntime) void {
        if (!self.running) return;
        self.runtime.shutdown();
        self.running = false;
    }

    /// Spawn an async task
    /// Returns a TaskHandle that can be awaited for the result
    pub fn spawn(
        self: *AsyncRuntime,
        comptime Func: type,
        args: anytype,
    ) !TaskHandle(Func) {
        if (!self.running) return error.RuntimeNotRunning;

        const handle = try zsync.spawnTask(self.runtime, Func, args);
        return TaskHandle(Func){ .handle = handle };
    }

    /// Spawn an async task on a specific worker
    pub fn spawnOn(
        self: *AsyncRuntime,
        worker_id: u32,
        comptime Func: type,
        args: anytype,
    ) !TaskHandle(Func) {
        if (!self.running) return error.RuntimeNotRunning;

        const handle = try zsync.spawnOn(self.runtime, worker_id, Func, args);
        return TaskHandle(Func){ .handle = handle };
    }

    /// Yield the current task to allow other tasks to run
    pub fn yield(self: *AsyncRuntime) !void {
        _ = self;
        try zsync.yieldTask();
    }

    /// Sleep for a specified duration (milliseconds)
    pub fn sleep(self: *AsyncRuntime, ms: u64) !void {
        _ = self;
        try zsync.sleepMs(ms);
    }

    /// Get runtime statistics
    pub fn getStats(self: *AsyncRuntime) RuntimeStats {
        const zsync_stats = self.runtime.getStats();
        return RuntimeStats{
            .total_tasks = zsync_stats.tasks_spawned,
            .completed_tasks = zsync_stats.tasks_completed,
            .pending_tasks = zsync_stats.tasks_spawned - zsync_stats.tasks_completed,
            .worker_threads = self.config.worker_threads,
        };
    }
};

/// Task handle for awaiting async results
pub fn TaskHandle(comptime Func: type) type {
    return struct {
        handle: zsync.TaskHandle(Func),

        const Self = @This();

        /// Wait for the task to complete and return its result
        pub fn await(self: *Self) !@TypeOf(Func).ReturnType {
            return try self.handle.await();
        }

        /// Check if the task has completed
        pub fn isDone(self: *const Self) bool {
            return self.handle.isDone();
        }

        /// Cancel the task
        pub fn cancel(self: *Self) void {
            self.handle.cancel();
        }
    };
}

/// Runtime statistics
pub const RuntimeStats = struct {
    total_tasks: u64,
    completed_tasks: u64,
    pending_tasks: u64,
    worker_threads: u32,
};

/// Create a channel for async communication
pub fn createChannel(
    allocator: std.mem.Allocator,
    comptime T: type,
    capacity: usize,
) !*Channel(T) {
    return try Channel(T).init(allocator, capacity);
}

/// Async channel for task communication
pub fn Channel(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        channel: zsync.Channel(T),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.* = Self{
                .allocator = allocator,
                .channel = try zsync.boundedChannel(T, capacity),
            };

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.channel.deinit();
            self.allocator.destroy(self);
        }

        /// Send a value to the channel (blocks if full)
        pub fn send(self: *Self, value: T) !void {
            try self.channel.send(value);
        }

        /// Receive a value from the channel (blocks if empty)
        pub fn receive(self: *Self) !T {
            return try self.channel.receive();
        }

        /// Try to send without blocking
        pub fn trySend(self: *Self, value: T) !bool {
            return try self.channel.trySend(value);
        }

        /// Try to receive without blocking
        pub fn tryReceive(self: *Self) !?T {
            return try self.channel.tryReceive();
        }
    };
}

// Tests
test "AsyncRuntime initialization" {
    const testing = std.testing;

    var runtime = try AsyncRuntime.init(testing.allocator, .{
        .worker_threads = 2,
        .debug_logging = false,
    });
    defer runtime.deinit();

    try testing.expect(!runtime.running);
    try testing.expectEqual(@as(u32, 2), runtime.config.worker_threads);
}

test "AsyncRuntime start and shutdown" {
    const testing = std.testing;

    var runtime = try AsyncRuntime.init(testing.allocator, .{
        .worker_threads = 1,
    });
    defer runtime.deinit();

    try runtime.start();
    try testing.expect(runtime.running);

    runtime.shutdown();
    try testing.expect(!runtime.running);
}

// Example async function for testing
fn exampleAsyncTask(x: i32, y: i32) !i32 {
    try zsync.sleepMs(10); // Simulate async work
    return x + y;
}

test "AsyncRuntime spawn task" {
    const testing = std.testing;

    var runtime = try AsyncRuntime.init(testing.allocator, .{
        .worker_threads = 1,
    });
    defer runtime.deinit();

    try runtime.start();
    defer runtime.shutdown();

    var task = try runtime.spawn(@TypeOf(exampleAsyncTask), .{ 10, 20 });
    const result = try task.await();

    try testing.expectEqual(@as(i32, 30), result);
}
