//! Histogram Widget - Frequency distribution of raw samples
//! Unlike BarChart (which plots pre-computed values), Histogram bins a set of
//! raw samples into equal-width buckets and renders the per-bucket counts.

const std = @import("std");
const phantom = @import("../root.zig");
const Rect = phantom.Rect;
const Position = phantom.Position;
const Color = phantom.Color;
const Style = phantom.Style;
const Buffer = phantom.Buffer;
const Cell = phantom.Cell;

/// Configuration for Histogram widget
pub const HistogramConfig = struct {
    /// Number of equal-width buckets to distribute samples across.
    bins: usize = 10,
    /// Fixed lower bound; when null, derived from the samples.
    min: ?f64 = null,
    /// Fixed upper bound; when null, derived from the samples.
    max: ?f64 = null,
    title: ?[]const u8 = null,
    color: Color = Color.cyan,
    show_axis: bool = true,
    show_counts: bool = true,
    title_style: Style = Style.default().withBold(),
    axis_style: Style = Style.default(),

    pub fn default() HistogramConfig {
        return .{};
    }
};

pub const Error = error{
    InvalidBinCount,
} || std.mem.Allocator.Error;

/// Histogram widget for frequency distributions
pub const Histogram = struct {
    allocator: std.mem.Allocator,
    samples: std.ArrayList(f64),
    bins: usize,
    min_override: ?f64,
    max_override: ?f64,
    title: ?[]const u8,
    color: Color,
    show_axis: bool,
    show_counts: bool,
    title_style: Style,
    axis_style: Style,

    /// Initialize Histogram with config
    pub fn init(allocator: std.mem.Allocator, config: HistogramConfig) Error!Histogram {
        if (config.bins == 0) return Error.InvalidBinCount;
        return Histogram{
            .allocator = allocator,
            .samples = .empty,
            .bins = config.bins,
            .min_override = config.min,
            .max_override = config.max,
            .title = config.title,
            .color = config.color,
            .show_axis = config.show_axis,
            .show_counts = config.show_counts,
            .title_style = config.title_style,
            .axis_style = config.axis_style,
        };
    }

    pub fn deinit(self: *Histogram) void {
        self.samples.deinit(self.allocator);
    }

    /// Add a single sample.
    pub fn addSample(self: *Histogram, value: f64) !void {
        try self.samples.append(self.allocator, value);
    }

    /// Add many samples at once.
    pub fn addSamples(self: *Histogram, values: []const f64) !void {
        try self.samples.appendSlice(self.allocator, values);
    }

    /// Data range, honoring configured overrides.
    fn bounds(self: *const Histogram) struct { min: f64, max: f64 } {
        var lo: f64 = std.math.floatMax(f64);
        var hi: f64 = -std.math.floatMax(f64);
        for (self.samples.items) |v| {
            if (v < lo) lo = v;
            if (v > hi) hi = v;
        }
        if (self.min_override) |m| lo = m;
        if (self.max_override) |m| hi = m;
        return .{ .min = lo, .max = hi };
    }

    /// Bin the samples into `counts`, which must have length `self.bins`.
    /// Returns the largest bucket count.
    pub fn computeBins(self: *const Histogram, counts: []usize) usize {
        std.debug.assert(counts.len == self.bins);
        @memset(counts, 0);
        if (self.samples.items.len == 0) return 0;

        const b = self.bounds();
        const range = b.max - b.min;

        var max_count: usize = 0;
        for (self.samples.items) |v| {
            if (v < b.min or v > b.max) continue; // Ignore out-of-range samples.
            const idx: usize = if (range == 0.0)
                0
            else blk: {
                const norm = (v - b.min) / range;
                const scaled: usize = @intFromFloat(norm * @as(f64, @floatFromInt(self.bins)));
                break :blk @min(scaled, self.bins - 1); // Clamp the max-value edge.
            };
            counts[idx] += 1;
            if (counts[idx] > max_count) max_count = counts[idx];
        }
        return max_count;
    }

    /// Render the Histogram
    pub fn render(self: *Histogram, buffer: *Buffer, area: Rect) void {
        if (self.samples.items.len == 0) return;
        if (area.width < 3 or area.height < 3) return;

        var render_area = area;

        // Title.
        if (self.title) |title| {
            const title_x = area.x + @divTrunc(area.width, 2) -
                @divTrunc(@as(u16, @intCast(title.len)), 2);
            buffer.writeText(title_x, area.y, title, self.title_style);
            render_area.y += 1;
            render_area.height = if (render_area.height > 1) render_area.height - 1 else 0;
        }

        const counts = self.allocator.alloc(usize, self.bins) catch return;
        defer self.allocator.free(counts);
        const max_count = self.computeBins(counts);
        if (max_count == 0) return;

        // Reserve one row at the bottom for the axis.
        const axis_height: u16 = if (self.show_axis) 1 else 0;
        const chart_height = if (render_area.height > axis_height)
            render_area.height - axis_height
        else
            1;

        // Distribute the bins across the available width.
        const bin_width = @max(1, @divTrunc(render_area.width, @as(u16, @intCast(self.bins))));
        const style = Style.default().withFg(self.color);

        for (counts, 0..) |count, i| {
            const bar_x = render_area.x + @as(u16, @intCast(i)) * bin_width;
            if (bar_x >= render_area.x + render_area.width) break;

            const bar_height = @as(u16, @intFromFloat(
                @as(f64, @floatFromInt(chart_height)) *
                    (@as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(max_count))),
            ));

            // Fill the bucket column(s) from the baseline up.
            var col: u16 = 0;
            while (col < bin_width and bar_x + col < render_area.x + render_area.width) : (col += 1) {
                var row: u16 = 0;
                while (row < bar_height) : (row += 1) {
                    const py = render_area.y + chart_height - 1 - row;
                    buffer.setCell(bar_x + col, py, Cell.init('█', style));
                }
            }

            // Optional count label above the bar.
            if (self.show_counts and count > 0 and bar_height < chart_height) {
                const label = std.fmt.allocPrint(self.allocator, "{d}", .{count}) catch continue;
                defer self.allocator.free(label);
                const label_y = render_area.y + chart_height - 1 - bar_height;
                buffer.writeText(bar_x, label_y, label, self.axis_style);
            }
        }

        // Baseline axis.
        if (self.show_axis) {
            const axis_y = render_area.y + chart_height;
            var x: u16 = render_area.x;
            while (x < render_area.x + render_area.width) : (x += 1) {
                buffer.setCell(x, axis_y, Cell.init('─', self.axis_style));
            }
        }
    }
};

