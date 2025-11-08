//! Unified constraint-based layout engine prototype
//! Provides variable registration, constraint management, and basic solving

const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Rect = @import("../../geometry.zig").Rect;

pub const Strength = enum(u8) {
    /// Must be satisfied; solver fails if violated.
    required,
    /// High-priority preference – honored ahead of medium/weak constraints.
    strong,
    /// Medium preference with moderate weight.
    medium,
    /// Lowest-priority preference.
    weak,
};

fn strengthWeight(strength: Strength) f64 {
    return switch (strength) {
        .required => 1.0e12,
        .strong => 1.0e6,
        .medium => 1.0e3,
        .weak => 1.0,
    };
}

pub const Relation = enum {
    equal,
    less_or_equal,
    greater_or_equal,
};

pub const Variable = struct {
    id: usize,
};

pub const Term = struct {
    variable: Variable,
    coefficient: f64,
};

const Constraint = struct {
    terms: []Term,
    relation: Relation,
    constant: f64,
    strength: Strength,
};

pub const ConstraintSpec = struct {
    terms: []const Term,
    relation: Relation = .equal,
    constant: f64 = 0,
    strength: Strength = .required,
};

pub const SolveError = error{
    UnsupportedRelation,
    Underdetermined,
    Overdetermined,
    SingularSystem,
    InvalidWeight,
    NegativeSlack,
};

