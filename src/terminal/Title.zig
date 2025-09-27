//! Title - Terminal title setting support
//! Provides cross-platform terminal title setting functionality

const std = @import("std");
const vxfw = @import("../vxfw.zig");

const Allocator = std.mem.Allocator;

/// Terminal title manager
pub const TerminalTitle = struct {
    allocator: Allocator,
    current_title: ?[]u8 = null,
    original_title: ?[]u8 = null,

    // ESC sequences for setting terminal title
    const OSC_TITLE_PREFIX = "\x1b]0;";  // Set both icon and window title
    const OSC_TITLE_SUFFIX = "\x07";     // Bell terminator
    const OSC_TITLE_ST = "\x1b\\";       // String terminator (alternative)

    const OSC_ICON_PREFIX = "\x1b]1;";   // Set icon title only
    const OSC_WINDOW_PREFIX = "\x1b]2;"; // Set window title only

    // Query sequences
    const OSC_TITLE_QUERY = "\x1b]0;?\x07";
    const OSC_ICON_QUERY = "\x1b]1;?\x07";
    const OSC_WINDOW_QUERY = "\x1b]2;?\x07";

    pub fn init(allocator: Allocator) TerminalTitle {
        return TerminalTitle{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TerminalTitle) void {
        if (self.current_title) |title| {
            self.allocator.free(title);
        }
        if (self.original_title) |title| {
            self.allocator.free(title);
        }
    }

    /// Set terminal title (both icon and window title)
    pub fn setTitle(self: *TerminalTitle, title: []const u8) ![]const u8 {
        // Update stored title
        if (self.current_title) |old_title| {
            self.allocator.free(old_title);
        }
        self.current_title = try self.allocator.dupe(u8, title);

        // Create escape sequence
        return try self.createTitleSequence(OSC_TITLE_PREFIX, title);
    }

    /// Set window title only
    pub fn setWindowTitle(self: *TerminalTitle, title: []const u8) ![]const u8 {
        return try self.createTitleSequence(OSC_WINDOW_PREFIX, title);
    }

    /// Set icon title only
    pub fn setIconTitle(self: *TerminalTitle, title: []const u8) ![]const u8 {
        return try self.createTitleSequence(OSC_ICON_PREFIX, title);
    }

    /// Create a formatted title with prefix
    pub fn setFormattedTitle(self: *TerminalTitle, comptime fmt: []const u8, args: anytype) ![]const u8 {
        const formatted_title = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(formatted_title);
        return self.setTitle(formatted_title);
    }

    /// Restore original title (if known)
    pub fn restoreTitle(self: *TerminalTitle) !?[]const u8 {
        if (self.original_title) |original| {
            return try self.setTitle(original);
        }
        return null;
    }

    /// Query current terminal title
    pub fn queryTitle(self: *TerminalTitle) []const u8 {
        _ = self;
        return OSC_TITLE_QUERY;
    }

    /// Query window title
    pub fn queryWindowTitle(self: *TerminalTitle) []const u8 {
        _ = self;
        return OSC_WINDOW_QUERY;
    }

    /// Query icon title
    pub fn queryIconTitle(self: *TerminalTitle) []const u8 {
        _ = self;
        return OSC_ICON_QUERY;
    }

    /// Process title query response
    pub fn processTitleResponse(self: *TerminalTitle, response: []const u8) !?[]const u8 {
        // Response format: \x1b]0;<title>\x07 or \x1b]0;<title>\x1b\\
        if (std.mem.startsWith(u8, response, OSC_TITLE_PREFIX)) {
            const start_pos = OSC_TITLE_PREFIX.len;
            var end_pos: usize = response.len;

            // Check for bell terminator
            if (std.mem.endsWith(u8, response, OSC_TITLE_SUFFIX)) {
                end_pos = response.len - OSC_TITLE_SUFFIX.len;
            }
            // Check for string terminator
            else if (std.mem.endsWith(u8, response, OSC_TITLE_ST)) {
                end_pos = response.len - OSC_TITLE_ST.len;
            }

            if (end_pos > start_pos) {
                const title = response[start_pos..end_pos];

                // Store as original if we don't have one
                if (self.original_title == null) {
                    self.original_title = try self.allocator.dupe(u8, title);
                }

                return try self.allocator.dupe(u8, title);
            }
        }

        return null;
    }

    /// Get current stored title
    pub fn getCurrentTitle(self: *const TerminalTitle) ?[]const u8 {
        return self.current_title;
    }

    /// Get original title
    pub fn getOriginalTitle(self: *const TerminalTitle) ?[]const u8 {
        return self.original_title;
    }

    /// Create title escape sequence
    fn createTitleSequence(self: *TerminalTitle, prefix: []const u8, title: []const u8) ![]const u8 {
        // Escape special characters in title
        const escaped_title = try self.escapeTitle(title);
        defer self.allocator.free(escaped_title);

        // Create sequence: prefix + title + suffix
        const sequence_len = prefix.len + escaped_title.len + OSC_TITLE_SUFFIX.len;
        const sequence = try self.allocator.alloc(u8, sequence_len);

        var pos: usize = 0;
        @memcpy(sequence[pos..pos + prefix.len], prefix);
        pos += prefix.len;

        @memcpy(sequence[pos..pos + escaped_title.len], escaped_title);
        pos += escaped_title.len;

        @memcpy(sequence[pos..pos + OSC_TITLE_SUFFIX.len], OSC_TITLE_SUFFIX);

        return sequence;
    }

    /// Escape special characters in title
    fn escapeTitle(self: *TerminalTitle, title: []const u8) ![]u8 {
        // Count characters that need escaping
        var escaped_count: usize = 0;
        for (title) |char| {
            switch (char) {
                0x07, 0x1b => escaped_count += 1, // Bell and ESC need escaping
                else => {},
            }
        }

        if (escaped_count == 0) {
            return try self.allocator.dupe(u8, title);
        }

        // Create escaped version
        const escaped = try self.allocator.alloc(u8, title.len + escaped_count);
        var pos: usize = 0;

        for (title) |char| {
            switch (char) {
                0x07 => {
                    // Replace bell with space
                    escaped[pos] = ' ';
                    pos += 1;
                },
                0x1b => {
                    // Replace ESC with space
                    escaped[pos] = ' ';
                    pos += 1;
                },
                else => {
                    escaped[pos] = char;
                    pos += 1;
                },
            }
        }

        return escaped;
    }

    /// Check if response is a title query response
    pub fn isTitleResponse(response: []const u8) bool {
        return std.mem.startsWith(u8, response, OSC_TITLE_PREFIX) or
               std.mem.startsWith(u8, response, OSC_WINDOW_PREFIX) or
               std.mem.startsWith(u8, response, OSC_ICON_PREFIX);
    }
};

/// Application title manager with automatic restoration
pub const AppTitleManager = struct {
    title_manager: TerminalTitle,
    app_name: []const u8,
    should_restore: bool = true,

    pub fn init(allocator: Allocator, app_name: []const u8) AppTitleManager {
        return AppTitleManager{
            .title_manager = TerminalTitle.init(allocator),
            .app_name = app_name,
        };
    }

    pub fn deinit(self: *AppTitleManager) void {
        self.title_manager.deinit();
    }

    /// Initialize app title (queries original and sets app title)
    pub fn initAppTitle(self: *AppTitleManager) !vxfw.Command {
        // Query original title first
        const query_sequence = self.title_manager.queryTitle();
        return vxfw.Command{ .write_stdout = query_sequence };
    }

    /// Set application title
    pub fn setAppTitle(self: *AppTitleManager, subtitle: ?[]const u8) !vxfw.Command {
        const full_title = if (subtitle) |sub|
            try std.fmt.allocPrint(self.title_manager.allocator, "{s} - {s}", .{ self.app_name, sub })
        else
            try self.title_manager.allocator.dupe(u8, self.app_name);

        defer self.title_manager.allocator.free(full_title);

        const title_sequence = try self.title_manager.setTitle(full_title);
        return vxfw.Command{ .write_stdout = title_sequence };
    }

    /// Update title with status
    pub fn updateStatus(self: *AppTitleManager, status: []const u8) !vxfw.Command {
        return self.setAppTitle(status);
    }

    /// Restore original title
    pub fn restoreOriginalTitle(self: *AppTitleManager) !?vxfw.Command {
        if (self.should_restore) {
            if (try self.title_manager.restoreTitle()) |restore_sequence| {
                return vxfw.Command{ .write_stdout = restore_sequence };
            }
        }
        return null;
    }

    /// Process title response (for original title capture)
    pub fn processTitleResponse(self: *AppTitleManager, response: []const u8) !?[]const u8 {
        return self.title_manager.processTitleResponse(response);
    }

    /// Disable title restoration on exit
    pub fn disableRestore(self: *AppTitleManager) void {
        self.should_restore = false;
    }
};

/// Widget mixin for title management
pub fn TitleWidget(comptime WidgetType: type) type {
    return struct {
        widget: WidgetType,
        title_manager: *AppTitleManager,

        const Self = @This();

        pub fn init(widget: WidgetType, title_manager: *AppTitleManager) Self {
            return Self{
                .widget = widget,
                .title_manager = title_manager,
            };
        }

        /// Set title for this widget
        pub fn setWidgetTitle(self: *Self, title: []const u8) !vxfw.Command {
            return self.title_manager.setAppTitle(title);
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

            // Handle title-related events
            var commands = ctx.createCommandList();

            // Process any title responses
            switch (ctx.event) {
                .color_report => |report| {
                    if (TerminalTitle.isTitleResponse(report)) {
                        _ = self.title_manager.processTitleResponse(report) catch null;
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
    };
}

test "TerminalTitle basic functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var title_manager = TerminalTitle.init(arena.allocator());
    defer title_manager.deinit();

    // Test setting title
    const title_sequence = try title_manager.setTitle("Test Application");
    defer arena.allocator().free(title_sequence);

    try std.testing.expect(std.mem.startsWith(u8, title_sequence, "\x1b]0;"));
    try std.testing.expect(std.mem.endsWith(u8, title_sequence, "\x07"));
    try std.testing.expect(std.mem.indexOf(u8, title_sequence, "Test Application") != null);

    // Test current title storage
    try std.testing.expectEqualStrings("Test Application", title_manager.getCurrentTitle().?);
}

test "TerminalTitle escape handling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var title_manager = TerminalTitle.init(arena.allocator());
    defer title_manager.deinit();

    // Test title with special characters
    const title_with_bell = "Test\x07App";
    const escaped_title = try title_manager.escapeTitle(title_with_bell);
    defer arena.allocator().free(escaped_title);

    try std.testing.expectEqualStrings("Test App", escaped_title);
}

test "AppTitleManager functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var app_manager = AppTitleManager.init(arena.allocator(), "MyApp");
    defer app_manager.deinit();

    // Test app title setting
    const title_cmd = try app_manager.setAppTitle("Loading...");
    try std.testing.expect(title_cmd == .write_stdout);
}