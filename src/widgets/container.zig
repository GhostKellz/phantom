//! Container widget for managing child widgets with flexible layout
//!
//! The Container widget provides a generic way to group and layout child widgets.
//! It supports different layout modes and automatic child positioning.
const std = @import("std");
const ArrayList = std.array_list.Managed;
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Event = @import("../event.zig").Event;
const Rect = @import("../geometry.zig").Rect;
const Style = @import("../style.zig").Style;

/// Layout direction for container children
pub const LayoutDirection = enum {
    /// Children laid out vertically (top to bottom)
    vertical,
    /// Children laid out horizontally (left to right)
    horizontal,
    /// Children manually positioned (free-form)
    manual,
};

/// Child widget with layout info
pub const ContainerChild = struct {
    widget: *Widget,
    /// For manual layout mode
    area: ?Rect = null,
    /// For automatic layout - flex grow factor
    flex: u16 = 1,
    /// Visible flag
    visible: bool = true,
};

/// Container widget for child management
pub const Container = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    children: ArrayList(ContainerChild),
    layout_direction: LayoutDirection,
    /// Gap between children (in automatic layout)
    gap: u16 = 0,
    /// Padding around children
    padding: u16 = 0,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
        .resize = resize,
    };

    pub fn init(allocator: std.mem.Allocator, direction: LayoutDirection) !*Container {
        const container = try allocator.create(Container);
        container.* = Container{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .children = ArrayList(ContainerChild).init(allocator),
            .layout_direction = direction,
        };
        return container;
    }

    /// Add a child widget (automatic layout)
    pub fn addChild(self: *Container, child: *Widget) !void {
        try self.children.append(ContainerChild{
            .widget = child,
        });
    }

    /// Add a child widget with flex factor
    pub fn addChildWithFlex(self: *Container, child: *Widget, flex: u16) !void {
        try self.children.append(ContainerChild{
            .widget = child,
            .flex = flex,
        });
    }

    /// Add a child widget at manual position (manual layout mode only)
    pub fn addChildAt(self: *Container, child: *Widget, area: Rect) !void {
        try self.children.append(ContainerChild{
            .widget = child,
            .area = area,
        });
    }

    /// Remove a child widget
    pub fn removeChild(self: *Container, child: *Widget) void {
        var i: usize = 0;
        while (i < self.children.items.len) {
            if (self.children.items[i].widget == child) {
                _ = self.children.swapRemove(i);
                return;
            }
            i += 1;
        }
    }

    /// Clear all children
    pub fn clear(self: *Container) void {
        self.children.clearRetainingCapacity();
    }

    /// Set layout direction
    pub fn setDirection(self: *Container, direction: LayoutDirection) void {
        self.layout_direction = direction;
    }

    /// Set gap between children
    pub fn setGap(self: *Container, gap: u16) void {
        self.gap = gap;
    }

    /// Set padding around children
    pub fn setPadding(self: *Container, padding: u16) void {
        self.padding = padding;
    }

    /// Calculate layout for children
    fn calculateLayout(self: *Container, area: Rect) void {
        if (self.layout_direction == .manual) return; // Manual layout uses predefined areas

        const visible_children = blk: {
            var count: usize = 0;
            for (self.children.items) |child| {
                if (child.visible) count += 1;
            }
            break :blk count;
        };

        if (visible_children == 0) return;

        // Calculate available space after padding and gaps
        const content_area = Rect{
            .x = area.x + self.padding,
            .y = area.y + self.padding,
            .width = if (area.width > self.padding * 2) area.width - self.padding * 2 else 0,
            .height = if (area.height > self.padding * 2) area.height - self.padding * 2 else 0,
        };

        const total_gap = if (visible_children > 1) self.gap * @as(u16, @intCast(visible_children - 1)) else 0;

        // Calculate total flex
        var total_flex: u32 = 0;
        for (self.children.items) |child| {
            if (child.visible) total_flex += child.flex;
        }

        switch (self.layout_direction) {
            .vertical => {
                const available_height = if (content_area.height > total_gap) content_area.height - total_gap else 0;
                var current_y = content_area.y;

                for (self.children.items) |*child| {
                    if (!child.visible) continue;

                    const child_height = if (total_flex > 0)
                        @as(u16, @intCast((available_height * child.flex) / total_flex))
                    else
                        available_height / @as(u16, @intCast(visible_children));

                    child.area = Rect{
                        .x = content_area.x,
                        .y = current_y,
                        .width = content_area.width,
                        .height = child_height,
                    };

                    current_y += child_height + self.gap;
                }
            },
            .horizontal => {
                const available_width = if (content_area.width > total_gap) content_area.width - total_gap else 0;
                var current_x = content_area.x;

                for (self.children.items) |*child| {
                    if (!child.visible) continue;

                    const child_width = if (total_flex > 0)
                        @as(u16, @intCast((available_width * child.flex) / total_flex))
                    else
                        available_width / @as(u16, @intCast(visible_children));

                    child.area = Rect{
                        .x = current_x,
                        .y = content_area.y,
                        .width = child_width,
                        .height = content_area.height,
                    };

                    current_x += child_width + self.gap;
                }
            },
            .manual => {}, // Manual layout already has areas set
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Container = @fieldParentPtr("widget", widget);

        // Calculate layout before rendering
        self.calculateLayout(area);

        // Render all children
        for (self.children.items) |child| {
            if (!child.visible) continue;
            if (child.area) |child_area| {
                child.widget.render(buffer, child_area);
            }
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Container = @fieldParentPtr("widget", widget);

        // Forward event to all children (first to last)
        for (self.children.items) |child| {
            if (!child.visible) continue;

            if (child.widget.handleEvent(event)) {
                return true; // Event consumed
            }
        }

        return false;
    }

    fn resize(widget: *Widget, new_area: Rect) void {
        const self: *Container = @fieldParentPtr("widget", widget);

        // Recalculate layout with new area
        self.calculateLayout(new_area);

        // Notify children of their new areas
        for (self.children.items) |child| {
            if (child.area) |area| {
                child.widget.resize(area);
            }
        }
    }

    fn deinit(widget: *Widget) void {
        const self: *Container = @fieldParentPtr("widget", widget);

        // Clean up all children widgets
        for (self.children.items) |child| {
            child.widget.deinit();
        }

        self.children.deinit();
        self.allocator.destroy(self);
    }
};

test "Container init and deinit" {
    const allocator = std.testing.allocator;
    const container = try Container.init(allocator, .vertical);
    defer container.widget.deinit();

    try std.testing.expect(container.children.items.len == 0);
    try std.testing.expect(container.layout_direction == .vertical);
}

test "Container layout calculation" {
    const allocator = std.testing.allocator;
    const container = try Container.init(allocator, .vertical);
    defer container.widget.deinit();

    container.setGap(2);
    container.setPadding(1);

    // Layout should work even with no children
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    container.calculateLayout(area);
}
