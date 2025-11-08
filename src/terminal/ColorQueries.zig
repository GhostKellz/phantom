//! ColorQueries - Terminal color capability detection
//! Provides OSC sequences for querying terminal colors and capabilities

const std = @import("std");
const vxfw = @import("../vxfw.zig");

const Allocator = std.mem.Allocator;

/// Terminal color query manager
pub const ColorQueryManager = struct {
    allocator: Allocator,
    pending_queries: std.HashMap(QueryType, QueryContext, QueryTypeContext, std.hash_map.default_max_load_percentage),
    color_cache: std.HashMap(ColorType, Color, ColorTypeContext, std.hash_map.default_max_load_percentage),
    response_timeout_ms: u32 = 1000,
    timer: std.time.Timer,

    const QueryTypeContext = struct {
        pub fn hash(self: @This(), key: QueryType) u64 {
            _ = self;
            return std.hash_map.getAutoHashFn(QueryType)(key);
        }
        pub fn eql(self: @This(), a: QueryType, b: QueryType) bool {
            _ = self;
            return std.hash_map.getAutoEqlFn(QueryType)(a, b);
        }
    };

    const ColorTypeContext = struct {
        pub fn hash(self: @This(), key: ColorType) u64 {
            _ = self;
            return std.hash_map.getAutoHashFn(ColorType)(key);
        }
        pub fn eql(self: @This(), a: ColorType, b: ColorType) bool {
            _ = self;
            return std.hash_map.getAutoEqlFn(ColorType)(a, b);
        }
    };

    pub fn init(allocator: Allocator) !ColorQueryManager {
        return ColorQueryManager{
            .allocator = allocator,
            .pending_queries = std.HashMap(QueryType, QueryContext, QueryTypeContext, std.hash_map.default_max_load_percentage).init(allocator),
            .color_cache = std.HashMap(ColorType, Color, ColorTypeContext, std.hash_map.default_max_load_percentage).init(allocator),
            .timer = try std.time.Timer.start(),
        };
    }

    pub fn deinit(self: *ColorQueryManager) void {
        self.pending_queries.deinit();
        self.color_cache.deinit();
    }

    /// Query specific color
    pub fn queryColor(self: *ColorQueryManager, color_type: ColorType) ![]const u8 {
        const query_type = QueryType{ .color = color_type };

        // Store query context
        try self.pending_queries.put(query_type, QueryContext{
            .timestamp = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms)),
            .callback = null,
        });

        // Return appropriate OSC sequence
        return switch (color_type) {
            .foreground => OSC_QUERY_FG,
            .background => OSC_QUERY_BG,
            .cursor => OSC_QUERY_CURSOR,
            .selection => OSC_QUERY_SELECTION,
            .palette => |index| blk: {
                const query = try std.fmt.allocPrint(self.allocator, "\x1b]4;{d};?\x07", .{index});
                break :blk query;
            },
        };
    }

    /// Query all basic colors
    pub fn queryAllColors(self: *ColorQueryManager) ![]const []const u8 {
        var queries = std.array_list.AlignedManaged([]const u8, null).init(self.allocator);

        // Query standard colors
        try queries.append(try self.queryColor(.foreground));
        try queries.append(try self.queryColor(.background));
        try queries.append(try self.queryColor(.cursor));
        try queries.append(try self.queryColor(.selection));

        return queries.toOwnedSlice();
    }

    /// Query palette colors (0-255)
    pub fn queryPalette(self: *ColorQueryManager, start_index: u8, count: u8) ![]const []const u8 {
        var queries = std.array_list.AlignedManaged([]const u8, null).init(self.allocator);

        var i: u8 = 0;
        while (i < count and start_index + i <= 255) : (i += 1) {
            const index = start_index + i;
            try queries.append(try self.queryColor(ColorType{ .palette = index }));
        }

        return queries.toOwnedSlice();
    }

    /// Process color query response
    pub fn processResponse(self: *ColorQueryManager, response: []const u8) !?ColorQueryResult {
        // Parse OSC response format: \x1b]<num>;<color>\x07 or \x1b]<num>;<color>\x1b\\
        if (response.len < 6) return null;

        if (!std.mem.startsWith(u8, response, "\x1b]")) return null;

        // Find the semicolon
        const semicolon_pos = std.mem.indexOf(u8, response, ";") orelse return null;
        if (semicolon_pos < 3) return null;

        // Extract OSC number
        const osc_num_str = response[2..semicolon_pos];
        const osc_num = std.fmt.parseInt(u16, osc_num_str, 10) catch return null;

        // Find terminator
        var end_pos: usize = response.len;
        if (std.mem.endsWith(u8, response, "\x07")) {
            end_pos = response.len - 1;
        } else if (std.mem.endsWith(u8, response, "\x1b\\")) {
            end_pos = response.len - 2;
        }

        if (end_pos <= semicolon_pos + 1) return null;

        // Extract color value
        const color_str = response[semicolon_pos + 1..end_pos];
        const color = try parseColor(color_str);

        // Determine color type from OSC number
        const color_type: ColorType = switch (osc_num) {
            10 => .foreground,
            11 => .background,
            12 => .cursor,
            17 => .selection,
            4 => blk: {
                // OSC 4 requires palette index parsing
                const next_semicolon = std.mem.indexOf(u8, color_str, ";");
                if (next_semicolon) |pos| {
                    const index_str = color_str[0..pos];
                    const index = std.fmt.parseInt(u8, index_str, 10) catch return null;
                    break :blk ColorType{ .palette = index };
                } else {
                    return null;
                }
            },
            else => return null,
        };

        // Cache the color
        try self.color_cache.put(color_type, color);

        // Remove from pending queries
        const query_type = QueryType{ .color = color_type };
        _ = self.pending_queries.remove(query_type);

        return ColorQueryResult{
            .color_type = color_type,
            .color = color,
            .raw_response = try self.allocator.dupe(u8, response),
        };
    }

    /// Get cached color
    pub fn getCachedColor(self: *const ColorQueryManager, color_type: ColorType) ?Color {
        return self.color_cache.get(color_type);
    }

    /// Check if query is pending
    pub fn isQueryPending(self: *const ColorQueryManager, color_type: ColorType) bool {
        const query_type = QueryType{ .color = color_type };
        return self.pending_queries.contains(query_type);
    }

    /// Clean up expired queries
    pub fn cleanupExpiredQueries(self: *ColorQueryManager) void {
        const current_time = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));

        var iterator = self.pending_queries.iterator();
        while (iterator.next()) |entry| {
            const age_ms = current_time - entry.value_ptr.timestamp;
            if (age_ms > self.response_timeout_ms) {
                _ = self.pending_queries.remove(entry.key_ptr.*);
            }
        }
    }

    /// Query terminal color support capabilities
    pub fn queryCapabilities(self: *ColorQueryManager) !CapabilityQuery {
        _ = self;
        return CapabilityQuery{
            .true_color_query = OSC_QUERY_TRUE_COLOR,
            .color_count_query = OSC_QUERY_COLOR_COUNT,
            .theme_query = OSC_QUERY_THEME,
        };
    }
};