pub const ConstraintSpace = struct {
    allocator: std.mem.Allocator,
    variables: ArrayListUnmanaged(u8),
    constraints: ArrayListUnmanaged(Constraint),
    non_negative: ArrayListUnmanaged(Variable),

    pub fn init(allocator: std.mem.Allocator) ConstraintSpace {
        return ConstraintSpace{
            .allocator = allocator,
            .variables = .{},
            .constraints = .{},
            .non_negative = .{},
        };
    }

    pub fn deinit(self: *ConstraintSpace) void {
        for (self.constraints.items) |constraint| {
            self.allocator.free(constraint.terms);
        }
        self.constraints.deinit(self.allocator);
        self.variables.deinit(self.allocator);
        self.non_negative.deinit(self.allocator);
    }

    pub fn createVariable(self: *ConstraintSpace) !Variable {
        try self.variables.append(self.allocator, 0);
        return Variable{ .id = self.variables.items.len - 1 };
    }

    pub fn addConstraint(self: *ConstraintSpace, spec: ConstraintSpec) !void {
        var terms_buffer = ArrayListUnmanaged(Term){};
        defer terms_buffer.deinit(self.allocator);

        try terms_buffer.ensureTotalCapacity(self.allocator, spec.terms.len + 1);
        for (spec.terms) |term| {
            try terms_buffer.append(self.allocator, term);
        }

        var relation = spec.relation;
        var constant = spec.constant;

        switch (relation) {
            .equal => {},
            .greater_or_equal => {
                relation = .less_or_equal;
                for (terms_buffer.items) |*term| {
                    term.coefficient = -term.coefficient;
                }
                constant = -constant;
            },
            .less_or_equal => {},
        }

        if (relation == .less_or_equal) {
            const slack = try self.createVariable();
            try self.non_negative.append(self.allocator, slack);
            try terms_buffer.append(self.allocator, .{ .variable = slack, .coefficient = 1.0 });
            relation = .equal;
        }

        const final_terms = try self.allocator.alloc(Term, terms_buffer.items.len);
        for (terms_buffer.items, 0..) |term, idx| {
            final_terms[idx] = term;
        }

        try self.constraints.append(self.allocator, Constraint{
            .terms = final_terms,
            .relation = relation,
            .constant = constant,
            .strength = spec.strength,
        });
    }

    pub fn solve(self: *ConstraintSpace) !Solution {
        const var_count = self.variables.items.len;
        if (var_count == 0) {
            return Solution{ .values = &[_]f64{} };
        }

        var required_count: usize = 0;

        var ata = try self.allocator.alloc(f64, var_count * var_count);
        defer self.allocator.free(ata);
        for (ata) |*value| {
            value.* = 0.0;
        }

        var rhs = try self.allocator.alloc(f64, var_count);
        defer self.allocator.free(rhs);
        for (rhs) |*value| {
            value.* = 0.0;
        }

        for (self.constraints.items) |constraint| {
            std.debug.assert(constraint.relation == .equal);

            const weight = strengthWeight(constraint.strength);
            if (weight <= 0) return SolveError.InvalidWeight;

            if (constraint.strength == .required) {
                required_count += 1;
            }

            for (constraint.terms) |term_i| {
                const var_i = term_i.variable.id;
                const coeff_i = term_i.coefficient;

                rhs[var_i] += weight * coeff_i * constraint.constant;

                for (constraint.terms) |term_j| {
                    const var_j = term_j.variable.id;
                    ata[var_i * var_count + var_j] += weight * coeff_i * term_j.coefficient;
                }
            }
        }

        if (required_count == 0) return SolveError.Underdetermined;

        var augmented = try self.allocator.alloc(f64, var_count * (var_count + 1));
        defer self.allocator.free(augmented);

        var row: usize = 0;
        while (row < var_count) : (row += 1) {
            var col: usize = 0;
            while (col < var_count) : (col += 1) {
                augmented[row * (var_count + 1) + col] = ata[row * var_count + col];
            }
            augmented[row * (var_count + 1) + var_count] = rhs[row];
        }

        var solution = gaussianSolve(self.allocator, var_count, var_count, augmented) catch |err| {
            return switch (err) {
                SolveError.SingularSystem => SolveError.Underdetermined,
                else => err,
            };
        };

        // Validate required constraints remain satisfied within tolerance.
        for (self.constraints.items) |constraint| {
            if (constraint.strength != .required) continue;

            var lhs: f64 = 0;
            for (constraint.terms) |term| {
                lhs += term.coefficient * solution[term.variable.id];
            }

            if (@abs(lhs - constraint.constant) > 1e-5) {
                self.allocator.free(solution);
                return SolveError.Overdetermined;
            }
        }

        // Enforce non-negative slack variables (within small epsilon)
        for (self.non_negative.items) |variable| {
            if (solution[variable.id] < -1e-6) {
                self.allocator.free(solution);
                return SolveError.NegativeSlack;
            }
            if (solution[variable.id] < 0) {
                solution[variable.id] = 0;
            }
        }

        return Solution{ .values = solution };
    }
};

pub const LayoutNodeHandle = struct {
    index: usize,
};

const LayoutRectVars = struct {
    x: Variable,
    y: Variable,
    width: Variable,
    height: Variable,
};

pub const ChildWeight = struct {
    handle: LayoutNodeHandle,
    weight: f64 = 1.0,
};

pub const WeightSpec = struct {
    weight: f64 = 1.0,
};

