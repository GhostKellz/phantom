//! SplitView - Resizable split pane container
//! Divides space between two child widgets with an adjustable splitter

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Rect = geometry.Rect;
const Style = style.Style;

const SplitView = @This();

left_child: vxfw.Widget,
right_child: vxfw.Widget,
orientation: Orientation,
split_ratio: f32 = 0.5,
min_pane_size: u16 = 1,
splitter_style: Style,
is_dragging: bool = false,
drag_start_pos: Point = Point{ .x = 0, .y = 0 },

pub const Orientation = enum {
    horizontal, // Left/right panes
    vertical,   // Top/bottom panes
};

/// Create a horizontal SplitView (left/right panes)
pub fn horizontal(left_child: vxfw.Widget, right_child: vxfw.Widget, splitter_style: Style) SplitView {
    return SplitView{
        .left_child = left_child,
        .right_child = right_child,
        .orientation = .horizontal,
        .splitter_style = splitter_style,
    };
}

/// Create a vertical SplitView (top/bottom panes)
pub fn vertical(top_child: vxfw.Widget, bottom_child: vxfw.Widget, splitter_style: Style) SplitView {
    return SplitView{
        .left_child = top_child,
        .right_child = bottom_child,
        .orientation = .vertical,
        .splitter_style = splitter_style,
    };
}

/// Create a SplitView with default splitter styling
pub fn init(orientation: Orientation, first_child: vxfw.Widget, second_child: vxfw.Widget) SplitView {
    const splitter_style = Style.default().withFg(.bright_black).withBg(.black);
    return SplitView{
        .left_child = first_child,
        .right_child = second_child,
        .orientation = orientation,
        .splitter_style = splitter_style,
    };
}

/// Create a SplitView with custom split ratio
pub fn withRatio(orientation: Orientation, first_child: vxfw.Widget, second_child: vxfw.Widget, ratio: f32, splitter_style: Style) SplitView {
    return SplitView{
        .left_child = first_child,
        .right_child = second_child,
        .orientation = orientation,
        .split_ratio = @max(0.1, @min(0.9, ratio)),
        .splitter_style = splitter_style,
    };
}

/// Create a SplitView with minimum pane size constraint
pub fn withMinPaneSize(orientation: Orientation, first_child: vxfw.Widget, second_child: vxfw.Widget, min_size: u16, splitter_style: Style) SplitView {
    return SplitView{
        .left_child = first_child,
        .right_child = second_child,
        .orientation = orientation,
        .min_pane_size = min_size,
        .splitter_style = splitter_style,
    };
}

/// Set the split ratio (0.0 to 1.0)
pub fn setSplitRatio(self: *SplitView, ratio: f32) void {
    self.split_ratio = @max(0.0, @min(1.0, ratio));
}

/// Calculate pane sizes based on available space and split ratio
fn calculatePaneSizes(self: *const SplitView, available_size: u16) struct { first: u16, splitter: u16, second: u16 } {
    if (available_size < 3) { // Need at least 1+1+1 for two panes and splitter
        return .{ .first = 0, .splitter = 0, .second = 0 };
    }

    const splitter_size: u16 = 1;
    const content_size = available_size - splitter_size;

    var first_size = @as(u16, @intFromFloat(@as(f32, @floatFromInt(content_size)) * self.split_ratio));
    var second_size = content_size - first_size;

    // Enforce minimum pane sizes
    if (first_size < self.min_pane_size) {
        first_size = self.min_pane_size;
        second_size = if (content_size > first_size) content_size - first_size else 0;
    }
    if (second_size < self.min_pane_size) {
        second_size = self.min_pane_size;
        first_size = if (content_size > second_size) content_size - second_size else 0;
    }

    return .{ .first = first_size, .splitter = splitter_size, .second = second_size };
}

/// Get splitter bounds for hit testing
fn getSplitterBounds(self: *const SplitView, width: u16, height: u16) Rect {
    switch (self.orientation) {
        .horizontal => {
            const sizes = self.calculatePaneSizes(width);
            return Rect.init(@intCast(sizes.first), 0, sizes.splitter, height);
        },
        .vertical => {
            const sizes = self.calculatePaneSizes(height);
            return Rect.init(0, @intCast(sizes.first), width, sizes.splitter);
        },
    }
}

/// Check if a point is within the splitter area
fn isPointInSplitter(self: *const SplitView, point: Point, width: u16, height: u16) bool {
    const splitter_bounds = self.getSplitterBounds(width, height);
    return splitter_bounds.containsPoint(point);
}

