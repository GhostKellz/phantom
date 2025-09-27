//! View - Base view component for custom widgets
//! Provides a simple container with optional background styling

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Style = style.Style;

const View = @This();

child: ?vxfw.Widget = null,
background_style: Style,
min_size: Size = Size.init(1, 1),

/// Create a View with optional child widget
pub fn init(child: ?vxfw.Widget, background_style: Style) View {
    return View{
        .child = child,
        .background_style = background_style,
    };
}

/// Create a simple View with default background
pub fn simple(child: ?vxfw.Widget) View {
    return init(child, Style.default());
}

/// Create a View with minimum size constraints
pub fn withMinSize(child: ?vxfw.Widget, background_style: Style, min_size: Size) View {
    return View{
        .child = child,
        .background_style = background_style,
        .min_size = min_size,
    };
}

/// Get the widget interface for this View
pub fn widget(self: *const View) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const View = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *const View = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const View, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    // Ensure we meet minimum size requirements
    const actual_width = @max(ctx.getWidth(), self.min_size.width);
    const actual_height = @max(ctx.getHeight(), self.min_size.height);

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(actual_width, actual_height)
    );

    // Fill background if we have a background style
    if (self.background_style.bg != null or
        self.background_style.fg != null or
        !std.meta.eql(self.background_style.attributes, style.Attributes.none())) {
        surface.fillRect(
            geometry.Rect.init(0, 0, actual_width, actual_height),
            ' ',
            self.background_style
        );
    }

    // Render child if present
    if (self.child) |child_widget| {
        const child_ctx = ctx.withConstraints(
            Size.init(0, 0),
            vxfw.DrawContext.SizeConstraints.init(actual_width, actual_height)
        );

        const child_surface = try child_widget.draw(child_ctx);

        // Center child within our bounds
        const child_x = @divTrunc(actual_width - child_surface.size.width, 2);
        const child_y = @divTrunc(actual_height - child_surface.size.height, 2);

        const child_subsurface = vxfw.SubSurface.init(
            geometry.Point{ .x = @intCast(child_x), .y = @intCast(child_y) },
            child_surface
        );
        try surface.addChild(child_subsurface);
    }

    return surface;
}

pub fn handleEvent(self: *const View, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    // Forward events to child if present
    if (self.child) |child_widget| {
        const child_commands = try child_widget.handleEvent(ctx);
        for (child_commands.items) |cmd| {
            try commands.append(cmd);
        }
    }

    return commands;
}

test "View creation and basic functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const view = View.simple(null);

    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(20, 10),
        vxfw.DrawContext.SizeConstraints.fixed(20, 10),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try view.draw(ctx);

    // Test basic surface creation
    try std.testing.expectEqual(Size.init(20, 10), surface.size);
}

test "View with minimum size" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const view = View.withMinSize(null, Style.default(), Size.init(50, 25));

    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(10, 5), // Smaller than minimum
        vxfw.DrawContext.SizeConstraints.fixed(10, 5),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try view.draw(ctx);

    // Should enforce minimum size
    try std.testing.expectEqual(Size.init(50, 25), surface.size);
}