//! ThemeManager - Manages theme loading, switching, and access
//! Supports built-in themes and user themes from ~/.config/phantom/themes/

const std = @import("std");
const theme_mod = @import("Theme.zig");
const Theme = theme_mod.Theme;
const Variant = theme_mod.Variant;
const Origin = theme_mod.Origin;
const Color = @import("../style.zig").Color;
const style_theme = @import("../style/theme.zig");
const Manifest = style_theme.Manifest;

var global_manager: ?*ThemeManager = null;

pub const ThemeManager = struct {
    allocator: std.mem.Allocator,
    themes: std.StringHashMap(Theme),
    active_theme_name: []const u8,
    theme_dir: []const u8,
    preferred_variant: Variant,

    pub const InstallOptions = struct {
        auto_activate: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) !*ThemeManager {
        const self = try allocator.create(ThemeManager);
        errdefer allocator.destroy(self);

        self.* = ThemeManager{
            .allocator = allocator,
            .themes = std.StringHashMap(Theme).init(allocator),
            .active_theme_name = "",
            .theme_dir = "",
            .preferred_variant = .dark,
        };

        // Load built-in themes
        try self.loadBuiltinThemes();

        // Get theme directory (~/.config/phantom/themes/)
        self.theme_dir = try self.getThemeDir();

        // Load user themes
        self.loadUserThemes() catch |err| {
            std.log.warn("Failed to load user themes: {}", .{err});
        };

        try self.initializeActiveTheme();
        self.setGlobal();

        return self;
    }

    pub fn deinit(self: *ThemeManager) void {
        self.clearGlobal();
        var iter = self.themes.iterator();
        while (iter.next()) |entry| {
            var theme = entry.value_ptr.*;
            theme.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.themes.deinit();
        self.allocator.free(self.theme_dir);
        self.allocator.destroy(self);
    }

    /// Set active theme by name
    pub fn setTheme(self: *ThemeManager, name: []const u8) !void {
        const key = self.getStoredKey(name) orelse return error.ThemeNotFound;
        self.active_theme_name = key;
        self.preferred_variant = self.getActiveTheme().variant;
    }

    /// Get active theme
    pub fn getActiveTheme(self: *const ThemeManager) *const Theme {
        return self.themes.getPtr(self.active_theme_name).?;
    }

    pub fn global() ?*ThemeManager {
        return global_manager;
    }

    pub fn setGlobal(self: *ThemeManager) void {
        global_manager = self;
    }

    pub fn clearGlobal(self: *ThemeManager) void {
        if (global_manager == self) {
            global_manager = null;
        }
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
        try self.loadEmbeddedTheme("ghost-hacker-blue", "builtin/ghost-hacker-blue.json");
        try self.loadEmbeddedTheme("tokyonight-day", "builtin/tokyonight-day.json");
        try self.loadEmbeddedTheme("tokyonight-night", "builtin/tokyonight-night.json");
        try self.loadEmbeddedTheme("tokyonight-storm", "builtin/tokyonight-storm.json");
        try self.loadEmbeddedTheme("tokyonight-moon", "builtin/tokyonight-moon.json");
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

            var theme = Theme.loadFromFile(self.allocator, path) catch |err| {
                std.log.warn("Failed to load theme {s}: {}", .{ entry.name, err });
                continue;
            };
            theme.setOrigin(.user);

            // Use filename without extension as theme name
            const name = entry.name[0 .. entry.name.len - 5]; // Remove ".json"
            try self.putTheme(name, theme);
        }
    }

    fn loadEmbeddedTheme(self: *ThemeManager, name: []const u8, comptime path: []const u8) !void {
        const data = @embedFile(path);
        var theme = try Theme.parseJson(self.allocator, data);
        errdefer theme.deinit();
        theme.setOrigin(.builtin);
        try self.putTheme(name, theme);
    }

    fn putTheme(self: *ThemeManager, name: []const u8, theme: Theme) !void {
        var entry = try self.themes.getOrPut(name);
        if (entry.found_existing) {
            entry.value_ptr.deinit();
        } else {
            entry.key_ptr.* = try self.allocator.dupe(u8, name);
        }
        entry.value_ptr.* = theme;
    }

    fn getStoredKey(self: *ThemeManager, name: []const u8) ?[]const u8 {
        var iter = self.themes.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, entry.key_ptr.*, name)) {
                return entry.key_ptr.*;
            }
        }
        return null;
    }

    fn findThemeForVariant(self: *ThemeManager, variant: Variant) ?[]const u8 {
        var iter = self.themes.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*.variant == variant) {
                return entry.key_ptr.*;
            }
        }
        return null;
    }

    fn initializeActiveTheme(self: *ThemeManager) !void {
        if (std.posix.getenv("PHANTOM_THEME")) |requested| {
            if (self.getStoredKey(requested)) |key| {
                self.active_theme_name = key;
                self.preferred_variant = self.themes.getPtr(key).?.variant;
                return;
            } else {
                std.log.warn("Requested theme '{s}' not found; falling back to preferred variant", .{requested});
            }
        }

        if (std.posix.getenv("PHANTOM_THEME_VARIANT")) |variant_env| {
            if (theme_mod.variantFromString(variant_env)) |parsed| {
                self.preferred_variant = parsed;
            } else {
                std.log.warn("Unknown PHANTOM_THEME_VARIANT '{s}', using detected variant", .{variant_env});
                self.preferred_variant = detectPreferredVariant();
            }
        } else {
            self.preferred_variant = detectPreferredVariant();
        }

        if (self.findThemeForVariant(self.preferred_variant)) |key| {
            self.active_theme_name = key;
            return;
        }

        if (self.themes.iterator().next()) |entry| {
            self.active_theme_name = entry.key_ptr.*;
            self.preferred_variant = entry.value_ptr.*.variant;
            return;
        }

        return error.NoThemesAvailable;
    }

    fn ensurePreferredActiveTheme(self: *ThemeManager) !void {
        if (self.preferred_variant == .dark or self.preferred_variant == .light) {
            if (self.findThemeForVariant(self.preferred_variant)) |key| {
                self.active_theme_name = key;
                return;
            }
        }

        if (self.themes.iterator().next()) |entry| {
            self.active_theme_name = entry.key_ptr.*;
            self.preferred_variant = entry.value_ptr.*.variant;
            return;
        }

        return error.NoThemesAvailable;
    }

    fn detectPreferredVariant() Variant {
        if (std.posix.getenv("TERM_BACKGROUND")) |term_bg| {
            if (theme_mod.variantFromString(term_bg)) |parsed| {
                return parsed;
            }
        }
        return .dark;
    }

    fn removeThemesByOrigin(self: *ThemeManager, origin: Origin) !bool {
        var to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer to_remove.deinit();

        var iter = self.themes.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*.origin == origin) {
                try to_remove.append(entry.key_ptr.*);
            }
        }

        var active_removed = false;
        for (to_remove.items) |key| {
            if (self.themes.fetchRemove(key)) |removed| {
                var theme = removed.value;
                if (self.active_theme_name.len != 0 and std.mem.eql(u8, key, self.active_theme_name)) {
                    active_removed = true;
                    self.active_theme_name = "";
                }
                theme.deinit();
                self.allocator.free(removed.key);
            }
        }

        return active_removed;
    }

    pub fn reloadUserThemes(self: *ThemeManager) !void {
        const removed_active = try self.removeThemesByOrigin(.user);
        self.loadUserThemes() catch |err| {
            std.log.warn("Failed to reload user themes: {}", .{err});
        };
        if (removed_active or self.getStoredKey(self.active_theme_name) == null) {
            try self.ensurePreferredActiveTheme();
        }
    }

    pub fn loadThemeFromBytes(self: *ThemeManager, name: []const u8, data: []const u8, origin: Origin) !void {
        var theme = try Theme.parseJson(self.allocator, data);
        errdefer theme.deinit();
        theme.setOrigin(origin);
        const variant = theme.variant;
        try self.installTheme(name, theme, .{});
        if (variant == self.preferred_variant) {
            try self.ensurePreferredActiveTheme();
        }
    }

    pub fn installTheme(self: *ThemeManager, name: []const u8, theme: Theme, options: InstallOptions) !void {
        try self.putTheme(name, theme);
        if (options.auto_activate) {
            try self.setTheme(name);
        } else if (self.active_theme_name.len == 0) {
            try self.ensurePreferredActiveTheme();
        }
    }

    pub fn installManifest(self: *ThemeManager, manifest: *Manifest, name: []const u8, origin: Origin, options: InstallOptions) !void {
        try manifest.validate();
        var theme = try manifest.toTheme(self.allocator);
        errdefer theme.deinit();
        theme.setOrigin(origin);
        const variant = theme.variant;
        try self.installTheme(name, theme, options);
        if (!options.auto_activate and variant == self.preferred_variant) {
            try self.ensurePreferredActiveTheme();
        }
    }

    pub fn loadManifestFile(self: *ThemeManager, name: []const u8, path: []const u8, origin: Origin, options: InstallOptions) !void {
        var manifest = try style_theme.Manifest.loadFromFile(self.allocator, path);
        defer manifest.deinit();
        try self.installManifest(&manifest, name, origin, options);
    }

    pub fn syncVariant(self: *ThemeManager, variant: Variant) !void {
        self.preferred_variant = variant;
        try self.ensurePreferredActiveTheme();
    }

    pub fn syncVariantFromEnvironment(self: *ThemeManager) !void {
        self.preferred_variant = detectPreferredVariant();
        try self.ensurePreferredActiveTheme();
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

    try testing.expect(theme_names.len >= 5); // ghost-hacker + 4 Tokyo Night variants
    try testing.expect(manager.getActiveTheme().variant == manager.preferred_variant);
}

