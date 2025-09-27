//! ScrollBars - Overlay scrollbars for any content
//! Provides overlay scrollbars that can be added to any widget without affecting layout

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Rect = geometry.Rect;
const Style = style.Style;

const ScrollBars = @This();

child: vxfw.Widget,
content_size: Size,
viewport_size: Size,
scroll_position: Point = Point{ .x = 0, .y = 0 },
show_vertical: bool = true,
show_horizontal: bool = true,
auto_hide: bool = true,
track_style: Style,
thumb_style: Style,
is_dragging_vertical: bool = false,
is_dragging_horizontal: bool = false,
drag_start_pos: Point = Point{ .x = 0, .y = 0 },

/// Create ScrollBars overlay for a child widget
pub fn init(child: vxfw.Widget, content_size: Size, track_style: Style, thumb_style: Style) ScrollBars {
    return ScrollBars{
        .child = child,
        .content_size = content_size,
        .viewport_size = Size.init(0, 0), // Will be set during draw
        .track_style = track_style,
        .thumb_style = thumb_style,
    };
}

/// Create ScrollBars with auto-hide disabled
pub fn alwaysVisible(child: vxfw.Widget, content_size: Size, track_style: Style, thumb_style: Style) ScrollBars {
    return ScrollBars{
        .child = child,
        .content_size = content_size,
        .viewport_size = Size.init(0, 0),
        .auto_hide = false,
        .track_style = track_style,
        .thumb_style = thumb_style,
    };
}

/// Create ScrollBars with only vertical scrollbar
pub fn verticalOnly(child: vxfw.Widget, content_size: Size, track_style: Style, thumb_style: Style) ScrollBars {
    return ScrollBars{
        .child = child,
        .content_size = content_size,
        .viewport_size = Size.init(0, 0),
        .show_horizontal = false,
        .track_style = track_style,
        .thumb_style = thumb_style,
    };
}

/// Create ScrollBars with only horizontal scrollbar
pub fn horizontalOnly(child: vxfw.Widget, content_size: Size, track_style: Style, thumb_style: Style) ScrollBars {
    return ScrollBars{
        .child = child,
        .content_size = content_size,
        .viewport_size = Size.init(0, 0),
        .show_vertical = false,
        .track_style = track_style,
        .thumb_style = thumb_style,
    };
}

/// Update content size (call when child content changes)
pub fn updateContentSize(self: *ScrollBars, new_content_size: Size) void {
    self.content_size = new_content_size;
    self.clampScrollPosition();
}

/// Set scroll position
pub fn setScrollPosition(self: *ScrollBars, position: Point) void {
    self.scroll_position = position;
    self.clampScrollPosition();
}

/// Scroll by delta
pub fn scrollBy(self: *ScrollBars, delta: Point) void {
    self.scroll_position.x += delta.x;
    self.scroll_position.y += delta.y;
    self.clampScrollPosition();
}

/// Clamp scroll position to valid range
fn clampScrollPosition(self: *ScrollBars) void {
    const max_x = if (self.content_size.width > self.viewport_size.width)
        @as(i16, @intCast(self.content_size.width - self.viewport_size.width))
    else
        0;
    const max_y = if (self.content_size.height > self.viewport_size.height)
        @as(i16, @intCast(self.content_size.height - self.viewport_size.height))
    else
        0;

    self.scroll_position.x = @max(0, @min(self.scroll_position.x, max_x));
    self.scroll_position.y = @max(0, @min(self.scroll_position.y, max_y));
}

/// Check if vertical scrollbar should be visible
fn shouldShowVertical(self: *const ScrollBars) bool {
    if (!self.show_vertical) return false;
    if (!self.auto_hide) return true;
    return self.content_size.height > self.viewport_size.height;
}

/// Check if horizontal scrollbar should be visible
fn shouldShowHorizontal(self: *const ScrollBars) bool {
    if (!self.show_horizontal) return false;
    if (!self.auto_hide) return true;
    return self.content_size.width > self.viewport_size.width;
}

/// Calculate vertical scrollbar bounds
fn getVerticalScrollbarBounds(self: *const ScrollBars) Rect {
    const track_height = if (self.shouldShowHorizontal()) self.viewport_size.height - 1 else self.viewport_size.height;
    return Rect.init(self.viewport_size.width - 1, 0, 1, track_height);
}

/// Calculate horizontal scrollbar bounds
fn getHorizontalScrollbarBounds(self: *const ScrollBars) Rect {
    const track_width = if (self.shouldShowVertical()) self.viewport_size.width - 1 else self.viewport_size.width;
    return Rect.init(0, self.viewport_size.height - 1, track_width, 1);
}

