//! Canvas Widget - General-purpose drawing with primitives
//! Supports lines, rectangles, circles, and arbitrary shapes
//! Uses Bresenham algorithms for rasterization

const std = @import("std");
const phantom = @import("../root.zig");
const Rect = phantom.Rect;
const Position = phantom.Position;
const Color = phantom.Color;
const Style = phantom.Style;
const Buffer = phantom.Buffer;
const Cell = phantom.Cell;

/// Canvas widget for custom drawing
pub const Canvas = struct {
    allocator: std.mem.Allocator,
    shapes: std.ArrayList(Shape),
    width: usize,
    height: usize,
    background: ?Color,
    x_scale: f64, // Data coord to canvas coord scale
    y_scale: f64,
    x_offset: f64,
    y_offset: f64,

    pub const Shape = union(enum) {
        line: Line,
        rectangle: Rectangle,
        circle: Circle,
        points: Points,
        text: Text,
        path: Path,
    };

    pub const Line = struct {
        x1: f64,
        y1: f64,
        x2: f64,
        y2: f64,
        color: Color,
        style: LineStyle,

        pub const LineStyle = enum {
            solid,
            dashed,
            dotted,
        };
    };

    pub const Rectangle = struct {
        x: f64,
        y: f64,
        width: f64,
        height: f64,
        color: Color,
        filled: bool,
    };

    pub const Circle = struct {
        x: f64,
        y: f64,
        radius: f64,
        color: Color,
        filled: bool,
    };

    pub const Points = struct {
        points: []const Point,
        color: Color,
        marker: u21,
    };

    pub const Point = struct {
        x: f64,
        y: f64,
    };

    pub const Text = struct {
        x: f64,
        y: f64,
        text: []const u8,
        style: Style,
    };

    pub const Path = struct {
        points: []const Point,
        color: Color,
        closed: bool,
    };

    /// Initialize Canvas
    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) Canvas {
        return Canvas{
            .allocator = allocator,
            .shapes = .{},
            .width = width,
            .height = height,
            .background = null,
            .x_scale = 1.0,
            .y_scale = 1.0,
            .x_offset = 0.0,
            .y_offset = 0.0,
        };
    }

    pub fn deinit(self: *Canvas) void {
        self.shapes.deinit(self.allocator);
    }

    /// Clear all shapes
    pub fn clear(self: *Canvas) void {
        self.shapes.clearRetainingCapacity();
    }

    /// Set coordinate system scaling
    pub fn setScale(self: *Canvas, x_scale: f64, y_scale: f64) void {
        self.x_scale = x_scale;
        self.y_scale = y_scale;
    }

    /// Set coordinate system offset
    pub fn setOffset(self: *Canvas, x_offset: f64, y_offset: f64) void {
        self.x_offset = x_offset;
        self.y_offset = y_offset;
    }

    /// Set background color
    pub fn setBackground(self: *Canvas, color: Color) void {
        self.background = color;
    }

    /// Draw a line
    pub fn drawLine(self: *Canvas, x1: f64, y1: f64, x2: f64, y2: f64, color: Color) !void {
        try self.shapes.append(self.allocator, .{ .line = .{
            .x1 = x1,
            .y1 = y1,
            .x2 = x2,
            .y2 = y2,
            .color = color,
            .style = .solid,
        } });
    }

    /// Draw a dashed line
    pub fn drawDashedLine(self: *Canvas, x1: f64, y1: f64, x2: f64, y2: f64, color: Color) !void {
        try self.shapes.append(self.allocator, .{ .line = .{
            .x1 = x1,
            .y1 = y1,
            .x2 = x2,
            .y2 = y2,
            .color = color,
            .style = .dashed,
        } });
    }

    /// Draw a rectangle
    pub fn drawRect(self: *Canvas, x: f64, y: f64, width: f64, height: f64, color: Color) !void {
        try self.shapes.append(self.allocator, .{ .rectangle = .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .color = color,
            .filled = false,
        } });
    }

    /// Draw a filled rectangle
    pub fn fillRect(self: *Canvas, x: f64, y: f64, width: f64, height: f64, color: Color) !void {
        try self.shapes.append(self.allocator, .{ .rectangle = .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .color = color,
            .filled = true,
        } });
    }

    /// Draw a circle
    pub fn drawCircle(self: *Canvas, x: f64, y: f64, radius: f64, color: Color) !void {
        try self.shapes.append(self.allocator, .{ .circle = .{
            .x = x,
            .y = y,
            .radius = radius,
            .color = color,
            .filled = false,
        } });
    }

    /// Draw a filled circle
    pub fn fillCircle(self: *Canvas, x: f64, y: f64, radius: f64, color: Color) !void {
        try self.shapes.append(self.allocator, .{ .circle = .{
            .x = x,
            .y = y,
            .radius = radius,
            .color = color,
            .filled = true,
        } });
    }

    /// Draw points
    pub fn drawPoints(self: *Canvas, points: []const Point, color: Color, marker: u21) !void {
        const points_copy = try self.allocator.dupe(Point, points);
        try self.shapes.append(self.allocator, .{ .points = .{
            .points = points_copy,
            .color = color,
            .marker = marker,
        } });
    }

    /// Draw text at position
    pub fn drawText(self: *Canvas, x: f64, y: f64, text: []const u8, style: Style) !void {
        try self.shapes.append(self.allocator, .{ .text = .{
            .x = x,
            .y = y,
            .text = text,
            .style = style,
        } });
    }

    /// Draw a path (connected points)
    pub fn drawPath(self: *Canvas, points: []const Point, color: Color, closed: bool) !void {
        const points_copy = try self.allocator.dupe(Point, points);
        try self.shapes.append(self.allocator, .{ .path = .{
            .points = points_copy,
            .color = color,
            .closed = closed,
        } });
    }

    /// Convert data coordinate to screen coordinate
    fn toScreenX(self: *const Canvas, data_x: f64, area: Rect) u16 {
        const scaled = (data_x - self.x_offset) * self.x_scale;
        const screen_x = area.x + @as(u16, @intFromFloat(@max(0.0, @min(scaled, @as(f64, @floatFromInt(area.width - 1))))));
        return screen_x;
    }

    fn toScreenY(self: *const Canvas, data_y: f64, area: Rect) u16 {
        const scaled = (data_y - self.y_offset) * self.y_scale;
        // Invert Y axis (screen Y grows downward)
        const screen_y = area.y + area.height - 1 - @as(u16, @intFromFloat(@max(0.0, @min(scaled, @as(f64, @floatFromInt(area.height - 1))))));
        return screen_y;
    }

    /// Render the Canvas
    pub fn render(self: *Canvas, buffer: *Buffer, area: Rect) void {
        // Fill background if set
        if (self.background) |bg_color| {
            const bg_style = Style.default().withBg(bg_color);
            var y: u16 = 0;
            while (y < area.height) : (y += 1) {
                var x: u16 = 0;
                while (x < area.width) : (x += 1) {
                    buffer.setCell(area.x + x, area.y + y, Cell.init(' ', bg_style));
                }
            }
        }

        // Render all shapes
        for (self.shapes.items) |shape| {
            switch (shape) {
                .line => |line| self.renderLine(buffer, area, line),
                .rectangle => |rect| self.renderRectangle(buffer, area, rect),
                .circle => |circle| self.renderCircle(buffer, area, circle),
                .points => |points| self.renderPoints(buffer, area, points),
                .text => |text| self.renderText(buffer, area, text),
                .path => |path| self.renderPath(buffer, area, path),
            }
        }
    }

    /// Render a line using Bresenham's algorithm
    fn renderLine(self: *Canvas, buffer: *Buffer, area: Rect, line: Line) void {
        const x1 = self.toScreenX(line.x1, area);
        const y1 = self.toScreenY(line.y1, area);
        const x2 = self.toScreenX(line.x2, area);
        const y2 = self.toScreenY(line.y2, area);

        const style = Style.default().withFg(line.color);
        const char: u21 = switch (line.style) {
            .solid => '·',
            .dashed => '┄',
            .dotted => '┈',
        };

        // Bresenham's line algorithm
        var x: i32 = @intCast(x1);
        var y: i32 = @intCast(y1);
        const x_end: i32 = @intCast(x2);
        const y_end: i32 = @intCast(y2);

        const dx: i32 = @intCast(@abs(x_end - x));
        const dy: i32 = @intCast(@abs(y_end - y));
        const sx: i32 = if (x < x_end) 1 else -1;
        const sy: i32 = if (y < y_end) 1 else -1;
        var err: i32 = dx - dy;

        var step: i32 = 0;
        while (true) {
            // For dashed lines, alternate drawing
            const should_draw = switch (line.style) {
                .solid => true,
                .dashed => (@mod(step, 4) < 2),
                .dotted => (@mod(step, 2) == 0),
            };

            if (should_draw) {
                buffer.setCell(@intCast(x), @intCast(y), Cell.init(char, style));
            }

            if (x == x_end and y == y_end) break;

            const e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x += sx;
            }
            if (e2 < dx) {
                err += dx;
                y += sy;
            }

            step += 1;
        }
    }

    /// Render a rectangle
    fn renderRectangle(self: *Canvas, buffer: *Buffer, area: Rect, rect: Rectangle) void {
        const x1 = self.toScreenX(rect.x, area);
        const y1 = self.toScreenY(rect.y + rect.height, area); // Top-left in screen coords
        const x2 = self.toScreenX(rect.x + rect.width, area);
        const y2 = self.toScreenY(rect.y, area); // Bottom-right in screen coords

        const style = Style.default().withFg(rect.color);

        if (rect.filled) {
            // Fill rectangle
            var y = y1;
            while (y <= y2) : (y += 1) {
                var x = x1;
                while (x <= x2) : (x += 1) {
                    buffer.setCell(x, y, Cell.init('█', style));
                }
            }
        } else {
            // Draw rectangle outline
            // Top edge
            var x = x1;
            while (x <= x2) : (x += 1) {
                buffer.setCell(x, y1, Cell.init('─', style));
            }
            // Bottom edge
            x = x1;
            while (x <= x2) : (x += 1) {
                buffer.setCell(x, y2, Cell.init('─', style));
            }
            // Left edge
            var y = y1;
            while (y <= y2) : (y += 1) {
                buffer.setCell(x1, y, Cell.init('│', style));
            }
            // Right edge
            y = y1;
            while (y <= y2) : (y += 1) {
                buffer.setCell(x2, y, Cell.init('│', style));
            }
            // Corners
            buffer.setCell(x1, y1, Cell.init('┌', style));
            buffer.setCell(x2, y1, Cell.init('┐', style));
            buffer.setCell(x1, y2, Cell.init('└', style));
            buffer.setCell(x2, y2, Cell.init('┘', style));
        }
    }

    /// Render a circle using Bresenham's circle algorithm
    fn renderCircle(self: *Canvas, buffer: *Buffer, area: Rect, circle: Circle) void {
        const cx = self.toScreenX(circle.x, area);
        const cy = self.toScreenY(circle.y, area);
        const radius = @as(i32, @intFromFloat(circle.radius * @min(self.x_scale, self.y_scale)));

        const style = Style.default().withFg(circle.color);

        if (circle.filled) {
            // Fill circle using midpoint circle algorithm
            var y: i32 = -radius;
            while (y <= radius) : (y += 1) {
                const dx = @as(i32, @intFromFloat(@sqrt(@as(f64, @floatFromInt(radius * radius - y * y)))));
                var x: i32 = -dx;
                while (x <= dx) : (x += 1) {
                    const px = @as(i32, @intCast(cx)) + x;
                    const py = @as(i32, @intCast(cy)) + y;
                    if (px >= 0 and py >= 0) {
                        buffer.setCell(@intCast(px), @intCast(py), Cell.init('█', style));
                    }
                }
            }
        } else {
            // Draw circle outline using Bresenham's circle algorithm
            var x: i32 = 0;
            var y: i32 = radius;
            var d: i32 = 3 - 2 * radius;

            while (y >= x) {
                // Draw 8 octants
                self.plotCirclePoints(buffer, cx, cy, x, y, style);

                x += 1;

                if (d > 0) {
                    y -= 1;
                    d = d + 4 * (x - y) + 10;
                } else {
                    d = d + 4 * x + 6;
                }
            }
        }
    }

    /// Plot 8-way symmetry for circle
    fn plotCirclePoints(self: *Canvas, buffer: *Buffer, cx: u16, cy: u16, x: i32, y: i32, style: Style) void {
        _ = self;
        const points = [_][2]i32{
            .{ x, y },   .{ -x, y },  .{ x, -y },  .{ -x, -y },
            .{ y, x },   .{ -y, x },  .{ y, -x },  .{ -y, -x },
        };

        for (points) |p| {
            const px = @as(i32, @intCast(cx)) + p[0];
            const py = @as(i32, @intCast(cy)) + p[1];
            if (px >= 0 and py >= 0) {
                buffer.setCell(@intCast(px), @intCast(py), Cell.init('●', style));
            }
        }
    }

    /// Render points
    fn renderPoints(self: *Canvas, buffer: *Buffer, area: Rect, points: Points) void {
        const style = Style.default().withFg(points.color);

        for (points.points) |point| {
            const x = self.toScreenX(point.x, area);
            const y = self.toScreenY(point.y, area);
            buffer.setCell(x, y, Cell.init(points.marker, style));
        }
    }

    /// Render text
    fn renderText(self: *Canvas, buffer: *Buffer, area: Rect, text: Text) void {
        const x = self.toScreenX(text.x, area);
        const y = self.toScreenY(text.y, area);
        buffer.writeText(x, y, text.text, text.style);
    }

    /// Render path
    fn renderPath(self: *Canvas, buffer: *Buffer, area: Rect, path: Path) void {
        if (path.points.len < 2) return;

        // Draw lines between consecutive points
        for (0..path.points.len - 1) |i| {
            const p1 = path.points[i];
            const p2 = path.points[i + 1];

            const line = Line{
                .x1 = p1.x,
                .y1 = p1.y,
                .x2 = p2.x,
                .y2 = p2.y,
                .color = path.color,
                .style = .solid,
            };

            self.renderLine(buffer, area, line);
        }

        // Close the path if needed
        if (path.closed and path.points.len >= 2) {
            const p_first = path.points[0];
            const p_last = path.points[path.points.len - 1];

            const line = Line{
                .x1 = p_last.x,
                .y1 = p_last.y,
                .x2 = p_first.x,
                .y2 = p_first.y,
                .color = path.color,
                .style = .solid,
            };

            self.renderLine(buffer, area, line);
        }
    }
};

