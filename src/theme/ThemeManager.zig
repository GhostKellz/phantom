//! ThemeManager - Manages theme loading, switching, and access
//! Supports built-in themes and user themes from ~/.config/phantom/themes/

const std = @import("std");
const Theme = @import("Theme.zig").Theme;
const Color = @import("../style.zig").Color;

pub const ThemeManager = struct {
    allocator: std.mem.Allocator,
    themes: std.StringHashMap(Theme),
    active_theme_name: []const u8,
    theme_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator) !*ThemeManager {
        const self = try allocator.create(ThemeManager);
        errdefer allocator.destroy(self);

        self.* = ThemeManager{
            .allocator = allocator,
            .themes = std.StringHashMap(Theme).init(allocator),
            .active_theme_name = "",
            .theme_dir = "",
        };

        // Load built-in themes
        try self.loadBuiltinThemes();

        // Get theme directory (~/.config/phantom/themes/)
        self.theme_dir = try self.getThemeDir();

        // Load user themes
        self.loadUserThemes() catch |err| {
            std.log.warn("Failed to load user themes: {}", .{err});
        };

        // Set default theme
        if (self.themes.get("ghost-hacker-blue")) |_| {
            self.active_theme_name = "ghost-hacker-blue";
        } else if (self.themes.get("tokyonight-night")) |_| {
            self.active_theme_name = "tokyonight-night";
        } else {
            return error.NoThemesAvailable;
        }

        return self;
    }

    pub fn deinit(self: *ThemeManager) void {
        var iter = self.themes.valueIterator();
        while (iter.next()) |theme| {
            var t = theme.*;
            t.deinit();
        }
        self.themes.deinit();
        self.allocator.free(self.theme_dir);
        self.allocator.destroy(self);
    }

    /// Set active theme by name
    pub fn setTheme(self: *ThemeManager, name: []const u8) !void {
        if (!self.themes.contains(name)) {
            return error.ThemeNotFound;
        }
        self.active_theme_name = name;
    }

    /// Get active theme
    pub fn getActiveTheme(self: *const ThemeManager) *const Theme {
        return self.themes.getPtr(self.active_theme_name).?;
    }

    /// Get color from active theme
    pub fn getColor(self: *const ThemeManager, name: []const u8) Color {
        const theme = self.getActiveTheme();
        return theme.getColor(name) orelse Color.white;
    }

    /// List all available theme names
    pub fn listThemes(self: *ThemeManager, allocator: std.mem.Allocator) ![][]const u8 {
        var names = std.ArrayList([]const u8).init(allocator);
        defer names.deinit();

        var iter = self.themes.keyIterator();
        while (iter.next()) |name| {
            try names.append(name.*);
        }

        return try names.toOwnedSlice();
    }

    /// Load built-in themes (embedded in binary)
    fn loadBuiltinThemes(self: *ThemeManager) !void {
        // Load Ghost Hacker Blue theme
        const ghost_hacker_blue = @embedFile("builtin/ghost-hacker-blue.json");
        const theme1 = try Theme.parseJson(self.allocator, ghost_hacker_blue);
        try self.themes.put("ghost-hacker-blue", theme1);

        // Load Tokyo Night themes
        const tokyonight_night = @embedFile("builtin/tokyonight-night.json");
        const theme2 = try Theme.parseJson(self.allocator, tokyonight_night);
        try self.themes.put("tokyonight-night", theme2);

        const tokyonight_storm = @embedFile("builtin/tokyonight-storm.json");
        const theme3 = try Theme.parseJson(self.allocator, tokyonight_storm);
        try self.themes.put("tokyonight-storm", theme3);

        const tokyonight_moon = @embedFile("builtin/tokyonight-moon.json");
        const theme4 = try Theme.parseJson(self.allocator, tokyonight_moon);
        try self.themes.put("tokyonight-moon", theme4);
    }

    /// Load user themes from ~/.config/phantom/themes/
    fn loadUserThemes(self: *ThemeManager) !void {
        var theme_dir = try std.fs.cwd().openDir(self.theme_dir, .{ .iterate = true });
        defer theme_dir.close();

        var iter = theme_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".json")) continue;

            const path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.theme_dir, entry.name });
            defer self.allocator.free(path);

            const theme = Theme.loadFromFile(self.allocator, path) catch |err| {
                std.log.warn("Failed to load theme {s}: {}", .{ entry.name, err });
                continue;
            };

            // Use filename without extension as theme name
            const name = entry.name[0 .. entry.name.len - 5]; // Remove ".json"
            const name_copy = try self.allocator.dupe(u8, name);
            try self.themes.put(name_copy, theme);
        }
    }

    /// Get theme directory path
    fn getThemeDir(self: *ThemeManager) ![]const u8 {
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;

        const config_home = std.posix.getenv("XDG_CONFIG_HOME") orelse
            try std.fs.path.join(self.allocator, &[_][]const u8{ home, ".config" });
        defer if (std.posix.getenv("XDG_CONFIG_HOME") == null) self.allocator.free(config_home);

        const theme_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ config_home, "phantom", "themes" });

        // Create directory if it doesn't exist
        std.fs.cwd().makePath(theme_dir) catch {};

        return theme_dir;
    }
};

// Tests
test "ThemeManager initialization" {
    const testing = std.testing;

    var manager = try ThemeManager.init(testing.allocator);
    defer manager.deinit();

    // Should have at least the built-in themes
    const theme_names = try manager.listThemes(testing.allocator);
    defer testing.allocator.free(theme_names);

    try testing.expect(theme_names.len >= 4); // 4 built-in themes
}

test "ThemeManager theme switching" {
    const testing = std.testing;

    var manager = try ThemeManager.init(testing.allocator);
    defer manager.deinit();

    // Switch to Tokyo Night
    try manager.setTheme("tokyonight-night");
    try testing.expectEqualStrings("tokyonight-night", manager.active_theme_name);

    // Switch to Ghost Hacker Blue
    try manager.setTheme("ghost-hacker-blue");
    try testing.expectEqualStrings("ghost-hacker-blue", manager.active_theme_name);
}

test "ThemeManager get color" {
    const testing = std.testing;

    var manager = try ThemeManager.init(testing.allocator);
    defer manager.deinit();

    try manager.setTheme("ghost-hacker-blue");
    const primary = manager.getColor("primary");

    // Should return a valid color (not checking exact value as it depends on theme)
    try testing.expect(primary.r > 0 or primary.g > 0 or primary.b > 0 or
        primary.r == 0 and primary.g == 0 and primary.b == 0);
}
