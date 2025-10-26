//! Core Widget abstraction for Phantom TUI Framework
//! Provides a unified interface for building composable widget trees
const std = @import("std");
const Event = @import("event.zig").Event;
const Rect = @import("geometry.zig").Rect;
const Buffer = @import("terminal.zig").Buffer;

/// Size constraints for widget layout
pub const SizeConstraints = struct {
    min_width: u16 = 0,
    min_height: u16 = 0,
    max_width: ?u16 = null,
    max_height: ?u16 = null,
    preferred_width: ?u16 = null,
    preferred_height: ?u16 = null,

    /// Create unconstrained size (default)
    pub fn unconstrained() SizeConstraints {
        return .{};
    }

    /// Create fixed size constraints
    pub fn fixed(width: u16, height: u16) SizeConstraints {
        return .{
            .min_width = width,
            .min_height = height,
            .max_width = width,
            .max_height = height,
            .preferred_width = width,
            .preferred_height = height,
        };
    }

    /// Create minimum size constraints
    pub fn minimum(width: u16, height: u16) SizeConstraints {
        return .{
            .min_width = width,
            .min_height = height,
        };
    }

    /// Create preferred size constraints
    pub fn preferred(width: u16, height: u16) SizeConstraints {
        return .{
            .preferred_width = width,
            .preferred_height = height,
        };
    }
};

/// Base Widget interface for all Phantom widgets
///
/// All widgets should:
/// 1. Embed a `widget: Widget` field
/// 2. Implement a vtable with required methods
/// 3. Use @fieldParentPtr to access the concrete widget from vtable callbacks
///
/// Example:
/// ```zig
/// pub const MyWidget = struct {
///     widget: Widget,
///     allocator: Allocator,
///     // ... other fields
///
///     const vtable = Widget.WidgetVTable{
///         .render = render,
///         .deinit = deinit,
///         .handleEvent = handleEvent,
///     };
///
///     pub fn init(allocator: Allocator) !*MyWidget {
///         const self = try allocator.create(MyWidget);
///         self.* = .{
///             .widget = .{ .vtable = &vtable },
///             .allocator = allocator,
///         };
///         return self;
///     }
///
///     fn render(widget: *Widget, buffer: anytype, area: Rect) void {
///         const self = @fieldParentPtr(MyWidget, "widget", widget);
///         // ... render implementation
///     }
///
///     fn deinit(widget: *Widget) void {
///         const self = @fieldParentPtr(MyWidget, "widget", widget);
///         self.allocator.destroy(self);
///     }
/// };
/// ```
pub const Widget = struct {
    vtable: *const WidgetVTable,

    pub const WidgetVTable = struct {
        /// Render this widget to the buffer in the given area (REQUIRED)
        render: *const fn (self: *Widget, buffer: *Buffer, area: Rect) void,

        /// Handle lifecycle cleanup (REQUIRED)
        deinit: *const fn (self: *Widget) void,

        /// Handle input events - return true if consumed (OPTIONAL)
        handleEvent: ?*const fn (self: *Widget, event: Event) bool = null,

        /// Handle resize events (OPTIONAL)
        resize: ?*const fn (self: *Widget, new_area: Rect) void = null,

        /// Get size constraints for layout (OPTIONAL)
        getConstraints: ?*const fn (self: *Widget) SizeConstraints = null,
    };

    /// Render this widget to the buffer
    pub fn render(self: *Widget, buffer: *Buffer, area: Rect) void {
        self.vtable.render(self, buffer, area);
    }

    /// Handle input event - returns true if event was consumed
    pub fn handleEvent(self: *Widget, event: Event) bool {
        if (self.vtable.handleEvent) |handler| {
            return handler(self, event);
        }
        return false;
    }

    /// Notify widget of resize
    pub fn resize(self: *Widget, area: Rect) void {
        if (self.vtable.resize) |resizer| {
            resizer(self, area);
        }
    }

    /// Clean up widget resources
    pub fn deinit(self: *Widget) void {
        self.vtable.deinit(self);
    }

    /// Get size constraints for this widget
    pub fn getConstraints(self: *Widget) SizeConstraints {
        if (self.vtable.getConstraints) |getter| {
            return getter(self);
        }
        return SizeConstraints.unconstrained();
    }
};

test "SizeConstraints constructors" {
    const unconstrained = SizeConstraints.unconstrained();
    try std.testing.expect(unconstrained.min_width == 0);
    try std.testing.expect(unconstrained.max_width == null);

    const fixed = SizeConstraints.fixed(80, 24);
    try std.testing.expect(fixed.min_width == 80);
    try std.testing.expect(fixed.max_width.? == 80);
    try std.testing.expect(fixed.min_height == 24);
    try std.testing.expect(fixed.max_height.? == 24);

    const minimum = SizeConstraints.minimum(10, 5);
    try std.testing.expect(minimum.min_width == 10);
    try std.testing.expect(minimum.min_height == 5);
    try std.testing.expect(minimum.max_width == null);

    const pref = SizeConstraints.preferred(100, 50);
    try std.testing.expect(pref.preferred_width.? == 100);
    try std.testing.expect(pref.preferred_height.? == 50);
}