/// Parse color string into Color struct
fn parseColor(color_str: []const u8) !Color {
    if (color_str.len == 0) return ColorError.InvalidFormat;

    // Handle rgb:RRRR/GGGG/BBBB format
    if (std.mem.startsWith(u8, color_str, "rgb:")) {
        const rgb_part = color_str[4..];
        var parts = std.mem.splitScalar(u8, rgb_part, '/');

        const r_str = parts.next() orelse return ColorError.InvalidFormat;
        const g_str = parts.next() orelse return ColorError.InvalidFormat;
        const b_str = parts.next() orelse return ColorError.InvalidFormat;

        // Parse hex values (can be 2 or 4 digits)
        const r = try parseHexComponent(r_str);
        const g = try parseHexComponent(g_str);
        const b = try parseHexComponent(b_str);

        return Color{
            .r = r,
            .g = g,
            .b = b,
            .a = 255,
        };
    }

    // Handle #RRGGBB format
    if (std.mem.startsWith(u8, color_str, "#") and color_str.len == 7) {
        const hex = color_str[1..];
        const rgb = try std.fmt.parseInt(u24, hex, 16);

        return Color{
            .r = @as(u8, @intCast((rgb >> 16) & 0xFF)),
            .g = @as(u8, @intCast((rgb >> 8) & 0xFF)),
            .b = @as(u8, @intCast(rgb & 0xFF)),
            .a = 255,
        };
    }

    return ColorError.InvalidFormat;
}

