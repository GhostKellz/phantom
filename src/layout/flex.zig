//! Flexbox-style layout engine for Phantom.
//! Provides a Ratatui-like API with configurable direction, alignment,
//! grow/shrink behaviour, and gaps.

const std = @import("std");
const geom = @import("../geometry.zig");
const types = @import("types.zig");
const engine = @import("engine/mod.zig");

const Rect = geom.Rect;
const Axis = types.Axis;
const Dimension = types.Dimension;
const ItemRect = types.ItemRect;

/// Main-axis alignment options.
pub const AlignMain = enum {
    start,
    center,
    end,
    space_between,
    space_around,
    space_evenly,
};

/// Cross-axis alignment options.
pub const AlignCross = enum {
    start,
    center,
    end,
    stretch,
};

/// Flex item configuration.
pub const Item = struct {
    id: ?u32 = null,
    basis: Dimension = .auto,
    grow: f32 = 1.0,
    shrink: f32 = 1.0,
    cross: Dimension = .auto,
    align_self: ?AlignCross = null,
};

/// Flex container specification.
pub const Spec = struct {
    direction: Axis = .horizontal,
    gap: u16 = 0,
    align_main: AlignMain = .start,
    align_cross: AlignCross = .stretch,
    items: []const Item,
};

/// Compute rectangles for each flex item within the supplied area.
pub fn compute(allocator: std.mem.Allocator, spec: Spec, area: Rect) ![]ItemRect {
    if (spec.items.len == 0) return &[_]ItemRect{};

    const main_extent: u16 = switch (spec.direction) {
        .horizontal => area.width,
        .vertical => area.height,
    };
    const cross_extent: u16 = switch (spec.direction) {
        .horizontal => area.height,
        .vertical => area.width,
    };

    const count = spec.items.len;

    var base_sizes = try allocator.alloc(u32, count);
    defer allocator.free(base_sizes);

    var cross_sizes = try allocator.alloc(u16, count);
    defer allocator.free(cross_sizes);

    var cross_offsets = try allocator.alloc(u16, count);
    defer allocator.free(cross_offsets);

    var grow_weights = try allocator.alloc(f64, count);
    defer allocator.free(grow_weights);

    var shrink_weights = try allocator.alloc(f64, count);
    defer allocator.free(shrink_weights);

    var fraction_weights = try allocator.alloc(u32, count);
    defer allocator.free(fraction_weights);

    var used: u64 = 0;
    var total_fraction: u32 = 0;
    var total_gap: u64 = 0;

    if (count > 1) {
        total_gap = @as(u64, spec.gap) * @as(u64, count - 1);
        used += total_gap;
    }

    for (spec.items, 0..) |item, idx| {
        fraction_weights[idx] = 0;
        grow_weights[idx] = if (item.grow > 0) @floatCast(item.grow) else 0.0;
        shrink_weights[idx] = if (item.shrink > 0) @floatCast(item.shrink) else 0.0;

        var base: u32 = 0;
        switch (item.basis) {
            .auto => base = 0,
            .px => |px| base = @min(@as(u32, px), @as(u32, main_extent)),
            .percent => |pct| {
                const clamped: u8 = if (pct > 100) 100 else pct;
                base = (@as(u32, main_extent) * clamped) / 100;
            },
            .fraction => |weight| {
                fraction_weights[idx] = if (weight == 0) 1 else weight;
                grow_weights[idx] = @floatFromInt(fraction_weights[idx]);
                base = 0;
                total_fraction += fraction_weights[idx];
            },
        }

        base_sizes[idx] = base;
        used += base;

        const alignment = item.align_self orelse spec.align_cross;
        const resolved_cross = types.resolveDimension(item.cross, cross_extent) orelse switch (alignment) {
            .stretch => cross_extent,
            else => cross_extent,
        };
        const cross_size = @min(resolved_cross, cross_extent);

        cross_sizes[idx] = cross_size;
        cross_offsets[idx] = switch (alignment) {
            .stretch => 0,
            .start => 0,
            .center => @intCast((@as(u32, cross_extent) - cross_size) / 2),
            .end => @intCast(@as(u32, cross_extent) - cross_size),
        };
    }

    var remaining: i64 = @as(i64, main_extent) - @as(i64, used);

    if (remaining > 0 and total_fraction > 0) {
        var distributed: i64 = 0;
        for (spec.items, 0..) |_, idx| {
            if (fraction_weights[idx] == 0) continue;
            const share = (@as(i64, fraction_weights[idx]) * remaining) / @as(i64, total_fraction);
            if (share > 0) {
                base_sizes[idx] += @intCast(share);
                distributed += share;
            }
        }
        remaining -= distributed;
    }

    if (remaining > 0) {
        var weight_sum: f64 = 0.0;
        for (grow_weights) |w| weight_sum += w;

        if (weight_sum > 0.0) {
            var distributed_total: i64 = 0;
            for (spec.items, 0..) |_, idx| {
                if (grow_weights[idx] <= 0.0) continue;
                const proportion = grow_weights[idx] / weight_sum;
                const share_f = proportion * @as(f64, @floatFromInt(remaining));
                const share = @as(i64, @intFromFloat(std.math.max(0.0, share_f)));
                if (share > 0) {
                    base_sizes[idx] += @intCast(share);
                    distributed_total += share;
                }
            }

            const leftover = remaining - distributed_total;
            if (leftover > 0) {
                for (spec.items, 0..) |_, idx| {
                    if (grow_weights[idx] > 0.0) {
                        base_sizes[idx] += @intCast(leftover);
                        break;
                    }
                }
            }
            remaining = 0;
        }
    }

    if (remaining < 0) {
        var deficit: i64 = -remaining;
        var shrink_sum: f64 = 0.0;
        for (spec.items, 0..) |_, idx| {
            if (base_sizes[idx] > 0 and shrink_weights[idx] > 0) {
                shrink_sum += shrink_weights[idx];
            }
        }

        if (shrink_sum > 0.0) {
            var reclaimed: i64 = 0;
            for (spec.items, 0..) |_, idx| {
                if (base_sizes[idx] == 0 or shrink_weights[idx] == 0) continue;
                const proportion = shrink_weights[idx] / shrink_sum;
                const shrink_f = proportion * @as(f64, @floatFromInt(deficit));
                var shrink_amt = @as(i64, @intFromFloat(std.math.max(0.0, shrink_f)));
                if (shrink_amt > @as(i64, base_sizes[idx])) {
                    shrink_amt = @intCast(base_sizes[idx]);
                }
                if (shrink_amt > 0) {
                    base_sizes[idx] -= @intCast(shrink_amt);
                    reclaimed += shrink_amt;
                }
            }
            deficit -= reclaimed;
        }

        remaining = -deficit;
    }

    const content_span = blk: {
        var sum: u64 = total_gap;
        for (base_sizes) |size| sum += size;
        break :blk sum;
    };

    var gap_value = @as(f64, spec.gap);
    var leading: f64 = 0.0;

    if (content_span < main_extent) {
        const free_space = @as(f64, @floatFromInt(main_extent - @as(u16, @intCast(content_span))));
        switch (spec.align_main) {
            .start => {},
            .center => leading = free_space / 2.0,
            .end => leading = free_space,
            .space_between => if (count > 1) {
                gap_value = @as(f64, spec.gap) + free_space / @as(f64, @floatFromInt(count - 1));
            } else {
                leading = free_space / 2.0;
            },
            .space_around => {
                const distributed = free_space / @as(f64, @floatFromInt(count));
                gap_value = @as(f64, spec.gap) + distributed;
                leading = distributed / 2.0;
            },
            .space_evenly => {
                const distributed = free_space / @as(f64, @floatFromInt(count + 1));
                gap_value = @as(f64, spec.gap) + distributed;
                leading = distributed;
            },
        }
    }

    const leading_offset = types.clampToU16(@intFromFloat(leading + 0.5));
    const epsilon_weight: f64 = 1e-6;

    const gap_entries = if (count > 1 and gap_value > 0.0) count - 1 else 0;
    const total_entries = count + gap_entries;

    var weights = try allocator.alloc(engine.WeightSpec, total_entries);
    defer allocator.free(weights);

    var entry_map = try allocator.alloc(?usize, total_entries);
    defer allocator.free(entry_map);

    var total_weight: f64 = 0.0;
    var entry_idx: usize = 0;
    for (spec.items, 0..) |_, idx| {
        const weight = if (base_sizes[idx] > 0)
            @as(f64, @floatFromInt(base_sizes[idx]))
        else
            epsilon_weight;

        weights[entry_idx] = .{ .weight = weight };
        entry_map[entry_idx] = idx;
        total_weight += weight;
        entry_idx += 1;

        if (gap_entries > 0 and idx + 1 < count and gap_value > 0.0) {
            const gap_weight = std.math.max(gap_value, epsilon_weight);
            weights[entry_idx] = .{ .weight = gap_weight };
            entry_map[entry_idx] = null;
            total_weight += gap_weight;
            entry_idx += 1;
        }
    }

    const total_span_weight = total_weight;
    var content_extent = types.clampToU16(@intFromFloat(total_span_weight + 0.5));
    if (content_extent == 0 and total_weight > 0.0) content_extent = 1;

    const available_main = switch (spec.direction) {
        .horizontal => if (area.width > leading_offset) area.width - leading_offset else 0,
        .vertical => if (area.height > leading_offset) area.height - leading_offset else 0,
    };

    if (available_main == 0 or content_extent == 0 or total_weight == 0.0) {
        var results = try allocator.alloc(ItemRect, count);
        errdefer allocator.free(results);

        const start_axis = switch (spec.direction) {
            .horizontal => area.x + leading_offset,
            .vertical => area.y + leading_offset,
        };

        for (spec.items, 0..) |item, idx| {
            const rect = switch (spec.direction) {
                .horizontal => Rect{
                    .x = start_axis,
                    .y = area.y + cross_offsets[idx],
                    .width = 0,
                    .height = cross_sizes[idx],
                },
                .vertical => Rect{
                    .x = area.x + cross_offsets[idx],
                    .y = start_axis,
                    .width = cross_sizes[idx],
                    .height = 0,
                },
            };
            results[idx] = ItemRect{ .id = item.id, .rect = types.clampRectToParent(rect, area) };
        }

        return results;
    }

    if (content_extent > available_main) {
        content_extent = available_main;
    }

    const content_area = switch (spec.direction) {
        .horizontal => Rect{
            .x = area.x + leading_offset,
            .y = area.y,
            .width = content_extent,
            .height = area.height,
        },
        .vertical => Rect{
            .x = area.x,
            .y = area.y + leading_offset,
            .width = area.width,
            .height = content_extent,
        },
    };

    const segments = switch (spec.direction) {
        .horizontal => try engine.splitRow(allocator, content_area, weights[0..entry_idx]),
        .vertical => try engine.splitColumn(allocator, content_area, weights[0..entry_idx]),
    };
    defer allocator.free(segments);

    var results = try allocator.alloc(ItemRect, count);
    errdefer allocator.free(results);

    for (entry_map, 0..) |maybe_idx, seg_idx| {
        if (maybe_idx) |item_idx| {
            const segment = segments[seg_idx];
            var rect = segment;

            switch (spec.direction) {
                .horizontal => {
                    rect.width = segment.width;
                    rect.y = area.y + cross_offsets[item_idx];
                    rect.height = cross_sizes[item_idx];
                },
                .vertical => {
                    rect.height = segment.height;
                    rect.x = area.x + cross_offsets[item_idx];
                    rect.width = cross_sizes[item_idx];
                },
            }

            results[item_idx] = ItemRect{
                .id = spec.items[item_idx].id,
                .rect = types.clampRectToParent(rect, area),
            };
        }
    }

    return results;
}

const testing = std.testing;

test "flex horizontal equal distribution" {
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };
    const items = [_]Item{
        .{},
        .{},
    };

    const spec = Spec{
        .direction = .horizontal,
        .items = &items,
    };

    const rects = try compute(testing.allocator, spec, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 50), rects[0].rect.width);
    try testing.expectEqual(@as(u16, 50), rects[1].rect.width);
}

test "flex vertical gap and alignment" {
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 40 };
    const items = [_]Item{
        .{ .basis = .px(10) },
        .{ .basis = .px(10) },
    };

    const spec = Spec{
        .direction = .vertical,
        .gap = 4,
        .align_main = .center,
        .align_cross = .stretch,
        .items = &items,
    };

    const rects = try compute(testing.allocator, spec, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expect(rects[0].rect.y > 0);
    try testing.expectEqual(@as(u16, 40), rects[0].rect.width);
    try testing.expectEqual(@as(u16, 40), rects[1].rect.width);
}
