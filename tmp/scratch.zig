const std = @import("std");

pub fn main() void {}

comptime {
    const info = @typeInfo(anyerror!void);
    @compileLog(info);
}
