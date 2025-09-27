//! EventContext - Context for widget event handling with arena allocation
//! Provides event information, focus state, and command collection

const std = @import("std");
const geometry = @import("../geometry.zig");
const vxfw = @import("../vxfw.zig");

const Allocator = std.mem.Allocator;
const Point = geometry.Point;
const Rect = geometry.Rect;

const EventContext = @This();

/// The event being processed
event: vxfw.Event,
/// Arena allocator for temporary allocations during event handling
arena: Allocator,
/// Widget bounds in parent coordinate system
bounds: Rect,
/// Whether this widget currently has focus
has_focus: bool = false,
/// Whether this widget can receive focus
can_focus: bool = false,

/// Create a new EventContext for the given event
pub fn init(
    event: vxfw.Event,
    arena: Allocator,
    bounds: Rect
) EventContext {
    return EventContext{
        .event = event,
        .arena = arena,
        .bounds = bounds,
    };
}

/// Create an EventContext with focus information
pub fn withFocus(
    event: vxfw.Event,
    arena: Allocator,
    bounds: Rect,
    has_focus: bool,
    can_focus: bool
) EventContext {
    return EventContext{
        .event = event,
        .arena = arena,
        .bounds = bounds,
        .has_focus = has_focus,
        .can_focus = can_focus,
    };
}

/// Check if the event is a key press for the given key
pub fn isKeyPress(self: *const EventContext, key: vxfw.Key.KeyType) bool {
    switch (self.event) {
        .key_press => |k| return k.key == key,
        else => return false,
    }
}

/// Check if the event is a key release for the given key
pub fn isKeyRelease(self: *const EventContext, key: vxfw.Key.KeyType) bool {
    switch (self.event) {
        .key_release => |k| return k.key == key,
        else => return false,
    }
}

/// Check if the event is a mouse event within this widget's bounds
pub fn isMouseEvent(self: *const EventContext) ?vxfw.Mouse {
    switch (self.event) {
        .mouse => |mouse| {
            if (self.bounds.containsPoint(mouse.position)) {
                return mouse;
            }
            return null;
        },
        else => return null,
    }
}

/// Get mouse position relative to this widget's bounds
pub fn getLocalMousePosition(self: *const EventContext) ?Point {
    if (self.isMouseEvent()) |mouse| {
        return Point{
            .x = mouse.position.x - self.bounds.x,
            .y = mouse.position.y - self.bounds.y,
        };
    }
    return null;
}

/// Check if the event is a mouse click (press or release)
pub fn isMouseClick(self: *const EventContext, button: vxfw.Mouse.Button) bool {
    if (self.isMouseEvent()) |mouse| {
        return mouse.button == button and
               (mouse.action == .press or mouse.action == .release);
    }
    return false;
}

/// Check if the event is a mouse wheel scroll
pub fn isMouseWheel(self: *const EventContext) ?vxfw.Mouse.Button {
    if (self.isMouseEvent()) |mouse| {
        switch (mouse.button) {
            .wheel_up, .wheel_down, .wheel_left, .wheel_right => return mouse.button,
            else => return null,
        }
    }
    return null;
}

/// Check if the event indicates the widget should handle it
pub fn shouldHandle(self: *const EventContext) bool {
    switch (self.event) {
        // Always handle lifecycle events
        .init, .tick => return true,

        // Handle focus events if widget can focus
        .focus_in, .focus_out => return self.can_focus,

        // Handle key events if widget has focus
        .key_press, .key_release => return self.has_focus,

        // Handle mouse events if they're within bounds
        .mouse => return self.isMouseEvent() != null,

        // Handle mouse enter/leave events
        .mouse_enter, .mouse_leave => return true,

        // Handle system events that affect all widgets
        .winsize, .color_scheme => return true,

        // Handle paste events if widget has focus
        .paste_start, .paste_end, .paste => return self.has_focus,

        // Handle user events (let widget decide)
        .user => return true,

        // Skip color reports by default
        .color_report => return false,
    }
}

