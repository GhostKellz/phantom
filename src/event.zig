//! Event system for Phantom TUI - keyboard, mouse, and system events
const std = @import("std");
const geometry = @import("geometry.zig");

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

/// Mouse event types
pub const MouseEvent = struct {
    button: MouseButton,
    position: Position,
    pressed: bool, // true for press, false for release

    pub fn init(button: MouseButton, pos: Position, pressed: bool) MouseEvent {
        return MouseEvent{
            .button = button,
            .position = pos,
            .pressed = pressed,
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

/// Async event loop using zsync
pub const EventLoop = struct {
    allocator: std.mem.Allocator,
    running: bool = false,
    handlers: std.ArrayList(EventHandler),
    tick_interval_ms: u64 = 16, // ~60 FPS

    pub fn init(allocator: std.mem.Allocator) EventLoop {
        return EventLoop{
            .allocator = allocator,
            .handlers = std.ArrayList(EventHandler){},
        };
    }

    pub fn deinit(self: *EventLoop) void {
        self.handlers.deinit(self.allocator);
    }

    pub fn addHandler(self: *EventLoop, handler: EventHandler) !void {
        try self.handlers.append(self.allocator, handler);
    }

    pub fn removeHandler(self: *EventLoop, handler: EventHandler) void {
        for (self.handlers.items, 0..) |h, i| {
            if (h == handler) {
                _ = self.handlers.swapRemove(i);
                return;
            }
        }
    }

    pub fn setTickInterval(self: *EventLoop, interval_ms: u64) void {
        self.tick_interval_ms = interval_ms;
    }

    /// Start the event loop (blocking)
    pub fn run(self: *EventLoop) !void {
        self.running = true;
        defer self.running = false;

        // Async event loop with zsync integration
        const runtime = @import("runtime.zig");
        
        while (self.running) {
            // Create async tasks for different event sources
            var tasks = std.ArrayList(runtime.Task){};
            defer tasks.deinit(self.allocator);
            
            // Keyboard polling task
            try tasks.append(self.allocator, runtime.Task.init(1));
            
            // Process events in parallel
            const keyboard_task = blk: {
                if (try self.pollKeyboard()) |event| {
                    if (try self.dispatchEvent(event)) {
                        break :blk true; // Event handler requested exit
                    }
                }
                break :blk false;
            };
            
            if (keyboard_task) break;

            // Send tick event
            if (try self.dispatchEvent(Event.fromTick())) {
                break;
            }

            // Yield control to other async tasks
            runtime.Runtime.yield();
            
            // Sleep for tick interval
            std.Thread.sleep(self.tick_interval_ms * 1_000_000); // Convert ms to ns
        }
    }

    /// Start the event loop asynchronously with zsync
    pub fn runAsync(self: *EventLoop) !void {
        const runtime = @import("runtime.zig");
        var rt = try runtime.Runtime.init(self.allocator);
        defer rt.deinit();
        
        
        // Spawn async event processing
        const EventProcessor = struct {
            fn process(loop: *EventLoop) void {
                loop.run() catch |err| {
                    std.log.err("Event loop error: {}", .{err});
                };
            }
        };
        
        const task = try rt.spawn(EventProcessor.process, .{self});
        task.wait();
    }

    pub fn stop(self: *EventLoop) void {
        self.running = false;
    }

    fn dispatchEvent(self: *EventLoop, event: Event) !bool {
        for (self.handlers.items) |handler| {
            if (try handler(event)) {
                return true; // Handler requested exit
            }
        }
        return false;
    }

    fn pollKeyboard(self: *EventLoop) !?Event {
        _ = self;
        // Simplified keyboard polling for now - just return null
        // Full implementation would require proper terminal handling
        return null;
    }
};

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

// Example event handlers for testing
fn echoHandler(event: Event) !bool {
    switch (event) {
        .key => |key| {
            switch (key) {
                .char => |c| std.debug.print("Key: {c}\n", .{c}),
                .ctrl_c => {
                    std.debug.print("Ctrl+C pressed, exiting\n", .{});
                    return true; // Request exit
                },
                else => std.debug.print("Special key pressed\n", .{}),
            }
        },
        .mouse => |mouse| {
            std.debug.print("Mouse {} at ({}, {})\n", .{ if (mouse.pressed) "press" else "release", mouse.position.x, mouse.position.y });
        },
        .system => |sys| {
            std.debug.print("System event: {}\n", .{sys});
        },
        .tick => {
            // Usually don't print tick events as they're frequent
        },
    }
    return false;
}

test "Event creation" {
    const key_event = keyEvent(Key.fromChar('a'));
    try std.testing.expect(key_event == .key);

    const mouse_event = mouseClickEvent(MouseButton.left, Position.init(10, 20));
    try std.testing.expect(mouse_event == .mouse);
    try std.testing.expect(mouse_event.mouse.button == MouseButton.left);
    try std.testing.expect(mouse_event.mouse.position.x == 10);
}

test "EventLoop basic operations" {
    const allocator = std.testing.allocator;
    var event_loop = EventLoop.init(allocator);
    defer event_loop.deinit();

    try event_loop.addHandler(echoHandler);
    try std.testing.expect(event_loop.handlers.items.len == 1);

    event_loop.removeHandler(echoHandler);
    try std.testing.expect(event_loop.handlers.items.len == 0);
}
