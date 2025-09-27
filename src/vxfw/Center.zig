//! Center - Centers a child widget within available space

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;

const Center = @This();

child: vxfw.Widget,

pub fn init(child: vxfw.Widget) Center {
    return Center{ .child = child };
}

pub fn widget(self: *const Center) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const Center = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *const Center = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const Center, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    // Draw child with unlimited constraints to get its natural size
    const child_ctx = ctx.withConstraints(
        Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.unlimited()
    );
    const child_surface = try self.child.draw(child_ctx);

    // Calculate centering offset
    const available_width = ctx.getWidth();
    const available_height = ctx.getHeight();

    const offset_x = if (available_width > child_surface.size.width)
        (available_width - child_surface.size.width) / 2
    else
        0;

    const offset_y = if (available_height > child_surface.size.height)
        (available_height - child_surface.size.height) / 2
    else
        0;

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(available_width, available_height)
    );

    // Add centered child
    const subsurface = vxfw.SubSurface.init(
        Point{ .x = @intCast(offset_x), .y = @intCast(offset_y) },
        child_surface
    );
    try surface.addChild(subsurface);

    return surface;
}

pub fn handleEvent(self: *const Center, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    // Forward events to child
    return self.child.handleEvent(ctx);
}

test "Center widget" {
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

    const child_widget = TestWidget{ .size = Size.init(10, 5) };
    const center_widget = Center.init(child_widget.widget());

    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(30, 15),
        vxfw.DrawContext.SizeConstraints.fixed(30, 15),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try center_widget.draw(ctx);

    // Test that surface has the right size and contains a child
    try std.testing.expectEqual(Size.init(30, 15), surface.size);
    try std.testing.expect(surface.children.items.len == 1);

    // Test that child is centered
    const child_subsurface = surface.children.items[0];
    try std.testing.expectEqual(@as(i16, 10), child_subsurface.origin.x); // (30-10)/2
    try std.testing.expectEqual(@as(i16, 5), child_subsurface.origin.y);  // (15-5)/2
}