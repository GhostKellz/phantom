//! Phantom Renderer
//! Hardened rendering pipeline with CPU backend, dirty-region merging, and stats.

const std = @import("std");
const ArrayList = std.array_list.Managed;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const time_utils = @import("../time/utils.zig");
const CellBuffer = @import("../rendering/CellBuffer.zig").CellBuffer;
const GraphemeCache = @import("../unicode/GraphemeCache.zig").GraphemeCache;

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Rect = geometry.Rect;
const Style = style.Style;

/// Rendering backend preference.
pub const BackendPreference = enum {
    /// Always use CPU renderer.
    cpu,
    /// Attempt GPU first, fallback to CPU if unavailable.
    auto,
    /// Require GPU backend (fails if not available).
    gpu,
};

/// Rendering target output.
pub const Target = union(enum) {
    /// Render directly to stdout.
    stdout,
    /// Render to a specific file handle.
    file: std.Io.File,
    /// Render into an in-memory buffer (useful for testing).
    buffer: *ArrayList(u8),
};

/// Renderer configuration.
pub const Config = struct {
    size: Size,
    target: Target = .stdout,
    backend: BackendPreference = .auto,
    merge_dirty_regions: bool = true,
    cursor_visible: bool = true,
    /// Per-frame time budget used for diagnostics. A frame whose flush exceeds
    /// this many nanoseconds is counted as over-budget. Set to 0 to disable.
    frame_budget_ns: u64 = 16_666_667, // ~60 FPS
};

/// Runtime statistics for the renderer.
pub const Stats = struct {
    active_backend: BackendKind = .cpu,
    frames: u64 = 0,
    cpu_frames: u64 = 0,
    gpu_frames: u64 = 0,
    resizes: u32 = 0,
    last_frame_ns: u64 = 0,
    last_dirty_regions: usize = 0,
    last_cells_covered: u64 = 0,
    /// Dirty regions submitted for the last frame before merging.
    last_input_regions: usize = 0,
    total_dirty_regions: u64 = 0,
    total_cells_covered: u64 = 0,
    max_dirty_regions: usize = 0,
    max_cells_covered: u64 = 0,
    /// Frames whose flush exceeded the configured budget.
    over_budget_frames: u64 = 0,

    /// Average cells touched per frame.
    pub fn averageCellsPerFrame(self: Stats) f64 {
        if (self.frames == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_cells_covered)) /
            @as(f64, @floatFromInt(self.frames));
    }
};

/// Per-frame diagnostics explaining the last flush: how many dirty regions were
/// submitted versus emitted after merging, how many were merged away, how many
/// cells were covered, and whether the frame exceeded its time budget.
pub const FrameDiagnostics = struct {
    frame_ns: u64,
    budget_ns: u64,
    over_budget: bool,
    input_regions: usize,
    merged_regions: usize,
    regions_merged_away: usize,
    cells_covered: u64,

    /// Write a human-readable one-line summary of the frame.
    pub fn format(self: FrameDiagnostics, writer: anytype) !void {
        try writer.print(
            "frame {d}ns/{d}ns{s} | regions {d}->{d} ({d} merged) | cells {d}",
            .{
                self.frame_ns,
                self.budget_ns,
                if (self.over_budget) " OVER" else "",
                self.input_regions,
                self.merged_regions,
                self.regions_merged_away,
                self.cells_covered,
            },
        );
    }
};

/// Active backend kind (CPU-only for now, GPU reserved for future use).
pub const BackendKind = enum {
    cpu,
    gpu,
};

const MergeResult = struct {
    region_count: usize = 0,
    cells_covered: u64 = 0,
    /// Dirty regions submitted before merging (>= region_count).
    input_regions: usize = 0,

    fn empty() MergeResult {
        return MergeResult{};
    }
};

