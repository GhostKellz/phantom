const std = @import("std");
const zigzag = @import("zigzag");

pub fn main() !void {}

comptime {
    @compileLog(@TypeOf(zigzag));
    @compileLog(@typeInfo(zigzag));

    const root_info = @typeInfo(@TypeOf(zigzag));
    _ = root_info;
}
