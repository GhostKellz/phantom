const std = @import("std");

pub fn main() !void {
    std.debug.print("monotonic type: {s}\n", .{@typeName(@TypeOf(std.posix.CLOCK.MONOTONIC))});
}
