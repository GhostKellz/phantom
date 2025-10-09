//! Unicode Performance Benchmarks
//! Compares gcode vs old unicode.zig implementation
//! Proves the value of the gcode integration

const std = @import("std");
const gcode = @import("gcode");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Phantom Unicode Performance Benchmarks ===\n\n", .{});

    // Test cases with different Unicode complexity
    const test_cases = [_]struct {
        name: []const u8,
        text: []const u8,
    }{
        .{ .name = "ASCII", .text = "The quick brown fox jumps over the lazy dog" ** 100 },
        .{ .name = "Mixed ASCII+Emoji", .text = "Hello 🌍! Welcome to Phantom 👻 TUI framework ⚡" ** 50 },
        .{ .name = "CJK", .text = "你好世界 こんにちは 안녕하세요 " ** 100 },
        .{ .name = "Arabic+BiDi", .text = "مرحبا بك في Phantom TUI Framework" ** 50 },
        .{ .name = "Complex Emoji", .text = "👨‍👩‍👧‍👦 👍🏽 🏳️‍🌈 🇺🇸" ** 100 },
        .{ .name = "Combining Marks", .text = "e\u{0301}l\u{0301}i\u{0301}t\u{0301}e\u{0301}" ** 200 },
    };

    for (test_cases) |test_case| {
        std.debug.print("--- {s} ---\n", .{test_case.name});

        // Benchmark gcode string width
        const gcode_time = try benchmarkGcodeWidth(test_case.text, 1000);
        std.debug.print("  gcode stringWidth: {d:.2}ns/iter\n", .{gcode_time});

        // Benchmark old unicode width
        const old_unicode_time = try benchmarkOldUnicodeWidth(test_case.text, 1000);
        std.debug.print("  old unicode.zig:   {d:.2}ns/iter\n", .{old_unicode_time});

        const speedup = old_unicode_time / gcode_time;
        std.debug.print("  Speedup: {d:.2}x faster\n\n", .{speedup});
    }

    // Grapheme clustering benchmarks
    std.debug.print("\n--- Grapheme Clustering ---\n", .{});
    const grapheme_text = "Hello 👨‍👩‍👧‍👦 World 🏳️‍🌈!" ** 100;

    const gcode_grapheme_time = try benchmarkGcodeGraphemes(allocator, grapheme_text, 100);
    std.debug.print("  gcode graphemes: {d:.2}μs/iter\n", .{gcode_grapheme_time / 1000.0});

    // Word boundary benchmarks
    std.debug.print("\n--- Word Boundary Detection ---\n", .{});
    const word_text = "The quick brown fox jumps over the lazy dog." ** 50;

    const gcode_word_time = try benchmarkGcodeWords(word_text, 100);
    std.debug.print("  gcode word iter: {d:.2}μs/iter\n", .{gcode_word_time / 1000.0});

    std.debug.print("\n=== Benchmark Complete ===\n", .{});
}

fn benchmarkGcodeWidth(text: []const u8, iterations: usize) !f64 {
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = gcode.stringWidth(text);
    }

    const elapsed = timer.read();
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(iterations));
}

fn benchmarkOldUnicodeWidth(text: []const u8, iterations: usize) !f64 {
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        // Use old unicode.zig implementation
        _ = try phantom.unicode.UnicodeWidth.stringWidth(text);
    }

    const elapsed = timer.read();
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(iterations));
}

fn benchmarkGcodeGraphemes(allocator: std.mem.Allocator, text: []const u8, iterations: usize) !f64 {
    _ = allocator;
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var iter = gcode.graphemeIterator(text);
        while (iter.next()) |_| {
            // Count graphemes
        }
    }

    const elapsed = timer.read();
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(iterations));
}

fn benchmarkGcodeWords(text: []const u8, iterations: usize) !f64 {
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var iter = gcode.wordIterator(text);
        while (iter.next()) |_| {
            // Count words
        }
    }

    const elapsed = timer.read();
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(iterations));
}