pub const LayoutBuilder = struct {
    allocator: std.mem.Allocator,
    space: ConstraintSpace,
    rects: std.ArrayList(LayoutRectVars),

    pub fn init(allocator: std.mem.Allocator) LayoutBuilder {
        return LayoutBuilder{
            .allocator = allocator,
            .space = ConstraintSpace.init(allocator),
            .rects = .{},
        };
    }

    pub fn deinit(self: *LayoutBuilder) void {
        self.rects.deinit(self.allocator);
        self.space.deinit();
    }

    pub fn createNode(self: *LayoutBuilder) !LayoutNodeHandle {
        const rect = LayoutRectVars{
            .x = try self.space.createVariable(),
            .y = try self.space.createVariable(),
            .width = try self.space.createVariable(),
            .height = try self.space.createVariable(),
        };
        try self.rects.append(self.allocator, rect);
        return LayoutNodeHandle{ .index = self.rects.items.len - 1 };
    }

    pub fn setRect(self: *LayoutBuilder, handle: LayoutNodeHandle, rect: Rect) !void {
        const vars = self.getVars(handle);

        try pinVariable(&self.space, vars.x, @floatFromInt(rect.x));
        try pinVariable(&self.space, vars.y, @floatFromInt(rect.y));
        try pinVariable(&self.space, vars.width, @floatFromInt(rect.width));
        try pinVariable(&self.space, vars.height, @floatFromInt(rect.height));
    }

    pub fn row(self: *LayoutBuilder, parent: LayoutNodeHandle, children: []const ChildWeight) !void {
        if (children.len == 0) return SolveError.InvalidWeight;

        var total_weight: f64 = 0;
        for (children) |child| {
            if (child.weight <= 0) return SolveError.InvalidWeight;
            total_weight += child.weight;
        }

        if (total_weight <= 0) return SolveError.InvalidWeight;

        const parent_vars = self.getVars(parent);

        var maybe_prev: ?LayoutRectVars = null;
        for (children, 0..) |child, idx| {
            const vars = self.getVars(child.handle);

            try alignEdge(&self.space, vars.y, parent_vars.y);
            try matchDimension(&self.space, vars.height, parent_vars.height);

            // Width proportion: total_weight * child.width == child.weight * parent.width
            var width_terms = [_]Term{
                .{ .variable = vars.width, .coefficient = total_weight },
                .{ .variable = parent_vars.width, .coefficient = -child.weight },
            };
            try self.space.addConstraint(.{ .terms = &width_terms, .constant = 0.0 });

            if (idx == 0) {
                try alignEdge(&self.space, vars.x, parent_vars.x);
            } else {
                const prev = maybe_prev.?;
                var terms = [_]Term{
                    .{ .variable = vars.x, .coefficient = 1.0 },
                    .{ .variable = prev.x, .coefficient = -1.0 },
                    .{ .variable = prev.width, .coefficient = -1.0 },
                };
                try self.space.addConstraint(.{ .terms = &terms, .constant = 0.0 });
            }

            maybe_prev = vars;
        }

        const last = maybe_prev.?;
        var right_terms = [_]Term{
            .{ .variable = last.x, .coefficient = 1.0 },
            .{ .variable = last.width, .coefficient = 1.0 },
            .{ .variable = parent_vars.x, .coefficient = -1.0 },
            .{ .variable = parent_vars.width, .coefficient = -1.0 },
        };
        try self.space.addConstraint(.{ .terms = &right_terms, .constant = 0.0 });
    }

    pub fn column(self: *LayoutBuilder, parent: LayoutNodeHandle, children: []const ChildWeight) !void {
        if (children.len == 0) return SolveError.InvalidWeight;

        var total_weight: f64 = 0;
        for (children) |child| {
            if (child.weight <= 0) return SolveError.InvalidWeight;
            total_weight += child.weight;
        }

        if (total_weight <= 0) return SolveError.InvalidWeight;

        const parent_vars = self.getVars(parent);

        var maybe_prev: ?LayoutRectVars = null;
        for (children, 0..) |child, idx| {
            const vars = self.getVars(child.handle);

            try alignEdge(&self.space, vars.x, parent_vars.x);
            try matchDimension(&self.space, vars.width, parent_vars.width);

            var height_terms = [_]Term{
                .{ .variable = vars.height, .coefficient = total_weight },
                .{ .variable = parent_vars.height, .coefficient = -child.weight },
            };
            try self.space.addConstraint(.{ .terms = &height_terms, .constant = 0.0 });

            if (idx == 0) {
                try alignEdge(&self.space, vars.y, parent_vars.y);
            } else {
                const prev = maybe_prev.?;
                var terms = [_]Term{
                    .{ .variable = vars.y, .coefficient = 1.0 },
                    .{ .variable = prev.y, .coefficient = -1.0 },
                    .{ .variable = prev.height, .coefficient = -1.0 },
                };
                try self.space.addConstraint(.{ .terms = &terms, .constant = 0.0 });
            }

            maybe_prev = vars;
        }

        const last = maybe_prev.?;
        var bottom_terms = [_]Term{
            .{ .variable = last.y, .coefficient = 1.0 },
            .{ .variable = last.height, .coefficient = 1.0 },
            .{ .variable = parent_vars.y, .coefficient = -1.0 },
            .{ .variable = parent_vars.height, .coefficient = -1.0 },
        };
        try self.space.addConstraint(.{ .terms = &bottom_terms, .constant = 0.0 });
    }

    pub fn solve(self: *LayoutBuilder) !ResolvedLayout {
        var solution = try self.space.solve();
        defer solution.deinit(self.allocator);

        const rect_count = self.rects.items.len;
        var rects = try self.allocator.alloc(Rect, rect_count);
        errdefer self.allocator.free(rects);

        for (self.rects.items, 0..) |vars, idx| {
            rects[idx] = Rect{
                .x = floatToU16(solution.valueOf(vars.x)),
                .y = floatToU16(solution.valueOf(vars.y)),
                .width = floatToU16(solution.valueOf(vars.width)),
                .height = floatToU16(solution.valueOf(vars.height)),
            };
        }

        return ResolvedLayout{
            .allocator = self.allocator,
            .rects = rects,
        };
    }

    fn getVars(self: *LayoutBuilder, handle: LayoutNodeHandle) LayoutRectVars {
        std.debug.assert(handle.index < self.rects.items.len);
        return self.rects.items[handle.index];
    }
};

