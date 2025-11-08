//! Async test harness utilities for Phantom
const std = @import("std");
const runtime_mod = @import("runtime.zig");
const nursery_mod = @import("nursery.zig");

const AsyncRuntime = runtime_mod.AsyncRuntime;
const Nursery = nursery_mod.Nursery;

pub const TestHarness = struct {
    runtime: *AsyncRuntime,
    nursery: *Nursery,

    pub fn spawn(self: *TestHarness, comptime Func: type, args: anytype) !void {
        try self.nursery.spawn(Func, args);
    }

    pub fn waitAll(self: *TestHarness) !void {
        try self.nursery.waitAll();
    }

    pub fn cancelAll(self: *TestHarness) void {
        self.nursery.cancelAll();
    }

    pub fn hasPending(self: *TestHarness) bool {
        return !self.nursery.isEmpty();
    }
};

pub fn withTestHarness(
    allocator: std.mem.Allocator,
    config: runtime_mod.Config,
    comptime Body: fn (*TestHarness) anyerror!void,
) !void {
    var runtime = try AsyncRuntime.init(allocator, config);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.shutdown();

    var nursery = Nursery.init(allocator, runtime);
    defer nursery.deinit();

    var harness = TestHarness{
        .runtime = runtime,
        .nursery = &nursery,
    };

    try Body(&harness);

    if (harness.hasPending()) {
        try harness.waitAll();
    }
}

// Tests ---------------------------------------------------------------------
const testing = std.testing;

fn asyncIncrement(state: *std.atomic.Value(i32), value: i32) !void {
    state.fetchAdd(value, .monotonic);
}

const HarnessContext = struct {
    pub var total = std.atomic.Value(i32).init(0);

    pub fn body(harness: *TestHarness) !void {
        total.store(0, .release);
        try harness.spawn(asyncIncrement, .{ &total, 1 });
        try harness.spawn(asyncIncrement, .{ &total, 2 });
    }
};

test "withTestHarness executes async body" {
    try withTestHarness(testing.allocator, .{ .worker_threads = 1 }, HarnessContext.body);
    try testing.expectEqual(@as(i32, 3), HarnessContext.total.load(.acquire));
}
