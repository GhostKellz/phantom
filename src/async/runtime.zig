//! Async Runtime Integration for Phantom TUI
//! Provides non-blocking operations using zsync async runtime
//! Essential for LSP operations (Grim) and AI streaming (Zeke)

const std = @import("std");
const zsync = @import("zsync");
const phantom = @import("../root.zig");
const time_utils = @import("../time/utils.zig");

pub const LifecycleHooks = struct {
    context: ?*anyopaque = null,
    on_start: ?*const fn (*AsyncRuntime, ?*anyopaque) void = null,
    on_shutdown: ?*const fn (*AsyncRuntime, ?*anyopaque) void = null,
    on_panic: ?*const fn (*AsyncRuntime, anyerror, ?*anyopaque) void = null,
};

/// Async runtime configuration
pub const Config = struct {
    /// Number of worker threads (0 = auto-detect CPU count)
    worker_threads: u32 = 0,

    /// Enable debug logging
    debug_logging: bool = false,

    /// Max concurrent tasks
    max_tasks: u32 = 1024,

    /// Human-friendly runtime name (used in diagnostics/logging)
    name: []const u8 = "phantom-runtime",

    /// Lifecycle hooks that fire on start/shutdown/panic
    hooks: LifecycleHooks = .{},
};

/// Async runtime for non-blocking operations
pub const AsyncRuntime = struct {
    allocator: std.mem.Allocator,
    runtime: *zsync.Runtime,
    config: Config,
    running: bool = false,
    name: []const u8,
    hooks: LifecycleHooks,
    start_timestamp_ns: ?i128 = null,

    pub fn init(allocator: std.mem.Allocator, config: Config) !*AsyncRuntime {
        const self = try allocator.create(AsyncRuntime);
        errdefer allocator.destroy(self);

        // Initialize zsync runtime
        const worker_count = if (config.worker_threads == 0)
            @as(u32, @intCast(try std.Thread.getCpuCount()))
        else
            config.worker_threads;

        var effective_config = config;
        effective_config.worker_threads = worker_count;

        const runtime_config = zsync.Config{
            .execution_model = .auto,
            .thread_pool_threads = worker_count,
            .max_green_threads = config.max_tasks,
            .enable_debugging = config.debug_logging,
        };

        const runtime = try zsync.Runtime.init(allocator, runtime_config);
        errdefer runtime.deinit();

        self.* = AsyncRuntime{
            .allocator = allocator,
            .runtime = runtime,
            .config = effective_config,
            .name = effective_config.name,
            .hooks = effective_config.hooks,
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
        self.runtime.setGlobal();
        self.running = true;
        self.start_timestamp_ns = @intCast(time_utils.monotonicTimestampNs());

        if (self.config.debug_logging) {
            std.log.info(
                "AsyncRuntime '{s}' started (workers={}, max_tasks={})",
                .{ self.name, self.config.worker_threads, self.config.max_tasks },
            );
        }

        if (self.hooks.on_start) |hook| {
            hook(self, self.hooks.context);
        }
    }

    /// Shutdown the async runtime gracefully
    pub fn shutdown(self: *AsyncRuntime) void {
        if (!self.running) return;
        self.runtime.shutdown();
        self.running = false;
        if (self.hooks.on_shutdown) |hook| {
            hook(self, self.hooks.context);
        }
        if (self.config.debug_logging) {
            self.logStats();
            std.log.info("AsyncRuntime '{s}' shutdown", .{self.name});
        }
        self.start_timestamp_ns = null;
    }

    pub fn isRunning(self: *const AsyncRuntime) bool {
        return self.running;
    }

    pub fn uptimeMs(self: *const AsyncRuntime) ?i64 {
        if (self.start_timestamp_ns) |started| {
            const elapsed_ns = time_utils.monotonicTimestampNs() - @as(u64, @intCast(started));
            return @intCast(elapsed_ns / std.time.ns_per_ms);
        }
        return null;
    }

    /// Spawn an async task (functions must return `!void`)
    pub fn spawn(
        self: *AsyncRuntime,
        comptime Func: type,
        args: anytype,
    ) !TaskHandle(Func) {
        if (!self.running) return error.RuntimeNotRunning;
        const future = try self.runtime.spawn(Func, args);
        return TaskHandle(Func){
            .runtime = self.runtime,
            .future = future,
        };
    }

    /// Spawn an async task on a specific worker (worker hint currently ignored)
    pub fn spawnOn(
        self: *AsyncRuntime,
        worker_id: u32,
        comptime Func: type,
        args: anytype,
    ) !TaskHandle(Func) {
        _ = worker_id; // thread pool scheduling handled by zsync runtime
        return self.spawn(Func, args);
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
        const metrics = self.runtime.getMetrics();
        return RuntimeStats{
            .tasks_spawned = metrics.tasks_spawned.load(.monotonic),
            .tasks_completed = metrics.tasks_completed.load(.monotonic),
            .futures_created = metrics.futures_created.load(.monotonic),
            .futures_cancelled = metrics.futures_cancelled.load(.monotonic),
            .io_operations = metrics.total_io_operations.load(.monotonic),
            .worker_threads = self.config.worker_threads,
            .runtime_name = self.name,
            .uptime_ms = self.uptimeMs(),
        };
    }

    pub fn logStats(self: *AsyncRuntime) void {
        const stats = self.getStats();
        const pending = if (stats.tasks_spawned >= stats.tasks_completed)
            stats.tasks_spawned - stats.tasks_completed
        else
            0;

        std.log.info(
            "AsyncRuntime metrics name={s} uptime_ms={d} spawned={d} completed={d} pending={d} io_ops={d}",
            .{
                stats.runtime_name,
                stats.uptime_ms orelse 0,
                stats.tasks_spawned,
                stats.tasks_completed,
                pending,
                stats.io_operations,
            },
        );
    }
};

/// Task handle for awaiting async results
pub fn TaskHandle(comptime Func: type) type {
    const fn_info = @typeInfo(Func);
    if (fn_info != .@"fn") @compileError("AsyncRuntime.spawn requires a function");
    const return_type_opt = fn_info.@"fn".return_type;
    if (return_type_opt == null) @compileError("AsyncRuntime.spawn expects functions returning !void");
    const ReturnType = return_type_opt.?;
    // TODO: Restore return type validation once Zig compiler bug is resolved

    const FutureState = zsync.Future.State;

    return struct {
        runtime: *zsync.Runtime,
        future: zsync.Future,

        const Self = @This();

        /// Wait for the task to complete
        pub fn await(self: *Self) ReturnType {
            self.future.await() catch |err| {
                return @errorCast(err);
            };
            return;
        }

        /// Check if the task has completed
        pub fn isDone(self: *const Self) bool {
            return self.future.state.load(.acquire) != FutureState.pending;
        }

        /// Cancel the task
        pub fn cancel(self: *Self) void {
            self.future.cancel();
        }

        /// Release runtime resources associated with this task
        pub fn deinit(self: *Self) void {
            self.future.destroy(self.runtime.allocator);
        }
    };
}

/// Runtime statistics
pub const RuntimeStats = struct {
    tasks_spawned: u64,
    tasks_completed: u64,
    futures_created: u64,
    futures_cancelled: u64,
    io_operations: u64,
    worker_threads: u32,
    runtime_name: []const u8,
    uptime_ms: ?i64,
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

const GlobalState = struct {
    runtime: ?*AsyncRuntime = null,
};

var global_state = GlobalState{};
var global_mutex = std.Thread.Mutex{};

pub fn ensureGlobal(allocator: std.mem.Allocator, config: Config) !*AsyncRuntime {
    global_mutex.lock();
    defer global_mutex.unlock();

    if (global_state.runtime) |runtime| {
        return runtime;
    }

    const runtime = try AsyncRuntime.init(allocator, config);
    global_state.runtime = runtime;
    return runtime;
}

pub fn startGlobal(allocator: std.mem.Allocator, config: Config) !*AsyncRuntime {
    var runtime = try ensureGlobal(allocator, config);
    if (!runtime.isRunning()) {
        try runtime.start();
    }
    return runtime;
}

pub fn globalRuntime() ?*AsyncRuntime {
    global_mutex.lock();
    defer global_mutex.unlock();
    return global_state.runtime;
}

pub fn shutdownGlobal() void {
    var runtime: ?*AsyncRuntime = null;

    global_mutex.lock();
    if (global_state.runtime) |rt| {
        runtime = rt;
        global_state.runtime = null;
    }
    global_mutex.unlock();

    if (runtime) |rt| {
        rt.deinit();
    }
}

// Tests
test "AsyncRuntime initialization" {
    const testing = std.testing;

    var runtime = try AsyncRuntime.init(testing.allocator, .{
        .worker_threads = 2,
        .name = "test-runtime",
    });
    defer runtime.deinit();

    try testing.expect(!runtime.isRunning());
    try testing.expectEqual(@as(u32, 2), runtime.config.worker_threads);
    try testing.expectEqualStrings("test-runtime", runtime.name);
}

test "AsyncRuntime start invokes hooks" {
    const testing = std.testing;

    const HookState = struct {
        start: std.atomic.Value(bool),
        stop: std.atomic.Value(bool),
    };

    var hook_state = HookState{
        .start = std.atomic.Value(bool).init(false),
        .stop = std.atomic.Value(bool).init(false),
    };

    const hooks = LifecycleHooks{
        .context = &hook_state,
        .on_start = struct {
            fn onStart(rt: *AsyncRuntime, ctx: ?*anyopaque) void {
                _ = rt;
                const state_ptr = @as(*HookState, @ptrCast(@alignCast(ctx.?)));
                state_ptr.start.store(true, .release);
            }
        }.onStart,
        .on_shutdown = struct {
            fn onShutdown(rt: *AsyncRuntime, ctx: ?*anyopaque) void {
                _ = rt;
                const state_ptr = @as(*HookState, @ptrCast(@alignCast(ctx.?)));
                state_ptr.stop.store(true, .release);
            }
        }.onShutdown,
    };

    var runtime = try AsyncRuntime.init(testing.allocator, .{
        .worker_threads = 1,
        .hooks = hooks,
    });
    defer runtime.deinit();

    try runtime.start();
    try testing.expect(runtime.isRunning());
    try testing.expect(hook_state.start.load(.acquire));

    runtime.shutdown();
    try testing.expect(!runtime.isRunning());
    try testing.expect(hook_state.stop.load(.acquire));
}

// Example async function for testing
const ExampleState = struct {
    result: *std.atomic.Value(i32),
};

fn exampleAsyncTask(state: *ExampleState, x: i32, y: i32) !void {
    try zsync.sleepMs(10);
    state.result.store(x + y, .release);
}

test "AsyncRuntime spawn task" {
    const testing = std.testing;

    var runtime = try AsyncRuntime.init(testing.allocator, .{
        .worker_threads = 1,
    });
    defer runtime.deinit();

    try runtime.start();
    defer runtime.shutdown();

    var result_storage = std.atomic.Value(i32).init(0);
    var state = ExampleState{ .result = &result_storage };
    var task = try runtime.spawn(@TypeOf(exampleAsyncTask), .{ &state, 10, 20 });
    defer task.deinit();

    try task.await();

    try testing.expectEqual(@as(i32, 30), result_storage.load(.acquire));
}

test "global runtime manager provides singleton" {
    const testing = std.testing;

    try startGlobal(testing.allocator, .{});
    defer shutdownGlobal();

    const runtime_opt = globalRuntime();
    try testing.expect(runtime_opt != null);
    const runtime = runtime_opt.?;
    try testing.expect(runtime.isRunning());

    // Subsequent start should be idempotent
    try startGlobal(testing.allocator, .{});
    try testing.expectEqual(runtime, (globalRuntime() orelse unreachable));
}
