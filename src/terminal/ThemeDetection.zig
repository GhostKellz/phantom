//! ThemeDetection - Light/dark theme detection for terminal applications
//! Provides comprehensive theme detection using multiple methods

const std = @import("std");
const time_utils = @import("../time/utils.zig");
const vxfw = @import("../vxfw.zig");
const ColorQueries = @import("ColorQueries.zig");

const Allocator = std.mem.Allocator;
const Color = ColorQueries.Color;
const ColorQueryManager = ColorQueries.ColorQueryManager;

/// Theme detection manager
pub const ThemeDetector = struct {
    allocator: Allocator,
    color_manager: *ColorQueryManager,
    current_theme: ?Theme = null,
    detection_methods: []const DetectionMethod,
    confidence_threshold: f32 = 0.7,
    callbacks: std.array_list.AlignedManaged(*const fn (Theme) void, null),

    pub fn init(allocator: Allocator, color_manager: *ColorQueryManager) ThemeDetector {
        const default_methods = [_]DetectionMethod{
            .background_color,
            .environment_variable,
            .terminal_specific,
        };

        return ThemeDetector{
            .allocator = allocator,
            .color_manager = color_manager,
            .detection_methods = &default_methods,
            .callbacks = std.array_list.AlignedManaged(*const fn (Theme) void, null).init(allocator),
        };
    }

    pub fn deinit(self: *ThemeDetector) void {
        self.callbacks.deinit();
    }

    /// Detect current theme using configured methods
    pub fn detectTheme(self: *ThemeDetector) !DetectionResult {
        var results = std.array_list.AlignedManaged(MethodResult, null).init(self.allocator);
        defer results.deinit();

        // Try each detection method
        for (self.detection_methods) |method| {
            const result = try self.detectWithMethod(method);
            if (result.confidence > 0.0) {
                try results.append(result);
            }
        }

        if (results.items.len == 0) {
            return DetectionResult{
                .theme = .unknown,
                .confidence = 0.0,
                .method = .none,
                .details = "No detection methods succeeded",
            };
        }

        // Find the most confident result
        var best_result = results.items[0];
        for (results.items[1..]) |result| {
            if (result.confidence > best_result.confidence) {
                best_result = result;
            }
        }

        // Update current theme if confidence is high enough
        if (best_result.confidence >= self.confidence_threshold) {
            const old_theme = self.current_theme;
            self.current_theme = best_result.theme;

            // Notify callbacks if theme changed
            if (old_theme != self.current_theme) {
                for (self.callbacks.items) |callback| {
                    callback(best_result.theme);
                }
            }
        }

        return DetectionResult{
            .theme = best_result.theme,
            .confidence = best_result.confidence,
            .method = best_result.method,
            .details = best_result.details,
        };
    }

    /// Detect theme using a specific method
    fn detectWithMethod(self: *ThemeDetector, method: DetectionMethod) !MethodResult {
        return switch (method) {
            .background_color => self.detectFromBackgroundColor(),
            .environment_variable => self.detectFromEnvironment(),
            .terminal_specific => self.detectFromTerminal(),
            .system_preference => self.detectFromSystem(),
            .time_based => self.detectFromTime(),
        };
    }

    /// Detect theme from terminal background color
    fn detectFromBackgroundColor(self: *ThemeDetector) MethodResult {
        if (self.color_manager.getCachedColor(.background)) |bg_color| {
            const is_light = bg_color.isLight();
            const luminance = bg_color.getLuminance();

            // Higher confidence for more extreme luminance values
            const confidence = if (luminance < 0.1 or luminance > 0.9) 1.0 else 0.8;

            return MethodResult{
                .theme = if (is_light) .light else .dark,
                .confidence = confidence,
                .method = .background_color,
                .details = try std.fmt.allocPrint(self.allocator, "Background luminance: {d:.2}, RGB: ({d}, {d}, {d})", .{ luminance, bg_color.r, bg_color.g, bg_color.b }),
            };
        }

        return MethodResult{
            .theme = .unknown,
            .confidence = 0.0,
            .method = .background_color,
            .details = "Background color not available",
        };
    }

    /// Detect theme from environment variables
    fn detectFromEnvironment(self: *ThemeDetector) MethodResult {
        // Check common environment variables
        const env_vars = [_][]const u8{
            "COLORFGBG", // Terminal colors
            "TERM_THEME", // Custom theme variable
            "GTK_THEME", // GTK theme
            "QT_STYLE_OVERRIDE", // Qt theme
        };

        for (env_vars) |var_name| {
            if (std.os.getenv(var_name)) |value| {
                const theme = parseThemeFromValue(value);
                if (theme != .unknown) {
                    return MethodResult{
                        .theme = theme,
                        .confidence = 0.7,
                        .method = .environment_variable,
                        .details = try std.fmt.allocPrint(self.allocator, "{s}={s}", .{ var_name, value }),
                    };
                }
            }
        }

        return MethodResult{
            .theme = .unknown,
            .confidence = 0.0,
            .method = .environment_variable,
            .details = "No relevant environment variables found",
        };
    }

    /// Detect theme from terminal-specific methods
    fn detectFromTerminal(self: *ThemeDetector) MethodResult {
        if (std.os.getenv("TERM")) |term| {
            // Some terminals set theme in TERM variable
            if (std.mem.indexOf(u8, term, "light")) |_| {
                return MethodResult{
                    .theme = .light,
                    .confidence = 0.6,
                    .method = .terminal_specific,
                    .details = try std.fmt.allocPrint(self.allocator, "TERM={s}", .{term}),
                };
            }
            if (std.mem.indexOf(u8, term, "dark")) |_| {
                return MethodResult{
                    .theme = .dark,
                    .confidence = 0.6,
                    .method = .terminal_specific,
                    .details = try std.fmt.allocPrint(self.allocator, "TERM={s}", .{term}),
                };
            }
        }

        // Check terminal-specific environment variables
        if (std.os.getenv("KITTY_CONFIG_DIRECTORY")) |_| {
            // Kitty terminal - could read config file
            return self.detectKittyTheme();
        }

        if (std.os.getenv("ALACRITTY_CONFIG_DIR")) |_| {
            // Alacritty terminal - could read config file
            return self.detectAlacrittyTheme();
        }

        return MethodResult{
            .theme = .unknown,
            .confidence = 0.0,
            .method = .terminal_specific,
            .details = "No terminal-specific detection available",
        };
    }

    /// Detect theme from system preferences
    fn detectFromSystem(self: *ThemeDetector) MethodResult {
        const builtin = @import("builtin");

        switch (builtin.os.tag) {
            .macos => return self.detectMacOSTheme(),
            .linux => return self.detectLinuxTheme(),
            .windows => return self.detectWindowsTheme(),
            else => {
                return MethodResult{
                    .theme = .unknown,
                    .confidence = 0.0,
                    .method = .system_preference,
                    .details = "System preferences not supported on this platform",
                };
            },
        }
    }

    /// Detect theme based on time of day
    fn detectFromTime(self: *ThemeDetector) MethodResult {
        const timestamp = time_utils.unixTimestampSeconds();
        const seconds_since_midnight = @mod(timestamp, 86400); // 24 hours in seconds
        const hour = @divFloor(seconds_since_midnight, 3600);

        // Simple heuristic: dark theme during night hours
        const is_night = hour < 6 or hour >= 20;
        const confidence = 0.3; // Low confidence for time-based detection

        return MethodResult{
            .theme = if (is_night) .dark else .light,
            .confidence = confidence,
            .method = .time_based,
            .details = try std.fmt.allocPrint(self.allocator, "Current hour: {d}", .{hour}),
        };
    }

    /// Detect Kitty terminal theme
    fn detectKittyTheme(_: *ThemeDetector) MethodResult {
        // This would read Kitty config file in a real implementation
        return MethodResult{
            .theme = .unknown,
            .confidence = 0.0,
            .method = .terminal_specific,
            .details = "Kitty theme detection not implemented",
        };
    }

    /// Detect Alacritty terminal theme
    fn detectAlacrittyTheme(_: *ThemeDetector) MethodResult {
        // This would read Alacritty config file in a real implementation
        return MethodResult{
            .theme = .unknown,
            .confidence = 0.0,
            .method = .terminal_specific,
            .details = "Alacritty theme detection not implemented",
        };
    }

    /// Detect macOS system theme
    fn detectMacOSTheme(self: *ThemeDetector) MethodResult {
        // Use AppleScript to query system appearance
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const script = "tell application \"System Events\" to tell appearance preferences to get dark mode";
        var cmd_args = [_][]const u8{ "osascript", "-e", script };
        var child = std.ChildProcess.init(&cmd_args, arena.allocator());

        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        if (child.spawn()) |_| {
            defer _ = child.wait() catch {};

            var output = std.array_list.AlignedManaged(u8, null).init(arena.allocator());
            if (child.stdout) |stdout| {
                stdout.reader().readAllArrayList(&output, 1024) catch {
                    return MethodResult{
                        .theme = .unknown,
                        .confidence = 0.0,
                        .method = .system_preference,
                        .details = "Failed to read AppleScript output",
                    };
                };
            }

            const output_str = std.mem.trim(u8, output.items, " \n\r\t");
            const is_dark = std.mem.eql(u8, output_str, "true");

            return MethodResult{
                .theme = if (is_dark) .dark else .light,
                .confidence = 0.9,
                .method = .system_preference,
                .details = try std.fmt.allocPrint(self.allocator, "macOS dark mode: {s}", .{output_str}),
            };
        } else |_| {}

        return MethodResult{
            .theme = .unknown,
            .confidence = 0.0,
            .method = .system_preference,
            .details = "Failed to execute AppleScript",
        };
    }

    /// Detect Linux system theme
    fn detectLinuxTheme(self: *ThemeDetector) MethodResult {
        // Try various Linux desktop environments
        if (std.os.getenv("XDG_CURRENT_DESKTOP")) |desktop| {
            if (std.mem.eql(u8, desktop, "GNOME")) {
                return self.detectGnomeTheme();
            } else if (std.mem.eql(u8, desktop, "KDE")) {
                return self.detectKdeTheme();
            }
        }

        return MethodResult{
            .theme = .unknown,
            .confidence = 0.0,
            .method = .system_preference,
            .details = "Linux system theme detection not implemented",
        };
    }

    /// Detect Windows system theme
    fn detectWindowsTheme(_: *ThemeDetector) MethodResult {
        // Query Windows registry for theme preference
        return MethodResult{
            .theme = .unknown,
            .confidence = 0.0,
            .method = .system_preference,
            .details = "Windows system theme detection not implemented",
        };
    }

    /// Detect GNOME theme
    fn detectGnomeTheme(_: *ThemeDetector) MethodResult {
        // Use gsettings to query GNOME theme
        return MethodResult{
            .theme = .unknown,
            .confidence = 0.0,
            .method = .system_preference,
            .details = "GNOME theme detection not implemented",
        };
    }

    /// Detect KDE theme
    fn detectKdeTheme(_: *ThemeDetector) MethodResult {
        // Read KDE configuration files
        return MethodResult{
            .theme = .unknown,
            .confidence = 0.0,
            .method = .system_preference,
            .details = "KDE theme detection not implemented",
        };
    }

    /// Add theme change callback
    pub fn addThemeCallback(self: *ThemeDetector, callback: *const fn (Theme) void) !void {
        try self.callbacks.append(callback);
    }

    /// Get current detected theme
    pub fn getCurrentTheme(self: *const ThemeDetector) ?Theme {
        return self.current_theme;
    }

    /// Force theme detection refresh
    pub fn refresh(self: *ThemeDetector) !DetectionResult {
        return self.detectTheme();
    }
};

