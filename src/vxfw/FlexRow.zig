//! FlexRow - Horizontal flexible layout container
//! Arranges child widgets in a row with flexible sizing

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;

const FlexRow = @This();

children: []const vxfw.FlexItem,

/// Create a FlexRow widget with the given children
pub fn init(children: []const vxfw.FlexItem) FlexRow {
    return FlexRow{ .children = children };
}

/// Get the widget interface for this FlexRow
pub fn widget(self: *const FlexRow) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const FlexRow = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *const FlexRow = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const FlexRow, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    // Require specific height constraints for proper layout
    std.debug.assert(ctx.max.height != null);
    std.debug.assert(ctx.max.width != null);

    if (self.children.len == 0) {
        return vxfw.Surface.initArena(ctx.arena, self.widget(), ctx.min);
    }

    // Store the inherent size of each widget
    const size_list = try ctx.arena.alloc(u16, self.children.len);

    // Create layout context for measuring widgets
    var layout_arena = std.heap.ArenaAllocator.init(ctx.arena);
    defer layout_arena.deinit();

    const layout_ctx = ctx.withConstraints(
        Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.init(null, ctx.max.height)
    );

    // First pass: measure fixed-size children
    var first_pass_width: u16 = 0;
    var total_flex: u16 = 0;
    for (self.children, 0..) |child, i| {
        if (child.flex == 0) {
            const surf = try child.widget.draw(layout_ctx);
            first_pass_width += surf.size.width;
            size_list[i] = surf.size.width;
        }
        total_flex += child.flex;
    }

    // Calculate remaining space for flexible children
    const remaining_space = ctx.max.width.? -| first_pass_width;

    // Create our surface and children list
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(ctx.max.width.?, ctx.max.height.?)
    );

    // Second pass: draw children with final sizes
    var x_offset: u16 = 0;
    var max_height: u16 = 0;

    for (self.children, 0..) |child, i| {
        const child_width = if (child.flex == 0)
            size_list[i]
        else if (i == self.children.len - 1)
            // Last flexible child gets remainder
            ctx.max.width.? -| x_offset
        else
            // Distribute remaining space proportionally
            if (total_flex > 0) (remaining_space * child.flex) / total_flex else 0;

        // Create context for this child
        const child_ctx = ctx.withConstraints(
            Size.init(child_width, 0),
            vxfw.DrawContext.SizeConstraints.init(child_width, ctx.max.height.?)
        );

        const child_surface = try child.widget.draw(child_ctx);
        max_height = @max(max_height, child_surface.size.height);

        // Add child as a subsurface
        const subsurface = vxfw.SubSurface.init(
            Point{ .x = @intCast(x_offset), .y = 0 },
            child_surface
        );
        try surface.addChild(subsurface);

        x_offset += child_width;
    }

    // Update surface size to actual content
    surface.size = Size.init(x_offset, max_height);
    return surface;
}

pub fn handleEvent(self: *const FlexRow, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    // Forward events to child widgets based on their positions
    // This is a simplified implementation - a full version would track child bounds
    for (self.children) |child| {
        const child_commands = try child.widget.handleEvent(ctx);

        // Append child commands to our list
        for (child_commands.items) |cmd| {
            try commands.append(cmd);
        }
    }

    return commands;
}

test "FlexRow basic layout" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Create test widgets (simplified for testing)
    const TestWidget = struct {
        width: u16,

        const Self = @This();

        pub fn widget(self: *const Self) vxfw.Widget {
            return .{
                .userdata = @constCast(self),
                .drawFn = drawFn,
            };
        }

        fn drawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
            const self_ptr: *const Self = @ptrCast(@alignCast(ptr));
            return vxfw.Surface.initArena(
                ctx.arena,
                self_ptr.widget(),
                Size.init(self_ptr.width, 1)
            );
        }
    };

    const widget1 = TestWidget{ .width = 10 };
    const widget2 = TestWidget{ .width = 15 };

    const children = [_]vxfw.FlexItem{
        .{ .widget = widget1.widget(), .flex = 0 }, // Fixed width
        .{ .widget = widget2.widget(), .flex = 1 }, // Flexible
    };

    const flex_row = FlexRow.init(&children);

    // Create draw context
    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.init(50, 10),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try flex_row.draw(ctx);

    // Test that surface was created successfully
    try std.testing.expect(surface.size.width <= 50);
    try std.testing.expect(surface.size.height <= 10);
    try std.testing.expect(surface.children.items.len == 2);
}