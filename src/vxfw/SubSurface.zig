//! SubSurface - A positioned surface for composable UI rendering
//! Represents a surface that is rendered at a specific offset within a parent surface

const std = @import("std");
const geometry = @import("../geometry.zig");
const vxfw = @import("../vxfw.zig");

const Point = geometry.Point;
const Rect = geometry.Rect;

const SubSurface = @This();

/// Position of this subsurface relative to parent
origin: Point,
/// The surface to render
surface: vxfw.Surface,

/// Create a new SubSurface at the given position
pub fn init(origin: Point, surface: vxfw.Surface) SubSurface {
    return SubSurface{
        .origin = origin,
        .surface = surface,
    };
}

/// Get the bounds of this subsurface in parent coordinates
pub fn bounds(self: *const SubSurface) Rect {
    return Rect.init(
        self.origin.x,
        self.origin.y,
        self.surface.size.width,
        self.surface.size.height
    );
}

/// Check if a point (in parent coordinates) is within this subsurface
pub fn contains(self: *const SubSurface, point: Point) bool {
    return self.bounds().contains(point);
}

/// Convert parent coordinates to local subsurface coordinates
pub fn parentToLocal(self: *const SubSurface, parent_point: Point) Point {
    return Point{
        .x = parent_point.x - self.origin.x,
        .y = parent_point.y - self.origin.y,
    };
}

/// Convert local subsurface coordinates to parent coordinates
pub fn localToParent(self: *const SubSurface, local_point: Point) Point {
    return Point{
        .x = local_point.x + self.origin.x,
        .y = local_point.y + self.origin.y,
    };
}

test "SubSurface positioning" {
    const allocator = std.testing.allocator;

    const test_widget = vxfw.Widget{
        .userdata = undefined,
        .drawFn = undefined,
    };

    var surface = try vxfw.Surface.init(allocator, test_widget, geometry.Size.init(5, 3));
    defer surface.deinit();

    const subsurface = SubSurface.init(Point{ .x = 10, .y = 5 }, surface);

    // Test bounds calculation
    const subsurface_bounds = subsurface.bounds();
    try std.testing.expectEqual(@as(u16, 10), subsurface_bounds.x);
    try std.testing.expectEqual(@as(u16, 5), subsurface_bounds.y);
    try std.testing.expectEqual(@as(u16, 5), subsurface_bounds.width);
    try std.testing.expectEqual(@as(u16, 3), subsurface_bounds.height);

    // Test contains
    try std.testing.expect(subsurface.contains(Point{ .x = 12, .y = 6 }));
    try std.testing.expect(!subsurface.contains(Point{ .x = 5, .y = 6 }));

    // Test coordinate conversion
    const local_point = subsurface.parentToLocal(Point{ .x = 12, .y = 6 });
    try std.testing.expectEqual(@as(i16, 2), local_point.x);
    try std.testing.expectEqual(@as(i16, 1), local_point.y);

    const parent_point = subsurface.localToParent(Point{ .x = 2, .y = 1 });
    try std.testing.expectEqual(@as(i16, 12), parent_point.x);
    try std.testing.expectEqual(@as(i16, 6), parent_point.y);
}