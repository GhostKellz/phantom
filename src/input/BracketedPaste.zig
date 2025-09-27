//! BracketedPaste - Support for bracketed paste mode
//! Handles terminal bracketed paste sequences for safe multi-line text pasting

const std = @import("std");
const vxfw = @import("../vxfw.zig");

const Allocator = std.mem.Allocator;

/// Bracketed paste mode manager
pub const BracketedPaste = struct {
    is_enabled: bool = false,
    paste_buffer: std.array_list.AlignedManaged(u8, null),
    is_pasting: bool = false,

    const PASTE_START = "\x1b[200~";
    const PASTE_END = "\x1b[201~";
    const ENABLE_BRACKETED_PASTE = "\x1b[?2004h";
    const DISABLE_BRACKETED_PASTE = "\x1b[?2004l";

    pub fn init(allocator: Allocator) BracketedPaste {
        return BracketedPaste{
            .paste_buffer = std.array_list.AlignedManaged(u8, null).init(allocator),
        };
    }

    pub fn deinit(self: *BracketedPaste) void {
        self.paste_buffer.deinit();
    }

    /// Enable bracketed paste mode (sends escape sequence to terminal)
    pub fn enable(self: *BracketedPaste) ![]const u8 {
        self.is_enabled = true;
        return ENABLE_BRACKETED_PASTE;
    }

    /// Disable bracketed paste mode (sends escape sequence to terminal)
    pub fn disable(self: *BracketedPaste) ![]const u8 {
        self.is_enabled = false;
        return DISABLE_BRACKETED_PASTE;
    }

    /// Check if currently in paste mode
    pub fn isPasting(self: *const BracketedPaste) bool {
        return self.is_pasting;
    }

    /// Process input data and return whether it was consumed by paste handling
    pub fn processInput(self: *BracketedPaste, input: []const u8) !?PasteEvent {
        if (!self.is_enabled) return null;

        // Check for paste start sequence
        if (std.mem.indexOf(u8, input, PASTE_START)) |start_pos| {
            self.is_pasting = true;
            self.paste_buffer.clearRetainingCapacity();

            // Look for data after paste start
            const data_start = start_pos + PASTE_START.len;
            if (data_start < input.len) {
                const remaining_data = input[data_start..];

                // Check if paste end is in the same input
                if (std.mem.indexOf(u8, remaining_data, PASTE_END)) |end_pos| {
                    // Complete paste in single input
                    const paste_data = remaining_data[0..end_pos];
                    try self.paste_buffer.appendSlice(paste_data);

                    const result = PasteEvent{
                        .text = try self.paste_buffer.toOwnedSlice(),
                        .is_complete = true,
                    };

                    self.is_pasting = false;
                    return result;
                } else {
                    // Partial paste data
                    try self.paste_buffer.appendSlice(remaining_data);
                    return PasteEvent{
                        .text = &[_]u8{},
                        .is_complete = false,
                    };
                }
            }

            return PasteEvent{
                .text = &[_]u8{},
                .is_complete = false,
            };
        }

        // Check for paste end sequence while pasting
        if (self.is_pasting) {
            if (std.mem.indexOf(u8, input, PASTE_END)) |end_pos| {
                // Add data before end sequence
                if (end_pos > 0) {
                    try self.paste_buffer.appendSlice(input[0..end_pos]);
                }

                const result = PasteEvent{
                    .text = try self.paste_buffer.toOwnedSlice(),
                    .is_complete = true,
                };

                self.is_pasting = false;
                return result;
            } else {
                // Continue accumulating paste data
                try self.paste_buffer.appendSlice(input);
                return PasteEvent{
                    .text = &[_]u8{},
                    .is_complete = false,
                };
            }
        }

        return null;
    }

    /// Clear any incomplete paste data
    pub fn clearPasteBuffer(self: *BracketedPaste) void {
        self.paste_buffer.clearRetainingCapacity();
        self.is_pasting = false;
    }

    /// Get current paste buffer contents (for debugging)
    pub fn getCurrentPasteData(self: *const BracketedPaste) []const u8 {
        return self.paste_buffer.items;
    }
};

/// Event data for paste operations
pub const PasteEvent = struct {
    text: []const u8,
    is_complete: bool,
};

