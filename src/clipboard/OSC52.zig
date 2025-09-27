//! OSC52 - OSC 52 clipboard support for terminal applications
//! Implements copy/paste operations using OSC 52 escape sequences

const std = @import("std");
const base64 = std.base64;
const vxfw = @import("../vxfw.zig");

const Allocator = std.mem.Allocator;

/// OSC 52 clipboard manager
pub const OSC52Clipboard = struct {
    allocator: Allocator,
    last_copy_data: ?[]u8 = null,

    const OSC52_COPY_PREFIX = "\x1b]52;c;";
    const OSC52_COPY_SUFFIX = "\x07";
    const OSC52_PASTE_REQUEST = "\x1b]52;c;?\x07";

    pub fn init(allocator: Allocator) OSC52Clipboard {
        return OSC52Clipboard{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OSC52Clipboard) void {
        if (self.last_copy_data) |data| {
            self.allocator.free(data);
        }
    }

    /// Copy text to clipboard using OSC 52
    pub fn copy(self: *OSC52Clipboard, text: []const u8) ![]const u8 {
        // Free previous copy data
        if (self.last_copy_data) |data| {
            self.allocator.free(data);
            self.last_copy_data = null;
        }

        // Store copy data for potential paste operations
        self.last_copy_data = try self.allocator.dupe(u8, text);

        // Encode text as base64
        const encoded_len = base64.standard.Encoder.calcSize(text.len);
        const encoded_data = try self.allocator.alloc(u8, encoded_len);
        defer self.allocator.free(encoded_data);

        _ = base64.standard.Encoder.encode(encoded_data, text);

        // Create OSC 52 sequence
        const sequence_len = OSC52_COPY_PREFIX.len + encoded_len + OSC52_COPY_SUFFIX.len;
        const sequence = try self.allocator.alloc(u8, sequence_len);

        var pos: usize = 0;
        @memcpy(sequence[pos..pos + OSC52_COPY_PREFIX.len], OSC52_COPY_PREFIX);
        pos += OSC52_COPY_PREFIX.len;

        @memcpy(sequence[pos..pos + encoded_len], encoded_data);
        pos += encoded_len;

        @memcpy(sequence[pos..pos + OSC52_COPY_SUFFIX.len], OSC52_COPY_SUFFIX);

        return sequence;
    }

    /// Request paste from clipboard using OSC 52
    pub fn requestPaste(self: *OSC52Clipboard) ![]const u8 {
        _ = self;
        return OSC52_PASTE_REQUEST;
    }

    /// Process OSC 52 response and extract clipboard data
    pub fn processPasteResponse(self: *OSC52Clipboard, response: []const u8) !?[]const u8 {
        // Expected format: \x1b]52;c;<base64_data>\x07
        if (!std.mem.startsWith(u8, response, OSC52_COPY_PREFIX)) {
            return null;
        }

        if (!std.mem.endsWith(u8, response, OSC52_COPY_SUFFIX)) {
            return null;
        }

        // Extract base64 data
        const start_pos = OSC52_COPY_PREFIX.len;
        const end_pos = response.len - OSC52_COPY_SUFFIX.len;

        if (end_pos <= start_pos) {
            return null;
        }

        const encoded_data = response[start_pos..end_pos];

        // Decode base64
        const decoded_len = try base64.standard.Decoder.calcSizeForSlice(encoded_data);
        const decoded_data = try self.allocator.alloc(u8, decoded_len);

        try base64.standard.Decoder.decode(decoded_data, encoded_data);

        return decoded_data;
    }

    /// Get the last copied data (fallback for terminals that don't support OSC 52 paste)
    pub fn getLastCopiedData(self: *const OSC52Clipboard) ?[]const u8 {
        return self.last_copy_data;
    }

    /// Check if a sequence is an OSC 52 response
    pub fn isOSC52Response(response: []const u8) bool {
        return std.mem.startsWith(u8, response, OSC52_COPY_PREFIX) and
               std.mem.endsWith(u8, response, OSC52_COPY_SUFFIX);
    }
};

/// Cross-platform clipboard interface
pub const ClipboardManager = struct {
    allocator: Allocator,
    osc52: OSC52Clipboard,
    native_available: bool = false,

    pub fn init(allocator: Allocator) ClipboardManager {
        return ClipboardManager{
            .allocator = allocator,
            .osc52 = OSC52Clipboard.init(allocator),
            .native_available = detectNativeClipboard(),
        };
    }

    pub fn deinit(self: *ClipboardManager) void {
        self.osc52.deinit();
    }

    /// Copy text to clipboard (tries native first, falls back to OSC 52)
    pub fn copy(self: *ClipboardManager, text: []const u8) ![]const u8 {
        if (self.native_available) {
            try self.copyNative(text);
            return &[_]u8{}; // No escape sequence needed
        } else {
            return self.osc52.copy(text);
        }
    }

    /// Request paste from clipboard
    pub fn paste(self: *ClipboardManager) ![]const u8 {
        if (self.native_available) {
            return self.pasteNative();
        } else {
            return self.osc52.requestPaste();
        }
    }

    /// Process potential clipboard response data
    pub fn processResponse(self: *ClipboardManager, response: []const u8) !?[]const u8 {
        if (OSC52Clipboard.isOSC52Response(response)) {
            return self.osc52.processPasteResponse(response);
        }
        return null;
    }

    /// Detect if native clipboard is available
    fn detectNativeClipboard() bool {
        // Check for common clipboard utilities
        if (std.process.hasEnvVar(std.heap.page_allocator, "WAYLAND_DISPLAY")) {
            // Wayland - check for wl-clipboard
            return commandExists("wl-copy");
        } else if (std.process.hasEnvVar(std.heap.page_allocator, "DISPLAY")) {
            // X11 - check for xclip or xsel
            return commandExists("xclip") or commandExists("xsel");
        } else {
            // Check for pbcopy/pbpaste (macOS)
            return commandExists("pbcopy");
        }
    }

    fn commandExists(command: []const u8) bool {
        const result = std.process.Child.exec(.{
            .allocator = std.heap.page_allocator,
            .argv = &[_][]const u8{ "which", command },
        }) catch return false;

        defer {
            std.heap.page_allocator.free(result.stdout);
            std.heap.page_allocator.free(result.stderr);
        }

        return result.term == .Exited and result.term.Exited == 0;
    }

    /// Copy using native clipboard utilities
    fn copyNative(self: *ClipboardManager, text: []const u8) !void {
        var child: std.process.Child = undefined;

        if (std.process.hasEnvVar(self.allocator, "WAYLAND_DISPLAY")) {
            // Wayland
            child = std.process.Child.init(&[_][]const u8{"wl-copy"}, self.allocator);
        } else if (std.process.hasEnvVar(self.allocator, "DISPLAY")) {
            // X11
            if (commandExists("xclip")) {
                child = std.process.Child.init(&[_][]const u8{ "xclip", "-selection", "clipboard" }, self.allocator);
            } else {
                child = std.process.Child.init(&[_][]const u8{ "xsel", "--clipboard", "--input" }, self.allocator);
            }
        } else {
            // macOS
            child = std.process.Child.init(&[_][]const u8{"pbcopy"}, self.allocator);
        }

        child.stdin_behavior = .Pipe;
        try child.spawn();

        // Write text to stdin
        try child.stdin.?.writeAll(text);
        child.stdin.?.close();
        child.stdin = null;

        _ = try child.wait();
    }

    /// Paste using native clipboard utilities
    fn pasteNative(self: *ClipboardManager) ![]const u8 {
        var argv: []const []const u8 = undefined;

        if (std.process.hasEnvVar(self.allocator, "WAYLAND_DISPLAY")) {
            // Wayland
            argv = &[_][]const u8{"wl-paste"};
        } else if (std.process.hasEnvVar(self.allocator, "DISPLAY")) {
            // X11
            if (commandExists("xclip")) {
                argv = &[_][]const u8{ "xclip", "-selection", "clipboard", "-out" };
            } else {
                argv = &[_][]const u8{ "xsel", "--clipboard", "--output" };
            }
        } else {
            // macOS
            argv = &[_][]const u8{"pbpaste"};
        }

        const result = try std.process.Child.exec(.{
            .allocator = self.allocator,
            .argv = argv,
        });

        if (result.term != .Exited or result.term.Exited != 0) {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
            return error.ClipboardError;
        }

        self.allocator.free(result.stderr);
        return result.stdout;
    }
};

/// Widget mixin for clipboard support
pub fn ClipboardWidget(comptime WidgetType: type) type {
    return struct {
        widget: WidgetType,
        clipboard: *ClipboardManager,

        const Self = @This();

        pub fn init(widget: WidgetType, clipboard: *ClipboardManager) Self {
            return Self{
                .widget = widget,
                .clipboard = clipboard,
            };
        }

        /// Copy text to clipboard
        pub fn copyText(self: *Self, text: []const u8) ![]const u8 {
            return self.clipboard.copy(text);
        }

        /// Request paste from clipboard
        pub fn requestPaste(self: *Self) ![]const u8 {
            return self.clipboard.paste();
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
            var commands = ctx.createCommandList();

            // Handle clipboard shortcuts
            switch (ctx.event) {
                .key_press => |key| {
                    if (ctx.has_focus and key.modifiers.ctrl) {
                        switch (key.key) {
                            .c => {
                                // Copy operation
                                if (self.getSelectedText()) |selected_text| {
                                    const copy_command = self.copyText(selected_text) catch return commands;
                                    if (copy_command.len > 0) {
                                        try commands.append(.{ .write_stdout = copy_command });
                                    }
                                }
                            },
                            .v => {
                                // Paste operation
                                const paste_command = self.requestPaste() catch return commands;
                                if (paste_command.len > 0) {
                                    try commands.append(.{ .write_stdout = paste_command });
                                }
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }

            // Forward to underlying widget
            const widget_commands = try self.widget.handleEvent(ctx);
            for (widget_commands.items) |cmd| {
                try commands.append(cmd);
            }

            return commands;
        }

        /// Get selected text from widget (must be implemented by specific widget types)
        fn getSelectedText(self: *Self) ?[]const u8 {
            _ = self;
            // This would need to be implemented by the specific widget
            return null;
        }
    };
}

test "OSC52Clipboard copy operation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var clipboard = OSC52Clipboard.init(arena.allocator());
    defer clipboard.deinit();

    const test_text = "Hello, World!";
    const copy_sequence = try clipboard.copy(test_text);
    defer arena.allocator().free(copy_sequence);

    // Should start with OSC 52 prefix
    try std.testing.expect(std.mem.startsWith(u8, copy_sequence, "\x1b]52;c;"));
    // Should end with bell character
    try std.testing.expect(std.mem.endsWith(u8, copy_sequence, "\x07"));
}

test "OSC52Clipboard paste response processing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var clipboard = OSC52Clipboard.init(arena.allocator());
    defer clipboard.deinit();

    // Create a mock OSC 52 response with base64 encoded "Hello"
    const test_response = "\x1b]52;c;SGVsbG8=\x07"; // "Hello" in base64

    const decoded = try clipboard.processPasteResponse(test_response);
    try std.testing.expect(decoded != null);
    try std.testing.expectEqualStrings("Hello", decoded.?);

    arena.allocator().free(decoded.?);
}

test "OSC52 response detection" {
    const valid_response = "\x1b]52;c;SGVsbG8=\x07";
    const invalid_response = "some other text";

    try std.testing.expect(OSC52Clipboard.isOSC52Response(valid_response));
    try std.testing.expect(!OSC52Clipboard.isOSC52Response(invalid_response));
}