/// Hardened renderer implementation.
pub const Renderer = struct {
    allocator: Allocator,
    config: Config,
    grapheme_cache: *GraphemeCache,
    cell_buffer: CellBuffer,
    merge_scratch: ArrayList(Rect),
    stats: Stats = .{},
    backend: BackendKind = .cpu,
    first_frame: bool = true,

    /// Initialize a renderer based on configuration.
    pub fn init(allocator: Allocator, config: Config) !Renderer {
        if (config.size.width == 0 or config.size.height == 0) {
            return error.InvalidSize;
        }

        const merge_scratch = ArrayList(Rect).init(allocator);

        // Heap-allocate the grapheme cache so its address stays stable when the
        // Renderer is returned by value (CellBuffer holds a pointer to it).
        const grapheme_cache = try allocator.create(GraphemeCache);
        errdefer allocator.destroy(grapheme_cache);
        grapheme_cache.* = GraphemeCache.init(allocator);

        var renderer = Renderer{
            .allocator = allocator,
            .config = config,
            .grapheme_cache = grapheme_cache,
            .cell_buffer = undefined,
            .merge_scratch = merge_scratch,
        };

        renderer.cell_buffer = try CellBuffer.init(
            allocator,
            config.size.width,
            config.size.height,
            renderer.grapheme_cache,
        );
        renderer.cell_buffer.setCursorVisible(config.cursor_visible);
        try renderer.requestFullRedraw();

        try renderer.selectBackend(config.backend);

        return renderer;
    }

    /// Release resources associated with the renderer.
    pub fn deinit(self: *Renderer) void {
        self.merge_scratch.deinit();
        self.cell_buffer.deinit();
        self.grapheme_cache.deinit();
        self.allocator.destroy(self.grapheme_cache);
    }

    /// Obtain the draw buffer for the current frame.
    pub fn beginFrame(self: *Renderer) *CellBuffer {
        return &self.cell_buffer;
    }

    /// Flush pending changes to the configured target.
    pub fn flush(self: *Renderer) !void {
        switch (self.backend) {
            .cpu => try self.flushCPU(),
            .gpu => {
                // GPU path is not yet implemented; fall back gracefully.
                try self.flushCPU();
            },
        }
    }

    /// Resize the renderer buffers.
    pub fn resize(self: *Renderer, new_size: Size) !void {
        if (new_size.width == 0 or new_size.height == 0) {
            return error.InvalidSize;
        }
        try self.cell_buffer.resize(new_size.width, new_size.height);
        self.config.size = new_size;
        try self.requestFullRedraw();
        self.stats.resizes += 1;
    }

    /// Clear the render buffer.
    pub fn clear(self: *Renderer) !void {
        try self.cell_buffer.clear();
    }

    /// Force the entire surface to be re-rendered.
    pub fn requestFullRedraw(self: *Renderer) !void {
        try self.cell_buffer.markDirty(Rect.init(0, 0, self.config.size.width, self.config.size.height));
    }

    /// Expose renderer statistics.
    pub fn getStats(self: *const Renderer) *const Stats {
        return &self.stats;
    }

    /// Check if there are pending dirty regions.
    pub fn isDirty(self: *const Renderer) bool {
        return self.cell_buffer.isDirty();
    }

    /// Set cursor position and visibility for subsequent flush.
    pub fn setCursor(self: *Renderer, x: u16, y: u16, visible: bool) void {
        self.cell_buffer.setCursor(x, y);
        self.cell_buffer.setCursorVisible(visible);
    }

    /// Retrieve the current render surface dimensions.
    pub fn size(self: *const Renderer) Size {
        return Size.init(self.config.size.width, self.config.size.height);
    }

    fn selectBackend(self: *Renderer, preference: BackendPreference) !void {
        switch (preference) {
            .cpu => {
                self.backend = .cpu;
                self.stats.active_backend = .cpu;
            },
            .auto => {
                self.backend = .cpu;
                self.stats.active_backend = .cpu;
            },
            .gpu => return error.GPUBackendUnavailable,
        }
    }

    fn flushCPU(self: *Renderer) !void {
        const merge_result = try self.prepareDirtyRegions();
        if (merge_result.region_count == 0) {
            return;
        }

        const frame_start = time_utils.monotonicTimestampNs();

        switch (self.config.target) {
            .stdout => {
                const io = std.Io.Threaded.global_single_threaded.io();
                var buf: [4096]u8 = undefined;
                var file_writer = std.Io.File.stdout().writerStreaming(io, &buf);
                try self.cell_buffer.render(&file_writer.interface);
                try file_writer.interface.flush();
            },
            .file => |file| {
                const io = std.Io.Threaded.global_single_threaded.io();
                var buf: [4096]u8 = undefined;
                var file_writer = file.writerStreaming(io, &buf);
                try self.cell_buffer.render(&file_writer.interface);
                try file_writer.interface.flush();
            },
            .buffer => |buffer| {
                var allocating = std.Io.Writer.Allocating.init(buffer.allocator);
                defer allocating.deinit();
                try self.cell_buffer.render(&allocating.writer);
                try buffer.appendSlice(allocating.written());
            },
        }

        const frame_end = time_utils.monotonicTimestampNs();
        const duration = frame_end - frame_start;

        self.stats.frames += 1;
        self.stats.cpu_frames += 1;
        self.stats.last_frame_ns = duration;
        self.stats.last_dirty_regions = merge_result.region_count;
        self.stats.last_cells_covered = merge_result.cells_covered;
        self.stats.last_input_regions = merge_result.input_regions;
        self.stats.total_dirty_regions += merge_result.region_count;
        self.stats.total_cells_covered += merge_result.cells_covered;
        self.stats.max_dirty_regions = @max(self.stats.max_dirty_regions, merge_result.region_count);
        self.stats.max_cells_covered = @max(self.stats.max_cells_covered, merge_result.cells_covered);
        if (self.config.frame_budget_ns != 0 and duration > self.config.frame_budget_ns) {
            self.stats.over_budget_frames += 1;
        }
        self.stats.active_backend = .cpu;
        self.first_frame = false;
    }

    /// Diagnostics for the most recently flushed frame.
    pub fn lastFrameDiagnostics(self: *const Renderer) FrameDiagnostics {
        const input = self.stats.last_input_regions;
        const merged = self.stats.last_dirty_regions;
        const budget = self.config.frame_budget_ns;
        return FrameDiagnostics{
            .frame_ns = self.stats.last_frame_ns,
            .budget_ns = budget,
            .over_budget = budget != 0 and self.stats.last_frame_ns > budget,
            .input_regions = input,
            .merged_regions = merged,
            .regions_merged_away = if (input > merged) input - merged else 0,
            .cells_covered = self.stats.last_cells_covered,
        };
    }

    fn prepareDirtyRegions(self: *Renderer) !MergeResult {
        const dirty = self.cell_buffer.getDirtyRegions();
        defer self.allocator.free(dirty);

        if (dirty.len == 0 and self.first_frame) {
            // Ensure the very first frame paints the full surface.
            try self.cell_buffer.markDirty(Rect.init(0, 0, self.config.size.width, self.config.size.height));
            return MergeResult{ .region_count = 1, .cells_covered = @as(u64, self.config.size.area()), .input_regions = 1 };
        } else if (dirty.len == 0) {
            return MergeResult.empty();
        }

        if (!self.config.merge_dirty_regions or dirty.len == 1) {
            var total_cells: u64 = 0;
            for (dirty) |region| {
                total_cells += rectArea(region);
                try self.cell_buffer.markDirty(region);
            }
            return MergeResult{
                .region_count = dirty.len,
                .cells_covered = total_cells,
                .input_regions = dirty.len,
            };
        }

        self.merge_scratch.clearRetainingCapacity();
        for (dirty) |region| {
            try self.insertMergedRegion(region);
        }

        var total_cells: u64 = 0;
        for (self.merge_scratch.items) |region| {
            total_cells += rectArea(region);
            try self.cell_buffer.markDirty(region);
        }

        return MergeResult{
            .region_count = self.merge_scratch.items.len,
            .cells_covered = total_cells,
            .input_regions = dirty.len,
        };
    }

    fn insertMergedRegion(self: *Renderer, region: Rect) !void {
        var merged = region;
        var index: usize = 0;

        while (index < self.merge_scratch.items.len) {
            const current = self.merge_scratch.items[index];
            if (rectanglesMergeable(current, merged)) {
                merged = current.union_(merged);
                _ = self.merge_scratch.swapRemove(index);
                index = 0;
                continue;
            }
            index += 1;
        }

        try self.merge_scratch.append(merged);
    }
};

