//! ScrollView - Scrollable container for content larger than the viewport
//! Provides vertical and horizontal scrolling with optional scrollbars

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Style = style.Style;

const ScrollView = @This();

child: vxfw.Widget,
scroll_x: u16 = 0,
scroll_y: u16 = 0,
show_scrollbars: bool = true,
scrollbar_style: Style,

/// Create a ScrollView with a child widget
pub fn init(child: vxfw.Widget) ScrollView {
    return ScrollView{
        .child = child,
        .scrollbar_style = Style.default().withFg(.bright_black),
    };
}

/// Create a ScrollView with custom scrollbar styling
pub fn withScrollbarStyle(child: vxfw.Widget, scrollbar_style: Style) ScrollView {
    return ScrollView{
        .child = child,
        .scrollbar_style = scrollbar_style,
        .show_scrollbars = true,
    };
}

/// Create a ScrollView without visible scrollbars
pub fn withoutScrollbars(child: vxfw.Widget) ScrollView {
    return ScrollView{
        .child = child,
        .show_scrollbars = false,
        .scrollbar_style = Style.default(),
    };
}

/// Get the widget interface for this ScrollView
pub fn widget(self: *const ScrollView) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const ScrollView = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *ScrollView = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const ScrollView, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const viewport_width = ctx.getWidth();
    const viewport_height = ctx.getHeight();

    // Reserve space for scrollbars if they're visible
    const content_width = if (self.show_scrollbars and viewport_width > 0)
        viewport_width - 1
    else
        viewport_width;

    const content_height = if (self.show_scrollbars and viewport_height > 0)
        viewport_height - 1
    else
        viewport_height;

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(viewport_width, viewport_height)
    );

    // Draw child content with unlimited constraints to get its natural size
    const child_ctx = ctx.withConstraints(
        Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.unlimited()
    );
    const child_surface = try self.child.draw(child_ctx);

    // Clamp scroll to the child's extent so the visible window never runs past
    // the content (the stored scroll offsets are advanced unbounded by events).
    const max_scroll_x = if (child_surface.size.width > content_width)
        child_surface.size.width - content_width
    else
        0;
    const max_scroll_y = if (child_surface.size.height > content_height)
        child_surface.size.height - content_height
    else
        0;
    const eff_scroll_x = @min(self.scroll_x, max_scroll_x);
    const eff_scroll_y = @min(self.scroll_y, max_scroll_y);

    // Create clipped child surface: the visible content window at the current
    // scroll offset, sized to the content area (excludes scrollbar gutter).
    const clipped_child = try self.clipChildSurface(
        ctx.arena,
        child_surface,
        Size.init(content_width, content_height),
        eff_scroll_x,
        eff_scroll_y,
    );

    // Add clipped child to our surface
    const child_subsurface = vxfw.SubSurface.init(Point{ .x = 0, .y = 0 }, clipped_child);
    try surface.addChild(child_subsurface);

    // Draw scrollbars if enabled
    if (self.show_scrollbars) {
        try self.drawScrollbars(&surface, content_width, content_height, child_surface.size, eff_scroll_x, eff_scroll_y);
    }

    return surface;
}

pub fn handleEvent(self: *ScrollView, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    // Handle scrolling events
    switch (ctx.event) {
        .mouse => |mouse| {
            if (ctx.isMouseEvent() != null) {
                switch (mouse.button) {
                    .wheel_up => {
                        if (self.scroll_y >= 3) {
                            self.scroll_y -= 3;
                        } else {
                            self.scroll_y = 0;
                        }
                        try commands.append(.redraw);
                    },
                    .wheel_down => {
                        self.scroll_y += 3;
                        try commands.append(.redraw);
                    },
                    .wheel_left => {
                        if (self.scroll_x >= 3) {
                            self.scroll_x -= 3;
                        } else {
                            self.scroll_x = 0;
                        }
                        try commands.append(.redraw);
                    },
                    .wheel_right => {
                        self.scroll_x += 3;
                        try commands.append(.redraw);
                    },
                    else => {},
                }
            }
        },
        .key_press => |key| {
            if (ctx.has_focus) {
                switch (key.key) {
                    .up => {
                        if (self.scroll_y > 0) {
                            self.scroll_y -= 1;
                        }
                        try commands.append(.redraw);
                    },
                    .down => {
                        self.scroll_y += 1;
                        try commands.append(.redraw);
                    },
                    .left => {
                        if (self.scroll_x > 0) {
                            self.scroll_x -= 1;
                        }
                        try commands.append(.redraw);
                    },
                    .right => {
                        self.scroll_x += 1;
                        try commands.append(.redraw);
                    },
                    .page_up => {
                        if (self.scroll_y >= 10) {
                            self.scroll_y -= 10;
                        } else {
                            self.scroll_y = 0;
                        }
                        try commands.append(.redraw);
                    },
                    .page_down => {
                        self.scroll_y += 10;
                        try commands.append(.redraw);
                    },
                    .home => {
                        self.scroll_y = 0;
                        self.scroll_x = 0;
                        try commands.append(.redraw);
                    },
                    else => {},
                }
            }
        },
        else => {},
    }

    // Forward events to child widget (with adjusted coordinates)
    const child_commands = try self.child.handleEvent(ctx);
    for (child_commands.items) |cmd| {
        try commands.append(cmd);
    }

    return commands;
}

