//! Async runtime utilities for Phantom TUI with zsync integration
const std = @import("std");
const zsync = @import("zsync");

/// Task handle for async operations
pub const Task = struct {
    id: u64,
    completed: std.atomic.Value(bool),
    result: ?anyerror = null,

    pub fn init(id: u64) Task {
        return Task{ 
            .id = id,
            .completed = std.atomic.Value(bool).init(false),
        };
    }

    pub fn isCompleted(self: *const Task) bool {
        return self.completed.load(.acquire);
    }

    pub fn complete(self: *Task) void {
        self.completed.store(true, .release);
    }

    pub fn wait(self: *Task) void {
        while (!self.isCompleted()) {
            std.Thread.sleep(1_000_000); // 1ms
        }
    }
};

/// Async runtime manager with zsync integration
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    next_task_id: std.atomic.Value(u64),
    tasks: std.ArrayList(Task),
    runtime: *zsync.runtime.Runtime,

    pub fn init(allocator: std.mem.Allocator) !Runtime {
        return Runtime{
            .allocator = allocator,
            .next_task_id = std.atomic.Value(u64).init(1),
            .tasks = std.ArrayList(Task){},
            .runtime = try zsync.runtime.Runtime.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.runtime.deinit();
        self.tasks.deinit(self.allocator);
    }

    pub fn spawn(self: *Runtime, comptime func: anytype, args: anytype) !Task {
        const task_id = self.next_task_id.fetchAdd(1, .monotonic);
        var task = Task.init(task_id);

        // Create async wrapper for the function
        const AsyncWrapper = struct {
            fn run(rt: *Runtime, t: *Task, f: anytype, a: anytype) void {
                defer t.complete();
                _ = rt;
                @call(.auto, f, a);
            }
        };

        // Queue the task for execution with zsync runtime
        const handle = try self.runtime.spawn(AsyncWrapper.run, .{self, &task, func, args});
        _ = handle; // Store handle if needed for cancellation

        try self.tasks.append(self.allocator, task);
        return task;
    }

    pub fn sleep(duration_ms: u64) void {
        std.Thread.sleep(duration_ms * 1_000_000); // Convert to nanoseconds
    }

    pub fn yield() void {
        // Yield to other threads
        std.Thread.yield() catch {
            // Fallback to short sleep if yield fails
            std.Thread.sleep(100_000); // 0.1ms
        };
    }

    pub fn runUntilComplete(self: *Runtime) void {
        self.runtime.run();
    }
};

/// Global runtime instance (simplified)
var global_runtime: ?Runtime = null;

pub fn getRuntime() !*Runtime {
    if (global_runtime == null) {
        return error.RuntimeNotInitialized;
    }
    return &global_runtime.?;
}

pub fn initRuntime(allocator: std.mem.Allocator) !void {
    global_runtime = try Runtime.init(allocator);
}

pub fn deinitRuntime() void {
    if (global_runtime) |*runtime| {
        runtime.deinit();
        global_runtime = null;
    }
}

test "Runtime basic operations" {
    const allocator = std.testing.allocator;

    var runtime = Runtime.init(allocator);
    defer runtime.deinit();

    const task = try runtime.spawn(testFunc, .{});
    try std.testing.expect(!task.isCompleted());
}

fn testFunc() void {
    // Test function for spawning
}
