//! Scrollbar - Visual scrollbar indicator widget
//! Standalone scrollbar component that can be used with any scrollable content

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Rect = geometry.Rect;
const Style = style.Style;

const Scrollbar = @This();

orientation: Orientation,
content_size: u32,
viewport_size: u32,
scroll_position: u32 = 0,
track_style: Style,
thumb_style: Style,
button_style: Style,
show_buttons: bool = true,

pub const Orientation = enum {
    vertical,
    horizontal,
};

/// Create a vertical scrollbar
pub fn vertical(content_size: u32, viewport_size: u32, track_style: Style, thumb_style: Style) Scrollbar {
    return Scrollbar{
        .orientation = .vertical,
        .content_size = content_size,
        .viewport_size = viewport_size,
        .track_style = track_style,
        .thumb_style = thumb_style,
        .button_style = track_style,
    };
}

/// Create a horizontal scrollbar
pub fn horizontal(content_size: u32, viewport_size: u32, track_style: Style, thumb_style: Style) Scrollbar {
    return Scrollbar{
        .orientation = .horizontal,
        .content_size = content_size,
        .viewport_size = viewport_size,
        .track_style = track_style,
        .thumb_style = thumb_style,
        .button_style = track_style,
    };
}

/// Create a scrollbar with default styling
pub fn init(orientation: Orientation, content_size: u32, viewport_size: u32) Scrollbar {
    const track_style = Style.default().withFg(.bright_black);
    const thumb_style = Style.default().withFg(.white).withBg(.bright_black);

    return Scrollbar{
        .orientation = orientation,
        .content_size = content_size,
        .viewport_size = viewport_size,
        .track_style = track_style,
        .thumb_style = thumb_style,
        .button_style = track_style,
    };
}

/// Create a scrollbar without scroll buttons
pub fn withoutButtons(orientation: Orientation, content_size: u32, viewport_size: u32, track_style: Style, thumb_style: Style) Scrollbar {
    return Scrollbar{
        .orientation = orientation,
        .content_size = content_size,
        .viewport_size = viewport_size,
        .track_style = track_style,
        .thumb_style = thumb_style,
        .button_style = track_style,
        .show_buttons = false,
    };
}

/// Set the scroll position
pub fn setScrollPosition(self: *Scrollbar, position: u32) void {
    const max_scroll = if (self.content_size > self.viewport_size)
        self.content_size - self.viewport_size
    else
        0;
    self.scroll_position = @min(position, max_scroll);
}

/// Get the maximum scroll position
pub fn getMaxScroll(self: *const Scrollbar) u32 {
    return if (self.content_size > self.viewport_size)
        self.content_size - self.viewport_size
    else
        0;
}

/// Check if scrolling is needed
pub fn isScrollable(self: *const Scrollbar) bool {
    return self.content_size > self.viewport_size;
}

/// Calculate thumb size and position
fn calculateThumb(self: *const Scrollbar, track_size: u32) struct { size: u32, position: u32 } {
    if (!self.isScrollable() or track_size == 0) {
        return .{ .size = track_size, .position = 0 };
    }

    // Thumb size proportional to viewport vs content
    const thumb_size = @max(1, (self.viewport_size * track_size) / self.content_size);

    // Thumb position proportional to scroll position
    const max_scroll = self.getMaxScroll();
    const thumb_position = if (max_scroll > 0)
        (self.scroll_position * (track_size - thumb_size)) / max_scroll
    else
        0;

    return .{ .size = thumb_size, .position = thumb_position };
}

/// Get the widget interface for this Scrollbar
pub fn widget(self: *const Scrollbar) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const Scrollbar = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *Scrollbar = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const Scrollbar, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const width = ctx.getWidth();
    const height = ctx.getHeight();

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(width, height)
    );

    switch (self.orientation) {
        .vertical => try self.drawVertical(&surface, width, height),
        .horizontal => try self.drawHorizontal(&surface, width, height),
    }

    return surface;
}

fn drawVertical(self: *const Scrollbar, surface: *vxfw.Surface, width: u16, height: u16) !void {
    // Calculate track area (excluding buttons if shown)
    const button_space: u16 = if (self.show_buttons) 2 else 0;
    const track_start: u16 = if (self.show_buttons) 1 else 0;
    const track_size = if (height > button_space) height - button_space else 0;

    // Draw scroll buttons
    if (self.show_buttons and height >= 2) {
        // Up button
        _ = surface.setCell(0, 0, '▲', self.button_style);
        if (width > 1) {
            var x: u16 = 1;
            while (x < width) : (x += 1) {
                _ = surface.setCell(x, 0, ' ', self.button_style);
            }
        }

        // Down button
        _ = surface.setCell(0, height - 1, '▼', self.button_style);
        if (width > 1) {
            var x: u16 = 1;
            while (x < width) : (x += 1) {
                _ = surface.setCell(x, height - 1, ' ', self.button_style);
            }
        }
    }

    // Draw track
    if (track_size > 0) {
        var y: u16 = track_start;
        while (y < track_start + track_size) : (y += 1) {
            var x: u16 = 0;
            while (x < width) : (x += 1) {
                _ = surface.setCell(x, y, '│', self.track_style);
            }
        }

        // Draw thumb
        if (self.isScrollable()) {
            const thumb_info = self.calculateThumb(track_size);
            const thumb_start = track_start + @as(u16, @intCast(thumb_info.position));
            const thumb_end = thumb_start + @as(u16, @intCast(thumb_info.size));

            var thumb_y = thumb_start;
            while (thumb_y < thumb_end and thumb_y < track_start + track_size) : (thumb_y += 1) {
                var x: u16 = 0;
                while (x < width) : (x += 1) {
                    _ = surface.setCell(x, thumb_y, '█', self.thumb_style);
                }
            }
        }
    }
}