fn rectArea(rect: Rect) u64 {
    return @as(u64, rect.width) * @as(u64, rect.height);
}

fn rectanglesMergeable(a: Rect, b: Rect) bool {
    if (rectanglesOverlap(a, b)) return true;
    if (rectanglesTouchHorizontally(a, b)) return true;
    if (rectanglesTouchVertically(a, b)) return true;
    return false;
}

fn rectanglesOverlap(a: Rect, b: Rect) bool {
    const left = @max(@as(u32, a.x), @as(u32, b.x));
    const right = @min(@as(u32, a.x) + @as(u32, a.width), @as(u32, b.x) + @as(u32, b.width));
    const top = @max(@as(u32, a.y), @as(u32, b.y));
    const bottom = @min(@as(u32, a.y) + @as(u32, a.height), @as(u32, b.y) + @as(u32, b.height));
    return left < right and top < bottom;
}

fn rectanglesTouchHorizontally(a: Rect, b: Rect) bool {
    const a_left = @as(u32, a.x);
    const a_right = a_left + @as(u32, a.width);
    const b_left = @as(u32, b.x);
    const b_right = b_left + @as(u32, b.width);

    const vertical_overlap = rangesOverlapOrTouch(
        @as(u32, a.y),
        @as(u32, a.y) + @as(u32, a.height),
        @as(u32, b.y),
        @as(u32, b.y) + @as(u32, b.height),
    );

    return vertical_overlap and (a_right == b_left or b_right == a_left);
}

