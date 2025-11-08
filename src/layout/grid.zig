//! Grid layout engine providing row/column based placement using shared layout
//! dimensions. Focuses on pragmatic sizing rules that map well to terminal UIs.
const std = @import("std");
const geom = @import("../geometry.zig");
const types = @import("types.zig");
const engine = @import("engine/mod.zig");

const Rect = geom.Rect;
const Dimension = types.Dimension;
const ItemRect = types.ItemRect;

/// Alignment options along a single axis inside a grid cell.
pub const AxisAlignment = enum {
    start,
    center,
    end,
    stretch,
};

/// Combined horizontal and vertical alignment configuration.
pub const CellAlignment = struct {
    horizontal: AxisAlignment = .stretch,
    vertical: AxisAlignment = .stretch,
};

/// Identifies the grid coordinates occupied by an item.
pub const Placement = struct {
    column: usize = 0,
    column_span: u16 = 1,
    row: usize = 0,
    row_span: u16 = 1,
};

/// Grid item configuration.
pub const Item = struct {
    id: ?u32 = null,
    placement: Placement = .{},
    width: Dimension = .auto,
    height: Dimension = .auto,
    align_self: ?CellAlignment = null,
};

/// Grid specification listing track definitions and contained items.
pub const Spec = struct {
    columns: []const Dimension,
    rows: []const Dimension,
    gap_column: u16 = 0,
    gap_row: u16 = 0,
    align_all: CellAlignment = .{},
    items: []const Item,
};

/// Compute rectangles for grid items within the supplied area.
pub fn compute(allocator: std.mem.Allocator, spec: Spec, area: Rect) ![]ItemRect {
    if (spec.items.len == 0 or spec.columns.len == 0 or spec.rows.len == 0) {
        return &[_]ItemRect{};
    }

    const column_sizes = try distributeTracks(allocator, spec.columns, area.width, spec.gap_column);
    defer allocator.free(column_sizes);
    const row_sizes = try distributeTracks(allocator, spec.rows, area.height, spec.gap_row);
    defer allocator.free(row_sizes);

    var total_column_span: u32 = 0;
    for (column_sizes) |size| total_column_span += size;
    const total_column_gap: u32 = if (column_sizes.len > 1)
        @as(u32, spec.gap_column) * @as(u32, column_sizes.len - 1)
    else
        0;

    var total_row_span: u32 = 0;
    for (row_sizes) |size| total_row_span += size;
    const total_row_gap: u32 = if (row_sizes.len > 1)
        @as(u32, spec.gap_row) * @as(u32, row_sizes.len - 1)
    else
        0;

    const grid_width_u32 = std.math.min(total_column_span + total_column_gap, @as(u32, area.width));
    const grid_height_u32 = std.math.min(total_row_span + total_row_gap, @as(u32, area.height));

    const grid_area = Rect{
        .x = area.x,
        .y = area.y,
        .width = @as(u16, @intCast(grid_width_u32)),
        .height = @as(u16, @intCast(grid_height_u32)),
    };

    const column_rects = try computeColumnRects(allocator, grid_area, column_sizes, spec.gap_column);
    defer allocator.free(column_rects);

    const row_rects = try computeRowRects(allocator, grid_area, row_sizes, spec.gap_row);
    defer allocator.free(row_rects);

    var results = try allocator.alloc(ItemRect, spec.items.len);
    errdefer allocator.free(results);

    for (spec.items, 0..) |item, idx| {
        if (item.placement.column >= column_sizes.len or item.placement.row >= row_sizes.len) {
            results[idx] = ItemRect{ .id = item.id, .rect = Rect{ .x = area.x, .y = area.y, .width = 0, .height = 0 } };
            continue;
        }

        const span_cols_u16 = if (item.placement.column_span == 0) 1 else item.placement.column_span;
        const span_rows_u16 = if (item.placement.row_span == 0) 1 else item.placement.row_span;

        const span_cols_end = std.math.min(column_sizes.len, item.placement.column + @as(usize, span_cols_u16));
        const span_rows_end = std.math.min(row_sizes.len, item.placement.row + @as(usize, span_rows_u16));

        const span_col_count = span_cols_end - item.placement.column;
        const span_row_count = span_rows_end - item.placement.row;

        if (span_col_count == 0 or span_row_count == 0) {
            results[idx] = ItemRect{ .id = item.id, .rect = Rect{ .x = area.x, .y = area.y, .width = 0, .height = 0 } };
            continue;
        }

        const first_col = column_rects[item.placement.column];
        const last_col = column_rects[span_cols_end - 1];
        const cell_x_start_u32 = @as(u32, first_col.x);
        const cell_x_end_u32 = @as(u32, last_col.x) + @as(u32, last_col.width);
        const cell_width: u16 = types.clampToU16(@as(i32, @intCast(cell_x_end_u32 - cell_x_start_u32)));

        const first_row = row_rects[item.placement.row];
        const last_row = row_rects[span_rows_end - 1];
        const cell_y_start_u32 = @as(u32, first_row.y);
        const cell_y_end_u32 = @as(u32, last_row.y) + @as(u32, last_row.height);
        const cell_height: u16 = types.clampToU16(@as(i32, @intCast(cell_y_end_u32 - cell_y_start_u32)));

        const alignment = item.align_self orelse spec.align_all;
        const resolved_width = resolveLengthWithinCell(item.width, cell_width, alignment.horizontal);
        const resolved_height = resolveLengthWithinCell(item.height, cell_height, alignment.vertical);

        const horizontal_offset = alignOffset(cell_width, resolved_width, alignment.horizontal);
        const vertical_offset = alignOffset(cell_height, resolved_height, alignment.vertical);

        const cell_x_start = types.clampToU16(@as(i32, @intCast(cell_x_start_u32)));
        const cell_y_start = types.clampToU16(@as(i32, @intCast(cell_y_start_u32)));

        const rect_x_u32 = @as(u32, cell_x_start) + @as(u32, horizontal_offset);
        const rect_y_u32 = @as(u32, cell_y_start) + @as(u32, vertical_offset);

        const rect = Rect{
            .x = types.clampToU16(@as(i32, @intCast(rect_x_u32))),
            .y = types.clampToU16(@as(i32, @intCast(rect_y_u32))),
            .width = resolved_width,
            .height = resolved_height,
        };

        results[idx] = ItemRect{ .id = item.id, .rect = types.clampRectToParent(rect, area) };
    }

    return results;
}