/// Get the widget interface for this SplitView
pub fn widget(self: *const SplitView) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const SplitView = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *SplitView = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const SplitView, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const width = ctx.getWidth();
    const height = ctx.getHeight();

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(width, height)
    );

    switch (self.orientation) {
        .horizontal => {
            const sizes = self.calculatePaneSizes(width);

            if (sizes.first > 0) {
                // Draw left pane
                const left_ctx = ctx.withConstraints(
                    Size.init(sizes.first, height),
                    vxfw.DrawContext.SizeConstraints.init(sizes.first, height)
                );
                const left_surface = try self.left_child.draw(left_ctx);
                const left_subsurface = vxfw.SubSurface.init(Point{ .x = 0, .y = 0 }, left_surface);
                try surface.addChild(left_subsurface);
            }

            if (sizes.splitter > 0) {
                // Draw vertical splitter
                const splitter_x = sizes.first;
                var y: u16 = 0;
                while (y < height) : (y += 1) {
                    _ = surface.setCell(splitter_x, y, '│', self.splitter_style);
                }
            }

            if (sizes.second > 0) {
                // Draw right pane
                const right_x = sizes.first + sizes.splitter;
                const right_ctx = ctx.withConstraints(
                    Size.init(sizes.second, height),
                    vxfw.DrawContext.SizeConstraints.init(sizes.second, height)
                );
                const right_surface = try self.right_child.draw(right_ctx);
                const right_subsurface = vxfw.SubSurface.init(Point{ .x = @intCast(right_x), .y = 0 }, right_surface);
                try surface.addChild(right_subsurface);
            }
        },
        .vertical => {
            const sizes = self.calculatePaneSizes(height);

            if (sizes.first > 0) {
                // Draw top pane
                const top_ctx = ctx.withConstraints(
                    Size.init(width, sizes.first),
                    vxfw.DrawContext.SizeConstraints.init(width, sizes.first)
                );
                const top_surface = try self.left_child.draw(top_ctx);
                const top_subsurface = vxfw.SubSurface.init(Point{ .x = 0, .y = 0 }, top_surface);
                try surface.addChild(top_subsurface);
            }

            if (sizes.splitter > 0) {
                // Draw horizontal splitter
                const splitter_y = sizes.first;
                var x: u16 = 0;
                while (x < width) : (x += 1) {
                    _ = surface.setCell(x, splitter_y, '─', self.splitter_style);
                }
            }

            if (sizes.second > 0) {
                // Draw bottom pane
                const bottom_y = sizes.first + sizes.splitter;
                const bottom_ctx = ctx.withConstraints(
                    Size.init(width, sizes.second),
                    vxfw.DrawContext.SizeConstraints.init(width, sizes.second)
                );
                const bottom_surface = try self.right_child.draw(bottom_ctx);
                const bottom_subsurface = vxfw.SubSurface.init(Point{ .x = 0, .y = @intCast(bottom_y) }, bottom_surface);
                try surface.addChild(bottom_subsurface);
            }
        },
    }

    return surface;
}