// Tests
test "Histogram rejects zero bins" {
    const testing = std.testing;
    try testing.expectError(Error.InvalidBinCount, Histogram.init(testing.allocator, .{ .bins = 0 }));
}

test "Histogram bins samples into buckets" {
    const testing = std.testing;

    var hist = try Histogram.init(testing.allocator, .{ .bins = 5, .min = 0.0, .max = 10.0 });
    defer hist.deinit();

    // Two samples in [0,2), three in [8,10].
    try hist.addSamples(&[_]f64{ 0.0, 1.0, 8.0, 9.0, 10.0 });

    var counts: [5]usize = undefined;
    const max_count = hist.computeBins(&counts);

    try testing.expectEqual(@as(usize, 2), counts[0]); // 0.0, 1.0
    try testing.expectEqual(@as(usize, 3), counts[4]); // 8.0, 9.0, 10.0 (edge clamps)
    try testing.expectEqual(@as(usize, 3), max_count);
}

test "Histogram handles zero-range samples" {
    const testing = std.testing;

    var hist = try Histogram.init(testing.allocator, .{ .bins = 4 });
    defer hist.deinit();

    try hist.addSamples(&[_]f64{ 5.0, 5.0, 5.0 });

    var counts: [4]usize = undefined;
    const max_count = hist.computeBins(&counts);
    try testing.expectEqual(@as(usize, 3), counts[0]);
    try testing.expectEqual(@as(usize, 3), max_count);
}

test "Histogram renders bars" {
    const testing = std.testing;

    var hist = try Histogram.init(testing.allocator, .{ .bins = 4, .show_counts = false });
    defer hist.deinit();

    try hist.addSamples(&[_]f64{ 1.0, 2.0, 2.5, 3.0, 8.0 });

    var buffer = try Buffer.init(testing.allocator, phantom.Size.init(20, 10));
    defer buffer.deinit();

    hist.render(&buffer, .{ .x = 0, .y = 0, .width = 20, .height = 10 });

    var filled: usize = 0;
    var y: u16 = 0;
    while (y < 10) : (y += 1) {
        var x: u16 = 0;
        while (x < 20) : (x += 1) {
            if (buffer.getCell(x, y)) |cell| {
                if (cell.char == '█') filled += 1;
            }
        }
    }
    try testing.expect(filled > 0);
}