pub const ResolvedLayout = struct {
    allocator: std.mem.Allocator,
    rects: []Rect,

    pub fn deinit(self: *ResolvedLayout) void {
        self.allocator.free(self.rects);
        self.rects = &[_]Rect{};
    }

    pub fn rectOf(self: ResolvedLayout, handle: LayoutNodeHandle) Rect {
        std.debug.assert(handle.index < self.rects.len);
        return self.rects[handle.index];
    }
};

pub fn splitRow(
    allocator: std.mem.Allocator,
    area: Rect,
    weights: []const WeightSpec,
) ![]Rect {
    return splitDirection(allocator, area, weights, .horizontal);
}

pub fn splitColumn(
    allocator: std.mem.Allocator,
    area: Rect,
    weights: []const WeightSpec,
) ![]Rect {
    return splitDirection(allocator, area, weights, .vertical);
}

const Direction = enum { horizontal, vertical };

fn splitDirection(
    allocator: std.mem.Allocator,
    area: Rect,
    weights: []const WeightSpec,
    direction: Direction,
) ![]Rect {
    if (weights.len == 0) return &[_]Rect{};

    var builder = LayoutBuilder.init(allocator);
    defer builder.deinit();

    const root = try builder.createNode();
    try builder.setRect(root, area);

    var handles = try allocator.alloc(LayoutNodeHandle, weights.len);
    defer allocator.free(handles);

    var children = try allocator.alloc(ChildWeight, weights.len);
    defer allocator.free(children);

    for (weights, 0..) |spec, idx| {
        if (!(spec.weight > 0)) return SolveError.InvalidWeight;
        handles[idx] = try builder.createNode();
        children[idx] = ChildWeight{ .handle = handles[idx], .weight = spec.weight };
    }

    switch (direction) {
        .horizontal => try builder.row(root, children),
        .vertical => try builder.column(root, children),
    }

    var resolved = try builder.solve();
    defer resolved.deinit();

    var rects = try allocator.alloc(Rect, weights.len);
    for (handles, 0..) |handle, idx| {
        rects[idx] = resolved.rectOf(handle);
    }

    return rects;
}

fn pinVariable(space: *ConstraintSpace, variable: Variable, value: f64) !void {
    var terms = [_]Term{
        .{ .variable = variable, .coefficient = 1.0 },
    };
    try space.addConstraint(.{ .terms = &terms, .constant = value });
}

