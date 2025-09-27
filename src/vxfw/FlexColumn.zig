//! FlexColumn - Vertical flexible layout container
//! Arranges child widgets in a column with flexible sizing

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;

const FlexColumn = @This();

children: []const vxfw.FlexItem,

/// Create a FlexColumn widget with the given children
pub fn init(children: []const vxfw.FlexItem) FlexColumn {
    return FlexColumn{ .children = children };
}

/// Get the widget interface for this FlexColumn
pub fn widget(self: *const FlexColumn) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const FlexColumn = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *const FlexColumn = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const FlexColumn, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    // Require specific width constraints for proper layout
    std.debug.assert(ctx.max.width != null);
    std.debug.assert(ctx.max.height != null);

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
        vxfw.DrawContext.SizeConstraints.init(ctx.max.width, null)
    );

    // First pass: measure fixed-size children
    var first_pass_height: u16 = 0;
    var total_flex: u16 = 0;
    for (self.children, 0..) |child, i| {
        if (child.flex == 0) {
            const surf = try child.widget.draw(layout_ctx);
            first_pass_height += surf.size.height;
            size_list[i] = surf.size.height;
        }
        total_flex += child.flex;
    }

    // Calculate remaining space for flexible children
    const remaining_space = ctx.max.height.? -| first_pass_height;

    // Create our surface and children list
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(ctx.max.width.?, ctx.max.height.?)
    );

    // Second pass: draw children with final sizes
    var y_offset: u16 = 0;
    var max_width: u16 = 0;

    for (self.children, 0..) |child, i| {
        const child_height = if (child.flex == 0)
            size_list[i]
        else if (i == self.children.len - 1)
            // Last flexible child gets remainder
            ctx.max.height.? -| y_offset
        else
            // Distribute remaining space proportionally
            if (total_flex > 0) (remaining_space * child.flex) / total_flex else 0;

        // Create context for this child
        const child_ctx = ctx.withConstraints(
            Size.init(0, child_height),
            vxfw.DrawContext.SizeConstraints.init(ctx.max.width.?, child_height)
        );

        const child_surface = try child.widget.draw(child_ctx);
        max_width = @max(max_width, child_surface.size.width);

        // Add child as a subsurface
        const subsurface = vxfw.SubSurface.init(
            Point{ .x = 0, .y = @intCast(y_offset) },
            child_surface
        );
        try surface.addChild(subsurface);

        y_offset += child_height;
    }

    // Update surface size to actual content
    surface.size = Size.init(max_width, y_offset);
    return surface;
}

pub fn handleEvent(self: *const FlexColumn, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
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

test "FlexColumn basic layout" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Create test widgets (simplified for testing)
    const TestWidget = struct {
        height: u16,

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
                Size.init(1, self_ptr.height)
            );
        }
    };

    const widget1 = TestWidget{ .height = 5 };
    const widget2 = TestWidget{ .height = 8 };

    const children = [_]vxfw.FlexItem{
        .{ .widget = widget1.widget(), .flex = 0 }, // Fixed height
        .{ .widget = widget2.widget(), .flex = 1 }, // Flexible
    };

    const flex_column = FlexColumn.init(&children);

    // Create draw context
    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.init(20, 30),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try flex_column.draw(ctx);

    // Test that surface was created successfully
    try std.testing.expect(surface.size.width <= 20);
    try std.testing.expect(surface.size.height <= 30);
    try std.testing.expect(surface.children.items.len == 2);
}