/// Calculate vertical thumb position and size
fn calculateVerticalThumb(self: *const ScrollBars) struct { position: u16, size: u16 } {
    const track_bounds = self.getVerticalScrollbarBounds();
    const track_height = track_bounds.height;

    if (track_height == 0 or !self.shouldShowVertical()) {
        return .{ .position = 0, .size = 0 };
    }

    // Thumb size proportional to viewport vs content
    const thumb_size = @max(1, (self.viewport_size.height * track_height) / self.content_size.height);

    // Thumb position proportional to scroll position
    const max_scroll = if (self.content_size.height > self.viewport_size.height)
        self.content_size.height - self.viewport_size.height
    else
        0;

    const thumb_position = if (max_scroll > 0)
        (@as(u32, @intCast(self.scroll_position.y)) * (track_height - thumb_size)) / max_scroll
    else
        0;

    return .{ .position = @intCast(thumb_position), .size = thumb_size };
}

/// Calculate horizontal thumb position and size
fn calculateHorizontalThumb(self: *const ScrollBars) struct { position: u16, size: u16 } {
    const track_bounds = self.getHorizontalScrollbarBounds();
    const track_width = track_bounds.width;

    if (track_width == 0 or !self.shouldShowHorizontal()) {
        return .{ .position = 0, .size = 0 };
    }

    // Thumb size proportional to viewport vs content
    const thumb_size = @max(1, (self.viewport_size.width * track_width) / self.content_size.width);

    // Thumb position proportional to scroll position
    const max_scroll = if (self.content_size.width > self.viewport_size.width)
        self.content_size.width - self.viewport_size.width
    else
        0;

    const thumb_position = if (max_scroll > 0)
        (@as(u32, @intCast(self.scroll_position.x)) * (track_width - thumb_size)) / max_scroll
    else
        0;

    return .{ .position = @intCast(thumb_position), .size = thumb_size };
}

/// Check if point is in vertical scrollbar thumb
fn isPointInVerticalThumb(self: *const ScrollBars, point: Point) bool {
    if (!self.shouldShowVertical()) return false;

    const track_bounds = self.getVerticalScrollbarBounds();
    const thumb = self.calculateVerticalThumb();

    const thumb_bounds = Rect.init(
        track_bounds.x,
        track_bounds.y + thumb.position,
        track_bounds.width,
        thumb.size
    );

    return thumb_bounds.containsPoint(point);
}

/// Check if point is in horizontal scrollbar thumb
fn isPointInHorizontalThumb(self: *const ScrollBars, point: Point) bool {
    if (!self.shouldShowHorizontal()) return false;

    const track_bounds = self.getHorizontalScrollbarBounds();
    const thumb = self.calculateHorizontalThumb();

    const thumb_bounds = Rect.init(
        track_bounds.x + thumb.position,
        track_bounds.y,
        thumb.size,
        track_bounds.height
    );

    return thumb_bounds.containsPoint(point);
}

/// Get the widget interface for this ScrollBars
pub fn widget(self: *const ScrollBars) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *ScrollBars = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *ScrollBars = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *ScrollBars, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const width = ctx.getWidth();
    const height = ctx.getHeight();

    // Update viewport size
    self.viewport_size = Size.init(width, height);

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(width, height)
    );

    // Draw child widget
    const child_surface = try self.child.draw(ctx);
    const child_subsurface = vxfw.SubSurface.init(Point{ .x = 0, .y = 0 }, child_surface);
    try surface.addChild(child_subsurface);

    // Draw vertical scrollbar
    if (self.shouldShowVertical()) {
        const track_bounds = self.getVerticalScrollbarBounds();
        const thumb = self.calculateVerticalThumb();

        // Draw track
        var y: u16 = track_bounds.y;
        while (y < track_bounds.y + track_bounds.height) : (y += 1) {
            _ = surface.setCell(track_bounds.x, y, '│', self.track_style);
        }

        // Draw thumb
        var thumb_y: u16 = 0;
        while (thumb_y < thumb.size) : (thumb_y += 1) {
            const cell_y = track_bounds.y + thumb.position + thumb_y;
            if (cell_y < track_bounds.y + track_bounds.height) {
                _ = surface.setCell(track_bounds.x, cell_y, '█', self.thumb_style);
            }
        }
    }

    // Draw horizontal scrollbar
    if (self.shouldShowHorizontal()) {
        const track_bounds = self.getHorizontalScrollbarBounds();
        const thumb = self.calculateHorizontalThumb();

        // Draw track
        var x: u16 = track_bounds.x;
        while (x < track_bounds.x + track_bounds.width) : (x += 1) {
            _ = surface.setCell(x, track_bounds.y, '─', self.track_style);
        }

        // Draw thumb
        var thumb_x: u16 = 0;
        while (thumb_x < thumb.size) : (thumb_x += 1) {
            const cell_x = track_bounds.x + thumb.position + thumb_x;
            if (cell_x < track_bounds.x + track_bounds.width) {
                _ = surface.setCell(cell_x, track_bounds.y, '█', self.thumb_style);
            }
        }
    }

    // Draw corner if both scrollbars are visible
    if (self.shouldShowVertical() and self.shouldShowHorizontal()) {
        _ = surface.setCell(width - 1, height - 1, '┼', self.track_style);
    }

    return surface;
}

