//! SizedBox - Fixed size container widget
//! Forces a child widget to a specific size, with optional overflow handling

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Rect = geometry.Rect;

const SizedBox = @This();

child: ?vxfw.Widget,
fixed_size: Size,
overflow_behavior: OverflowBehavior = .clip,

pub const OverflowBehavior = enum {
    /// Clip child content that exceeds the fixed size
    clip,
    /// Show child content that exceeds the fixed size (may overflow container)
    visible,
    /// Scale child content to fit within the fixed size
    scale,
};

/// Create a SizedBox with a fixed size and child widget
pub fn init(child: ?vxfw.Widget, fixed_size: Size) SizedBox {
    return SizedBox{
        .child = child,
        .fixed_size = fixed_size,
    };
}

/// Create a SizedBox with custom overflow behavior
pub fn withOverflow(child: ?vxfw.Widget, fixed_size: Size, overflow_behavior: OverflowBehavior) SizedBox {
    return SizedBox{
        .child = child,
        .fixed_size = fixed_size,
        .overflow_behavior = overflow_behavior,
    };
}

/// Create a square SizedBox
pub fn square(child: ?vxfw.Widget, size: u16) SizedBox {
    return init(child, Size.init(size, size));
}

/// Get the widget interface for this SizedBox
pub fn widget(self: *const SizedBox) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const SizedBox = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *const SizedBox = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const SizedBox, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    // Create our surface with the fixed size
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        self.fixed_size
    );

    // Render child if present
    if (self.child) |child_widget| {
        switch (self.overflow_behavior) {
            .clip, .visible => {
                // Constrain child to our fixed size for clipping, or give unlimited for visible
                const child_constraints = switch (self.overflow_behavior) {
                    .clip => vxfw.DrawContext.SizeConstraints.init(self.fixed_size.width, self.fixed_size.height),
                    .visible => vxfw.DrawContext.SizeConstraints.unlimited(),
                    else => unreachable,
                };

                const child_ctx = ctx.withConstraints(
                    Size.init(0, 0),
                    child_constraints
                );

                const child_surface = try child_widget.draw(child_ctx);

                // Position child at origin
                const child_subsurface = vxfw.SubSurface.init(
                    Point{ .x = 0, .y = 0 },
                    child_surface
                );
                try surface.addChild(child_subsurface);
            },
            .scale => {
                // First measure child's natural size
                const measure_ctx = ctx.withConstraints(
                    Size.init(0, 0),
                    vxfw.DrawContext.SizeConstraints.unlimited()
                );
                const measured_surface = try child_widget.draw(measure_ctx);

                // Calculate scale factors
                const scale_x = if (measured_surface.size.width > 0)
                    @as(f32, @floatFromInt(self.fixed_size.width)) / @as(f32, @floatFromInt(measured_surface.size.width))
                else
                    1.0;
                const scale_y = if (measured_surface.size.height > 0)
                    @as(f32, @floatFromInt(self.fixed_size.height)) / @as(f32, @floatFromInt(measured_surface.size.height))
                else
                    1.0;

                // Use minimum scale to maintain aspect ratio
                const scale = @min(scale_x, scale_y);

                // Calculate scaled size
                const scaled_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(measured_surface.size.width)) * scale));
                const scaled_height = @as(u16, @intFromFloat(@as(f32, @floatFromInt(measured_surface.size.height)) * scale));

                // For now, just use the measured surface as-is (scaling rendering is complex)
                // In a full implementation, you'd need to implement character-level scaling
                const child_subsurface = vxfw.SubSurface.init(
                    Point{ .x = 0, .y = 0 },
                    measured_surface
                );
                try surface.addChild(child_subsurface);

                // Note: True scaling would require custom rendering logic
                _ = scaled_width;
                _ = scaled_height;
            },
        }
    }

    return surface;
}

pub fn handleEvent(self: *const SizedBox, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    // Forward events to child if present and within bounds
    if (self.child) |child_widget| {
        // Check if event is within our fixed size bounds
        const within_bounds = switch (ctx.event) {
            .mouse => |mouse| {
                const local_bounds = Rect.init(0, 0, self.fixed_size.width, self.fixed_size.height);
                local_bounds.containsPoint(mouse.position);
            },
            else => true, // Non-mouse events are always forwarded
        };

        if (within_bounds) {
            const child_commands = try child_widget.handleEvent(ctx);
            for (child_commands.items) |cmd| {
                try commands.append(cmd);
            }
        }
    }

    return commands;
}

test "SizedBox creation and sizing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const sized_box = SizedBox.init(null, Size.init(50, 30));

    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(100, 50), // Larger than our fixed size
        vxfw.DrawContext.SizeConstraints.fixed(100, 50),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try sized_box.draw(ctx);

    // Should enforce the fixed size regardless of available space
    try std.testing.expectEqual(Size.init(50, 30), surface.size);
}

test "SizedBox square creation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const sized_box = SizedBox.square(null, 25);

    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(100, 100),
        vxfw.DrawContext.SizeConstraints.fixed(100, 100),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try sized_box.draw(ctx);

    // Should create a square surface
    try std.testing.expectEqual(Size.init(25, 25), surface.size);
}