pub fn handleEvent(self: *SplitView, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    // Handle splitter dragging
    switch (ctx.event) {
        .mouse => |mouse| {
            if (ctx.isMouseEvent()) |_| {
                const local_pos = ctx.getLocalMousePosition() orelse return commands;

                switch (mouse.action) {
                    .press => {
                        if (mouse.button == .left and
                            self.isPointInSplitter(local_pos, @intCast(ctx.bounds.width), @intCast(ctx.bounds.height))) {
                            self.is_dragging = true;
                            self.drag_start_pos = local_pos;
                            try commands.append(.redraw);
                            return commands; // Don't forward to children while dragging
                        }
                    },
                    .release => {
                        if (mouse.button == .left and self.is_dragging) {
                            self.is_dragging = false;
                            try commands.append(.redraw);
                        }
                    },
                    .move => {
                        if (self.is_dragging) {
                            // Calculate new split ratio based on mouse position
                            const new_ratio = switch (self.orientation) {
                                .horizontal => @as(f32, @floatFromInt(local_pos.x)) / @as(f32, @floatFromInt(ctx.bounds.width)),
                                .vertical => @as(f32, @floatFromInt(local_pos.y)) / @as(f32, @floatFromInt(ctx.bounds.height)),
                            };
                            self.setSplitRatio(new_ratio);
                            try commands.append(.redraw);
                            return commands; // Don't forward to children while dragging
                        }
                    },
                }
            }
        },
        else => {},
    }

    // Forward events to appropriate child panes if not dragging
    if (!self.is_dragging) {
        // Calculate which pane should receive the event based on mouse position or focus
        switch (ctx.event) {
            .mouse => |_| {
                if (ctx.isMouseEvent()) |_| {
                    const local_pos = ctx.getLocalMousePosition() orelse return commands;

                    switch (self.orientation) {
                        .horizontal => {
                            const sizes = self.calculatePaneSizes(@intCast(ctx.bounds.width));
                            if (local_pos.x < sizes.first) {
                                // Event is in left pane
                                const left_commands = try self.left_child.handleEvent(ctx);
                                for (left_commands.items) |cmd| {
                                    try commands.append(cmd);
                                }
                            } else if (local_pos.x >= sizes.first + sizes.splitter) {
                                // Event is in right pane
                                const right_commands = try self.right_child.handleEvent(ctx);
                                for (right_commands.items) |cmd| {
                                    try commands.append(cmd);
                                }
                            }
                        },
                        .vertical => {
                            const sizes = self.calculatePaneSizes(@intCast(ctx.bounds.height));
                            if (local_pos.y < sizes.first) {
                                // Event is in top pane
                                const top_commands = try self.left_child.handleEvent(ctx);
                                for (top_commands.items) |cmd| {
                                    try commands.append(cmd);
                                }
                            } else if (local_pos.y >= sizes.first + sizes.splitter) {
                                // Event is in bottom pane
                                const bottom_commands = try self.right_child.handleEvent(ctx);
                                for (bottom_commands.items) |cmd| {
                                    try commands.append(cmd);
                                }
                            }
                        },
                    }
                }
            },
            else => {
                // Non-mouse events go to both children
                const left_commands = try self.left_child.handleEvent(ctx);
                for (left_commands.items) |cmd| {
                    try commands.append(cmd);
                }

                const right_commands = try self.right_child.handleEvent(ctx);
                for (right_commands.items) |cmd| {
                    try commands.append(cmd);
                }
            },
        }
    }

    return commands;
}

test "SplitView creation and pane size calculation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Create test widgets (simplified for testing)
    const TestWidget = struct {
        name: []const u8,

        const Self = @This();

        pub fn widget(self: *const Self) vxfw.Widget {
            return .{
                .userdata = @constCast(self),
                .drawFn = drawFn,
            };
        }

        fn drawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
            _ = ptr;
            return vxfw.Surface.initArena(ctx.arena, vxfw.Widget{
                .userdata = undefined,
                .drawFn = undefined,
            }, Size.init(1, 1));
        }
    };

    const left_widget = TestWidget{ .name = "left" };
    const right_widget = TestWidget{ .name = "right" };

    var split_view = SplitView.horizontal(left_widget.widget(), right_widget.widget(), Style.default());

    // Test pane size calculation
    const sizes = split_view.calculatePaneSizes(20);
    try std.testing.expectEqual(@as(u16, 9), sizes.first);   // ~50% of 19 (20-1 for splitter)
    try std.testing.expectEqual(@as(u16, 1), sizes.splitter);
    try std.testing.expectEqual(@as(u16, 10), sizes.second);

    // Test split ratio change
    split_view.setSplitRatio(0.3);
    const new_sizes = split_view.calculatePaneSizes(20);
    try std.testing.expectEqual(@as(u16, 5), new_sizes.first);  // ~30% of 19
    try std.testing.expectEqual(@as(u16, 14), new_sizes.second);
}

test "SplitView splitter bounds calculation" {
    const TestWidget = struct {
        pub fn widget(self: *const @This()) vxfw.Widget {
            return .{
                .userdata = @constCast(self),
                .drawFn = undefined,
            };
        }
    };

    const widget1 = TestWidget{};
    const widget2 = TestWidget{};

    const h_split = SplitView.horizontal(widget1.widget(), widget2.widget(), Style.default());
    const h_bounds = h_split.getSplitterBounds(20, 10);

    // Horizontal splitter should be vertical line
    try std.testing.expectEqual(@as(u16, 1), h_bounds.width);
    try std.testing.expectEqual(@as(u16, 10), h_bounds.height);

    const v_split = SplitView.vertical(widget1.widget(), widget2.widget(), Style.default());
    const v_bounds = v_split.getSplitterBounds(20, 10);

    // Vertical splitter should be horizontal line
    try std.testing.expectEqual(@as(u16, 20), v_bounds.width);
    try std.testing.expectEqual(@as(u16, 1), v_bounds.height);
}