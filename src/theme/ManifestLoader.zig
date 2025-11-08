//! Runtime theme manifest loader with hot-swap support
const std = @import("std");
const theme_manager = @import("ThemeManager.zig");
const ThemeManager = theme_manager.ThemeManager;
const Origin = @import("Theme.zig").Origin;
const InstallOptions = ThemeManager.InstallOptions;
const style_theme = @import("../style/theme.zig");

const log = std.log.scoped(.theme_manifest);

pub const ManifestLoader = struct {
    allocator: std.mem.Allocator,
    manager: *ThemeManager,
    entries: std.ArrayList(Entry),

    pub const Entry = struct {
        name: []const u8,
        path: []const u8,
        origin: Origin,
        auto_activate: bool,
        last_stat: ?std.fs.File.Stat = null,
    };

    pub const RegisterOptions = struct {
        origin: Origin = .dynamic,
        auto_activate: bool = true,
    };

    pub const Error = error{ManifestNotRegistered};

    pub fn init(allocator: std.mem.Allocator, manager: *ThemeManager) ManifestLoader {
        return ManifestLoader{
            .allocator = allocator,
            .manager = manager,
            .entries = std.ArrayList(Entry).init(allocator),
        };
    }

    pub fn deinit(self: *ManifestLoader) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.path);
        }
        self.entries.deinit();
    }

    pub fn registerFile(self: *ManifestLoader, name: []const u8, path: []const u8, options: RegisterOptions) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        try self.entries.append(.{
            .name = owned_name,
            .path = owned_path,
            .origin = options.origin,
            .auto_activate = options.auto_activate,
            .last_stat = null,
        });
        errdefer {
            const removed = self.entries.pop();
            self.allocator.free(removed.name);
            self.allocator.free(removed.path);
        }

        const entry = &self.entries.items[self.entries.items.len - 1];
        try self.reloadEntry(entry, null);
        log.info("registered theme manifest '{s}' from {s}", .{ entry.name, entry.path });
    }

    pub fn refresh(self: *ManifestLoader) void {
        for (self.entries.items) |*entry| {
            const stat = std.fs.cwd().statFile(entry.path) catch |err| {
                log.warn("failed to stat manifest {s}: {}", .{ entry.path, err });
                continue;
            };

            if (entry.last_stat) |last| {
                if (statsEqual(last, stat)) continue;
            }

            self.reloadEntry(entry, stat) catch |err| {
                log.err("failed to reload manifest {s}: {}", .{ entry.path, err });
                continue;
            };
            log.info("reloaded theme manifest '{s}'", .{entry.name});
        }
    }

    pub fn forceReload(self: *ManifestLoader, name: []const u8) !void {
        const entry = self.findEntry(name) orelse return Error.ManifestNotRegistered;
        try self.reloadEntry(entry, null);
    }

    fn findEntry(self: *ManifestLoader, name: []const u8) ?*Entry {
        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry;
        }
        return null;
    }

    fn reloadEntry(self: *ManifestLoader, entry: *Entry, stat_hint: ?std.fs.File.Stat) !void {
        var manifest = try style_theme.Manifest.loadFromFile(self.allocator, entry.path);
        defer manifest.deinit();

        try self.manager.installManifest(&manifest, entry.name, entry.origin, .{
            .auto_activate = entry.auto_activate,
        });

        const stat = stat_hint orelse try std.fs.cwd().statFile(entry.path);
        entry.last_stat = stat;
    }
};

fn statsEqual(a: std.fs.File.Stat, b: std.fs.File.Stat) bool {
    return a.size == b.size and a.mtime.sec == b.mtime.sec and a.mtime.nsec == b.mtime.nsec;
}

// Tests
const testing = std.testing;

fn expectAccent(color: @import("../style.zig").Color, expected: struct { r: u8, g: u8, b: u8 }) !void {
    switch (color) {
        .rgb => |rgb| {
            try testing.expectEqual(expected.r, rgb.r);
            try testing.expectEqual(expected.g, rgb.g);
            try testing.expectEqual(expected.b, rgb.b);
        },
        else => try testing.expect(false),
    }
}

test "ManifestLoader registers and refreshes themes" {
    var tmp = try testing.tmpDir(.{});
    defer tmp.cleanup();

    const initial_json =
        \\\{
        \\  "name": "Runtime Theme",
        \\  "variant": "dark",
        \\  "palette": {
        \\    "background": "#000000",
        \\    "surface": "#111111",
        \\    "surface_alt": "#222222",
        \\    "accent": "#123456",
        \\    "accent_hover": "#234567",
        \\    "text": "#ffffff",
        \\    "text_muted": "#cccccc",
        \\    "border": "#444444"
        \\  },
        \\  "tokens": {
        \\    "background": "background",
        \\    "surface": "surface",
        \\    "surface_alt": "surface_alt",
        \\    "accent": "accent",
        \\    "accent_hover": "accent_hover",
        \\    "text": "text",
        \\    "text_muted": "text_muted",
        \\    "border": "border"
        \\  }
        \\}
    ;

    try tmp.dir.writeFile("runtime.json", initial_json);
    const manifest_path = try tmp.dir.realpathAlloc(testing.allocator, "runtime.json");
    defer testing.allocator.free(manifest_path);

    var manager = try ThemeManager.init(testing.allocator);
    defer manager.deinit();

    var loader = ManifestLoader.init(testing.allocator, manager);
    defer loader.deinit();

    try loader.registerFile("runtime-night", manifest_path, .{ .origin = .dynamic, .auto_activate = true });

    try expectAccent(manager.getColor("accent"), .{ .r = 0x12, .g = 0x34, .b = 0x56 });

    const updated_json =
        \\\{
        \\  "name": "Runtime Theme",
        \\  "variant": "dark",
        \\  "palette": {
        \\    "background": "#000000",
        \\    "surface": "#111111",
        \\    "surface_alt": "#333333",
        \\    "accent": "#654321",
        \\    "accent_hover": "#712345",
        \\    "text": "#ffffff",
        \\    "text_muted": "#bbbbbb",
        \\    "border": "#555555"
        \\  },
        \\  "tokens": {
        \\    "background": "background",
        \\    "surface": "surface",
        \\    "surface_alt": "surface_alt",
        \\    "accent": "accent",
        \\    "accent_hover": "accent_hover",
        \\    "text": "text",
        \\    "text_muted": "text_muted",
        \\    "border": "border"
        \\  }
        \\}
    ;

    try std.time.sleep(std.time.ns_per_ms * 2);
    try tmp.dir.writeFile("runtime.json", updated_json);

    loader.refresh();

    try expectAccent(manager.getColor("accent"), .{ .r = 0x65, .g = 0x43, .b = 0x21 });
}
