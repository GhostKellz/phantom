//! Event system module for Phantom TUI
//! Provides event loop, queue, and coalescing functionality

pub const EventQueue = @import("EventQueue.zig").EventQueue;
pub const EventPriority = @import("EventQueue.zig").EventPriority;
pub const QueuedEvent = @import("EventQueue.zig").QueuedEvent;

pub const EventCoalescer = @import("EventCoalescer.zig").EventCoalescer;
pub const CoalescingConfig = @import("EventCoalescer.zig").CoalescingConfig;
pub const CoalesceResult = @import("EventCoalescer.zig").CoalesceResult;

pub const ZigZagBackend = @import("ZigZagBackend.zig").ZigZagBackend;

// Export Loop.zig if it exists
pub const Loop = if (@import("builtin").is_test or @hasDecl(@import("../root.zig"), "event_loop_type"))
    @import("Loop.zig")
else
    void;
