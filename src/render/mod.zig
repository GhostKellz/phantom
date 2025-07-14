//! Rendering system module exports
const std = @import("std");

// Core rendering types
pub const Renderer = @import("renderer.zig").Renderer;

test {
    _ = @import("renderer.zig");
}