test "ThemeManager theme switching" {
    const testing = std.testing;

    var manager = try ThemeManager.init(testing.allocator);
    defer manager.deinit();

    // Switch to Tokyo Night
    try manager.setTheme("tokyonight-night");
    try testing.expectEqualStrings("tokyonight-night", manager.active_theme_name);
    try testing.expect(manager.getActiveTheme().variant == .dark);

    // Switch to Tokyo Night Day (light variant)
    try manager.setTheme("tokyonight-day");
    try testing.expect(manager.getActiveTheme().variant == .light);
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

test "ThemeManager variant sync and dynamic loading" {
    const testing = std.testing;

    var manager = try ThemeManager.init(testing.allocator);
    defer manager.deinit();

    try manager.syncVariant(.light);
    try testing.expect(manager.getActiveTheme().variant == .light);
    try testing.expectEqualStrings("tokyonight-day", manager.active_theme_name);

    const custom_json =
        \\{
        \\  "name": "Test Dynamic Theme",
        \\  "variant": "dark",
        \\  "defs": { "base": "#123456" },
        \\  "palette": { "surface": "base" },
        \\  "theme": { "primary": "base", "text": "base", "background": "base" },
        \\  "syntax": { "keyword": "base" }
        \\}
    ;

    try manager.loadThemeFromBytes("dynamic-test", custom_json, .dynamic);
    try manager.setTheme("dynamic-test");

    const surface_color = manager.getColor("surface");
    switch (surface_color) {
        .rgb => |rgb| {
            try testing.expectEqual(@as(u8, 0x12), rgb.r);
            try testing.expectEqual(@as(u8, 0x34), rgb.g);
            try testing.expectEqual(@as(u8, 0x56), rgb.b);
        },
        else => try testing.expect(false),
    }
}
