//! Shared layout types and helpers for Phantom's layout engine.
const std = @import("std");
const Rect = @import("../geometry.zig").Rect;

/// Primary axis selection used by flex layouts.
pub const Axis = enum { horizontal, vertical };

/// General purpose dimension descriptor for layout inputs.
pub const Dimension = union(enum) {
    auto,
    px: u16,
    percent: u8,
    fraction: u32,
};

/// Evaluate a dimension against a reference span, returning the resolved size
/// or null when the dimension is `auto`.
pub fn resolveDimension(dim: Dimension, reference: u16) ?u16 {
    return switch (dim) {
        .auto => null,
        .px => |px| @min(px, reference),
        .percent => |pct| {
            const clamped: u8 = if (pct > 100) 100 else pct;
            return @as(u16, @intCast((@as(u32, reference) * clamped) / 100));
        },
        .fraction => |weight| {
            if (weight == 0) return 0;
            return null; // Fractions are handled by callers when distributing extra space.
        },
    };
}

/// Utility to clamp a value into `u16` while ensuring it cannot wrap.
pub fn clampToU16(value: i32) u16 {
    return if (value <= 0) 0 else if (value >= std.math.maxInt(u16)) std.math.maxInt(u16) else @intCast(value);
}

/// Bounding helper that ensures a rectangle stays within parent bounds.
pub fn clampRectToParent(rect: Rect, parent: Rect) Rect {
    const right = @min(rect.x + rect.width, parent.x + parent.width);
    const bottom = @min(rect.y + rect.height, parent.y + parent.height);
    const width = if (right <= rect.x) 0 else right - rect.x;
    const height = if (bottom <= rect.y) 0 else bottom - rect.y;
    return Rect{
        .x = rect.x,
        .y = rect.y,
        .width = width,
        .height = height,
    };
}

/// Represents an output rectangle paired with an optional stable identifier so
/// callers can map layout results back to their respective widgets or nodes.
pub const ItemRect = struct {
    id: ?u32 = null,
    rect: Rect,
};