/// Parse theme from environment variable value
fn parseThemeFromValue(value: []const u8) Theme {
    const lower_value = std.ascii.lowerString(std.heap.page_allocator, value) catch return .unknown;
    defer std.heap.page_allocator.free(lower_value);

    if (std.mem.indexOf(u8, lower_value, "dark")) |_| return .dark;
    if (std.mem.indexOf(u8, lower_value, "light")) |_| return .light;

    // Check COLORFGBG format: "15;0" (light fg, dark bg) means dark theme
    if (std.mem.indexOf(u8, value, ";")) |semicolon| {
        const bg_str = value[semicolon + 1 ..];
        if (std.fmt.parseInt(u8, bg_str, 10)) |bg_color| {
            // Low values (0-7) typically indicate dark background
            return if (bg_color < 8) .dark else .light;
        } else |_| {}
    }

    return .unknown;
}

/// Theme enumeration
pub const Theme = enum {
    light,
    dark,
    unknown,

    /// Get complementary theme
    pub fn complement(self: Theme) Theme {
        return switch (self) {
            .light => .dark,
            .dark => .light,
            .unknown => .unknown,
        };
    }

    /// Convert to string
    pub fn toString(self: Theme) []const u8 {
        return switch (self) {
            .light => "light",
            .dark => "dark",
            .unknown => "unknown",
        };
    }
};

