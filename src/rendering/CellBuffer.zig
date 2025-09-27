//! CellBuffer - Cell-based rendering system like vaxis
//! Provides a complete cell buffer for terminal rendering with Unicode support

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const GraphemeCache = @import("../unicode/GraphemeCache.zig").GraphemeCache;

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Rect = geometry.Rect;
const Style = style.Style;

/// Cell-based screen buffer for efficient terminal rendering
pub const CellBuffer = struct {
    allocator: Allocator,
    cells: []Cell,
    width: u16,
    height: u16,
    dirty_regions: std.array_list.AlignedManaged(Rect, null),
    grapheme_cache: *GraphemeCache,
    cursor_position: Point = Point.init(0, 0),
    cursor_visible: bool = true,

    pub fn init(allocator: Allocator, width: u16, height: u16, grapheme_cache: *GraphemeCache) !CellBuffer {
        const total_cells = @as(usize, width) * height;
        const cells = try allocator.alloc(Cell, total_cells);

        // Initialize all cells
        for (cells) |*cell| {
            cell.* = Cell.empty();
        }

        return CellBuffer{
            .allocator = allocator,
            .cells = cells,
            .width = width,
            .height = height,
            .dirty_regions = std.array_list.AlignedManaged(Rect, null).init(allocator),
            .grapheme_cache = grapheme_cache,
        };
    }

    pub fn deinit(self: *CellBuffer) void {
        for (self.cells) |*cell| {
            cell.deinit(self.allocator);
        }
        self.allocator.free(self.cells);
        self.dirty_regions.deinit();
    }

    /// Resize the buffer
    pub fn resize(self: *CellBuffer, new_width: u16, new_height: u16) !void {
        const new_total = @as(usize, new_width) * new_height;
        const new_cells = try self.allocator.alloc(Cell, new_total);

        // Initialize new cells
        for (new_cells) |*cell| {
            cell.* = Cell.empty();
        }

        // Copy existing cells that fit
        const copy_width = @min(self.width, new_width);
        const copy_height = @min(self.height, new_height);

        var y: u16 = 0;
        while (y < copy_height) : (y += 1) {
            var x: u16 = 0;
            while (x < copy_width) : (x += 1) {
                const old_index = @as(usize, y) * self.width + x;
                const new_index = @as(usize, y) * new_width + x;
                new_cells[new_index] = self.cells[old_index];
                self.cells[old_index] = Cell.empty(); // Prevent double-free
            }
        }

        // Free old cells
        for (self.cells) |*cell| {
            cell.deinit(self.allocator);
        }
        self.allocator.free(self.cells);

        // Update buffer
        self.cells = new_cells;
        self.width = new_width;
        self.height = new_height;

        // Mark entire screen as dirty
        try self.markDirty(Rect.init(0, 0, new_width, new_height));
    }

    /// Clear the entire buffer
    pub fn clear(self: *CellBuffer) !void {
        for (self.cells) |*cell| {
            cell.deinit(self.allocator);
            cell.* = Cell.empty();
        }
        try self.markDirty(Rect.init(0, 0, self.width, self.height));
    }

    /// Clear a specific region
    pub fn clearRegion(self: *CellBuffer, region: Rect) !void {
        const clipped = region.intersect(Rect.init(0, 0, self.width, self.height));

        var y: u16 = clipped.y;
        while (y < clipped.y + clipped.height) : (y += 1) {
            var x: u16 = clipped.x;
            while (x < clipped.x + clipped.width) : (x += 1) {
                const index = @as(usize, y) * self.width + x;
                self.cells[index].deinit(self.allocator);
                self.cells[index] = Cell.empty();
            }
        }

        try self.markDirty(clipped);
    }

    /// Write a single character at position
    pub fn writeCell(self: *CellBuffer, x: u16, y: u16, cell: Cell) !void {
        if (x >= self.width or y >= self.height) return;

        const index = @as(usize, y) * self.width + x;
        self.cells[index].deinit(self.allocator);
        self.cells[index] = try cell.clone(self.allocator);

        try self.markDirty(Rect.init(x, y, 1, 1));
    }

    /// Write text at position with style
    pub fn writeText(self: *CellBuffer, x: u16, y: u16, text: []const u8, text_style: Style) !u16 {
        if (y >= self.height) return 0;

        var current_x = x;
        const graphemes = try self.grapheme_cache.getGraphemes(text);
        defer self.allocator.free(graphemes);

        for (graphemes) |cluster| {
            if (current_x >= self.width) break;

            // Handle wide characters
            if (cluster.width > 1 and current_x + cluster.width > self.width) {
                // Wide character doesn't fit, stop here
                break;
            }

            const cell = Cell{
                .char = .{ .grapheme = try self.allocator.dupe(u8, cluster.bytes) },
                .style = text_style,
                .width = cluster.width,
            };

            try self.writeCell(current_x, y, cell);

            // For wide characters, mark the next cell as a continuation
            if (cluster.width > 1) {
                const continuation_cell = Cell{
                    .char = .{ .continuation = true },
                    .style = text_style,
                    .width = 0,
                };
                try self.writeCell(current_x + 1, y, continuation_cell);
            }

            current_x += cluster.width;
        }

        return current_x - x; // Return number of columns written
    }

    /// Fill a region with a character and style
    pub fn fillRegion(self: *CellBuffer, region: Rect, char: u8, fill_style: Style) !void {
        const clipped = region.intersect(Rect.init(0, 0, self.width, self.height));

        const cell = Cell{
            .char = .{ .ascii = char },
            .style = fill_style,
            .width = 1,
        };

        var y: u16 = clipped.y;
        while (y < clipped.y + clipped.height) : (y += 1) {
            var x: u16 = clipped.x;
            while (x < clipped.x + clipped.width) : (x += 1) {
                try self.writeCell(x, y, cell);
            }
        }
    }

    /// Draw a border around a region
    pub fn drawBorder(self: *CellBuffer, region: Rect, border_style: Style, border_chars: BorderChars) !void {
        if (region.width < 2 or region.height < 2) return;

        const clipped = region.intersect(Rect.init(0, 0, self.width, self.height));

        // Top and bottom borders
        var x: u16 = clipped.x;
        while (x < clipped.x + clipped.width) : (x += 1) {
            if (x == clipped.x) {
                // Top-left corner
                try self.writeCell(x, clipped.y, Cell{
                    .char = .{ .ascii = border_chars.top_left },
                    .style = border_style,
                    .width = 1,
                });
                // Bottom-left corner
                if (clipped.height > 1) {
                    try self.writeCell(x, clipped.y + clipped.height - 1, Cell{
                        .char = .{ .ascii = border_chars.bottom_left },
                        .style = border_style,
                        .width = 1,
                    });
                }
            } else if (x == clipped.x + clipped.width - 1) {
                // Top-right corner
                try self.writeCell(x, clipped.y, Cell{
                    .char = .{ .ascii = border_chars.top_right },
                    .style = border_style,
                    .width = 1,
                });
                // Bottom-right corner
                if (clipped.height > 1) {
                    try self.writeCell(x, clipped.y + clipped.height - 1, Cell{
                        .char = .{ .ascii = border_chars.bottom_right },
                        .style = border_style,
                        .width = 1,
                    });
                }
            } else {
                // Top border
                try self.writeCell(x, clipped.y, Cell{
                    .char = .{ .ascii = border_chars.horizontal },
                    .style = border_style,
                    .width = 1,
                });
                // Bottom border
                if (clipped.height > 1) {
                    try self.writeCell(x, clipped.y + clipped.height - 1, Cell{
                        .char = .{ .ascii = border_chars.horizontal },
                        .style = border_style,
                        .width = 1,
                    });
                }
            }
        }

        // Left and right borders
        var y: u16 = clipped.y + 1;
        while (y < clipped.y + clipped.height - 1) : (y += 1) {
            // Left border
            try self.writeCell(clipped.x, y, Cell{
                .char = .{ .ascii = border_chars.vertical },
                .style = border_style,
                .width = 1,
            });
            // Right border
            if (clipped.width > 1) {
                try self.writeCell(clipped.x + clipped.width - 1, y, Cell{
                    .char = .{ .ascii = border_chars.vertical },
                    .style = border_style,
                    .width = 1,
                });
            }
        }
    }

    /// Get cell at position
    pub fn getCell(self: *const CellBuffer, x: u16, y: u16) ?*const Cell {
        if (x >= self.width or y >= self.height) return null;
        const index = @as(usize, y) * self.width + x;
        return &self.cells[index];
    }

    /// Get mutable cell at position
    pub fn getCellMut(self: *CellBuffer, x: u16, y: u16) ?*Cell {
        if (x >= self.width or y >= self.height) return null;
        const index = @as(usize, y) * self.width + x;
        return &self.cells[index];
    }

    /// Mark a region as dirty for rendering
    pub fn markDirty(self: *CellBuffer, region: Rect) !void {
        try self.dirty_regions.append(region);
    }

    /// Get and clear dirty regions
    pub fn getDirtyRegions(self: *CellBuffer) []Rect {
        const regions = self.dirty_regions.toOwnedSlice() catch &[_]Rect{};
        self.dirty_regions = std.array_list.AlignedManaged(Rect, null).init(self.allocator);
        return regions;
    }

    /// Check if buffer has any dirty regions
    pub fn isDirty(self: *const CellBuffer) bool {
        return self.dirty_regions.items.len > 0;
    }

    /// Set cursor position
    pub fn setCursor(self: *CellBuffer, x: u16, y: u16) void {
        self.cursor_position = Point.init(x, y);
    }

    /// Get cursor position
    pub fn getCursor(self: *const CellBuffer) Point {
        return self.cursor_position;
    }

    /// Set cursor visibility
    pub fn setCursorVisible(self: *CellBuffer, visible: bool) void {
        self.cursor_visible = visible;
    }

    /// Check if cursor is visible
    pub fn isCursorVisible(self: *const CellBuffer) bool {
        return self.cursor_visible;
    }

    /// Generate terminal escape sequences for rendering
    pub fn render(self: *CellBuffer, writer: anytype) !void {
        // Hide cursor during rendering
        if (self.cursor_visible) {
            try writer.writeAll("\x1b[?25l");
        }

        const dirty_regions = self.getDirtyRegions();
        defer self.allocator.free(dirty_regions);

        for (dirty_regions) |region| {
            try self.renderRegion(writer, region);
        }

        // Show cursor and position it
        if (self.cursor_visible) {
            try writer.print("\x1b[{d};{d}H", .{ self.cursor_position.y + 1, self.cursor_position.x + 1 });
            try writer.writeAll("\x1b[?25h");
        }
    }

    /// Render a specific region
    fn renderRegion(self: *CellBuffer, writer: anytype, region: Rect) !void {
        const clipped = region.intersect(Rect.init(0, 0, self.width, self.height));

        var y: u16 = clipped.y;
        while (y < clipped.y + clipped.height) : (y += 1) {
            var x: u16 = clipped.x;
            var current_style: ?Style = null;

            // Position cursor at start of line
            try writer.print("\x1b[{d};{d}H", .{ y + 1, x + 1 });

            while (x < clipped.x + clipped.width) : (x += 1) {
                const cell = self.getCell(x, y) orelse continue;

                // Apply style if changed
                if (current_style == null or !current_style.?.eq(cell.style)) {
                    try self.applyStyle(writer, cell.style);
                    current_style = cell.style;
                }

                // Write character
                switch (cell.char) {
                    .empty => try writer.writeAll(" "),
                    .ascii => |ch| try writer.writeByte(ch),
                    .grapheme => |grapheme| try writer.writeAll(grapheme),
                    .continuation => {}, // Skip continuation cells
                }

                // Skip additional cells for wide characters
                if (cell.width > 1) {
                    x += cell.width - 1;
                }
            }

            // Reset style at end of line
            if (current_style != null) {
                try writer.writeAll("\x1b[0m");
            }
        }
    }

    /// Apply style to output
    fn applyStyle(self: *CellBuffer, writer: anytype, cell_style: Style) !void {
        _ = self;

        // Reset first
        try writer.writeAll("\x1b[0m");

        // Apply colors
        if (cell_style.fg) |fg| {
            switch (fg) {
                .rgb => |rgb| try writer.print("\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }),
                .palette => |idx| try writer.print("\x1b[38;5;{d}m", .{idx}),
                .ansi => |ansi| try writer.print("\x1b[{d}m", .{30 + @as(u8, @intFromEnum(ansi))}),
            }
        }

        if (cell_style.bg) |bg| {
            switch (bg) {
                .rgb => |rgb| try writer.print("\x1b[48;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }),
                .palette => |idx| try writer.print("\x1b[48;5;{d}m", .{idx}),
                .ansi => |ansi| try writer.print("\x1b[{d}m", .{40 + @as(u8, @intFromEnum(ansi))}),
            }
        }

        // Apply attributes
        if (cell_style.bold) try writer.writeAll("\x1b[1m");
        if (cell_style.italic) try writer.writeAll("\x1b[3m");
        if (cell_style.underline) try writer.writeAll("\x1b[4m");
        if (cell_style.strikethrough) try writer.writeAll("\x1b[9m");
        if (cell_style.reverse) try writer.writeAll("\x1b[7m");
    }
};

/// Individual cell in the buffer
pub const Cell = struct {
    char: CharData = .empty,
    style: Style = Style.default(),
    width: u8 = 1,

    pub const CharData = union(enum) {
        empty,
        ascii: u8,
        grapheme: []u8,
        continuation: bool, // For wide character continuation
    };

    pub fn empty() Cell {
        return Cell{};
    }

    pub fn ascii(ch: u8, cell_style: Style) Cell {
        return Cell{
            .char = .{ .ascii = ch },
            .style = cell_style,
            .width = 1,
        };
    }

    pub fn unicode(grapheme: []const u8, cell_style: Style, width: u8, allocator: Allocator) !Cell {
        return Cell{
            .char = .{ .grapheme = try allocator.dupe(u8, grapheme) },
            .style = cell_style,
            .width = width,
        };
    }

    pub fn deinit(self: *Cell, allocator: Allocator) void {
        switch (self.char) {
            .grapheme => |grapheme| allocator.free(grapheme),
            else => {},
        }
    }

    pub fn clone(self: *const Cell, allocator: Allocator) !Cell {
        var cloned = self.*;
        switch (self.char) {
            .grapheme => |grapheme| {
                cloned.char = .{ .grapheme = try allocator.dupe(u8, grapheme) };
            },
            else => {},
        }
        return cloned;
    }

    pub fn isEmpty(self: *const Cell) bool {
        return self.char == .empty;
    }

    pub fn getDisplayWidth(self: *const Cell) u8 {
        return self.width;
    }
};

/// Border character set
pub const BorderChars = struct {
    top_left: u8 = '+',
    top_right: u8 = '+',
    bottom_left: u8 = '+',
    bottom_right: u8 = '+',
    horizontal: u8 = '-',
    vertical: u8 = '|',

    pub const unicode = BorderChars{
        .top_left = '┌',
        .top_right = '┐',
        .bottom_left = '└',
        .bottom_right = '┘',
        .horizontal = '─',
        .vertical = '│',
    };

    pub const double = BorderChars{
        .top_left = '╔',
        .top_right = '╗',
        .bottom_left = '╚',
        .bottom_right = '╝',
        .horizontal = '═',
        .vertical = '║',
    };

    pub const rounded = BorderChars{
        .top_left = '╭',
        .top_right = '╮',
        .bottom_left = '╰',
        .bottom_right = '╯',
        .horizontal = '─',
        .vertical = '│',
    };
};

/// Cell buffer widget for integration with vxfw
pub const CellBufferWidget = struct {
    cell_buffer: *CellBuffer,
    background_style: Style = Style.default(),

    pub fn init(cell_buffer: *CellBuffer) CellBufferWidget {
        return CellBufferWidget{
            .cell_buffer = cell_buffer,
        };
    }

    pub fn widget(self: *const CellBufferWidget) vxfw.Widget {
        return .{
            .userdata = @constCast(self),
            .drawFn = typeErasedDrawFn,
            .eventHandlerFn = typeErasedEventHandler,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *const CellBufferWidget = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
        const self: *CellBufferWidget = @ptrCast(@alignCast(ptr));
        return self.handleEvent(ctx);
    }

    pub fn draw(self: *const CellBufferWidget, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const width = ctx.getWidth();
        const height = ctx.getHeight();

        // Resize cell buffer if needed
        if (self.cell_buffer.width != width or self.cell_buffer.height != height) {
            try self.cell_buffer.resize(width, height);
        }

        // Create surface from cell buffer data
        var surface = try vxfw.Surface.initArena(
            ctx.arena,
            self.widget(),
            Size.init(width, height)
        );

        // Copy cell buffer content to surface
        var y: u16 = 0;
        while (y < height) : (y += 1) {
            var x: u16 = 0;
            while (x < width) : (x += 1) {
                if (self.cell_buffer.getCell(x, y)) |cell| {
                    if (!cell.isEmpty()) {
                        switch (cell.char) {
                            .ascii => |ch| {
                                _ = surface.writeCell(x, y, ch, cell.style);
                            },
                            .grapheme => |grapheme| {
                                _ = surface.writeText(x, y, grapheme, cell.style);
                            },
                            else => {},
                        }
                    }
                }
            }
        }

        return surface;
    }

    pub fn handleEvent(self: *CellBufferWidget, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
        _ = self;
        return ctx.createCommandList();
    }
};

test "CellBuffer basic operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var grapheme_cache = GraphemeCache.init(arena.allocator());
    defer grapheme_cache.deinit();

    var buffer = try CellBuffer.init(arena.allocator(), 10, 5, &grapheme_cache);
    defer buffer.deinit();

    // Test writing text
    const written = try buffer.writeText(0, 0, "Hello", Style.default());
    try std.testing.expectEqual(@as(u16, 5), written);

    // Test getting cell
    const cell = buffer.getCell(0, 0).?;
    try std.testing.expectEqual(@as(u8, 'H'), cell.char.ascii);

    // Test dirty regions
    try std.testing.expect(buffer.isDirty());
}

test "Cell operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cell = Cell.ascii('A', Style.default());
    try std.testing.expectEqual(@as(u8, 'A'), cell.char.ascii);
    try std.testing.expectEqual(@as(u8, 1), cell.width);

    cell.deinit(arena.allocator()); // Should be safe for ASCII cells
}

test "Border drawing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var grapheme_cache = GraphemeCache.init(arena.allocator());
    defer grapheme_cache.deinit();

    var buffer = try CellBuffer.init(arena.allocator(), 5, 3, &grapheme_cache);
    defer buffer.deinit();

    try buffer.drawBorder(Rect.init(0, 0, 5, 3), Style.default(), BorderChars{});

    // Check corners
    try std.testing.expectEqual(@as(u8, '+'), buffer.getCell(0, 0).?.char.ascii);
    try std.testing.expectEqual(@as(u8, '+'), buffer.getCell(4, 0).?.char.ascii);
    try std.testing.expectEqual(@as(u8, '+'), buffer.getCell(0, 2).?.char.ascii);
    try std.testing.expectEqual(@as(u8, '+'), buffer.getCell(4, 2).?.char.ascii);
}