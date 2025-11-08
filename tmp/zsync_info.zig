const std = @import("std");
const zsync = @import("zsync");

comptime {
    @compileLog(@TypeOf(zsync.Runtime.init));
}

pub fn main() void {}
