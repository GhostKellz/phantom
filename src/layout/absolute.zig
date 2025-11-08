//! Absolute positioning helper that resolves offsets and sizes using shared
//! layout Dimension helpers. Designed for overlays, popovers, and manual
//! placement scenarios where items do not participate in flow layouts.
const std = @import("std");
const geom = @import("../geometry.zig");
const types = @import("types.zig");

const Rect = geom.Rect;
const Dimension = types.Dimension;
const ItemRect = types.ItemRect;

/// Configuration for an absolutely positioned item.
pub const Item = struct {
    id: ?u32 = null,
    x: Dimension = .auto,
    y: Dimension = .auto,
    width: Dimension = .auto,
    height: Dimension = .auto,
};

/// Compute absolute rectangles for the provided items inside `area`.
pub fn compute(allocator: std.mem.Allocator, items: []const Item, area: Rect) ![]ItemRect {
    if (items.len == 0) return &[_]ItemRect{};

    var total_width_fraction: u32 = 0;
    var total_height_fraction: u32 = 0;
    var total_x_fraction: u32 = 0;
    var total_y_fraction: u32 = 0;

    for (items) |item| {
        total_width_fraction += fractionWeight(item.width);
        total_height_fraction += fractionWeight(item.height);
        total_x_fraction += fractionWeight(item.x);
        total_y_fraction += fractionWeight(item.y);
    }

    var results = try allocator.alloc(ItemRect, items.len);
    errdefer allocator.free(results);

    for (items, 0..) |item, idx| {
        const offset_x = resolveAbsolute(item.x, area.width, total_x_fraction, 0, area.width);
        const offset_y = resolveAbsolute(item.y, area.height, total_y_fraction, 0, area.height);

        const remaining_width = if (area.width > offset_x) area.width - offset_x else 0;
        const remaining_height = if (area.height > offset_y) area.height - offset_y else 0;

        const width = resolveAbsolute(item.width, area.width, total_width_fraction, remaining_width, remaining_width);
        const height = resolveAbsolute(item.height, area.height, total_height_fraction, remaining_height, remaining_height);

        const rect = Rect{
            .x = area.x + offset_x,
            .y = area.y + offset_y,
            .width = width,
            .height = height,
        };

        results[idx] = ItemRect{ .id = item.id, .rect = types.clampRectToParent(rect, area) };
    }

    return results;
}

fn fractionWeight(dim: Dimension) u32 {
    return switch (dim) {
        .fraction => |weight| if (weight == 0) 1 else weight,
        else => 0,
    };
}

fn resolveAbsolute(dim: Dimension, reference: u16, total_fraction: u32, default_value: u16, limit: u16) u16 {
    var resolved: u16 = default_value;
    switch (dim) {
        .auto => {},
        .px => |px| resolved = @min(px, reference),
        .percent => |pct| resolved = types.resolveDimension(.{ .percent = pct }, reference) orelse default_value,
        .fraction => |weight| {
            const w = if (weight == 0) 1 else weight;
            if (total_fraction == 0) {
                resolved = reference;
            } else {
                const share = (@as(u64, reference) * @as(u64, w)) / @as(u64, total_fraction);
                const share_i32: i32 = @intCast(@min(share, @as(u64, std.math.maxInt(i32))));
                resolved = types.clampToU16(share_i32);
            }
        },
    }

    return if (limit == 0) 0 else @min(resolved, limit);
}

const testing = std.testing;

test "absolute percent positioning" {
    const items = [_]Item{
        .{ .x = .percent(50), .y = .percent(50), .width = .percent(50), .height = .percent(50) },
        .{ .x = .px(5), .y = .px(2), .width = .px(10), .height = .px(3) },
    };

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 40 };
    const rects = try compute(testing.allocator, &items, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 50), rects[0].rect.x);
    try testing.expectEqual(@as(u16, 50), rects[0].rect.y);
    try testing.expectEqual(@as(u16, 50), rects[0].rect.width);
    try testing.expectEqual(@as(u16, 50), rects[0].rect.height);
    try testing.expectEqual(@as(u16, 5), rects[1].rect.x);
    try testing.expectEqual(@as(u16, 2), rects[1].rect.y);
}

test "absolute fraction sizing shares width" {
    const items = [_]Item{
        .{ .width = .fraction(1) },
        .{ .x = .fraction(1), .width = .fraction(2) },
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    const rects = try compute(testing.allocator, &items, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 0), rects[0].rect.x);
    try testing.expect(rects[0].rect.width <= 30);
    try testing.expect(rects[1].rect.x >= rects[0].rect.width);
}
