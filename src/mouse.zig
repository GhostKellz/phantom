//! Enhanced mouse support for Phantom TUI
//! Adds hover, drag, and advanced mouse interactions
const std = @import("std");
const geometry = @import("geometry.zig");
const event_types = @import("event.zig");
const Event = event_types.Event;
const MouseEvent = event_types.MouseEvent;
const MouseButton = event_types.MouseButton;
const Modifiers = event_types.Modifiers;

const Position = geometry.Position;
const Rect = geometry.Rect;

/// Mouse cursor shapes
pub const CursorShape = enum {
    default,
    pointer,      // Hand pointer (for links/buttons)
    text,         // I-beam (for text selection)
    crosshair,
    move,         // Four arrows (for draggable items)
    not_allowed,  // Circle with line through it
    resize_ns,    // North-South resize
    resize_ew,    // East-West resize
    resize_nesw,  // Diagonal resize
    resize_nwse,  // Diagonal resize
    progress,     // Hourglass/spinner
};

/// Mouse event kinds with more detail
pub const MouseKind = enum {
    press,
    release,
    click,
    double_click,
    drag_start,
    dragging,
    drag_end,
    move,
    hover_enter,
    hover_exit,
    scroll_up,
    scroll_down,
};

/// Enhanced mouse event with more context
pub const EnhancedMouseEvent = struct {
    kind: MouseKind,
    button: MouseButton,
    position: Position,
    drag_start: ?Position = null,  // For drag events
    delta_x: i16 = 0,               // For drag events
    delta_y: i16 = 0,               // For drag events
    modifiers: Modifiers = .{},
};

/// Mouse state tracker
pub const MouseState = struct {
    current_pos: Position,
    last_pos: Position,
    buttons_pressed: std.EnumSet(MouseButton),
    hover_areas: std.ArrayList(Rect),
    drag_state: ?DragState = null,
    double_click_tracker: DoubleClickTracker,
    allocator: std.mem.Allocator,

    const DragState = struct {
        button: MouseButton,
        start_pos: Position,
        started_ms: u64,
    };

    const DoubleClickTracker = struct {
        last_click_pos: ?Position = null,
        last_click_time_ms: u64 = 0,
        double_click_threshold_ms: u64 = 500,
        double_click_distance: u16 = 2,
    };

    pub fn init(allocator: std.mem.Allocator) MouseState {
        return MouseState{
            .current_pos = Position.init(0, 0),
            .last_pos = Position.init(0, 0),
            .buttons_pressed = std.EnumSet(MouseButton).initEmpty(),
            .hover_areas = .{},
            .double_click_tracker = DoubleClickTracker{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MouseState) void {
        self.hover_areas.deinit(self.allocator);
    }

    pub fn processEvent(self: *MouseState, event: MouseEvent, current_time_ms: u64) ?EnhancedMouseEvent {
        const old_pos = self.current_pos;
        self.last_pos = old_pos;
        self.current_pos = event.position;

        const kind = self.classifyEvent(event, current_time_ms);

        return EnhancedMouseEvent{
            .kind = kind,
            .button = event.button,
            .position = event.position,
            .drag_start = if (self.drag_state) |drag| drag.start_pos else null,
            .delta_x = @as(i16, @intCast(event.position.x)) - @as(i16, @intCast(old_pos.x)),
            .delta_y = @as(i16, @intCast(event.position.y)) - @as(i16, @intCast(old_pos.y)),
            .modifiers = event.modifiers,
        };
    }

    fn classifyEvent(self: *MouseState, event: MouseEvent, current_time_ms: u64) MouseKind {
        // Handle scroll events
        if (event.button == .wheel_up) return .scroll_up;
        if (event.button == .wheel_down) return .scroll_down;

        // Handle press/release
        if (event.pressed) {
            // Button pressed
            self.buttons_pressed.insert(event.button);

            // Check for double click
            if (self.isDoubleClick(event.position, current_time_ms)) {
                return .double_click;
            }

            // Start drag
            self.drag_state = DragState{
                .button = event.button,
                .start_pos = event.position,
                .started_ms = current_time_ms,
            };

            // Update double click tracker
            self.double_click_tracker.last_click_pos = event.position;
            self.double_click_tracker.last_click_time_ms = current_time_ms;

            return .press;
        } else {
            // Button released
            self.buttons_pressed.remove(event.button);

            // End drag if dragging
            if (self.drag_state) |drag| {
                if (drag.button == event.button) {
                    self.drag_state = null;
                    return .drag_end;
                }
            }

            return .release;
        }
    }

    fn isDoubleClick(self: *MouseState, pos: Position, current_time_ms: u64) bool {
        const tracker = self.double_click_tracker;

        if (tracker.last_click_pos) |last_pos| {
            const time_delta = current_time_ms - tracker.last_click_time_ms;
            const dist = self.distance(pos, last_pos);

            return time_delta <= tracker.double_click_threshold_ms and
                dist <= tracker.double_click_distance;
        }

        return false;
    }

    fn distance(self: *MouseState, a: Position, b: Position) u16 {
        _ = self;
        const dx = if (a.x > b.x) a.x - b.x else b.x - a.x;
        const dy = if (a.y > b.y) a.y - b.y else b.y - a.y;
        return dx + dy; // Manhattan distance for simplicity
    }

    pub fn isButtonPressed(self: *const MouseState, button: MouseButton) bool {
        return self.buttons_pressed.contains(button);
    }

    pub fn isDragging(self: *const MouseState) bool {
        return self.drag_state != null;
    }

    pub fn getDragDistance(self: *const MouseState) ?Position {
        if (self.drag_state) |drag| {
            return Position.init(
                if (self.current_pos.x > drag.start_pos.x)
                    self.current_pos.x - drag.start_pos.x
                else
                    drag.start_pos.x - self.current_pos.x,
                if (self.current_pos.y > drag.start_pos.y)
                    self.current_pos.y - drag.start_pos.y
                else
                    drag.start_pos.y - self.current_pos.y,
            );
        }
        return null;
    }

    pub fn isInRect(pos: Position, rect: Rect) bool {
        return pos.x >= rect.x and
            pos.x < rect.x + rect.width and
            pos.y >= rect.y and
            pos.y < rect.y + rect.height;
    }
};

test "Mouse state tracking" {
    const allocator = std.testing.allocator;

    var state = MouseState.init(allocator);
    defer state.deinit();

    // Test button press
    const press_event = MouseEvent.init(.left, Position.init(10, 10), true);
    _ = state.processEvent(press_event, 1000);

    try std.testing.expect(state.isButtonPressed(.left));
    try std.testing.expect(state.isDragging());
}

test "Mouse hover detection" {
    const pos = Position.init(5, 5);
    const rect = Rect.init(0, 0, 10, 10);

    try std.testing.expect(MouseState.isInRect(pos, rect));

    const outside = Position.init(15, 15);
    try std.testing.expect(!MouseState.isInRect(outside, rect));
}
