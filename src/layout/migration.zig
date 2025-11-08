//! Migration helpers for transitioning from legacy layout APIs to the constraint engine.
//! These helpers intentionally emit compile-time diagnostics to encourage adoption
//! of `layout.engine` constructs while keeping older code paths functional.

const std = @import("std");
const geom = @import("../geometry.zig");
const engine = @import("engine/mod.zig");

const Rect = geom.Rect;
const WeightSpec = engine.WeightSpec;

fn warn(comptime message: []const u8) void {
    @compileLog(message);
}

fn allocSpecsFromWeights(allocator: std.mem.Allocator, weights: []const f64) ![]WeightSpec {
    var specs = try allocator.alloc(WeightSpec, weights.len);
    for (weights, 0..) |weight, idx| {
        specs[idx] = .{ .weight = weight };
    }
    return specs;
}

/// Legacy shim for row splits that accepts raw weights.
pub fn splitRowLegacy(allocator: std.mem.Allocator, area: Rect, weights: []const f64) ![]Rect {
    warn("layout.migration.splitRowLegacy is deprecated; call layout.engine.splitRow with WeightSpec instead.");
    const specs = try allocSpecsFromWeights(allocator, weights);
    defer allocator.free(specs);
    return engine.splitRow(allocator, area, specs);
}

/// Legacy shim for column splits that accepts raw weights.
pub fn splitColumnLegacy(allocator: std.mem.Allocator, area: Rect, weights: []const f64) ![]Rect {
    warn("layout.migration.splitColumnLegacy is deprecated; call layout.engine.splitColumn with WeightSpec instead.");
    const specs = try allocSpecsFromWeights(allocator, weights);
    defer allocator.free(specs);
    return engine.splitColumn(allocator, area, specs);
}

/// Helper that returns both row and column tracks for callers migrating to engine-based grids.
pub const GridTracks = struct {
    allocator: std.mem.Allocator,
    rows: []Rect,
    columns: []Rect,

    pub fn deinit(self: *GridTracks) void {
        self.allocator.free(self.rows);
        self.allocator.free(self.columns);
        self.rows = &[_]Rect{};
        self.columns = &[_]Rect{};
    }
};

pub fn splitGridLegacy(
    allocator: std.mem.Allocator,
    area: Rect,
    row_weights: []const f64,
    column_weights: []const f64,
) !GridTracks {
    warn("layout.migration.splitGridLegacy is deprecated; migrate to layout.engine LayoutBuilder helpers.");

    const row_specs = try allocSpecsFromWeights(allocator, row_weights);
    defer allocator.free(row_specs);

    const column_specs = try allocSpecsFromWeights(allocator, column_weights);
    defer allocator.free(column_specs);

    const rows = try engine.splitColumn(allocator, area, row_specs);
    errdefer allocator.free(rows);

    const columns = try engine.splitRow(allocator, area, column_specs);
    errdefer allocator.free(columns);

    return GridTracks{
        .allocator = allocator,
        .rows = rows,
        .columns = columns,
    };
}

const testing = std.testing;

test "splitRowLegacy proxies to engine" {
    const allocator = testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 20 };

    const weights = [_]f64{ 1.0, 2.0, 1.0 };

    const legacy = try splitRowLegacy(allocator, area, &weights);
    defer allocator.free(legacy);

    var specs = [_]WeightSpec{
        .{ .weight = 1.0 },
        .{ .weight = 2.0 },
        .{ .weight = 1.0 },
    };

    const modern = try engine.splitRow(allocator, area, &specs);
    defer allocator.free(modern);

    try testing.expectEqual(legacy.len, modern.len);
    for (legacy, modern) |lhs, rhs| {
        try testing.expectEqual(lhs, rhs);
    }
}
