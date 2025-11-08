//! Core event type definitions shared across Phantom's event system.
//! Separated from `event.zig` to allow internal modules (queues/backends)
//! to depend on the types without creating circular imports.
const std = @import("std");
const geometry = @import("../geometry.zig");

const Position = geometry.Position;

/// Keyboard key representation
pub const Key = union(enum) {
    char: u21,

    // Special keys
    backspace,
    enter,
    left,
    right,
    up,
    down,
    home,
    end,
    page_up,
    page_down,
    tab,
    shift_tab,
    delete,
    insert,
    escape,

    // Function keys
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,

    // Ctrl combinations
    ctrl_a,
    ctrl_b,
    ctrl_c,
    ctrl_d,
    ctrl_e,
    ctrl_f,
    ctrl_g,
    ctrl_h,
    ctrl_i,
    ctrl_j,
    ctrl_k,
    ctrl_l,
    ctrl_m,
    ctrl_n,
    ctrl_o,
    ctrl_p,
    ctrl_q,
    ctrl_r,
    ctrl_s,
    ctrl_t,
    ctrl_u,
    ctrl_v,
    ctrl_w,
    ctrl_x,
    ctrl_y,
    ctrl_z,

    pub fn fromChar(c: u8) Key {
        return Key{ .char = c };
    }

    pub fn isChar(self: Key, c: u8) bool {
        return switch (self) {
            .char => |ch| ch == c,
            else => false,
        };
    }
};

/// Mouse button representation
pub const MouseButton = enum {
    left,
    right,
    middle,
    wheel_up,
    wheel_down,
};

/// Keyboard modifiers
pub const Modifiers = struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    meta: bool = false,

    pub fn none() Modifiers {
        return Modifiers{};
    }

    pub fn hasAny(self: Modifiers) bool {
        return self.shift or self.ctrl or self.alt or self.meta;
    }
};

/// Mouse event types
pub const MouseEvent = struct {
    button: MouseButton,
    position: Position,
    pressed: bool, // true for press, false for release
    modifiers: Modifiers = .{},

    pub fn init(button: MouseButton, pos: Position, pressed: bool) MouseEvent {
        return MouseEvent{
            .button = button,
            .position = pos,
            .pressed = pressed,
            .modifiers = .{},
        };
    }

    pub fn initWithModifiers(button: MouseButton, pos: Position, pressed: bool, mods: Modifiers) MouseEvent {
        return MouseEvent{
            .button = button,
            .position = pos,
            .pressed = pressed,
            .modifiers = mods,
        };
    }
};

/// System events
pub const SystemEvent = enum {
    resize,
    focus_gained,
    focus_lost,
    suspended,
    resumed,
};

/// Main event type
pub const Event = union(enum) {
    key: Key,
    mouse: MouseEvent,
    system: SystemEvent,
    tick, // Regular timer tick

    pub fn fromKey(k: Key) Event {
        return Event{ .key = k };
    }

    pub fn fromMouse(mouse_event: MouseEvent) Event {
        return Event{ .mouse = mouse_event };
    }

    pub fn fromSystem(sys_event: SystemEvent) Event {
        return Event{ .system = sys_event };
    }

    pub fn fromTick() Event {
        return Event.tick;
    }
};

/// Event handler function type
pub const EventHandler = *const fn (event: Event) anyerror!bool;

/// Helper functions for creating common events
pub fn keyEvent(key: Key) Event {
    return Event.fromKey(key);
}

pub fn charEvent(c: u8) Event {
    return Event.fromKey(Key.fromChar(c));
}

pub fn mouseClickEvent(button: MouseButton, pos: Position) Event {
    return Event.fromMouse(MouseEvent.init(button, pos, true));
}

pub fn mouseReleaseEvent(button: MouseButton, pos: Position) Event {
    return Event.fromMouse(MouseEvent.init(button, pos, false));
}

pub fn resizeEvent() Event {
    return Event.fromSystem(SystemEvent.resize);
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test "event type helpers" {
    const key_event = keyEvent(Key.fromChar('a'));
    try std.testing.expect(key_event == .key);

    const mouse_event = mouseClickEvent(MouseButton.left, Position.init(10, 20));
    try std.testing.expect(mouse_event == .mouse);
    try std.testing.expect(mouse_event.mouse.button == MouseButton.left);
    try std.testing.expect(mouse_event.mouse.position.x == 10);
}
