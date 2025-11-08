//! Stack widget for layering widgets with z-index
//! Perfect for modal dialogs, popups, tooltips, overlays, etc.
//!
//! The Stack widget renders children in order, with later children appearing on top.
//! This enables floating windows, context menus, and overlay UI elements.
const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Event = @import("../event.zig").Event;
const Rect = @import("../geometry.zig").Rect;
const Style = @import("../style.zig").Style;

/// Child widget with positioning info
pub const StackChild = struct {
    widget: *Widget,
    area: Rect,
    visible: bool = true,
    /// If true, this layer blocks events from reaching layers below
    modal: bool = false,
};

/// Stack widget for layered rendering (z-index)
pub const Stack = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    children: std.ArrayList(StackChild),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
        .resize = resize,
    };

    pub fn init(allocator: std.mem.Allocator) !*Stack {
        const stack = try allocator.create(Stack);
        stack.* = Stack{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .children = .{},
        };
        return stack;
    }

    /// Add a child widget at the given position
    pub fn addChild(self: *Stack, child: *Widget, area: Rect) !void {
        try self.children.append(self.allocator, StackChild{
            .widget = child,
            .area = area,
        });
    }

    /// Add a modal child (blocks events to layers below)
    pub fn addModalChild(self: *Stack, child: *Widget, area: Rect) !void {
        try self.children.append(self.allocator, StackChild{
            .widget = child,
            .area = area,
            .modal = true,
        });
    }

    /// Remove a child widget
    pub fn removeChild(self: *Stack, child: *Widget) void {
        var i: usize = 0;
        while (i < self.children.items.len) {
            if (self.children.items[i].widget == child) {
                _ = self.children.swapRemove(i);
                return;
            }
            i += 1;
        }
    }

    /// Set visibility for a child widget
    pub fn setChildVisible(self: *Stack, child: *Widget, visible: bool) void {
        for (self.children.items) |*stack_child| {
            if (stack_child.widget == child) {
                stack_child.visible = visible;
                return;
            }
        }
    }

    /// Bring a child to front (top of z-order)
    pub fn bringToFront(self: *Stack, child: *Widget) void {
        for (self.children.items, 0..) |stack_child, i| {
            if (stack_child.widget == child) {
                const item = self.children.swapRemove(i);
                self.children.append(self.allocator, item) catch return;
                return;
            }
        }
    }

    /// Send a child to back (bottom of z-order)
    pub fn sendToBack(self: *Stack, child: *Widget) void {
        for (self.children.items, 0..) |stack_child, i| {
            if (stack_child.widget == child) {
                const item = self.children.swapRemove(i);
                self.children.insert(self.allocator, 0, item) catch return;
                return;
            }
        }
    }

    /// Clear all children
    pub fn clear(self: *Stack) void {
        self.children.clearRetainingCapacity();
    }

    /// Update the target area for a child widget.
    pub fn setChildArea(self: *Stack, child: *Widget, area: Rect) void {
        for (self.children.items) |*stack_child| {
            if (stack_child.widget == child) {
                stack_child.area = area;
                return;
            }
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, _: Rect) void {
        const self: *Stack = @fieldParentPtr("widget", widget);

        // Render children in order (painters algorithm - bottom to top)
        for (self.children.items) |stack_child| {
            if (!stack_child.visible) continue;

            // Render child in its designated area
            stack_child.widget.render(buffer, stack_child.area);
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Stack = @fieldParentPtr("widget", widget);

        // Process events from top to bottom (reverse order)
        // This ensures topmost (modal) widgets get first chance at events
        var i = self.children.items.len;
        while (i > 0) {
            i -= 1;
            const stack_child = &self.children.items[i];

            if (!stack_child.visible) continue;

            // Delegate event to child
            if (stack_child.widget.handleEvent(event)) {
                return true; // Event consumed
            }

            // If this layer is modal, stop propagation
            if (stack_child.modal) {
                return true; // Block event from reaching lower layers
            }
        }

        return false;
    }

    fn resize(widget: *Widget, new_area: Rect) void {
        const self: *Stack = @fieldParentPtr("widget", widget);

        // Notify all children of resize
        // Children are responsible for adjusting their own areas
        for (self.children.items) |stack_child| {
            stack_child.widget.resize(new_area);
        }
    }

    fn deinit(widget: *Widget) void {
        const self: *Stack = @fieldParentPtr("widget", widget);
        self.children.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

test "Stack init and deinit" {
    const allocator = std.testing.allocator;
    const stack = try Stack.init(allocator);
    defer stack.widget.deinit();

    try std.testing.expect(stack.children.items.len == 0);
}
