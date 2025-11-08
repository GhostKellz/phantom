//! Constraint-based layout system inspired by Ratatui/Cassowary
//! Provides declarative space distribution with automatic calculation

const std = @import("std");
const phantom = @import("../root.zig");
const Rect = phantom.Rect;

/// Layout direction
pub const Direction = enum {
    horizontal,
    vertical,
};

/// Constraint type for layout sizing
pub const Constraint = union(enum) {
    /// Fixed size in cells
    length: u16,

    /// Percentage of available space (0-100)
    percentage: u16,

    /// Ratio of available space (numerator/denominator)
    ratio: struct { num: u32, den: u32 },

    /// Minimum size (takes remaining space if larger)
    min: u16,

    /// Maximum size (takes at most this much space)
    max: u16,

    /// Fill with priority (higher priority fills first)
    fill: u16,
};

/// Layout calculator
pub const Layout = struct {
    direction: Direction,
    constraints: []const Constraint,
    margin: u16,
    horizontal_margin: u16,
    vertical_margin: u16,

    /// Initialize Layout
    pub fn init(direction: Direction, constraints: []const Constraint) Layout {
        return Layout{
            .direction = direction,
            .constraints = constraints,
            .margin = 0,
            .horizontal_margin = 0,
            .vertical_margin = 0,
        };
    }

    /// Set uniform margin
    pub fn withMargin(self: Layout, margin: u16) Layout {
        var result = self;
        result.margin = margin;
        result.horizontal_margin = margin;
        result.vertical_margin = margin;
        return result;
    }

    /// Set horizontal margin
    pub fn withHorizontalMargin(self: Layout, margin: u16) Layout {
        var result = self;
        result.horizontal_margin = margin;
        return result;
    }

    /// Set vertical margin
    pub fn withVerticalMargin(self: Layout, margin: u16) Layout {
        var result = self;
        result.vertical_margin = margin;
        return result;
    }

    /// Split area according to constraints
    pub fn split(self: Layout, allocator: std.mem.Allocator, area: Rect) ![]Rect {
        comptime {
            @compileLog("layout.constraint.Layout.split is deprecated; migrate to layout.engine.LayoutBuilder or layout.migration helpers.");
        }
        if (self.constraints.len == 0) {
            return &[_]Rect{};
        }

        // Apply margins
        const inner_area = self.applyMargins(area);
        if (inner_area.width == 0 or inner_area.height == 0) {
            return &[_]Rect{};
        }

        // Calculate sizes based on direction
        const available_space = switch (self.direction) {
            .horizontal => inner_area.width,
            .vertical => inner_area.height,
        };

        // First pass: calculate fixed sizes
        const sizes = try self.calculateSizes(allocator, available_space);
        defer allocator.free(sizes);

        // Second pass: create rectangles
        var result = try allocator.alloc(Rect, self.constraints.len);

        var current_pos: u16 = 0;
        for (sizes, 0..) |size, i| {
            switch (self.direction) {
                .horizontal => {
                    result[i] = Rect{
                        .x = inner_area.x + current_pos,
                        .y = inner_area.y,
                        .width = size,
                        .height = inner_area.height,
                    };
                },
                .vertical => {
                    result[i] = Rect{
                        .x = inner_area.x,
                        .y = inner_area.y + current_pos,
                        .width = inner_area.width,
                        .height = size,
                    };
                },
            }
            current_pos += size;
        }

        return result;
    }

    /// Apply margins to area
    fn applyMargins(self: Layout, area: Rect) Rect {
        const h_margin = if (self.horizontal_margin > 0) self.horizontal_margin else self.margin;
        const v_margin = if (self.vertical_margin > 0) self.vertical_margin else self.margin;

        const margin_x = @min(h_margin, @divTrunc(area.width, 2));
        const margin_y = @min(v_margin, @divTrunc(area.height, 2));

        return Rect{
            .x = area.x + margin_x,
            .y = area.y + margin_y,
            .width = if (area.width >= 2 * margin_x) area.width - 2 * margin_x else 0,
            .height = if (area.height >= 2 * margin_y) area.height - 2 * margin_y else 0,
        };
    }

    /// Calculate sizes for each constraint
    fn calculateSizes(self: Layout, allocator: std.mem.Allocator, available_space: u16) ![]u16 {
        var sizes = try allocator.alloc(u16, self.constraints.len);

        // First pass: calculate fixed, percentage, and ratio sizes
        var remaining_space: i32 = @intCast(available_space);
        var remaining_fill_constraints: usize = 0;
        var total_fill_priority: u32 = 0;

        for (self.constraints, 0..) |constraint, i| {
            switch (constraint) {
                .length => |len| {
                    sizes[i] = @min(len, available_space);
                    remaining_space -= @intCast(sizes[i]);
                },
                .percentage => |pct| {
                    const size = @as(u16, @intCast((@as(u32, available_space) * @min(pct, 100)) / 100));
                    sizes[i] = size;
                    remaining_space -= @intCast(size);
                },
                .ratio => |r| {
                    const size = @as(u16, @intCast((@as(u64, available_space) * r.num) / r.den));
                    sizes[i] = size;
                    remaining_space -= @intCast(size);
                },
                .min => |min_size| {
                    sizes[i] = 0; // Will be calculated in second pass
                    remaining_space -= @intCast(min_size);
                    remaining_fill_constraints += 1;
                },
                .max => |max_size| {
                    // Take as much as available up to max
                    const size = @min(max_size, available_space);
                    sizes[i] = size;
                    remaining_space -= @intCast(size);
                },
                .fill => |priority| {
                    sizes[i] = 0; // Will be calculated in second pass
                    remaining_fill_constraints += 1;
                    total_fill_priority += priority;
                },
            }
        }

        // Ensure remaining space is non-negative
        remaining_space = @max(0, remaining_space);

        // Second pass: distribute remaining space to min and fill constraints
        if (remaining_fill_constraints > 0 and remaining_space > 0) {
            const remaining_u16: u16 = @intCast(remaining_space);

            // Sort fill constraints by priority
            var fill_items = std.ArrayList(struct { idx: usize, priority: u16 }){};
            defer fill_items.deinit(allocator);

            for (self.constraints, 0..) |constraint, i| {
                switch (constraint) {
                    .fill => |priority| try fill_items.append(allocator, .{ .idx = i, .priority = priority }),
                    .min => try fill_items.append(allocator, .{ .idx = i, .priority = 1 }),
                    else => {},
                }
            }

            // Distribute space based on priority
            if (total_fill_priority == 0) {
                // Equal distribution if no priorities
                const per_item = @divTrunc(remaining_u16, @as(u16, @intCast(remaining_fill_constraints)));
                for (fill_items.items) |item| {
                    sizes[item.idx] = per_item;
                }
            } else {
                // Priority-based distribution
                var distributed: u16 = 0;
                for (fill_items.items) |item| {
                    const share = (@as(u32, remaining_u16) * item.priority) / total_fill_priority;
                    sizes[item.idx] = @intCast(share);
                    distributed += sizes[item.idx];
                }

                // Distribute any remaining pixels to first fill constraint
                if (distributed < remaining_u16 and fill_items.items.len > 0) {
                    sizes[fill_items.items[0].idx] += remaining_u16 - distributed;
                }
            }

            // Apply min constraint limits
            for (self.constraints, 0..) |constraint, i| {
                if (constraint == .min) {
                    sizes[i] = @max(sizes[i], constraint.min);
                }
            }
        }

        return sizes;
    }
};