fn rectanglesTouchVertically(a: Rect, b: Rect) bool {
    const a_top = @as(u32, a.y);
    const a_bottom = a_top + @as(u32, a.height);
    const b_top = @as(u32, b.y);
    const b_bottom = b_top + @as(u32, b.height);

    const horizontal_overlap = rangesOverlapOrTouch(
        @as(u32, a.x),
        @as(u32, a.x) + @as(u32, a.width),
        @as(u32, b.x),
        @as(u32, b.x) + @as(u32, b.width),
    );

    return horizontal_overlap and (a_bottom == b_top or b_bottom == a_top);
}

fn rangesOverlapOrTouch(a_start: u32, a_end: u32, b_start: u32, b_end: u32) bool {
    return !(a_end < b_start or b_end < a_start);
}

test "renderer emits escape sequences for text" {
    const allocator = std.testing.allocator;
    var output = ArrayList(u8).init(allocator);
    defer output.deinit();

    var renderer = try Renderer.init(allocator, .{
        .size = Size.init(8, 4),
        .target = .{ .buffer = &output },
    });
    defer renderer.deinit();

    var frame = renderer.beginFrame();
    _ = try frame.writeText(0, 0, "Hi", Style.default());

    try renderer.flush();

    try std.testing.expect(output.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "Hi") != null);
}

test "renderer merges adjacent dirty regions" {
    const allocator = std.testing.allocator;
    var output = ArrayList(u8).init(allocator);
    defer output.deinit();

    var renderer = try Renderer.init(allocator, .{
        .size = Size.init(10, 3),
        .target = .{ .buffer = &output },
        .merge_dirty_regions = true,
    });
    defer renderer.deinit();

    try renderer.flush(); // consume initial full redraw

    var frame = renderer.beginFrame();
    _ = try frame.writeText(0, 0, "AB", Style.default());

    try renderer.flush();

    const stats = renderer.getStats();
    try std.testing.expect(stats.last_dirty_regions == 1);
    try std.testing.expect(stats.last_cells_covered == 2);
}

test "renderer resize triggers full redraw" {
    const allocator = std.testing.allocator;
    var output = ArrayList(u8).init(allocator);
    defer output.deinit();

    var renderer = try Renderer.init(allocator, .{
        .size = Size.init(4, 2),
        .target = .{ .buffer = &output },
    });
    defer renderer.deinit();

    try renderer.flush(); // consume initial full redraw
    try renderer.resize(Size.init(6, 4));
    try renderer.flush();

    const stats = renderer.getStats();
    try std.testing.expect(stats.last_cells_covered == 24);
    try std.testing.expect(stats.last_dirty_regions == 1);
    try std.testing.expect(stats.resizes == 1);
}