/// Widget mixin for bracketed paste support
pub fn BracketedPasteWidget(comptime WidgetType: type) type {
    return struct {
        widget: WidgetType,
        paste_handler: BracketedPaste,

        const Self = @This();

        pub fn init(allocator: Allocator, widget: WidgetType) Self {
            return Self{
                .widget = widget,
                .paste_handler = BracketedPaste.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.paste_handler.deinit();
        }

        /// Enable bracketed paste for this widget
        pub fn enableBracketedPaste(self: *Self) !vxfw.Command {
            const escape_sequence = try self.paste_handler.enable();
            return vxfw.Command{
                .write_stdout = escape_sequence,
            };
        }

        /// Disable bracketed paste for this widget
        pub fn disableBracketedPaste(self: *Self) !vxfw.Command {
            const escape_sequence = try self.paste_handler.disable();
            return vxfw.Command{
                .write_stdout = escape_sequence,
            };
        }

        /// Process paste events and forward to widget
        pub fn handlePasteEvent(self: *Self, paste_event: PasteEvent, ctx: vxfw.EventContext) !vxfw.CommandList {
            if (paste_event.is_complete) {
                // Send paste_start event
                const paste_start_event = vxfw.Event{ .paste_start = {} };
                const start_ctx = vxfw.EventContext.init(paste_start_event, ctx.arena, ctx.bounds);
                var commands = try self.widget.handleEvent(start_ctx);

                // Send paste event with data
                const paste_data_event = vxfw.Event{ .paste = paste_event.text };
                const paste_ctx = vxfw.EventContext.init(paste_data_event, ctx.arena, ctx.bounds);
                const paste_commands = try self.widget.handleEvent(paste_ctx);
                for (paste_commands.items) |cmd| {
                    try commands.append(cmd);
                }

                // Send paste_end event
                const paste_end_event = vxfw.Event{ .paste_end = {} };
                const end_ctx = vxfw.EventContext.init(paste_end_event, ctx.arena, ctx.bounds);
                const end_commands = try self.widget.handleEvent(end_ctx);
                for (end_commands.items) |cmd| {
                    try commands.append(cmd);
                }

                return commands;
            } else {
                // Incomplete paste - just send paste_start if this is the beginning
                if (paste_event.text.len == 0 and self.paste_handler.paste_buffer.items.len == 0) {
                    const paste_start_event = vxfw.Event{ .paste_start = {} };
                    const start_ctx = vxfw.EventContext.init(paste_start_event, ctx.arena, ctx.bounds);
                    return self.widget.handleEvent(start_ctx);
                }

                return vxfw.CommandList.init(ctx.arena);
            }
        }

        pub fn widget_interface(self: *const Self) vxfw.Widget {
            return .{
                .userdata = @constCast(self),
                .drawFn = typeErasedDrawFn,
                .eventHandlerFn = typeErasedEventHandler,
            };
        }

        fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
            const self: *const Self = @ptrCast(@alignCast(ptr));
            return self.widget.draw(ctx);
        }

        fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
            const self: *Self = @ptrCast(@alignCast(ptr));

            // Check for paste events first
            switch (ctx.event) {
                .paste_start, .paste, .paste_end => {
                    return self.widget.handleEvent(ctx);
                },
                else => {},
            }

            // For other events, forward directly
            return self.widget.handleEvent(ctx);
        }
    };
}

/// Enhanced TextField with bracketed paste support
pub const PasteAwareTextField = BracketedPasteWidget(vxfw.TextField);

/// Enhanced CodeView with bracketed paste support
pub const PasteAwareCodeView = BracketedPasteWidget(vxfw.CodeView);

test "BracketedPaste basic functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var paste_handler = BracketedPaste.init(arena.allocator());
    defer paste_handler.deinit();

    // Test enabling
    const enable_seq = try paste_handler.enable();
    try std.testing.expectEqualStrings("\x1b[?2004h", enable_seq);
    try std.testing.expect(paste_handler.is_enabled);

    // Test single input paste
    const input = "\x1b[200~Hello World\x1b[201~";
    const paste_event = try paste_handler.processInput(input);

    try std.testing.expect(paste_event != null);
    try std.testing.expectEqualStrings("Hello World", paste_event.?.text);
    try std.testing.expect(paste_event.?.is_complete);
}

test "BracketedPaste multi-part input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var paste_handler = BracketedPaste.init(arena.allocator());
    defer paste_handler.deinit();

    _ = try paste_handler.enable();

    // First part - paste start + partial data
    const input1 = "\x1b[200~Hello ";
    const event1 = try paste_handler.processInput(input1);
    try std.testing.expect(event1 != null);
    try std.testing.expect(!event1.?.is_complete);

    // Second part - more data
    const input2 = "World\nMultiline ";
    const event2 = try paste_handler.processInput(input2);
    try std.testing.expect(event2 != null);
    try std.testing.expect(!event2.?.is_complete);

    // Final part - remaining data + paste end
    const input3 = "Text\x1b[201~";
    const event3 = try paste_handler.processInput(input3);
    try std.testing.expect(event3 != null);
    try std.testing.expectEqualStrings("Hello World\nMultiline Text", event3.?.text);
    try std.testing.expect(event3.?.is_complete);
}