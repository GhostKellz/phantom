//! Phantom Widget Framework (vxfw) - Advanced widget system inspired by Vaxis
//! Provides Surface/SubSurface rendering, DrawContext, EventContext, and widget lifecycle management

const std = @import("std");
const geometry = @import("geometry.zig");
const style = @import("style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Rect = geometry.Rect;
const Style = style.Style;

// Re-export core widget framework components
pub const Surface = @import("vxfw/Surface.zig");
pub const SubSurface = @import("vxfw/SubSurface.zig");
pub const DrawContext = @import("vxfw/DrawContext.zig");
pub const EventContext = @import("vxfw/EventContext.zig");
pub const WidgetLifecycle = @import("vxfw/WidgetLifecycle.zig");

// Layout widgets
pub const FlexRow = @import("vxfw/FlexRow.zig");
pub const FlexColumn = @import("vxfw/FlexColumn.zig");
pub const Center = @import("vxfw/Center.zig");
pub const Padding = @import("vxfw/Padding.zig");

// Core UI widgets
pub const ScrollView = @import("vxfw/ScrollView.zig");
pub const TextView = @import("vxfw/TextView.zig");

// Essential widgets
pub const View = @import("vxfw/View.zig");
pub const SizedBox = @import("vxfw/SizedBox.zig");
pub const Border = @import("vxfw/Border.zig");
pub const LineNumbers = @import("vxfw/LineNumbers.zig");
pub const TextField = @import("vxfw/TextField.zig");
pub const Scrollbar = @import("vxfw/Scrollbar.zig");
pub const CodeView = @import("vxfw/CodeView.zig");
pub const SplitView = @import("vxfw/SplitView.zig");

// Advanced widgets
pub const ListView = @import("vxfw/ListView.zig");
pub const RichText = @import("vxfw/RichText.zig");
pub const Spinner = @import("vxfw/Spinner.zig");
pub const ScrollBars = @import("vxfw/ScrollBars.zig");

// TODO: Terminal widget (requires significant implementation)
// pub const Terminal = @import("vxfw/Terminal.zig");

// Input and interaction systems
pub const BracketedPaste = @import("input/BracketedPaste.zig");
pub const DragDrop = @import("input/DragDrop.zig");

// Clipboard support
pub const OSC52 = @import("clipboard/OSC52.zig");

// System integration modules
pub const Title = @import("terminal/Title.zig");
pub const Notifications = @import("notifications/Notifications.zig");
pub const ColorQueries = @import("terminal/ColorQueries.zig");
pub const ThemeDetection = @import("terminal/ThemeDetection.zig");
pub const GlobalTTY = @import("tty/GlobalTTY.zig");
pub const PanicHandler = @import("panic/PanicHandler.zig");
pub const ControlSequences = @import("terminal/ControlSequences.zig");
pub const Parser = @import("terminal/Parser.zig");

// Graphics and rendering modules
pub const Image = @import("graphics/Image.zig");
pub const CellBuffer = @import("rendering/CellBuffer.zig");

// Unicode processing modules
pub const GraphemeCache = @import("unicode/GraphemeCache.zig");
pub const DisplayWidth = @import("unicode/DisplayWidth.zig");
pub const GcodeIntegration = @import("unicode/GcodeIntegration.zig");

// Search and filtering modules
pub const FuzzySearch = @import("search/FuzzySearch.zig");

/// Command system for widget state updates and system interactions
pub const Command = union(enum) {
    /// Schedule a tick event for this widget after the specified delay
    tick: Tick,
    /// Change the mouse cursor shape
    set_mouse_shape: MouseShape,
    /// Request that this widget receives focus
    request_focus: Widget,
    /// Copy text to system clipboard (OSC 52)
    copy_to_clipboard: []const u8,
    /// Set terminal window title
    set_title: []const u8,
    /// Queue a full screen refresh
    queue_refresh,
    /// Send a system notification
    notify: struct {
        title: ?[]const u8,
        body: []const u8,
    },
    /// Query terminal color capabilities
    query_color: ColorKind,
    /// Mark screen as needing redraw
    redraw,
};

pub const CommandList = std.array_list.AlignedManaged(Command, null);

/// Timer-based tick events for animations and periodic updates
pub const Tick = struct {
    deadline_ms: i64,
    widget: Widget,

    pub fn lessThan(_: void, lhs: Tick, rhs: Tick) bool {
        return lhs.deadline_ms > rhs.deadline_ms;
    }

    /// Create a tick command that fires after the specified milliseconds
    pub fn in(ms: u32, widget: Widget) Command {
        // Use nanoTimestamp since we don't have a timer instance here
        const now_ns = std.time.nanoTimestamp();
        const now_ms = @as(i64, @intCast(@as(u64, @intCast(now_ns)) / std.time.ns_per_ms));
        return .{ .tick = .{
            .deadline_ms = now_ms + ms,
            .widget = widget,
        } };
    }
};

/// Mouse cursor shapes for enhanced UI feedback
pub const MouseShape = enum {
    default,
    pointer,
    text,
    crosshair,
    resize_ns,
    resize_ew,
    resize_nesw,
    resize_nwse,
    not_allowed,
    grab,
    grabbing,
};

/// Color query types for terminal capability detection
pub const ColorKind = enum {
    foreground,
    background,
    cursor,
    highlight,
};

/// Enhanced event system supporting all widget interactions
pub const Event = union(enum) {
    // Input events
    key_press: Key,
    key_release: Key,
    mouse: Mouse,

    // Focus events
    focus_in,
    focus_out,

    // Paste events
    paste_start,
    paste_end,
    paste: []const u8,

    // System events
    color_report: ColorReport,
    color_scheme: ColorScheme,
    winsize: Size,

    // Widget lifecycle events
    tick,
    init,
    mouse_enter,
    mouse_leave,

    // Custom application events
    user: UserEvent,
};

/// Custom user events for application-specific communication
pub const UserEvent = struct {
    name: []const u8,
    data: ?*const anyopaque = null,
};

/// Key event with enhanced modifier support
pub const Key = struct {
    key: KeyType,
    mods: Modifiers = .{},

    pub const KeyType = enum {
        // Control keys
        escape,
        enter,
        tab,
        backspace,
        delete,

        // Navigation
        up,
        down,
        left,
        right,
        home,
        end,
        page_up,
        page_down,

        // Function keys
        f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,

        // Character keys (use codepoint for unicode)
        character,

        // Special combinations
        ctrl_c,
        ctrl_d,
        ctrl_z,

        pub fn fromChar(ch: u21) KeyType {
            _ = ch;
            return .character;
        }
    };

    pub const Modifiers = struct {
        ctrl: bool = false,
        alt: bool = false,
        shift: bool = false,
        super: bool = false,
    };
};

/// Enhanced mouse event with wheel and drag support
pub const Mouse = struct {
    button: Button,
    action: Action,
    position: geometry.Point,
    mods: Key.Modifiers = .{},

    pub const Button = enum {
        left,
        right,
        middle,
        wheel_up,
        wheel_down,
        wheel_left,
        wheel_right,
    };

    pub const Action = enum {
        press,
        release,
        drag,
        move,
    };
};

/// Color report from terminal
pub const ColorReport = struct {
    kind: ColorKind,
    color: u32, // RGB value
};

/// System color scheme detection
pub const ColorScheme = enum {
    light,
    dark,
    auto,
};

/// Core widget interface - enhanced from basic vtable approach
pub const Widget = struct {
    userdata: *anyopaque,
    drawFn: *const fn (ptr: *anyopaque, ctx: DrawContext) Allocator.Error!Surface,
    eventHandlerFn: ?*const fn (ptr: *anyopaque, ctx: EventContext) Allocator.Error!CommandList = null,

    /// Draw this widget within the given context constraints
    pub fn draw(self: Widget, ctx: DrawContext) Allocator.Error!Surface {
        return self.drawFn(self.userdata, ctx);
    }

    /// Handle an event and return list of commands to execute
    pub fn handleEvent(self: Widget, ctx: EventContext) Allocator.Error!CommandList {
        if (self.eventHandlerFn) |handler| {
            return handler(self.userdata, ctx);
        }
        return CommandList.init(ctx.arena);
    }
};

/// Flexible layout item for FlexRow/FlexColumn
pub const FlexItem = struct {
    widget: Widget,
    flex: u16 = 0, // 0 = fixed size, >0 = flexible size weight
};

test "Widget interface" {
    const TestWidget = struct {
        value: u32,

        const Self = @This();

        pub fn widget(self: *Self) Widget {
            return .{
                .userdata = self,
                .drawFn = draw,
                .eventHandlerFn = handleEvent,
            };
        }

        fn draw(ptr: *anyopaque, ctx: DrawContext) Allocator.Error!Surface {
            _ = ptr;
            return Surface.init(ctx.arena, undefined, ctx.min);
        }

        fn handleEvent(ptr: *anyopaque, ctx: EventContext) Allocator.Error!CommandList {
            _ = ptr;
            return CommandList.init(ctx.arena);
        }
    };

    var test_widget = TestWidget{ .value = 42 };
    const widget = test_widget.widget();

    // Test that widget interface works
    _ = widget;
}

test "Event types" {
    // Test key event creation
    const key_event = Event{ .key_press = .{
        .key = .escape,
        .mods = .{ .ctrl = true },
    }};

    // Test mouse event creation
    const mouse_event = Event{ .mouse = .{
        .button = .left,
        .action = .press,
        .position = .{ .x = 10, .y = 5 },
    }};

    // Test user event
    const user_event = Event{ .user = .{
        .name = "test_event",
        .data = null,
    }};

    _ = key_event;
    _ = mouse_event;
    _ = user_event;
}

test "Command creation" {
    const dummy_widget = Widget{
        .userdata = undefined,
        .drawFn = undefined,
    };

    // Test tick command
    const tick_cmd = Tick.in(100, dummy_widget);
    try std.testing.expect(tick_cmd == .tick);

    // Test other commands
    const focus_cmd = Command{ .request_focus = dummy_widget };
    const title_cmd = Command{ .set_title = "Test Title" };

    _ = focus_cmd;
    _ = title_cmd;
}