/// Parse hex component (2 or 4 digits) to 8-bit value
fn parseHexComponent(hex_str: []const u8) !u8 {
    if (hex_str.len == 2) {
        return try std.fmt.parseInt(u8, hex_str, 16);
    } else if (hex_str.len == 4) {
        const val = try std.fmt.parseInt(u16, hex_str, 16);
        return @as(u8, @intCast(val >> 8)); // Convert 16-bit to 8-bit
    } else {
        return ColorError.InvalidFormat;
    }
}

// OSC sequences for color queries
const OSC_QUERY_FG = "\x1b]10;?\x07";          // Query foreground color
const OSC_QUERY_BG = "\x1b]11;?\x07";          // Query background color
const OSC_QUERY_CURSOR = "\x1b]12;?\x07";      // Query cursor color
const OSC_QUERY_SELECTION = "\x1b]17;?\x07";   // Query selection color

// Additional capability queries
const OSC_QUERY_TRUE_COLOR = "\x1b]4;256;?\x07";  // Check if true color is supported
const OSC_QUERY_COLOR_COUNT = "\x1b]4;255;?\x07"; // Check maximum color index
const OSC_QUERY_THEME = "\x1b]11;?\x07";          // Background color indicates theme

/// Color type enumeration
pub const ColorType = union(enum) {
    foreground,
    background,
    cursor,
    selection,
    palette: u8, // 0-255 palette index
};

/// Query type for tracking
pub const QueryType = union(enum) {
    color: ColorType,
    capability: CapabilityType,
};

/// Capability type for terminal features
pub const CapabilityType = enum {
    true_color,
    color_count,
    theme_support,
};

/// Color representation
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    /// Convert to hex string
    pub fn toHex(self: Color, allocator: Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "#{X:0>2}{X:0>2}{X:0>2}", .{ self.r, self.g, self.b });
    }

    /// Convert to RGB string
    pub fn toRgb(self: Color, allocator: Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "rgb({d}, {d}, {d})", .{ self.r, self.g, self.b });
    }

    /// Check if color is light or dark
    pub fn isLight(self: Color) bool {
        // Calculate luminance using standard formula
        const luminance = 0.299 * @as(f32, @floatFromInt(self.r)) +
                         0.587 * @as(f32, @floatFromInt(self.g)) +
                         0.114 * @as(f32, @floatFromInt(self.b));
        return luminance > 127.5;
    }

    /// Get contrast ratio with another color
    pub fn getContrastRatio(self: Color, other: Color) f32 {
        const l1 = self.getLuminance();
        const l2 = other.getLuminance();

        const lighter = @max(l1, l2);
        const darker = @min(l1, l2);

        return (lighter + 0.05) / (darker + 0.05);
    }

    /// Calculate relative luminance
    fn getLuminance(self: Color) f32 {
        const r = srgbToLinear(@as(f32, @floatFromInt(self.r)) / 255.0);
        const g = srgbToLinear(@as(f32, @floatFromInt(self.g)) / 255.0);
        const b = srgbToLinear(@as(f32, @floatFromInt(self.b)) / 255.0);

        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    fn srgbToLinear(c: f32) f32 {
        return if (c <= 0.03928) c / 12.92 else std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
    }
};

/// Query context for tracking pending requests
pub const QueryContext = struct {
    timestamp: i64,
    callback: ?*const fn (ColorQueryResult) void = null,
};