/// Create a clipped version of the child surface based on scroll position.
///
/// Produces a fresh surface of `view_size` whose top-left corresponds to
/// `(scroll_x, scroll_y)` in the child. Cells outside the child's bounds are
/// left blank, so scrolling near the bottom/right edge simply shows empty space.
fn clipChildSurface(
    self: *const ScrollView,
    allocator: Allocator,
    child_surface: vxfw.Surface,
    view_size: Size,
    scroll_x: u16,
    scroll_y: u16,
) !vxfw.Surface {
    var clipped = try vxfw.Surface.initArena(allocator, self.widget(), view_size);

    // getCell requires a mutable receiver but does not mutate; use a local copy
    // of the (by-value) child surface so we can read its cells.
    var src = child_surface;

    var y: u16 = 0;
    while (y < view_size.height) : (y += 1) {
        var x: u16 = 0;
        while (x < view_size.width) : (x += 1) {
            const src_x = @as(u32, x) + scroll_x;
            const src_y = @as(u32, y) + scroll_y;
            if (src_x >= src.size.width or src_y >= src.size.height) continue;
            if (src.getCell(@intCast(src_x), @intCast(src_y))) |cell| {
                _ = clipped.setCell(x, y, cell.char, cell.style);
            }
        }
    }

    return clipped;
}

/// Draw vertical and horizontal scrollbars
fn drawScrollbars(
    self: *const ScrollView,
    surface: *vxfw.Surface,
    content_width: u16,
    content_height: u16,
    child_size: Size,
    scroll_x: u16,
    scroll_y: u16,
) !void {
    // Draw vertical scrollbar
    if (child_size.height > content_height) {
        const scrollbar_height = content_height;
        const thumb_size = @max(1, (content_height * content_height) / child_size.height);
        const thumb_position = (scroll_y * (scrollbar_height - thumb_size)) /
                               @max(1, child_size.height - content_height);

        // Draw scrollbar track
        var y: u16 = 0;
        while (y < scrollbar_height) : (y += 1) {
            _ = surface.setCell(content_width, y, '│', self.scrollbar_style);
        }

        // Draw scrollbar thumb
        var thumb_y: u16 = 0;
        while (thumb_y < thumb_size) : (thumb_y += 1) {
            _ = surface.setCell(content_width, thumb_position + thumb_y, '█', self.scrollbar_style);
        }
    }

    // Draw horizontal scrollbar
    if (child_size.width > content_width) {
        const scrollbar_width = content_width;
        const thumb_size = @max(1, (content_width * content_width) / child_size.width);
        const thumb_position = (scroll_x * (scrollbar_width - thumb_size)) /
                               @max(1, child_size.width - content_width);

        // Draw scrollbar track
        var x: u16 = 0;
        while (x < scrollbar_width) : (x += 1) {
            _ = surface.setCell(x, content_height, '─', self.scrollbar_style);
        }

        // Draw scrollbar thumb
        var thumb_x: u16 = 0;
        while (thumb_x < thumb_size) : (thumb_x += 1) {
            _ = surface.setCell(thumb_position + thumb_x, content_height, '█', self.scrollbar_style);
        }
    }

    // Draw corner if both scrollbars are present
    if (child_size.height > content_height and child_size.width > content_width) {
        _ = surface.setCell(content_width, content_height, '┼', self.scrollbar_style);
    }
}

/// Scroll to make the given point visible
pub fn scrollTo(self: *ScrollView, point: Point, viewport_size: Size) void {
    // Scroll horizontally if needed
    if (point.x < self.scroll_x) {
        self.scroll_x = @intCast(point.x);
    } else if (point.x >= self.scroll_x + viewport_size.width) {
        self.scroll_x = @intCast(@as(i32, point.x) - @as(i32, viewport_size.width) + 1);
    }

    // Scroll vertically if needed
    if (point.y < self.scroll_y) {
        self.scroll_y = @intCast(point.y);
    } else if (point.y >= self.scroll_y + viewport_size.height) {
        self.scroll_y = @intCast(@as(i32, point.y) - @as(i32, viewport_size.height) + 1);
    }
}