fn alignEdge(space: *ConstraintSpace, a: Variable, b: Variable) !void {
    var terms = [_]Term{
        .{ .variable = a, .coefficient = 1.0 },
        .{ .variable = b, .coefficient = -1.0 },
    };
    try space.addConstraint(.{ .terms = &terms, .constant = 0.0 });
}

fn matchDimension(space: *ConstraintSpace, a: Variable, b: Variable) !void {
    try alignEdge(space, a, b);
}

fn floatToU16(value: f64) u16 {
    const max_val = @as(f64, @floatFromInt(std.math.maxInt(u16)));
    const clamped = std.math.clamp(value, 0.0, max_val);
    const rounded = std.math.round(clamped);
    return @intFromFloat(rounded);
}

pub const Solution = struct {
    values: []f64,

    pub fn deinit(self: *Solution, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
        self.values = &[_]f64{};
    }

    pub fn valueOf(self: Solution, variable: Variable) f64 {
        if (variable.id >= self.values.len) return 0;
        return self.values[variable.id];
    }
};

fn gaussianSolve(
    allocator: std.mem.Allocator,
    var_count: usize,
    eq_count: usize,
    matrix: []f64,
) ![]f64 {
    // Augmented matrix dimensions: eq_count rows, var_count + 1 columns
    const width = var_count + 1;
    var aug = try allocator.alloc(f64, eq_count * width);
    errdefer allocator.free(aug);
    for (matrix, 0..) |value, idx| {
        aug[idx] = value;
    }

    var row: usize = 0;
    while (row < eq_count and row < var_count) : (row += 1) {
        // Find pivot
        var pivot_row = row;
        var max_abs = @abs(aug[row * width + row]);
        var search_row = row + 1;
        while (search_row < eq_count) : (search_row += 1) {
            const val = @abs(aug[search_row * width + row]);
            if (val > max_abs) {
                max_abs = val;
                pivot_row = search_row;
            }
        }

        if (max_abs <= 1e-9) {
            allocator.free(aug);
            return SolveError.SingularSystem;
        }

        if (pivot_row != row) {
            const pivot_slice = aug[pivot_row * width .. (pivot_row + 1) * width];
            const current_slice = aug[row * width .. (row + 1) * width];
            swapSlices(pivot_slice, current_slice);
        }

        // Normalize row
        const pivot = aug[row * width + row];
        var col: usize = row;
        while (col < width) : (col += 1) {
            aug[row * width + col] /= pivot;
        }

        // Eliminate other rows
        var elim_row: usize = 0;
        while (elim_row < eq_count) : (elim_row += 1) {
            if (elim_row == row) continue;
            const factor = aug[elim_row * width + row];
            if (@abs(factor) <= 1e-12) continue;
            var elim_col: usize = row;
            while (elim_col < width) : (elim_col += 1) {
                aug[elim_row * width + elim_col] -= factor * aug[row * width + elim_col];
            }
        }
    }

    var result = try allocator.alloc(f64, var_count);
    errdefer allocator.free(result);
    var i: usize = 0;
    while (i < var_count) : (i += 1) {
        result[i] = aug[i * width + var_count];
    }

    allocator.free(aug);
    return result;
}

fn swapSlices(a: []f64, b: []f64) void {
    std.debug.assert(a.len == b.len);
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        const tmp = a[i];
        a[i] = b[i];
        b[i] = tmp;
    }
}

// Tests ---------------------------------------------------------------------
const testing = std.testing;

