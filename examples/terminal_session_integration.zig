//! Terminal Session Integration Demo
//! Shows how to bridge the PTY manager into the Phantom app tick loop.

const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try phantom.async_runtime.AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    std.debug.print("runtime started? {any}\n", .{runtime.running});
}