pub fn handleEvent(self: *ScrollBars, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    switch (ctx.event) {
        .mouse => |mouse| {
            if (ctx.isMouseEvent()) |_| {
                const local_pos = ctx.getLocalMousePosition() orelse return commands;

                switch (mouse.action) {
                    .press => {
                        if (mouse.button == .left) {
                            if (self.isPointInVerticalThumb(local_pos)) {
                                self.is_dragging_vertical = true;
                                self.drag_start_pos = local_pos;
                                try commands.append(.redraw);
                                return commands;
                            } else if (self.isPointInHorizontalThumb(local_pos)) {
                                self.is_dragging_horizontal = true;
                                self.drag_start_pos = local_pos;
                                try commands.append(.redraw);
                                return commands;
                            }
                        }

                        // Handle wheel scrolling
                        switch (mouse.button) {
                            .wheel_up => {
                                self.scrollBy(Point{ .x = 0, .y = -3 });
                                try commands.append(.redraw);
                            },
                            .wheel_down => {
                                self.scrollBy(Point{ .x = 0, .y = 3 });
                                try commands.append(.redraw);
                            },
                            .wheel_left => {
                                self.scrollBy(Point{ .x = -3, .y = 0 });
                                try commands.append(.redraw);
                            },
                            .wheel_right => {
                                self.scrollBy(Point{ .x = 3, .y = 0 });
                                try commands.append(.redraw);
                            },
                            else => {},
                        }
                    },
                    .release => {
                        if (mouse.button == .left) {
                            if (self.is_dragging_vertical or self.is_dragging_horizontal) {
                                self.is_dragging_vertical = false;
                                self.is_dragging_horizontal = false;
                                try commands.append(.redraw);
                                return commands;
                            }
                        }
                    },
                    .move => {
                        if (self.is_dragging_vertical) {
                            const delta_y = local_pos.y - self.drag_start_pos.y;
                            self.scrollBy(Point{ .x = 0, .y = delta_y * 2 }); // Scale for better control
                            self.drag_start_pos = local_pos;
                            try commands.append(.redraw);
                            return commands;
                        } else if (self.is_dragging_horizontal) {
                            const delta_x = local_pos.x - self.drag_start_pos.x;
                            self.scrollBy(Point{ .x = delta_x * 2, .y = 0 }); // Scale for better control
                            self.drag_start_pos = local_pos;
                            try commands.append(.redraw);
                            return commands;
                        }
                    },
                }
            }
        },
        else => {},
    }

    // Forward non-scrollbar events to child
    if (!self.is_dragging_vertical and !self.is_dragging_horizontal) {
        const child_commands = try self.child.handleEvent(ctx);
        for (child_commands.items) |cmd| {
            try commands.append(cmd);
        }
    }

    return commands;
}

test "ScrollBars creation and visibility" {
    const TestWidget = struct {
        pub fn widget(self: *const @This()) vxfw.Widget {
            return .{
                .userdata = @constCast(self),
                .drawFn = undefined,
            };
        }
    };

    const child_widget = TestWidget{};
    var scroll_bars = ScrollBars.init(child_widget.widget(), Size.init(100, 50), Style.default(), Style.default());

    // Set viewport size smaller than content
    scroll_bars.viewport_size = Size.init(20, 10);

    // Should show both scrollbars
    try std.testing.expect(scroll_bars.shouldShowVertical());
    try std.testing.expect(scroll_bars.shouldShowHorizontal());

    // Set viewport size larger than content
    scroll_bars.viewport_size = Size.init(150, 100);

    // Should hide both scrollbars (auto-hide enabled)
    try std.testing.expect(!scroll_bars.shouldShowVertical());
    try std.testing.expect(!scroll_bars.shouldShowHorizontal());
}

test "ScrollBars thumb calculation" {
    const TestWidget = struct {
        pub fn widget(self: *const @This()) vxfw.Widget {
            return .{
                .userdata = @constCast(self),
                .drawFn = undefined,
            };
        }
    };

    const child_widget = TestWidget{};
    var scroll_bars = ScrollBars.init(child_widget.widget(), Size.init(100, 50), Style.default(), Style.default());
    scroll_bars.viewport_size = Size.init(20, 10);

    const v_thumb = scroll_bars.calculateVerticalThumb();
    try std.testing.expect(v_thumb.size > 0);
    try std.testing.expect(v_thumb.size <= 10); // Should fit in viewport

    const h_thumb = scroll_bars.calculateHorizontalThumb();
    try std.testing.expect(h_thumb.size > 0);
    try std.testing.expect(h_thumb.size <= 20); // Should fit in viewport
}