fn drawHorizontal(self: *const Scrollbar, surface: *vxfw.Surface, width: u16, height: u16) !void {
    // Calculate track area (excluding buttons if shown)
    const button_space: u16 = if (self.show_buttons) 2 else 0;
    const track_start: u16 = if (self.show_buttons) 1 else 0;
    const track_size = if (width > button_space) width - button_space else 0;

    // Draw scroll buttons
    if (self.show_buttons and width >= 2) {
        // Left button
        _ = surface.setCell(0, 0, '◀', self.button_style);
        if (height > 1) {
            var y: u16 = 1;
            while (y < height) : (y += 1) {
                _ = surface.setCell(0, y, ' ', self.button_style);
            }
        }

        // Right button
        _ = surface.setCell(width - 1, 0, '▶', self.button_style);
        if (height > 1) {
            var y: u16 = 1;
            while (y < height) : (y += 1) {
                _ = surface.setCell(width - 1, y, ' ', self.button_style);
            }
        }
    }

    // Draw track
    if (track_size > 0) {
        var x: u16 = track_start;
        while (x < track_start + track_size) : (x += 1) {
            var y: u16 = 0;
            while (y < height) : (y += 1) {
                _ = surface.setCell(x, y, '─', self.track_style);
            }
        }

        // Draw thumb
        if (self.isScrollable()) {
            const thumb_info = self.calculateThumb(track_size);
            const thumb_start = track_start + @as(u16, @intCast(thumb_info.position));
            const thumb_end = thumb_start + @as(u16, @intCast(thumb_info.size));

            var thumb_x = thumb_start;
            while (thumb_x < thumb_end and thumb_x < track_start + track_size) : (thumb_x += 1) {
                var y: u16 = 0;
                while (y < height) : (y += 1) {
                    _ = surface.setCell(thumb_x, y, '█', self.thumb_style);
                }
            }
        }
    }
}

pub fn handleEvent(self: *Scrollbar, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    switch (ctx.event) {
        .mouse => |mouse| {
            if (ctx.isMouseEvent() != null) {
                switch (mouse.button) {
                    .wheel_up => {
                        if (self.orientation == .vertical) {
                            const new_pos = if (self.scroll_position >= 3) self.scroll_position - 3 else 0;
                            self.setScrollPosition(new_pos);
                            try commands.append(.redraw);
                        }
                    },
                    .wheel_down => {
                        if (self.orientation == .vertical) {
                            self.setScrollPosition(self.scroll_position + 3);
                            try commands.append(.redraw);
                        }
                    },
                    .wheel_left => {
                        if (self.orientation == .horizontal) {
                            const new_pos = if (self.scroll_position >= 3) self.scroll_position - 3 else 0;
                            self.setScrollPosition(new_pos);
                            try commands.append(.redraw);
                        }
                    },
                    .wheel_right => {
                        if (self.orientation == .horizontal) {
                            self.setScrollPosition(self.scroll_position + 3);
                            try commands.append(.redraw);
                        }
                    },
                    .left => {
                        if (mouse.action == .press) {
                            // Handle click on scrollbar (track, thumb, or buttons)
                            // This would require more complex hit testing
                            try commands.append(.redraw);
                        }
                    },
                    else => {},
                }
            }
        },
        else => {},
    }

    return commands;
}

test "Scrollbar creation and calculations" {
    const scrollbar = Scrollbar.vertical(100, 20, Style.default(), Style.default());

    // Test scrollability
    try std.testing.expect(scrollbar.isScrollable());
    try std.testing.expectEqual(@as(u32, 80), scrollbar.getMaxScroll());

    // Test thumb calculation
    const thumb = scrollbar.calculateThumb(10);
    try std.testing.expectEqual(@as(u32, 2), thumb.size); // (20 * 10) / 100 = 2
    try std.testing.expectEqual(@as(u32, 0), thumb.position);
}

test "Scrollbar position setting" {
    var scrollbar = Scrollbar.horizontal(50, 10, Style.default(), Style.default());

    scrollbar.setScrollPosition(100); // Exceeds max
    try std.testing.expectEqual(@as(u32, 40), scrollbar.scroll_position); // Clamped to max

    scrollbar.setScrollPosition(20);
    try std.testing.expectEqual(@as(u32, 20), scrollbar.scroll_position);
}