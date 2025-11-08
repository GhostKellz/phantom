//! Rendering system module exports
const std = @import("std");

// Core rendering types
const renderer = @import("renderer.zig");

pub const Renderer = renderer.Renderer;
pub const RendererConfig = renderer.Config;
pub const RendererStats = renderer.Stats;
pub const RendererTarget = renderer.Target;
pub const RendererBackendPreference = renderer.BackendPreference;

test {
    _ = renderer;
}