fn distributeTracks(allocator: std.mem.Allocator, tracks: []const Dimension, span: u16, gap: u16) ![]u16 {
    if (tracks.len == 0) return &[_]u16{};

    var sizes = try allocator.alloc(u16, tracks.len);
    errdefer allocator.free(sizes);

    var weights = try allocator.alloc(u32, tracks.len);
    defer allocator.free(weights);

    const total_gap: u32 = if (tracks.len > 1) @as(u32, gap) * @as(u32, tracks.len - 1) else 0;

    var remaining: i64 = @as(i64, span);
    remaining -= @as(i64, std.math.min(total_gap, @as(u32, span)));
    if (remaining < 0) remaining = 0;

    var total_weight: u64 = 0;

    for (tracks, 0..) |track, idx| {
        weights[idx] = 0;
        switch (track) {
            .auto => {
                weights[idx] = 1;
            },
            .fraction => |weight| {
                weights[idx] = if (weight == 0) 1 else weight;
            },
            else => {
                const resolved = types.resolveDimension(track, span) orelse 0;
                sizes[idx] = resolved;
                remaining -= @as(i64, resolved);
                if (remaining < 0) remaining = 0;
                continue;
            },
        }
        sizes[idx] = 0;
        total_weight += weights[idx];
    }

    if (remaining > 0 and total_weight > 0) {
        var distributed: i64 = 0;
        for (tracks, 0..) |_, idx| {
            if (weights[idx] == 0) continue;
            const share_f = (@as(f64, remaining) * @as(f64, weights[idx])) / @as(f64, total_weight);
            const share: i64 = @as(i64, @intFromFloat(std.math.max(0.0, share_f)));
            if (share > 0) {
                const bounded_share: i64 = if (share > @as(i64, std.math.maxInt(i32))) @as(i64, std.math.maxInt(i32)) else share;
                const share_i32: i32 = @intCast(bounded_share);
                const share_u16: u16 = types.clampToU16(share_i32);
                sizes[idx] += share_u16;
                distributed += share;
            }
        }

        var leftover = remaining - distributed;
        if (leftover > 0) {
            for (tracks, 0..) |_, idx| {
                if (weights[idx] > 0) {
                    const bounded: i64 = if (leftover > @as(i64, std.math.maxInt(i32))) @as(i64, std.math.maxInt(i32)) else leftover;
                    const bonus: u16 = types.clampToU16(@intCast(bounded));
                    sizes[idx] += bonus;
                    leftover -= @as(i64, bonus);
                    if (leftover <= 0) break;
                }
            }
        }
        remaining = 0;
    }

    return sizes;
}

fn resolveLengthWithinCell(dim: Dimension, cell: u16, alignment: AxisAlignment) u16 {
    return switch (dim) {
        .auto => switch (alignment) {
            .stretch => cell,
            else => cell,
        },
        .px => |px| @min(px, cell),
        .percent => |pct| types.resolveDimension(.{ .percent = pct }, cell) orelse cell,
        .fraction => |_| cell,
    };
}

fn alignOffset(cell: u16, content: u16, alignment: AxisAlignment) u16 {
    if (content >= cell) return 0;

    return switch (alignment) {
        .start, .stretch => 0,
        .center => @as(u16, @intCast((@as(u32, cell) - content) / 2)),
        .end => @as(u16, @intCast(@as(u32, cell) - content)),
    };
}