test "solve simple equality system" {
    var space = ConstraintSpace.init(testing.allocator);
    defer space.deinit();

    const a = try space.createVariable();
    const b = try space.createVariable();

    try space.addConstraint(.{
        .terms = &.{ .{ .variable = a, .coefficient = 1.0 }, .{ .variable = b, .coefficient = 1.0 } },
        .relation = .equal,
        .constant = 100.0,
    });

    try space.addConstraint(.{
        .terms = &.{ .{ .variable = a, .coefficient = 1.0 }, .{ .variable = b, .coefficient = -1.0 } },
        .relation = .equal,
        .constant = 0.0,
    });

    var solution = try space.solve();
    defer solution.deinit(testing.allocator);

    try testing.expectApproxEqRel(50.0, solution.valueOf(a), 1e-6);
    try testing.expectApproxEqRel(50.0, solution.valueOf(b), 1e-6);
}

test "underdetermined system fails" {
    var space = ConstraintSpace.init(testing.allocator);
    defer space.deinit();

    const a = try space.createVariable();
    _ = a;

    const err = space.solve() catch |e| e;
    try testing.expectEqual(SolveError.Underdetermined, err);
}

test "layout builder row distributes weights" {
    var builder = LayoutBuilder.init(testing.allocator);
    defer builder.deinit();

    const parent = try builder.createNode();
    const first = try builder.createNode();
    const second = try builder.createNode();

    try builder.setRect(parent, Rect{
        .x = 0,
        .y = 0,
        .width = 120,
        .height = 30,
    });

    try builder.row(parent, &.{
        .{ .handle = first, .weight = 1.0 },
        .{ .handle = second, .weight = 2.0 },
    });

    var resolved = try builder.solve();
    defer resolved.deinit();

    const rect_first = resolved.rectOf(first);
    const rect_second = resolved.rectOf(second);

    try testing.expectEqual(@as(u16, 0), rect_first.x);
    try testing.expectEqual(@as(u16, 40), rect_first.width);
    try testing.expectEqual(@as(u16, 30), rect_first.height);

    try testing.expectEqual(@as(u16, 40), rect_second.x);
    try testing.expectEqual(@as(u16, 80), rect_second.width);
    try testing.expectEqual(@as(u16, 30), rect_second.height);
}

test "layout builder column distributes weights" {
    var builder = LayoutBuilder.init(testing.allocator);
    defer builder.deinit();

    const parent = try builder.createNode();
    const first = try builder.createNode();
    const second = try builder.createNode();

    try builder.setRect(parent, Rect{
        .x = 0,
        .y = 0,
        .width = 60,
        .height = 90,
    });

    try builder.column(parent, &.{
        .{ .handle = first, .weight = 1.0 },
        .{ .handle = second, .weight = 2.0 },
    });

    var resolved = try builder.solve();
    defer resolved.deinit();

    const rect_first = resolved.rectOf(first);
    const rect_second = resolved.rectOf(second);

    try testing.expectEqual(@as(u16, 0), rect_first.y);
    try testing.expectEqual(@as(u16, 30), rect_first.height);
    try testing.expectEqual(@as(u16, 60), rect_first.width);

    try testing.expectEqual(@as(u16, 30), rect_second.y);
    try testing.expectEqual(@as(u16, 60), rect_second.height);
    try testing.expectEqual(@as(u16, 60), rect_second.width);
}

test "constraint space solves with inequalities" {
    var space = ConstraintSpace.init(testing.allocator);
    defer space.deinit();

    const x = try space.createVariable();

    try space.addConstraint(.{
        .terms = &.{.{ .variable = x, .coefficient = 1.0 }},
        .relation = .less_or_equal,
        .constant = 120.0,
    });

    try space.addConstraint(.{
        .terms = &.{.{ .variable = x, .coefficient = 1.0 }},
        .relation = .greater_or_equal,
        .constant = 60.0,
    });

    try space.addConstraint(.{
        .terms = &.{.{ .variable = x, .coefficient = 1.0 }},
        .relation = .equal,
        .constant = 80.0,
    });

    var solution = try space.solve();
    defer solution.deinit(testing.allocator);

    try testing.expectApproxEqRel(80.0, solution.valueOf(x), 1e-6);
}

