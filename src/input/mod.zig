//! Input system module exports
const std = @import("std");

// Input handling types
pub const InputHandler = @import("handler.zig").InputHandler;

test {
    _ = @import("handler.zig");
}
