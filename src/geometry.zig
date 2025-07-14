//! Core geometry types for Phantom TUI
const std = @import("std");

/// Represents a position with x, y coordinates
pub const Position = struct {
    x: u16,
    y: u16,

    pub fn init(x: u16, y: u16) Position {
        return Position{ .x = x, .y = y };
    }

    pub fn origin() Position {
        return Position{ .x = 0, .y = 0 };
    }

    pub fn offset(self: Position, dx: i16, dy: i16) Position {
        return Position{
            .x = @intCast(@as(i32, self.x) + dx),
            .y = @intCast(@as(i32, self.y) + dy),
        };
    }
};

/// Represents dimensions with width and height
pub const Size = struct {
    width: u16,
    height: u16,

    pub fn init(width: u16, height: u16) Size {
        return Size{ .width = width, .height = height };
    }

    pub fn zero() Size {
        return Size{ .width = 0, .height = 0 };
    }

    pub fn area(self: Size) u32 {
        return @as(u32, self.width) * @as(u32, self.height);
    }
};

/// Represents a rectangular area with position and size
pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    pub fn init(x: u16, y: u16, width: u16, height: u16) Rect {
        return Rect{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn fromPosSize(pos: Position, sz: Size) Rect {
        return Rect{
            .x = pos.x,
            .y = pos.y,
            .width = sz.width,
            .height = sz.height,
        };
    }

    pub fn position(self: Rect) Position {
        return Position{ .x = self.x, .y = self.y };
    }

    pub fn size(self: Rect) Size {
        return Size{ .width = self.width, .height = self.height };
    }

    pub fn area(self: Rect) u32 {
        return @as(u32, self.width) * @as(u32, self.height);
    }

    pub fn right(self: Rect) u16 {
        return self.x + self.width;
    }

    pub fn bottom(self: Rect) u16 {
        return self.y + self.height;
    }

    pub fn contains(self: Rect, pos: Position) bool {
        return pos.x >= self.x and pos.x < self.right() and
            pos.y >= self.y and pos.y < self.bottom();
    }

    pub fn intersect(self: Rect, other: Rect) ?Rect {
        const left = @max(self.x, other.x);
        const top = @max(self.y, other.y);
        const right_edge = @min(self.right(), other.right());
        const bottom_edge = @min(self.bottom(), other.bottom());

        if (left >= right_edge or top >= bottom_edge) {
            return null;
        }

        return Rect{
            .x = left,
            .y = top,
            .width = right_edge - left,
            .height = bottom_edge - top,
        };
    }

    pub fn union_(self: Rect, other: Rect) Rect {
        const left = @min(self.x, other.x);
        const top = @min(self.y, other.y);
        const right_edge = @max(self.right(), other.right());
        const bottom_edge = @max(self.bottom(), other.bottom());

        return Rect{
            .x = left,
            .y = top,
            .width = right_edge - left,
            .height = bottom_edge - top,
        };
    }
};

test "Position operations" {
    const pos = Position.init(10, 20);
    try std.testing.expect(pos.x == 10);
    try std.testing.expect(pos.y == 20);

    const offset_pos = pos.offset(5, -3);
    try std.testing.expect(offset_pos.x == 15);
    try std.testing.expect(offset_pos.y == 17);
}

test "Size operations" {
    const size = Size.init(100, 50);
    try std.testing.expect(size.width == 100);
    try std.testing.expect(size.height == 50);
    try std.testing.expect(size.area() == 5000);
}

test "Rect operations" {
    const rect = Rect.init(10, 10, 20, 15);
    try std.testing.expect(rect.right() == 30);
    try std.testing.expect(rect.bottom() == 25);
    try std.testing.expect(rect.area() == 300);

    const pos_inside = Position.init(15, 12);
    const pos_outside = Position.init(35, 12);
    try std.testing.expect(rect.contains(pos_inside));
    try std.testing.expect(!rect.contains(pos_outside));
}
