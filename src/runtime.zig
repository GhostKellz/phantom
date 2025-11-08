const std = @import("std");
const async_runtime = @import("async/runtime.zig");

pub const AsyncRuntime = async_runtime.AsyncRuntime;
pub const Config = async_runtime.Config;
pub const LifecycleHooks = async_runtime.LifecycleHooks;
pub const TaskHandle = async_runtime.TaskHandle;
pub const Channel = async_runtime.Channel;
pub const createChannel = async_runtime.createChannel;
pub const RuntimeStats = async_runtime.RuntimeStats;

pub fn initRuntime(allocator: std.mem.Allocator) !void {
    _ = try async_runtime.startGlobal(allocator, .{});
}

pub fn initRuntimeWithConfig(allocator: std.mem.Allocator, config: Config) !void {
    _ = try async_runtime.startGlobal(allocator, config);
}

pub fn deinitRuntime() void {
    async_runtime.shutdownGlobal();
}

pub fn getRuntime() !*AsyncRuntime {
    return async_runtime.globalRuntime() orelse error.RuntimeNotInitialized;
}

test "legacy initRuntime forwards to async runtime" {
    const allocator = std.testing.allocator;
    try initRuntime(allocator);
    defer deinitRuntime();

    const runtime = try getRuntime();
    try std.testing.expect(runtime.isRunning());
}
