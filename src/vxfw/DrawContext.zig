//! DrawContext - Provides constraints and arena allocation for widget drawing
//! Inspired by vaxis DrawContext but adapted for Phantom's architecture

const std = @import("std");
const geometry = @import("../geometry.zig");
const vxfw = @import("../vxfw.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;

const DrawContext = @This();

/// Minimum size constraints for the widget
min: Size,
/// Maximum size constraints for the widget (null = unlimited)
max: SizeConstraints,
/// Arena allocator for temporary allocations during draw
arena: Allocator,
/// Cell size information for calculating pixel dimensions
cell_size: CellSize,

/// Size constraints with optional unlimited dimensions
pub const SizeConstraints = struct {
    width: ?u16,
    height: ?u16,

    pub fn init(width: ?u16, height: ?u16) SizeConstraints {
        return .{ .width = width, .height = height };
    }

    pub fn unlimited() SizeConstraints {
        return .{ .width = null, .height = null };
    }

    pub fn fixed(width: u16, height: u16) SizeConstraints {
        return .{ .width = width, .height = height };
    }

    pub fn withWidth(self: SizeConstraints, width: ?u16) SizeConstraints {
        return .{ .width = width, .height = self.height };
    }

    pub fn withHeight(self: SizeConstraints, height: ?u16) SizeConstraints {
        return .{ .width = self.width, .height = height };
    }
};

/// Information about terminal cell dimensions
pub const CellSize = struct {
    width_px: u16 = 8,   // Average character width in pixels
    height_px: u16 = 16, // Character height in pixels

    pub fn default() CellSize {
        return .{};
    }
};

/// Create a new DrawContext with the given constraints
pub fn init(
    arena: Allocator,
    min: Size,
    max: SizeConstraints,
    cell_size: CellSize
) DrawContext {
    return DrawContext{
        .min = min,
        .max = max,
        .arena = arena,
        .cell_size = cell_size,
    };
}

/// Create a new DrawContext with modified constraints
pub fn withConstraints(
    self: DrawContext,
    new_min: Size,
    new_max: SizeConstraints
) DrawContext {
    return DrawContext{
        .min = new_min,
        .max = new_max,
        .arena = self.arena,
        .cell_size = self.cell_size,
    };
}

/// Create a DrawContext constrained to a specific size
pub fn withSize(self: DrawContext, size: Size) DrawContext {
    return self.withConstraints(size, SizeConstraints.fixed(size.width, size.height));
}

/// Get the effective width constraint (minimum if no maximum)
pub fn getWidth(self: DrawContext) u16 {
    if (self.max.width) |max_width| {
        return @max(self.min.width, max_width);
    }
    return self.min.width;
}

/// Get the effective height constraint (minimum if no maximum)
pub fn getHeight(self: DrawContext) u16 {
    if (self.max.height) |max_height| {
        return @max(self.min.height, max_height);
    }
    return self.min.height;
}

/// Get the effective size using constraints
pub fn getSize(self: DrawContext) Size {
    return Size.init(self.getWidth(), self.getHeight());
}

/// Check if the context has unlimited width
pub fn hasUnlimitedWidth(self: DrawContext) bool {
    return self.max.width == null;
}

/// Check if the context has unlimited height
pub fn hasUnlimitedHeight(self: DrawContext) bool {
    return self.max.height == null;
}

/// Constrain a size to fit within this context's limits
pub fn constrainSize(self: DrawContext, size: Size) Size {
    var result = size;

    // Apply minimum constraints
    result.width = @max(result.width, self.min.width);
    result.height = @max(result.height, self.min.height);

    // Apply maximum constraints
    if (self.max.width) |max_width| {
        result.width = @min(result.width, max_width);
    }
    if (self.max.height) |max_height| {
        result.height = @min(result.height, max_height);
    }

    return result;
}

/// Create a child context for the given available space
pub fn createChild(
    self: DrawContext,
    available: Size
) DrawContext {
    const child_max = SizeConstraints{
        .width = if (self.max.width) |max_w| @min(max_w, available.width) else available.width,
        .height = if (self.max.height) |max_h| @min(max_h, available.height) else available.height,
    };

    return DrawContext{
        .min = Size.init(0, 0), // Child can be smaller
        .max = child_max,
        .arena = self.arena,
        .cell_size = self.cell_size,
    };
}

/// Calculate pixel dimensions for the given cell size
pub fn toPixels(self: DrawContext, cell_size: Size) Size {
    return Size.init(
        cell_size.width * self.cell_size.width_px,
        cell_size.height * self.cell_size.height_px
    );
}

/// Calculate cell dimensions for the given pixel size
pub fn fromPixels(self: DrawContext, pixel_size: Size) Size {
    return Size.init(
        pixel_size.width / self.cell_size.width_px,
        pixel_size.height / self.cell_size.height_px
    );
}

test "DrawContext creation and constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const ctx = DrawContext.init(
        arena.allocator(),
        Size.init(10, 5),
        SizeConstraints.fixed(50, 25),
        CellSize.default()
    );

    // Test basic properties
    try std.testing.expectEqual(@as(u16, 10), ctx.min.width);
    try std.testing.expectEqual(@as(u16, 5), ctx.min.height);
    try std.testing.expectEqual(@as(u16, 50), ctx.max.width.?);
    try std.testing.expectEqual(@as(u16, 25), ctx.max.height.?);

    // Test effective size calculation
    try std.testing.expectEqual(@as(u16, 50), ctx.getWidth());
    try std.testing.expectEqual(@as(u16, 25), ctx.getHeight());

    // Test unlimited constraints
    try std.testing.expect(!ctx.hasUnlimitedWidth());
    try std.testing.expect(!ctx.hasUnlimitedHeight());
}

test "DrawContext size constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const ctx = DrawContext.init(
        arena.allocator(),
        Size.init(10, 5),
        SizeConstraints.fixed(20, 15),
        CellSize.default()
    );

    // Test constraining various sizes
    try std.testing.expectEqual(
        Size.init(10, 5),
        ctx.constrainSize(Size.init(5, 2)) // Too small, clamped to minimum
    );

    try std.testing.expectEqual(
        Size.init(15, 10),
        ctx.constrainSize(Size.init(15, 10)) // Within bounds
    );

    try std.testing.expectEqual(
        Size.init(20, 15),
        ctx.constrainSize(Size.init(30, 25)) // Too large, clamped to maximum
    );
}

test "DrawContext child creation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const parent_ctx = DrawContext.init(
        arena.allocator(),
        Size.init(5, 3),
        SizeConstraints.fixed(50, 30),
        CellSize.default()
    );

    const child_ctx = parent_ctx.createChild(Size.init(20, 15));

    // Child should have no minimum but respect available space
    try std.testing.expectEqual(@as(u16, 0), child_ctx.min.width);
    try std.testing.expectEqual(@as(u16, 0), child_ctx.min.height);
    try std.testing.expectEqual(@as(u16, 20), child_ctx.max.width.?);
    try std.testing.expectEqual(@as(u16, 15), child_ctx.max.height.?);
}