/// Result of a color query
pub const ColorQueryResult = struct {
    color_type: ColorType,
    color: Color,
    raw_response: []u8,

    pub fn deinit(self: *ColorQueryResult, allocator: Allocator) void {
        allocator.free(self.raw_response);
    }
};

/// Capability query sequences
pub const CapabilityQuery = struct {
    true_color_query: []const u8,
    color_count_query: []const u8,
    theme_query: []const u8,
};

/// Color query errors
pub const ColorError = error{
    InvalidFormat,
    UnsupportedColor,
    QueryTimeout,
    ParseError,
};

/// Widget mixin for color query support
pub fn ColorQueryWidget(comptime WidgetType: type) type {
    return struct {
        widget: WidgetType,
        color_manager: *ColorQueryManager,
        auto_query: bool = false,

        const Self = @This();

        pub fn init(widget: WidgetType, color_manager: *ColorQueryManager) Self {
            return Self{
                .widget = widget,
                .color_manager = color_manager,
            };
        }

        /// Enable automatic color querying on init
        pub fn withAutoQuery(widget: WidgetType, color_manager: *ColorQueryManager) Self {
            return Self{
                .widget = widget,
                .color_manager = color_manager,
                .auto_query = true,
            };
        }

        /// Query terminal colors
        pub fn queryColors(self: *Self) !vxfw.Command {
            const queries = try self.color_manager.queryAllColors();
            defer self.color_manager.allocator.free(queries);

            // Send first query (others would be chained)
            if (queries.len > 0) {
                return vxfw.Command{ .write_stdout = queries[0] };
            }
            return vxfw.Command.redraw;
        }

        /// Get foreground color
        pub fn getForegroundColor(self: *const Self) ?Color {
            return self.color_manager.getCachedColor(.foreground);
        }

        /// Get background color
        pub fn getBackgroundColor(self: *const Self) ?Color {
            return self.color_manager.getCachedColor(.background);
        }

        /// Detect if terminal has light or dark theme
        pub fn detectTheme(self: *const Self) ?Theme {
            if (self.getBackgroundColor()) |bg_color| {
                return if (bg_color.isLight()) .light else .dark;
            }
            return null;
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

            // Handle color query events
            switch (ctx.event) {
                .color_report => |report| {
                    if (self.color_manager.processResponse(report)) |result| {
                        _ = result; // Color cached automatically
                        try commands.append(.redraw);
                    } else |_| {}
                },
                .init => {
                    if (self.auto_query) {
                        const query_cmd = self.queryColors() catch vxfw.Command.redraw;
                        try commands.append(query_cmd);
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

/// Theme enumeration
pub const Theme = enum {
    light,
    dark,
};

test "Color parsing" {
    // Test rgb: format
    const color1 = try parseColor("rgb:FFFF/0000/0000");
    try std.testing.expectEqual(@as(u8, 255), color1.r);
    try std.testing.expectEqual(@as(u8, 0), color1.g);
    try std.testing.expectEqual(@as(u8, 0), color1.b);

    // Test hex format
    const color2 = try parseColor("#FF0000");
    try std.testing.expectEqual(@as(u8, 255), color2.r);
    try std.testing.expectEqual(@as(u8, 0), color2.g);
    try std.testing.expectEqual(@as(u8, 0), color2.b);
}

test "Color luminance" {
    const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

    try std.testing.expect(white.isLight());
    try std.testing.expect(!black.isLight());

    const contrast = white.getContrastRatio(black);
    try std.testing.expect(contrast > 20.0); // Should be 21:1 for pure white/black
}

test "ColorQueryManager" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var manager = try ColorQueryManager.init(arena.allocator());
    defer manager.deinit();

    // Test query generation
    const fg_query = try manager.queryColor(.foreground);
    try std.testing.expectEqualStrings(OSC_QUERY_FG, fg_query);

    // Test pending query tracking
    try std.testing.expect(manager.isQueryPending(.foreground));
}