/// Create a child EventContext for a sub-widget
pub fn createChild(
    self: *const EventContext,
    child_bounds: Rect
) EventContext {
    return EventContext{
        .event = self.event,
        .arena = self.arena,
        .bounds = child_bounds,
        .has_focus = false, // Child focus is managed separately
        .can_focus = false,
    };
}

/// Create a child EventContext with focus information
pub fn createChildWithFocus(
    self: *const EventContext,
    child_bounds: Rect,
    has_focus: bool,
    can_focus: bool
) EventContext {
    return EventContext{
        .event = self.event,
        .arena = self.arena,
        .bounds = child_bounds,
        .has_focus = has_focus,
        .can_focus = can_focus,
    };
}

/// Helper to create a command list for returning from event handlers
pub fn createCommandList(self: *const EventContext) vxfw.CommandList {
    return vxfw.CommandList.init(self.arena);
}

/// Helper to create a single command as a list
pub fn singleCommand(self: *const EventContext, command: vxfw.Command) !vxfw.CommandList {
    var list = self.createCommandList();
    try list.append(command);
    return list;
}

/// Helper to request focus for a widget
pub fn requestFocus(self: *const EventContext, widget: vxfw.Widget) !vxfw.CommandList {
    return self.singleCommand(.{ .request_focus = widget });
}

/// Helper to schedule a tick event
pub fn scheduleTick(self: *const EventContext, widget: vxfw.Widget, delay_ms: u32) !vxfw.CommandList {
    return self.singleCommand(vxfw.Tick.in(delay_ms, widget));
}

/// Helper to copy text to clipboard
pub fn copyToClipboard(self: *const EventContext, text: []const u8) !vxfw.CommandList {
    // Make a copy of the text in arena memory
    const text_copy = try self.arena.dupe(u8, text);
    return self.singleCommand(.{ .copy_to_clipboard = text_copy });
}

test "EventContext creation and basic queries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const key_event = vxfw.Event{ .key_press = .{ .key = .enter } };
    const bounds = Rect.init(10, 5, 20, 10);

    const ctx = EventContext.withFocus(
        key_event,
        arena.allocator(),
        bounds,
        true,  // has_focus
        true   // can_focus
    );

    // Test focus state
    try std.testing.expect(ctx.has_focus);
    try std.testing.expect(ctx.can_focus);

    // Test key event detection
    try std.testing.expect(ctx.isKeyPress(.enter));
    try std.testing.expect(!ctx.isKeyPress(.escape));

    // Test should handle logic
    try std.testing.expect(ctx.shouldHandle());
}

test "EventContext mouse event handling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const mouse_event = vxfw.Event{ .mouse = .{
        .button = .left,
        .action = .press,
        .position = Point{ .x = 15, .y = 8 },
    }};

    const bounds = Rect.init(10, 5, 20, 10);
    const ctx = EventContext.init(mouse_event, arena.allocator(), bounds);

    // Test mouse event detection
    try std.testing.expect(ctx.isMouseEvent() != null);
    try std.testing.expect(ctx.isMouseClick(.left));

    // Test local coordinate conversion
    const local_pos = ctx.getLocalMousePosition().?;
    try std.testing.expectEqual(@as(i16, 5), local_pos.x);
    try std.testing.expectEqual(@as(i16, 3), local_pos.y);
}

test "EventContext child creation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = vxfw.Event{ .init = {} };
    const parent_bounds = Rect.init(0, 0, 50, 30);
    const parent_ctx = EventContext.withFocus(
        event,
        arena.allocator(),
        parent_bounds,
        true,
        true
    );

    const child_bounds = Rect.init(10, 5, 20, 10);
    const child_ctx = parent_ctx.createChild(child_bounds);

    // Child should have same event and arena but different bounds and no focus
    try std.testing.expectEqual(child_bounds, child_ctx.bounds);
    try std.testing.expect(!child_ctx.has_focus);
    try std.testing.expect(!child_ctx.can_focus);
}