test "constraint space detects negative slack" {
    var space = ConstraintSpace.init(testing.allocator);
    defer space.deinit();

    const x = try space.createVariable();

    try space.addConstraint(.{
        .terms = &.{.{ .variable = x, .coefficient = 1.0 }},
        .relation = .greater_or_equal,
        .constant = 50.0,
    });

    try space.addConstraint(.{
        .terms = &.{.{ .variable = x, .coefficient = 1.0 }},
        .relation = .less_or_equal,
        .constant = 40.0,
    });

    try space.addConstraint(.{
        .terms = &.{.{ .variable = x, .coefficient = 1.0 }},
        .relation = .equal,
        .constant = 45.0,
    });

    const err = space.solve() catch |e| e;
    try testing.expectEqual(SolveError.NegativeSlack, err);
}

test "strength prioritization favors strong over weak" {
    var space = ConstraintSpace.init(testing.allocator);
    defer space.deinit();

    const x = try space.createVariable();
    const slack = try space.createVariable();

    try space.addConstraint(.{
        .terms = &.{
            .{ .variable = x, .coefficient = 1.0 },
            .{ .variable = slack, .coefficient = 1.0 },
        },
        .relation = .equal,
        .constant = 100.0,
        .strength = .required,
    });

    try space.addConstraint(.{
        .terms = &.{.{ .variable = x, .coefficient = 1.0 }},
        .relation = .equal,
        .constant = 80.0,
        .strength = .strong,
    });

    try space.addConstraint(.{
        .terms = &.{.{ .variable = x, .coefficient = 1.0 }},
        .relation = .equal,
        .constant = 20.0,
        .strength = .weak,
    });

    var solution = try space.solve();
    defer solution.deinit(testing.allocator);

    try testing.expectApproxEqRel(80.0, solution.valueOf(x), 1e-3);
    try testing.expectApproxEqRel(20.0, solution.valueOf(slack), 1e-3);
}

test "conflicting required constraints fail" {
    var space = ConstraintSpace.init(testing.allocator);
    defer space.deinit();

    const x = try space.createVariable();

    try space.addConstraint(.{
        .terms = &.{.{ .variable = x, .coefficient = 1.0 }},
        .relation = .equal,
        .constant = 10.0,
        .strength = .required,
    });

    try space.addConstraint(.{
        .terms = &.{.{ .variable = x, .coefficient = 1.0 }},
        .relation = .equal,
        .constant = 20.0,
        .strength = .required,
    });

    const err = space.solve() catch |e| e;
    try testing.expectEqual(SolveError.Overdetermined, err);
}

test "splitRow convenience helper" {
    const allocator = testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 20 };

    var weights = [_]WeightSpec{
        .{ .weight = 1.0 },
        .{ .weight = 2.0 },
    };

    const rects = try splitRow(allocator, area, &weights);
    defer allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 40), rects[0].width);
    try testing.expectEqual(@as(u16, 80), rects[1].width);
    try testing.expectEqual(@as(u16, 0), rects[0].x);
    try testing.expectEqual(@as(u16, 40), rects[1].x);
}

test "splitColumn convenience helper" {
    const allocator = testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 90 };

    var weights = [_]WeightSpec{
        .{ .weight = 1.0 },
        .{ .weight = 1.0 },
        .{ .weight = 2.0 },
    };

    const rects = try splitColumn(allocator, area, &weights);
    defer allocator.free(rects);

    try testing.expectEqual(@as(usize, 3), rects.len);
    try testing.expectEqual(@as(u16, 30), rects[0].height);
    try testing.expectEqual(@as(u16, 30), rects[1].height);
    try testing.expectEqual(@as(u16, 60), rects[2].height);
    try testing.expectEqual(@as(u16, 0), rects[0].y);
    try testing.expectEqual(@as(u16, 30), rects[1].y);
    try testing.expectEqual(@as(u16, 60), rects[2].y);
}
