//! XDG Base Directory Specification Support
//! Provides standard paths for configuration, data, and cache

const std = @import("std");

/// Resource paths following XDG Base Directory spec
pub const ResourcePaths = struct {
    allocator: std.mem.Allocator,
    config_dir: []const u8,
    data_dir: []const u8,
    cache_dir: []const u8,
    theme_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, app_name: []const u8) !*ResourcePaths {
        const self = try allocator.create(ResourcePaths);
        errdefer allocator.destroy(self);

        const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;

        // XDG Base Directory Specification
        const config_home = std.posix.getenv("XDG_CONFIG_HOME") orelse blk: {
            break :blk try std.fs.path.join(allocator, &[_][]const u8{ home, ".config" });
        };
        const config_home_allocated = std.posix.getenv("XDG_CONFIG_HOME") == null;
        defer if (config_home_allocated) allocator.free(config_home);

        const data_home = std.posix.getenv("XDG_DATA_HOME") orelse blk: {
            break :blk try std.fs.path.join(allocator, &[_][]const u8{ home, ".local/share" });
        };
        const data_home_allocated = std.posix.getenv("XDG_DATA_HOME") == null;
        defer if (data_home_allocated) allocator.free(data_home);

        const cache_home = std.posix.getenv("XDG_CACHE_HOME") orelse blk: {
            break :blk try std.fs.path.join(allocator, &[_][]const u8{ home, ".cache" });
        };
        const cache_home_allocated = std.posix.getenv("XDG_CACHE_HOME") == null;
        defer if (cache_home_allocated) allocator.free(cache_home);

        const config_dir = try std.fs.path.join(allocator, &[_][]const u8{ config_home, app_name });
        const data_dir = try std.fs.path.join(allocator, &[_][]const u8{ data_home, app_name });
        const cache_dir = try std.fs.path.join(allocator, &[_][]const u8{ cache_home, app_name });
        const theme_dir = try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "themes" });

        // Create directories if they don't exist
        std.fs.cwd().makePath(config_dir) catch {};
        std.fs.cwd().makePath(data_dir) catch {};
        std.fs.cwd().makePath(cache_dir) catch {};
        std.fs.cwd().makePath(theme_dir) catch {};

        self.* = ResourcePaths{
            .allocator = allocator,
            .config_dir = config_dir,
            .data_dir = data_dir,
            .cache_dir = cache_dir,
            .theme_dir = theme_dir,
        };

        return self;
    }

    pub fn deinit(self: *ResourcePaths) void {
        self.allocator.free(self.config_dir);
        self.allocator.free(self.data_dir);
        self.allocator.free(self.cache_dir);
        self.allocator.free(self.theme_dir);
        self.allocator.destroy(self);
    }

    /// Get path to config file
    pub fn getConfigPath(self: *ResourcePaths, filename: []const u8) ![]const u8 {
        return try std.fs.path.join(self.allocator, &[_][]const u8{ self.config_dir, filename });
    }

    /// Get path to data file
    pub fn getDataPath(self: *ResourcePaths, filename: []const u8) ![]const u8 {
        return try std.fs.path.join(self.allocator, &[_][]const u8{ self.data_dir, filename });
    }

    /// Get path to cache file
    pub fn getCachePath(self: *ResourcePaths, filename: []const u8) ![]const u8 {
        return try std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, filename });
    }

    /// Get path to theme file
    pub fn getThemePath(self: *ResourcePaths, filename: []const u8) ![]const u8 {
        return try std.fs.path.join(self.allocator, &[_][]const u8{ self.theme_dir, filename });
    }
};

// Tests
test "ResourcePaths initialization" {
    const testing = std.testing;

    var paths = try ResourcePaths.init(testing.allocator, "phantom");
    defer paths.deinit();

    // Should have created paths
    try testing.expect(paths.config_dir.len > 0);
    try testing.expect(paths.data_dir.len > 0);
    try testing.expect(paths.cache_dir.len > 0);
    try testing.expect(paths.theme_dir.len > 0);

    // Should end with "phantom"
    try testing.expect(std.mem.endsWith(u8, paths.config_dir, "phantom"));
}

test "ResourcePaths getConfigPath" {
    const testing = std.testing;

    var paths = try ResourcePaths.init(testing.allocator, "phantom");
    defer paths.deinit();

    const config_path = try paths.getConfigPath("test.json");
    defer testing.allocator.free(config_path);

    try testing.expect(std.mem.endsWith(u8, config_path, "test.json"));
}
