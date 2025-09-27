//! Surface - A renderable area with cells that can contain SubSurfaces
//! Similar to vaxis Surface but adapted for Phantom's rendering system

const std = @import("std");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const vxfw = @import("../vxfw.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Rect = geometry.Rect;
const Style = style.Style;

const Surface = @This();

/// Widget that owns this surface
widget: vxfw.Widget,
/// Size of this surface
size: Size,
/// Cell buffer for this surface
cells: []Cell,
/// Child surfaces rendered on top of this surface
children: std.array_list.AlignedManaged(vxfw.SubSurface, null),
/// Allocator used for this surface
allocator: Allocator,

/// Individual cell in the surface buffer
pub const Cell = struct {
    char: u21 = ' ',
    style: Style = Style.default(),
    /// Whether this cell has been written to (for optimization)
    dirty: bool = true,

    pub fn clear(self: *Cell) void {
        self.char = ' ';
        self.style = Style.default();
        self.dirty = true;
    }

    pub fn write(self: *Cell, char: u21, cell_style: Style) void {
        if (self.char != char or !self.style.eq(cell_style)) {
            self.char = char;
            self.style = cell_style;
            self.dirty = true;
        }
    }
};

/// Initialize a new surface with the given size
pub fn init(allocator: Allocator, widget: vxfw.Widget, size: Size) !Surface {
    const cell_count = @as(usize, size.width) * @as(usize, size.height);
    const cells = try allocator.alloc(Cell, cell_count);

    // Initialize all cells to empty
    for (cells) |*cell| {
        cell.clear();
    }

    return Surface{
        .widget = widget,
        .size = size,
        .cells = cells,
        .children = std.array_list.AlignedManaged(vxfw.SubSurface, null).init(allocator),
        .allocator = allocator,
    };
}

/// Create a surface using arena allocator (no explicit deinit needed)
pub fn initArena(arena: Allocator, widget: vxfw.Widget, size: Size) !Surface {
    const cell_count = @as(usize, size.width) * @as(usize, size.height);
    const cells = try arena.alloc(Cell, cell_count);

    // Initialize all cells to empty
    for (cells) |*cell| {
        cell.clear();
    }

    return Surface{
        .widget = widget,
        .size = size,
        .cells = cells,
        .children = std.array_list.AlignedManaged(vxfw.SubSurface, null).init(arena),
        .allocator = arena,
    };
}

pub fn deinit(self: *Surface) void {
    self.children.deinit();
    self.allocator.free(self.cells);
}

/// Get cell at the given position, returns null if out of bounds
pub fn getCell(self: *Surface, x: u16, y: u16) ?*Cell {
    if (x >= self.size.width or y >= self.size.height) return null;
    const index = @as(usize, y) * @as(usize, self.size.width) + @as(usize, x);
    return &self.cells[index];
}

/// Set cell at the given position, returns false if out of bounds
pub fn setCell(self: *Surface, x: u16, y: u16, char: u21, cell_style: Style) bool {
    if (self.getCell(x, y)) |cell| {
        cell.write(char, cell_style);
        return true;
    }
    return false;
}

/// Fill a rectangular area with the given character and style
pub fn fillRect(self: *Surface, rect: Rect, char: u21, cell_style: Style) void {
    const end_x = @min(rect.x + rect.width, self.size.width);
    const end_y = @min(rect.y + rect.height, self.size.height);

    var y: u16 = rect.y;
    while (y < end_y) : (y += 1) {
        var x: u16 = rect.x;
        while (x < end_x) : (x += 1) {
            _ = self.setCell(x, y, char, cell_style);
        }
    }
}

/// Write text at the given position with the specified style
pub fn writeText(self: *Surface, x: u16, y: u16, text: []const u8, text_style: Style) u16 {
    var col = x;
    var utf8_view = std.unicode.Utf8View.init(text) catch return 0;
    var iterator = utf8_view.iterator();

    while (iterator.nextCodepoint()) |codepoint| {
        if (col >= self.size.width) break;
        _ = self.setCell(col, y, codepoint, text_style);
        col += 1;
    }

    return col - x; // Return number of characters written
}

/// Clear the entire surface
pub fn clear(self: *Surface) void {
    for (self.cells) |*cell| {
        cell.clear();
    }
}

/// Add a child SubSurface to be rendered on top of this Surface
pub fn addChild(self: *Surface, subsurface: vxfw.SubSurface) !void {
    try self.children.append(subsurface);
}

/// Remove all child SubSurfaces
pub fn clearChildren(self: *Surface) void {
    self.children.clearRetainingCapacity();
}

/// Get the bounds of this surface as a rectangle
pub fn bounds(self: *Surface) Rect {
    return Rect.init(0, 0, self.size.width, self.size.height);
}

/// Create a subsurface at the given origin pointing to another surface
pub fn createSubSurface(self: *Surface, origin: Point, surface: Surface) vxfw.SubSurface {
    _ = self;
    return vxfw.SubSurface{
        .origin = origin,
        .surface = surface,
    };
}

/// Copy contents from another surface at the given offset
pub fn blitFrom(self: *Surface, other: *const Surface, offset: Point) void {
    const dst_rect = self.bounds();
    const src_rect = Rect.init(offset.x, offset.y, other.size.width, other.size.height);
    const clip_rect = dst_rect.intersect(src_rect) orelse return;

    var y: u16 = 0;
    while (y < clip_rect.height) : (y += 1) {
        var x: u16 = 0;
        while (x < clip_rect.width) : (x += 1) {
            const src_x = x + (clip_rect.x - offset.x);
            const src_y = y + (clip_rect.y - offset.y);
            const dst_x = x + clip_rect.x;
            const dst_y = y + clip_rect.y;

            if (other.getCell(src_x, src_y)) |src_cell| {
                _ = self.setCell(dst_x, dst_y, src_cell.char, src_cell.style);
            }
        }
    }
}

test "Surface creation and basic operations" {
    const allocator = std.testing.allocator;

    const test_widget = vxfw.Widget{
        .userdata = undefined,
        .drawFn = undefined,
    };

    var surface = try Surface.init(allocator, test_widget, Size.init(10, 5));
    defer surface.deinit();

    // Test bounds
    try std.testing.expectEqual(Size.init(10, 5), surface.size);

    // Test cell access
    try std.testing.expect(surface.setCell(5, 2, 'A', Style.default()));
    const cell = surface.getCell(5, 2).?;
    try std.testing.expectEqual(@as(u21, 'A'), cell.char);

    // Test out of bounds
    try std.testing.expect(!surface.setCell(15, 2, 'B', Style.default()));
    try std.testing.expect(surface.getCell(15, 2) == null);
}

test "Surface text writing" {
    const allocator = std.testing.allocator;

    const test_widget = vxfw.Widget{
        .userdata = undefined,
        .drawFn = undefined,
    };

    var surface = try Surface.init(allocator, test_widget, Size.init(20, 5));
    defer surface.deinit();

    const chars_written = surface.writeText(2, 1, "Hello", Style.default());
    try std.testing.expectEqual(@as(u16, 5), chars_written);

    // Verify characters were written correctly
    try std.testing.expectEqual(@as(u21, 'H'), surface.getCell(2, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), surface.getCell(3, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'l'), surface.getCell(4, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'l'), surface.getCell(5, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'o'), surface.getCell(6, 1).?.char);
}