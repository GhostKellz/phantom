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
    total_dirty_regions: u64 = 0,
    total_cells_covered: u64 = 0,
    max_dirty_regions: usize = 0,
    max_cells_covered: u64 = 0,

    /// Average cells touched per frame.
    pub fn averageCellsPerFrame(self: Stats) f64 {
        if (self.frames == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_cells_covered)) /
            @as(f64, @floatFromInt(self.frames));
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

    fn empty() MergeResult {
        return MergeResult{};
    }
};

/// Hardened renderer implementation.
pub const Renderer = struct {
    allocator: Allocator,
    config: Config,
    grapheme_cache: GraphemeCache,
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

        const merge_scratch = try ArrayList(Rect).init(allocator);

        var renderer = Renderer{
            .allocator = allocator,
            .config = config,
            .grapheme_cache = GraphemeCache.init(allocator),
            .cell_buffer = undefined,
            .merge_scratch = merge_scratch,
        };

        renderer.cell_buffer = try CellBuffer.init(
            allocator,
            config.size.width,
            config.size.height,
            &renderer.grapheme_cache,
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
                const writer = std.io.getStdOut().writer();
                try self.cell_buffer.render(writer);
            },
            .file => |file| {
                const writer = file.writer();
                try self.cell_buffer.render(writer);
            },
            .buffer => |buffer| {
                const writer = buffer.writer();
                try self.cell_buffer.render(writer);
            },
        }

        const frame_end = time_utils.monotonicTimestampNs();
        const duration = frame_end - frame_start;

        self.stats.frames += 1;
        self.stats.cpu_frames += 1;
        self.stats.last_frame_ns = duration;
        self.stats.last_dirty_regions = merge_result.region_count;
        self.stats.last_cells_covered = merge_result.cells_covered;
        self.stats.total_dirty_regions += merge_result.region_count;
        self.stats.total_cells_covered += merge_result.cells_covered;
        self.stats.max_dirty_regions = @max(self.stats.max_dirty_regions, merge_result.region_count);
        self.stats.max_cells_covered = @max(self.stats.max_cells_covered, merge_result.cells_covered);
        self.stats.active_backend = .cpu;
        self.first_frame = false;
    }

    fn prepareDirtyRegions(self: *Renderer) !MergeResult {
        const dirty = self.cell_buffer.getDirtyRegions();
        defer self.allocator.free(dirty);

        if (dirty.len == 0 and self.first_frame) {
            // Ensure the very first frame paints the full surface.
            try self.cell_buffer.markDirty(Rect.init(0, 0, self.config.size.width, self.config.size.height));
            return MergeResult{ .region_count = 1, .cells_covered = @as(u64, self.config.size.area()) };
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
    const left = std.math.max(@as(u32, a.x), @as(u32, b.x));
    const right = std.math.min(@as(u32, a.x) + @as(u32, a.width), @as(u32, b.x) + @as(u32, b.width));
    const top = std.math.max(@as(u32, a.y), @as(u32, b.y));
    const bottom = std.math.min(@as(u32, a.y) + @as(u32, a.height), @as(u32, b.y) + @as(u32, b.height));
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
    var output = try ArrayList(u8).init(allocator);
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
    var output = try ArrayList(u8).init(allocator);
    defer output.deinit();

    var renderer = try Renderer.init(allocator, .{
        .size = Size.init(10, 3),
        .target = .{ .buffer = &output },
        .merge_dirty_regions = true,
    });
    defer renderer.deinit();

    var frame = renderer.beginFrame();
    _ = try frame.writeText(0, 0, "AB", Style.default());

    try renderer.flush();

    const stats = renderer.getStats();
    try std.testing.expect(stats.last_dirty_regions == 1);
    try std.testing.expect(stats.last_cells_covered == 2);
}

test "renderer resize triggers full redraw" {
    const allocator = std.testing.allocator;
    var output = try ArrayList(u8).init(allocator);
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