/// Get the current scroll position
pub fn getScrollPosition(self: *const ScrollView) Point {
    return Point{ .x = @intCast(self.scroll_x), .y = @intCast(self.scroll_y) };
}

/// Set the scroll position
pub fn setScrollPosition(self: *ScrollView, position: Point) void {
    self.scroll_x = @intCast(@max(0, position.x));
    self.scroll_y = @intCast(@max(0, position.y));
}

test "ScrollView creation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const TestWidget = struct {
        size: Size,

        const Self = @This();

        pub fn widget(self: *const Self) vxfw.Widget {
            return .{
                .userdata = @constCast(self),
                .drawFn = drawFn,
            };
        }

        fn drawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
            const self_ptr: *const Self = @ptrCast(@alignCast(ptr));
            return vxfw.Surface.initArena(ctx.arena, self_ptr.widget(), self_ptr.size);
        }
    };

    const child_widget = TestWidget{ .size = Size.init(50, 30) };
    const scroll_view = ScrollView.init(child_widget.widget());

    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(20, 15),
        vxfw.DrawContext.SizeConstraints.fixed(20, 15),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try scroll_view.draw(ctx);

    // Test basic surface creation
    try std.testing.expectEqual(Size.init(20, 15), surface.size);
    try std.testing.expect(surface.children.items.len == 1);
}

test "ScrollView clips child content to the scroll offset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Child fills each row with a distinct letter: row y -> ('A' + y % 26).
    const FillWidget = struct {
        size: Size,

        const Self = @This();

        pub fn widget(self: *const Self) vxfw.Widget {
            return .{ .userdata = @constCast(self), .drawFn = drawFn };
        }

        fn drawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
            const self_ptr: *const Self = @ptrCast(@alignCast(ptr));
            var s = try vxfw.Surface.initArena(ctx.arena, self_ptr.widget(), self_ptr.size);
            var y: u16 = 0;
            while (y < self_ptr.size.height) : (y += 1) {
                const ch: u21 = @intCast(@as(u32, 'A') + (@as(u32, y) % 26));
                var x: u16 = 0;
                while (x < self_ptr.size.width) : (x += 1) {
                    _ = s.setCell(x, y, ch, Style.default());
                }
            }
            return s;
        }
    };

    const child = FillWidget{ .size = Size.init(50, 30) };
    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(20, 15),
        vxfw.DrawContext.SizeConstraints.fixed(20, 15),
        vxfw.DrawContext.CellSize.default(),
    );

    // Scroll down by 5: the clipped top-left row must come from child row 5.
    {
        var sv = ScrollView.init(child.widget());
        sv.scroll_y = 5;
        const surface = try sv.draw(ctx);
        try std.testing.expectEqual(@as(usize, 1), surface.children.items.len);
        var clipped = surface.children.items[0].surface;
        // Content area excludes the 1-column/row scrollbar gutter.
        try std.testing.expectEqual(Size.init(19, 14), clipped.size);
        try std.testing.expectEqual(@as(u21, 'A' + 5), clipped.getCell(0, 0).?.char);
        try std.testing.expectEqual(@as(u21, 'A' + 6), clipped.getCell(0, 1).?.char);
    }

    // Over-scroll is clamped to max (child_h 30 - content_h 14 = 16).
    {
        var sv = ScrollView.init(child.widget());
        sv.scroll_y = 1000;
        const surface = try sv.draw(ctx);
        var clipped = surface.children.items[0].surface;
        try std.testing.expectEqual(@as(u21, 'A' + 16), clipped.getCell(0, 0).?.char);
    }
}

test "ScrollView position management" {
    var scroll_view = ScrollView.init(undefined);

    // Test scroll position setting and getting
    scroll_view.setScrollPosition(Point{ .x = 10, .y = 5 });
    const pos = scroll_view.getScrollPosition();
    try std.testing.expectEqual(@as(i16, 10), pos.x);
    try std.testing.expectEqual(@as(i16, 5), pos.y);

    // Test scrollTo functionality
    scroll_view.scrollTo(Point{ .x = 25, .y = 20 }, Size.init(10, 8));
    const new_pos = scroll_view.getScrollPosition();

    // Should scroll to make point visible
    try std.testing.expect(new_pos.x <= 25);
    try std.testing.expect(new_pos.y <= 20);
}