// Tests
test "Canvas initialization" {
    const testing = std.testing;

    var canvas = Canvas.init(testing.allocator, 80, 24);
    defer canvas.deinit();

    try testing.expectEqual(@as(usize, 80), canvas.width);
    try testing.expectEqual(@as(usize, 24), canvas.height);
    try testing.expectEqual(@as(usize, 0), canvas.shapes.items.len);
}

test "Canvas draw shapes" {
    const testing = std.testing;

    var canvas = Canvas.init(testing.allocator, 80, 24);
    defer canvas.deinit();

    try canvas.drawLine(0.0, 0.0, 10.0, 10.0, Color.red);
    try canvas.drawRect(5.0, 5.0, 10.0, 10.0, Color.blue);
    try canvas.drawCircle(15.0, 15.0, 5.0, Color.green);

    try testing.expectEqual(@as(usize, 3), canvas.shapes.items.len);
}

test "Canvas coordinate transformation" {
    const testing = std.testing;

    var canvas = Canvas.init(testing.allocator, 100, 100);
    defer canvas.deinit();

    canvas.setScale(2.0, 2.0);
    canvas.setOffset(10.0, 10.0);

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };

    const screen_x = canvas.toScreenX(15.0, area);
    _ = canvas.toScreenY(15.0, area);

    // (15 - 10) * 2 = 10
    try testing.expectEqual(@as(u16, 10), screen_x);
}

test "Canvas clear" {
    const testing = std.testing;

    var canvas = Canvas.init(testing.allocator, 80, 24);
    defer canvas.deinit();

    try canvas.drawLine(0.0, 0.0, 10.0, 10.0, Color.red);
    try canvas.drawRect(5.0, 5.0, 10.0, 10.0, Color.blue);

    try testing.expectEqual(@as(usize, 2), canvas.shapes.items.len);

    canvas.clear();
    try testing.expectEqual(@as(usize, 0), canvas.shapes.items.len);
}
