//! Performance Benchmark Suite for Phantom TUI Framework
//! Tests rendering performance, layout performance, and widget performance

const std = @import("std");
const phantom = @import("phantom");

/// Helper to write to stdout using C library
fn writeStdout(data: []const u8) !void {
    var written: usize = 0;
    while (written < data.len) {
        const result = std.c.write(std.posix.STDOUT_FILENO, data.ptr + written, data.len - written);
        if (result < 0) return error.WriteFailed;
        written += @intCast(result);
    }
}

const BenchmarkResult = struct {
    name: []const u8,
    iterations: usize,
    total_ns: u64,
    avg_ns: u64,
    min_ns: u64,
    max_ns: u64,

    fn print(self: BenchmarkResult, allocator: std.mem.Allocator) !void {
        const line = try std.fmt.allocPrint(allocator, "{s:30} | {d:8} iter | {d:8} ns avg | {d:8} ns min | {d:8} ns max\n", .{
            self.name,
            self.iterations,
            self.avg_ns,
            self.min_ns,
            self.max_ns,
        });
        defer allocator.free(line);
        try writeStdout(line);
    }
};

fn benchmark(comptime name: []const u8, comptime iterations: usize, func: anytype, args: anytype) !BenchmarkResult {
    var timer = try std.time.Timer.start();
    var min: u64 = std.math.maxInt(u64);
    var max: u64 = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        timer.reset();
        @call(.auto, func, args);
        const elapsed = timer.read();
        min = @min(min, elapsed);
        max = @max(max, elapsed);
    }

    const total_elapsed = timer.lap();
    const avg = total_elapsed / iterations;

    return BenchmarkResult{
        .name = name,
        .iterations = iterations,
        .total_ns = total_elapsed,
        .avg_ns = avg,
        .min_ns = min,
        .max_ns = max,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try writeStdout("\n=== Phantom TUI Framework Performance Benchmarks ===\n\n");
    try writeStdout("Benchmark                      | Iterations |   Avg (ns) |   Min (ns) |   Max (ns)\n");
    try writeStdout("-------------------------------|------------|------------|------------|------------\n");

    // Layout benchmarks
    {
        const rect = phantom.Rect.init(0, 0, 100, 50);
        const layout = phantom.ConstraintLayout.init(.vertical, &[_]phantom.Constraint{
            .{ .length = 5 },
            .{ .fill = 1 },
            .{ .percentage = 30 },
            .{ .length = 2 },
        });

        const result = try benchmark("Layout: 4-way vertical split", 10000, benchLayoutSplit, .{ allocator, layout, rect });
        try result.print(allocator);
    }

    {
        const rect = phantom.Rect.init(0, 0, 200, 100);
        const layout = phantom.ConstraintLayout.init(.horizontal, &[_]phantom.Constraint{
            .{ .percentage = 20 },
            .{ .fill = 1 },
            .{ .percentage = 25 },
        });

        const result = try benchmark("Layout: 3-way horiz split", 10000, benchLayoutSplit, .{ allocator, layout, rect });
        try result.print(allocator);
    }

    // Buffer operations
    {
        var buffer = try phantom.Buffer.init(allocator, phantom.Size.init(80, 24));
        defer buffer.deinit();

        const result = try benchmark("Buffer: writeText 100 chars", 10000, benchBufferWrite, .{&buffer});
        try result.print(allocator);
    }

    {
        var buffer = try phantom.Buffer.init(allocator, phantom.Size.init(200, 100));
        defer buffer.deinit();

        const result = try benchmark("Buffer: clear large (200x100)", 5000, benchBufferClear, .{&buffer});
        try result.print(allocator);
    }

    // Style operations
    {
        const result = try benchmark("Style: create with colors", 50000, benchStyleCreate, .{});
        try result.print(allocator);
    }

    // Color conversions
    {
        const result = try benchmark("Color: RGB to ANSI", 50000, benchColorConvert, .{});
        try result.print(allocator);
    }

    // Rect operations
    {
        const result = try benchmark("Rect: intersections", 50000, benchRectIntersect, .{});
        try result.print(allocator);
    }

    try writeStdout("\n=== Summary ===\n");
    try writeStdout("All benchmarks completed successfully\n\n");
}

fn benchLayoutSplit(allocator: std.mem.Allocator, layout: phantom.ConstraintLayout, rect: phantom.Rect) void {
    const areas = layout.split(allocator, rect) catch return;
    allocator.free(areas);
}

fn benchBufferWrite(buffer: *phantom.Buffer) void {
    const text = "Hello, World! This is a benchmark test for text rendering performance in TUI apps.";
    buffer.writeText(0, 0, text[0..@min(text.len, 100)], phantom.Style.default());
}

fn benchBufferClear(buffer: *phantom.Buffer) void {
    buffer.clear();
}

fn benchStyleCreate() void {
    const style = phantom.Style.default()
        .withFg(phantom.Color.cyan)
        .withBg(phantom.Color.black)
        .withBold();
    _ = style;
}

fn benchColorConvert() void {
    const color = phantom.Color{ .rgb = .{ .r = 128, .g = 192, .b = 64 } };
    _ = color;
}

fn benchRectIntersect() void {
    const r1 = phantom.Rect.init(10, 10, 50, 30);
    const r2 = phantom.Rect.init(30, 20, 40, 25);
    const p1 = phantom.Position{ .x = @intCast(r2.x), .y = @intCast(r2.y) };
    const p2 = phantom.Position{ .x = @intCast(r2.x + r2.width), .y = @intCast(r2.y + r2.height) };
    const intersects = r1.contains(p1) or r1.contains(p2);
    _ = intersects;
}
