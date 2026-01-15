//! Comprehensive memory leak tests for Phantom
//! Run with: zig build test-memory
//! Uses GeneralPurposeAllocator with leak detection enabled

const std = @import("std");
const phantom = @import("phantom");
const Theme = phantom.theme.Theme;
const ThemeManager = phantom.theme.ThemeManager;
const ManifestLoader = phantom.theme.ManifestLoader;
const style_theme = phantom.style_theme;

/// Test allocator that detects leaks
fn getTestAllocator() std.heap.GeneralPurposeAllocator(.{
    .stack_trace_frames = 10,
    .safety = true,
    .never_unmap = true,
}) {
    return .{};
}

test "Theme parsing and cleanup - no leaks" {
    var gpa = getTestAllocator();
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("LEAK DETECTED in Theme parsing test!\n", .{});
            @panic("Memory leak detected");
        }
    }
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "name": "test-theme",
        \\  "description": "A test theme",
        \\  "variant": "dark",
        \\  "colors": {
        \\    "accent": "#ff5500",
        \\    "background": "#1a1a1a",
        \\    "foreground": "#ffffff"
        \\  }
        \\}
    ;

    // Parse and immediately deinit
    {
        var theme = try Theme.parseJson(allocator, json);
        defer theme.deinit();

        // Access some fields to ensure they're properly allocated
        _ = theme.getColor("accent");
        _ = theme.getColor("background");
        _ = theme.isDark();
    }

    // Parse multiple times to stress test
    for (0..100) |_| {
        var theme = try Theme.parseJson(allocator, json);
        theme.deinit();
    }
}

test "Theme with setName/setDescription - no leaks" {
    var gpa = getTestAllocator();
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("LEAK DETECTED in Theme setName test!\n", .{});
            @panic("Memory leak detected");
        }
    }
    const allocator = gpa.allocator();

    var theme = Theme.init(allocator);
    defer theme.deinit();

    // Set and override name multiple times (tests reallocation)
    for (0..50) |i| {
        var buf: [64]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "theme-name-iteration-{d}", .{i}) catch unreachable;
        try theme.setName(name);
    }

    // Set and override description multiple times
    for (0..50) |i| {
        var buf: [128]u8 = undefined;
        const desc = std.fmt.bufPrint(&buf, "This is description iteration number {d} with some padding text", .{i}) catch unreachable;
        try theme.setDescription(desc);
    }
}

test "ThemeManager lifecycle - no leaks" {
    var gpa = getTestAllocator();
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("LEAK DETECTED in ThemeManager test!\n", .{});
            @panic("Memory leak detected");
        }
    }
    const allocator = gpa.allocator();

    // Create and destroy manager multiple times
    for (0..10) |_| {
        var manager = try ThemeManager.init(allocator);
        defer manager.deinit();

        // Access theme to ensure internal structures are allocated
        _ = manager.getActiveTheme();
    }
}

test "Manifest parsing - no leaks" {
    var gpa = getTestAllocator();
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("LEAK DETECTED in Manifest parsing test!\n", .{});
            @panic("Memory leak detected");
        }
    }
    const allocator = gpa.allocator();

    const manifest_json =
        \\{
        \\  "name": "test-manifest",
        \\  "version": "1.0.0",
        \\  "palette": {
        \\    "bg": "#1a1a2e",
        \\    "fg": "#eaeaea"
        \\  },
        \\  "themes": {
        \\    "light": {
        \\      "variant": "light",
        \\      "colors": {
        \\        "background": "#ffffff",
        \\        "foreground": "#000000"
        \\      }
        \\    },
        \\    "dark": {
        \\      "variant": "dark",
        \\      "colors": {
        \\        "background": "#000000",
        \\        "foreground": "#ffffff"
        \\      }
        \\    }
        \\  }
        \\}
    ;

    // Parse and cleanup multiple times
    for (0..50) |_| {
        var manifest = try style_theme.Manifest.parse(allocator, manifest_json);
        manifest.deinit();
    }
}

test "ManifestLoader with ThemeManager - no leaks" {
    var gpa = getTestAllocator();
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("LEAK DETECTED in ManifestLoader test!\n", .{});
            @panic("Memory leak detected");
        }
    }
    const allocator = gpa.allocator();

    var manager = try ThemeManager.init(allocator);
    defer manager.deinit();

    // Create and destroy loader multiple times
    for (0..10) |_| {
        var loader = ManifestLoader.init(allocator, manager);
        defer loader.deinit();

        // Refresh (no files registered, but exercises the code path)
        loader.refresh();
    }
}

test "Stress test - rapid allocation/deallocation cycles" {
    var gpa = getTestAllocator();
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("LEAK DETECTED in stress test!\n", .{});
            @panic("Memory leak detected");
        }
    }
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "name": "stress-theme",
        \\  "variant": "dark",
        \\  "colors": {
        \\    "c1": "#111111", "c2": "#222222", "c3": "#333333",
        \\    "c4": "#444444", "c5": "#555555", "c6": "#666666"
        \\  }
        \\}
    ;

    // Rapid create/destroy cycles
    for (0..500) |_| {
        var theme = try Theme.parseJson(allocator, json);
        theme.deinit();
    }

    // Interleaved allocations
    var themes: [10]?Theme = [_]?Theme{null} ** 10;
    defer {
        for (&themes) |*t| {
            if (t.*) |*theme| {
                theme.deinit();
                t.* = null;
            }
        }
    }

    for (0..100) |i| {
        const idx = i % 10;
        if (themes[idx]) |*t| {
            t.deinit();
        }
        themes[idx] = try Theme.parseJson(allocator, json);
    }
}

test "Component styles - no leaks" {
    var gpa = getTestAllocator();
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("LEAK DETECTED in component styles test!\n", .{});
            @panic("Memory leak detected");
        }
    }
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "name": "component-test",
        \\  "variant": "dark",
        \\  "colors": { "accent": "#ff0000" },
        \\  "components": {
        \\    "button": { "foreground": "accent", "bold": true },
        \\    "input": { "background": "#333333", "italic": true }
        \\  }
        \\}
    ;

    for (0..100) |_| {
        var theme = try Theme.parseJson(allocator, json);
        defer theme.deinit();

        // Access component styles
        _ = theme.getComponentStyle("button");
        _ = theme.getComponentStyle("input");
        _ = theme.resolveComponentStyle("button");
    }
}