test "renderer golden: full-frame ascii output" {
    const allocator = std.testing.allocator;
    var output = ArrayList(u8).init(allocator);
    defer output.deinit();

    var renderer = try Renderer.init(allocator, .{
        .size = Size.init(4, 1),
        .target = .{ .buffer = &output },
        .cursor_visible = false,
    });
    defer renderer.deinit();

    var frame = renderer.beginFrame();
    _ = try frame.writeText(0, 0, "Hi", Style.default());

    try renderer.flush();

    // Cursor position at line/col 1, a leading style reset, the two glyphs,
    // two blank cells filling the row, and a trailing style reset.
    try std.testing.expectEqualStrings("\x1b[1;1H\x1b[0mHi  \x1b[0m", output.items);
}

test "renderer golden: style reset between differing cells" {
    const allocator = std.testing.allocator;
    var output = ArrayList(u8).init(allocator);
    defer output.deinit();

    var renderer = try Renderer.init(allocator, .{
        .size = Size.init(2, 1),
        .target = .{ .buffer = &output },
        .cursor_visible = false,
    });
    defer renderer.deinit();

    var frame = renderer.beginFrame();
    _ = try frame.writeText(0, 0, "A", Style.default().withBold());
    _ = try frame.writeText(1, 0, "B", Style.default());

    try renderer.flush();

    // Bold cell emits reset+bold, the default cell re-resets before "B",
    // and the row ends with a final reset.
    try std.testing.expectEqualStrings("\x1b[1;1H\x1b[0m\x1b[1mA\x1b[0mB\x1b[0m", output.items);
}

test "renderer golden: wide grapheme is not duplicated" {
    const allocator = std.testing.allocator;
    var output = ArrayList(u8).init(allocator);
    defer output.deinit();

    var renderer = try Renderer.init(allocator, .{
        .size = Size.init(4, 1),
        .target = .{ .buffer = &output },
        .cursor_visible = false,
    });
    defer renderer.deinit();

    const needle = "世";
    var frame = renderer.beginFrame();
    _ = try frame.writeText(0, 0, needle, Style.default());

    const first = frame.getCell(0, 0).?;
    try std.testing.expectEqualStrings(needle, first.char.grapheme);

    // A wide grapheme occupies a continuation cell that render must skip so the
    // glyph is not written twice across the grapheme boundary.
    if (first.width > 1) {
        const cont = frame.getCell(1, 0).?;
        try std.testing.expect(cont.char == .continuation);
    }

    try renderer.flush();

    const idx = std.mem.indexOf(u8, output.items, needle).?;
    try std.testing.expect(std.mem.indexOfPos(u8, output.items, idx + needle.len, needle) == null);
}

test "renderer diagnostics report merged regions and budget" {
    const allocator = std.testing.allocator;
    var output = ArrayList(u8).init(allocator);
    defer output.deinit();

    var renderer = try Renderer.init(allocator, .{
        .size = Size.init(10, 3),
        .target = .{ .buffer = &output },
        .merge_dirty_regions = true,
        .frame_budget_ns = 0, // disable over-budget accounting for determinism
    });
    defer renderer.deinit();

    try renderer.flush(); // consume initial full redraw

    var frame = renderer.beginFrame();
    _ = try frame.writeText(0, 0, "AB", Style.default());
    try renderer.flush();

    const diag = renderer.lastFrameDiagnostics();
    // Two per-cell dirty regions submitted, merged down to one emitted region.
    try std.testing.expectEqual(@as(usize, 2), diag.input_regions);
    try std.testing.expectEqual(@as(usize, 1), diag.merged_regions);
    try std.testing.expectEqual(@as(usize, 1), diag.regions_merged_away);
    try std.testing.expectEqual(@as(u64, 2), diag.cells_covered);
    // Budget disabled, so no frame is ever flagged over-budget.
    try std.testing.expect(!diag.over_budget);
    try std.testing.expectEqual(@as(u64, 0), renderer.getStats().over_budget_frames);

    // The formatted summary surfaces the region transition.
    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();
    try diag.format(&allocating.writer);
    try std.testing.expect(std.mem.indexOf(u8, allocating.written(), "regions 2->1") != null);
}
