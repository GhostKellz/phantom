//! Nursery helpers for structured asynchronous task management
const std = @import("std");
const ArrayList = std.array_list.Managed;
const runtime_mod = @import("runtime.zig");

const AsyncRuntime = runtime_mod.AsyncRuntime;
const TaskHandle = runtime_mod.TaskHandle;

pub const Nursery = struct {
    allocator: std.mem.Allocator,
    runtime: *AsyncRuntime,
    tasks: ArrayList(TaskSlot),

    const TaskSlot = struct {
        ptr: *anyopaque,
        awaitFn: *const fn (*anyopaque) anyerror!void,
        cancelFn: *const fn (*anyopaque) void,
        deinitFn: *const fn (*anyopaque, std.mem.Allocator) void,
    };

    pub fn init(allocator: std.mem.Allocator, runtime: *AsyncRuntime) Nursery {
        return Nursery{
            .allocator = allocator,
            .runtime = runtime,
            .tasks = ArrayList(TaskSlot).init(allocator),
        };
    }

    pub fn deinit(self: *Nursery) void {
        if (self.tasks.items.len > 0) {
            std.log.warn(
                "Nursery deinit canceling {d} pending task(s)",
                .{self.tasks.items.len},
            );
            self.cancelAll();
        }
        self.tasks.deinit();
    }

    pub fn spawn(self: *Nursery, comptime Func: type, args: anytype) !void {
        const handle = try self.runtime.spawn(Func, args);

        const Node = struct {
            handle: TaskHandle(Func),

            const Self = @This();

            fn await(ptr: *anyopaque) anyerror!void {
                const node = @as(*Self, @ptrCast(@alignCast(ptr)));
                try node.handle.await();
            }

            fn cancel(ptr: *anyopaque) void {
                const node = @as(*Self, @ptrCast(@alignCast(ptr)));
                node.handle.cancel();
            }

            fn deinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const node = @as(*Self, @ptrCast(@alignCast(ptr)));
                node.handle.deinit();
                allocator.destroy(node);
            }
        };

        const node = try self.allocator.create(Node);
        node.* = Node{ .handle = handle };

        try self.tasks.append(TaskSlot{
            .ptr = node,
            .awaitFn = Node.await,
            .cancelFn = Node.cancel,
            .deinitFn = Node.deinit,
        });
    }

    pub fn waitAll(self: *Nursery) !void {
        var first_err: ?anyerror = null;
        for (self.tasks.items) |slot| {
            slot.awaitFn(slot.ptr) catch |err| {
                if (first_err == null) first_err = err;
            };
        }
        self.cleanup();
        if (first_err) |err| return err;
    }

    pub fn cancelAll(self: *Nursery) void {
        for (self.tasks.items) |slot| {
            slot.cancelFn(slot.ptr);
        }
        self.cleanup();
    }

    pub fn isEmpty(self: *Nursery) bool {
        return self.tasks.items.len == 0;
    }

    fn cleanup(self: *Nursery) void {
        for (self.tasks.items) |slot| {
            slot.deinitFn(slot.ptr, self.allocator);
        }
        self.tasks.clearRetainingCapacity();
    }
};

// Tests ---------------------------------------------------------------------
const testing = std.testing;

fn sampleTask(counter: *std.atomic.Value(u32), value: u32) !void {
    counter.fetchAdd(value, .monotonic);
}

fn failingTask() !void {
    return error.IntentionalFailure;
}

test "Nursery waits for spawned tasks" {
    var runtime = try AsyncRuntime.init(testing.allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();

    try runtime.start();
    defer runtime.shutdown();

    var nursery = Nursery.init(testing.allocator, runtime);
    defer nursery.deinit();

    var counter = std.atomic.Value(u32).init(0);
    try nursery.spawn(sampleTask, .{ &counter, 2 });
    try nursery.spawn(sampleTask, .{ &counter, 3 });

    try nursery.waitAll();
    try testing.expectEqual(@as(u32, 5), counter.load(.acquire));
}

test "Nursery propagates errors and cleans up" {
    var runtime = try AsyncRuntime.init(testing.allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();

    try runtime.start();
    defer runtime.shutdown();

    var nursery = Nursery.init(testing.allocator, runtime);
    defer nursery.deinit();

    try nursery.spawn(failingTask, .{});
    try nursery.spawn(sampleTask, .{ &std.atomic.Value(u32).init(0), 1 });

    const err = nursery.waitAll() catch |caught| caught;
    try testing.expect(err == error.IntentionalFailure);
    try testing.expect(nursery.isEmpty());
}
