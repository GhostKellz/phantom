//! Padding - Adds padding around a child widget

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;

const Padding = @This();

child: vxfw.Widget,
padding: PaddingInsets,

pub const PaddingInsets = struct {
    top: u16 = 0,
    right: u16 = 0,
    bottom: u16 = 0,
    left: u16 = 0,

    pub fn all(value: u16) PaddingInsets {
        return .{ .top = value, .right = value, .bottom = value, .left = value };
    }

    pub fn symmetric(horizontal: u16, vertical: u16) PaddingInsets {
        return .{ .top = vertical, .right = horizontal, .bottom = vertical, .left = horizontal };
    }

    pub fn only(top: u16, right: u16, bottom: u16, left: u16) PaddingInsets {
        return .{ .top = top, .right = right, .bottom = bottom, .left = left };
    }

    pub fn totalWidth(self: PaddingInsets) u16 {
        return self.left + self.right;
    }

    pub fn totalHeight(self: PaddingInsets) u16 {
        return self.top + self.bottom;
    }
};

pub fn init(child: vxfw.Widget, padding: PaddingInsets) Padding {
    return Padding{ .child = child, .padding = padding };
}

pub fn widget(self: *const Padding) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const Padding = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *const Padding = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const Padding, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    // Calculate available space for child after padding
    const padding_width = self.padding.totalWidth();
    const padding_height = self.padding.totalHeight();

    const child_max_width = if (ctx.max.width) |max_w|
        if (max_w > padding_width) max_w - padding_width else 0
    else
        null;

    const child_max_height = if (ctx.max.height) |max_h|
        if (max_h > padding_height) max_h - padding_height else 0
    else
        null;

    // Create child context
    const child_ctx = ctx.withConstraints(
        Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.init(child_max_width, child_max_height)
    );

    // Draw child
    const child_surface = try self.child.draw(child_ctx);

    // Calculate total size including padding
    const total_width = child_surface.size.width + padding_width;
    const total_height = child_surface.size.height + padding_height;

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(total_width, total_height)
    );

    // Add child at padded position
    const subsurface = vxfw.SubSurface.init(
        Point{ .x = @intCast(self.padding.left), .y = @intCast(self.padding.top) },
        child_surface
    );
    try surface.addChild(subsurface);

    return surface;
}

pub fn handleEvent(self: *const Padding, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    // Create adjusted context for child (accounting for padding offset)
    const child_bounds = geometry.Rect.init(
        ctx.bounds.x + self.padding.left,
        ctx.bounds.y + self.padding.top,
        ctx.bounds.width -| self.padding.totalWidth(),
        ctx.bounds.height -| self.padding.totalHeight()
    );

    const child_ctx = ctx.createChild(child_bounds);
    return self.child.handleEvent(child_ctx);
}

test "Padding widget" {
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
    const padding_widget = Padding.init(child_widget.widget(), PaddingInsets.all(2));

    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.unlimited(),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try padding_widget.draw(ctx);

    // Test total size includes padding
    try std.testing.expectEqual(Size.init(14, 9), surface.size); // 10+4, 5+4
    try std.testing.expect(surface.children.items.len == 1);

    // Test child positioning
    const child_subsurface = surface.children.items[0];
    try std.testing.expectEqual(@as(i16, 2), child_subsurface.origin.x);
    try std.testing.expectEqual(@as(i16, 2), child_subsurface.origin.y);
}

test "Padding insets calculations" {
    const all_padding = PaddingInsets.all(5);
    try std.testing.expectEqual(@as(u16, 10), all_padding.totalWidth());
    try std.testing.expectEqual(@as(u16, 10), all_padding.totalHeight());

    const sym_padding = PaddingInsets.symmetric(3, 4);
    try std.testing.expectEqual(@as(u16, 6), sym_padding.totalWidth());
    try std.testing.expectEqual(@as(u16, 8), sym_padding.totalHeight());

    const custom_padding = PaddingInsets.only(1, 2, 3, 4);
    try std.testing.expectEqual(@as(u16, 6), custom_padding.totalWidth()); // 2+4
    try std.testing.expectEqual(@as(u16, 4), custom_padding.totalHeight()); // 1+3
}