/// Detection method types
pub const DetectionMethod = enum {
    background_color, // Use terminal background color
    environment_variable, // Check environment variables
    terminal_specific, // Terminal-specific detection
    system_preference, // OS-level theme preference
    time_based, // Time-of-day heuristic
};

/// Result of a single detection method
pub const MethodResult = struct {
    theme: Theme,
    confidence: f32, // 0.0 to 1.0
    method: DetectionMethod,
    details: []const u8,
};

/// Overall detection result
pub const DetectionResult = struct {
    theme: Theme,
    confidence: f32,
    method: DetectionMethod,
    details: []const u8,
};

/// Widget mixin for theme detection
pub fn ThemeAwareWidget(comptime WidgetType: type) type {
    return struct {
        widget: WidgetType,
        theme_detector: *ThemeDetector,
        auto_detect: bool = false,
        theme_specific_styles: ?ThemeStyles = null,

        const Self = @This();

        pub const ThemeStyles = struct {
            light_style: vxfw.Style,
            dark_style: vxfw.Style,
        };

        pub fn init(widget: WidgetType, theme_detector: *ThemeDetector) Self {
            return Self{
                .widget = widget,
                .theme_detector = theme_detector,
            };
        }

        /// Enable automatic theme detection and styling
        pub fn withAutoTheme(widget: WidgetType, theme_detector: *ThemeDetector, styles: ThemeStyles) Self {
            return Self{
                .widget = widget,
                .theme_detector = theme_detector,
                .auto_detect = true,
                .theme_specific_styles = styles,
            };
        }

        /// Get appropriate style for current theme
        pub fn getCurrentStyle(self: *const Self) ?vxfw.Style {
            if (self.theme_specific_styles) |styles| {
                const theme = self.theme_detector.getCurrentTheme() orelse return null;
                return switch (theme) {
                    .light => styles.light_style,
                    .dark => styles.dark_style,
                    .unknown => null,
                };
            }
            return null;
        }

        /// Trigger theme detection
        pub fn detectTheme(self: *Self) !vxfw.Command {
            _ = try self.theme_detector.detectTheme();
            return vxfw.Command.redraw;
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

            // Handle theme-related events
            switch (ctx.event) {
                .init => {
                    if (self.auto_detect) {
                        const detect_cmd = self.detectTheme() catch vxfw.Command.redraw;
                        try commands.append(detect_cmd);
                    }
                },
                .color_report => |_| {
                    // Color report might affect theme detection
                    if (self.auto_detect) {
                        const detect_cmd = self.detectTheme() catch vxfw.Command.redraw;
                        try commands.append(detect_cmd);
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

test "Theme detection from environment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Test COLORFGBG parsing
    try std.testing.expectEqual(Theme.dark, parseThemeFromValue("15;0"));
    try std.testing.expectEqual(Theme.light, parseThemeFromValue("0;15"));

    // Test string parsing
    try std.testing.expectEqual(Theme.dark, parseThemeFromValue("dark"));
    try std.testing.expectEqual(Theme.light, parseThemeFromValue("light"));
    try std.testing.expectEqual(Theme.unknown, parseThemeFromValue("invalid"));
}

test "Theme complement" {
    try std.testing.expectEqual(Theme.dark, Theme.light.complement());
    try std.testing.expectEqual(Theme.light, Theme.dark.complement());
    try std.testing.expectEqual(Theme.unknown, Theme.unknown.complement());
}

test "ThemeDetector creation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var color_manager = ColorQueryManager.init(arena.allocator());
    defer color_manager.deinit();

    var detector = ThemeDetector.init(arena.allocator(), &color_manager);
    defer detector.deinit();

    try std.testing.expectEqual(@as(?Theme, null), detector.getCurrentTheme());
}