fn computeColumnRects(allocator: std.mem.Allocator, area: Rect, sizes: []const u16, gap: u16) ![]Rect {
    if (sizes.len == 0) return &[_]Rect{};

    const gap_entries = if (sizes.len > 1 and gap > 0) sizes.len - 1 else 0;
    const total_entries = sizes.len + gap_entries;

    var weights = try allocator.alloc(engine.WeightSpec, total_entries);
    defer allocator.free(weights);

    var entry_map = try allocator.alloc(?usize, total_entries);
    defer allocator.free(entry_map);

    const epsilon: f64 = 1e-6;

    var entry_idx: usize = 0;
    for (sizes, 0..) |size, idx| {
        const weight = if (size > 0) @as(f64, @floatFromInt(size)) else epsilon;
        weights[entry_idx] = .{ .weight = weight };
        entry_map[entry_idx] = idx;
        entry_idx += 1;

        if (gap_entries > 0 and idx + 1 < sizes.len and gap > 0) {
            const gap_weight = std.math.max(@as(f64, @floatFromInt(gap)), epsilon);
            weights[entry_idx] = .{ .weight = gap_weight };
            entry_map[entry_idx] = null;
            entry_idx += 1;
        }
    }

    const segments = try engine.splitRow(allocator, area, weights[0..entry_idx]);
    defer allocator.free(segments);

    var tracks = try allocator.alloc(Rect, sizes.len);
    errdefer allocator.free(tracks);

    for (entry_map, 0..) |maybe_idx, seg_idx| {
        if (maybe_idx) |track_idx| {
            tracks[track_idx] = segments[seg_idx];
        }
    }

    return tracks;
}

fn computeRowRects(allocator: std.mem.Allocator, area: Rect, sizes: []const u16, gap: u16) ![]Rect {
    if (sizes.len == 0) return &[_]Rect{};

    const gap_entries = if (sizes.len > 1 and gap > 0) sizes.len - 1 else 0;
    const total_entries = sizes.len + gap_entries;

    var weights = try allocator.alloc(engine.WeightSpec, total_entries);
    defer allocator.free(weights);

    var entry_map = try allocator.alloc(?usize, total_entries);
    defer allocator.free(entry_map);

    const epsilon: f64 = 1e-6;

    var entry_idx: usize = 0;
    for (sizes, 0..) |size, idx| {
        const weight = if (size > 0) @as(f64, @floatFromInt(size)) else epsilon;
        weights[entry_idx] = .{ .weight = weight };
        entry_map[entry_idx] = idx;
        entry_idx += 1;

        if (gap_entries > 0 and idx + 1 < sizes.len and gap > 0) {
            const gap_weight = std.math.max(@as(f64, @floatFromInt(gap)), epsilon);
            weights[entry_idx] = .{ .weight = gap_weight };
            entry_map[entry_idx] = null;
            entry_idx += 1;
        }
    }

    const segments = try engine.splitColumn(allocator, area, weights[0..entry_idx]);
    defer allocator.free(segments);

    var tracks = try allocator.alloc(Rect, sizes.len);
    errdefer allocator.free(tracks);

    for (entry_map, 0..) |maybe_idx, seg_idx| {
        if (maybe_idx) |track_idx| {
            tracks[track_idx] = segments[seg_idx];
        }
    }

    return tracks;
}

const testing = std.testing;

test "grid basic placement" {
    const columns = [_]Dimension{ .px(10), .px(10) };
    const rows = [_]Dimension{ .px(5), .px(5) };

    const items = [_]Item{
        .{ .placement = .{ .column = 0, .row = 0 } },
        .{ .placement = .{ .column = 1, .row = 1 } },
    };

    const spec = Spec{
        .columns = &columns,
        .rows = &rows,
        .items = &items,
    };

    const rects = try compute(testing.allocator, spec, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 0), rects[0].rect.x);
    try testing.expectEqual(@as(u16, 10), rects[1].rect.x);
    try testing.expectEqual(@as(u16, 5), rects[1].rect.y);
}

test "grid span with fractions and gaps" {
    const columns = [_]Dimension{ .fraction(1), .fraction(2) };
    const rows = [_]Dimension{ .px(4), .fraction(1) };

    const items = [_]Item{
        .{ .placement = .{ .column = 0, .column_span = 2, .row = 0 } },
        .{ .placement = .{ .column = 1, .row = 1 }, .align_self = .{ .horizontal = .end, .vertical = .start }, .width = .percent(50), .height = .percent(50) },
    };

    const spec = Spec{
        .columns = &columns,
        .rows = &rows,
        .gap_column = 2,
        .gap_row = 1,
        .items = &items,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 12 };
    const rects = try compute(testing.allocator, spec, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 0), rects[0].rect.x);
    try testing.expectEqual(@as(u16, 0), rects[0].rect.y);
    try testing.expect(rects[0].rect.width >= 28);
    try testing.expectEqual(@as(u16, 15), rects[1].rect.x); // Should land in second column region
}
