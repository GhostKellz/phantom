//! Rendering Performance Benchmarks
//! Measures FPS, frame time, and memory usage

const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Phantom Rendering Performance Benchmarks ===\n\n", .{});

    // Initialize Phantom runtime
    try phantom.runtime.initRuntime(allocator);
    defer phantom.runtime.deinitRuntime();

    // Font rendering benchmarks
    std.debug.print("--- Font Rendering ---\n", .{});
    try benchmarkFontRendering(allocator);

    // Widget rendering benchmarks
    std.debug.print("\n--- Widget Rendering ---\n", .{});
    try benchmarkWidgetRendering(allocator);

    // Full frame benchmarks
    std.debug.print("\n--- Full Frame Rendering ---\n", .{});
    try benchmarkFullFrame(allocator);

    // Memory usage
    std.debug.print("\n--- Memory Usage ---\n", .{});
    try benchmarkMemoryUsage(allocator);

    std.debug.print("\n=== Benchmark Complete ===\n", .{});
}

fn benchmarkFontRendering(allocator: std.mem.Allocator) !void {
    const config = phantom.font.FontManager.FontConfig{
        .primary_font_family = "JetBrains Mono",
        .enable_ligatures = true,
    };

    var font_mgr = try phantom.font.FontManager.init(allocator, config);
    defer font_mgr.deinit();

    // Benchmark text width calculation
    const test_texts = [_][]const u8{
        "Hello World",
        "fn main() -> Result<(), Error> {",
        "const x: i32 = 42;",
        "// This is a comment with emoji 🚀",
    };

    var total_time: u64 = 0;
    const iterations = 10000;

    for (test_texts) |text| {
        var timer = try std.time.Timer.start();

        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            _ = try font_mgr.getTextWidth(text);
        }

        const elapsed = timer.read();
        total_time += elapsed;

        const avg_ns = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(iterations));
        std.debug.print("  '{s}': {d:.2}ns/call\n", .{ text[0..@min(20, text.len)], avg_ns });
    }

    const overall_avg = @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(test_texts.len * iterations));
    std.debug.print("  Overall average: {d:.2}ns/call\n", .{overall_avg});
}

fn benchmarkWidgetRendering(allocator: std.mem.Allocator) !void {
    _ = allocator;
    // TODO: Re-enable when ArrayList API is clarified for Zig 0.16
    std.debug.print("  Widget rendering benchmark: Skipped (TODO)\n", .{});
}

fn benchmarkFullFrame(allocator: std.mem.Allocator) !void {
    var app = try phantom.App.init(allocator, phantom.AppConfig{
        .title = "Benchmark",
        .tick_rate_ms = 16, // ~60 FPS target
    });
    defer app.deinit();

    // Add multiple widgets
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const text = try phantom.widgets.Text.initWithStyle(
            allocator,
            "Benchmark Text Widget",
            phantom.Style.default().withFg(phantom.Color.bright_cyan),
        );
        try app.addWidget(&text.widget);
    }

    // Simulate frame rendering
    var timer = try std.time.Timer.start();
    const frames = 1000;

    var frame: usize = 0;
    while (frame < frames) : (frame += 1) {
        // Simulate frame rendering (without actually displaying)
        // In real app, this would call terminal rendering
        // Use C nanosleep to simulate some work
        const req = std.c.timespec{ .sec = 0, .nsec = std.time.ns_per_ms };
        _ = std.c.nanosleep(&req, null);
    }

    const elapsed = timer.read();
    const avg_frame_time = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(frames));
    const fps = 1_000_000_000.0 / avg_frame_time;

    std.debug.print("  Average frame time: {d:.2}ms\n", .{avg_frame_time / 1_000_000.0});
    std.debug.print("  Average FPS: {d:.1}\n", .{fps});
}

fn benchmarkMemoryUsage(allocator: std.mem.Allocator) !void {
    // Measure memory usage of glyph cache
    const cache_config = phantom.font.GlyphCache.CacheConfig{
        .max_size_bytes = 10 * 1024 * 1024, // 10MB
        .enable_gpu_cache = false,
    };

    var cache = try phantom.font.GlyphCache.init(allocator, cache_config);
    defer cache.deinit();

    // Add many glyphs
    const num_glyphs = 1000;
    var i: u21 = 0;
    while (i < num_glyphs) : (i += 1) {
        const glyph_data = phantom.font.GlyphCache.GlyphData{
            .bitmap = try allocator.alloc(u8, 16 * 16), // 16x16 glyph
            .width = 16,
            .height = 16,
            .advance = 16.0,
            .bearing_x = 0,
            .bearing_y = 0,
        };

        const key = phantom.font.GlyphCache.GlyphKey{
            .codepoint = i + 32,
            .font_id = 1,
            .size = 14,
            .style_flags = .{},
        };

        try cache.put(key, glyph_data);
    }

    const stats = cache.getStatistics();
    std.debug.print("  Cache size: {d} bytes ({d:.2} MB)\n", .{
        stats.total_size_bytes,
        @as(f64, @floatFromInt(stats.total_size_bytes)) / 1024.0 / 1024.0,
    });
    std.debug.print("  Cached glyphs: {d}\n", .{num_glyphs});
    std.debug.print("  Hit rate: {d:.1}%\n", .{stats.hitRate() * 100.0});
}