// Tests
test "Layout split horizontal equally" {
    const testing = std.testing;

    const constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };

    const layout = Layout.init(.horizontal, &constraints);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };

    const rects = try layout.split(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 50), rects[0].width);
    try testing.expectEqual(@as(u16, 50), rects[1].width);
    try testing.expectEqual(@as(u16, 0), rects[0].x);
    try testing.expectEqual(@as(u16, 50), rects[1].x);
}

test "Layout split vertical with length" {
    const testing = std.testing;

    const constraints = [_]Constraint{
        .{ .length = 5 },
        .{ .length = 10 },
        .{ .length = 5 },
    };

    const layout = Layout.init(.vertical, &constraints);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const rects = try layout.split(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 3), rects.len);
    try testing.expectEqual(@as(u16, 5), rects[0].height);
    try testing.expectEqual(@as(u16, 10), rects[1].height);
    try testing.expectEqual(@as(u16, 5), rects[2].height);
}

test "Layout with margins" {
    const testing = std.testing;

    const constraints = [_]Constraint{
        .{ .percentage = 100 },
    };

    const layout = Layout.init(.horizontal, &constraints).withMargin(5);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };

    const rects = try layout.split(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 1), rects.len);
    try testing.expectEqual(@as(u16, 5), rects[0].x);
    try testing.expectEqual(@as(u16, 5), rects[0].y);
    try testing.expectEqual(@as(u16, 90), rects[0].width);
    try testing.expectEqual(@as(u16, 10), rects[0].height);
}

test "Layout with fill constraint" {
    const testing = std.testing;

    const constraints = [_]Constraint{
        .{ .length = 10 },
        .{ .fill = 1 },
        .{ .length = 10 },
    };

    const layout = Layout.init(.horizontal, &constraints);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };

    const rects = try layout.split(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 3), rects.len);
    try testing.expectEqual(@as(u16, 10), rects[0].width);
    try testing.expectEqual(@as(u16, 80), rects[1].width); // Fills remaining space
    try testing.expectEqual(@as(u16, 10), rects[2].width);
}

test "Layout with ratio constraint" {
    const testing = std.testing;

    const constraints = [_]Constraint{
        .{ .ratio = .{ .num = 1, .den = 3 } },
        .{ .ratio = .{ .num = 2, .den = 3 } },
    };

    const layout = Layout.init(.horizontal, &constraints);
    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 20 };

    const rects = try layout.split(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 30), rects[0].width); // 1/3 of 90
    try testing.expectEqual(@as(u16, 60), rects[1].width); // 2/3 of 90
}

test "Layout with min constraint" {
    const testing = std.testing;

    const constraints = [_]Constraint{
        .{ .length = 20 },
        .{ .min = 10 },
    };

    const layout = Layout.init(.horizontal, &constraints);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };

    const rects = try layout.split(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 20), rects[0].width);
    try testing.expect(rects[1].width >= 10); // At least 10, gets remaining
}

test "Layout with max constraint" {
    const testing = std.testing;

    const constraints = [_]Constraint{
        .{ .max = 50 },
    };

    const layout = Layout.init(.horizontal, &constraints);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };

    const rects = try layout.split(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 1), rects.len);
    try testing.expectEqual(@as(u16, 50), rects[0].width); // Capped at max
}
