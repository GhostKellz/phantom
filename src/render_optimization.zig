//! Rendering optimization utilities for Phantom TUI
const std = @import("std");
const ArrayList = std.array_list.Managed;
const builtin = @import("builtin");
const geometry = @import("geometry.zig");
const style = @import("style.zig");
const time_utils = @import("time/utils.zig");
const Buffer = @import("terminal.zig").Buffer;
const Cell = @import("terminal.zig").Cell;

const Rect = geometry.Rect;
const Style = style.Style;

/// Dirty rectangle tracking for efficient rendering
pub const DirtyRect = struct {
    rect: Rect,
    dirty: bool = false,

    pub fn init(rect: Rect) DirtyRect {
        return DirtyRect{
            .rect = rect,
            .dirty = false,
        };
    }

    pub fn markDirty(self: *DirtyRect) void {
        self.dirty = true;
    }

    pub fn markClean(self: *DirtyRect) void {
        self.dirty = false;
    }

    pub fn isDirty(self: *const DirtyRect) bool {
        return self.dirty;
    }

    pub fn intersects(self: *const DirtyRect, other: Rect) bool {
        return self.rect.intersects(other);
    }

    pub fn contains(self: *const DirtyRect, point: geometry.Position) bool {
        return self.rect.contains(point);
    }
};

/// Dirty region manager for tracking areas that need rerendering
pub const DirtyRegionManager = struct {
    allocator: std.mem.Allocator,
    dirty_rects: ArrayList(DirtyRect),
    screen_size: geometry.Size,

    pub fn init(allocator: std.mem.Allocator, screen_size: geometry.Size) DirtyRegionManager {
        return DirtyRegionManager{
            .allocator = allocator,
            .dirty_rects = ArrayList(DirtyRect).init(allocator),
            .screen_size = screen_size,
        };
    }

    pub fn deinit(self: *DirtyRegionManager) void {
        self.dirty_rects.deinit();
    }

    pub fn markDirty(self: *DirtyRegionManager, rect: Rect) !void {
        // Check if this rect overlaps with any existing dirty rect
        for (self.dirty_rects.items) |*dirty_rect| {
            if (dirty_rect.rect.intersects(rect)) {
                // Merge the rectangles
                dirty_rect.rect = dirty_rect.rect.union_(rect);
                dirty_rect.markDirty();
                return;
            }
        }

        // No overlap, add as new dirty rect
        try self.dirty_rects.append(DirtyRect.init(rect));
        self.dirty_rects.items[self.dirty_rects.items.len - 1].markDirty();
    }

    pub fn markClean(self: *DirtyRegionManager, rect: Rect) void {
        var i: usize = 0;
        while (i < self.dirty_rects.items.len) {
            if (self.dirty_rects.items[i].rect.intersects(rect)) {
                // Remove or modify the dirty rect
                if (self.dirty_rects.items[i].rect.equals(rect)) {
                    _ = self.dirty_rects.swapRemove(i);
                } else {
                    self.dirty_rects.items[i].markClean();
                    i += 1;
                }
            } else {
                i += 1;
            }
        }
    }

    pub fn markFullScreenDirty(self: *DirtyRegionManager) !void {
        self.dirty_rects.clearAndFree();
        const full_screen = Rect.init(0, 0, self.screen_size.width, self.screen_size.height);
        try self.markDirty(full_screen);
    }

    pub fn clearDirty(self: *DirtyRegionManager) void {
        self.dirty_rects.clearAndFree();
    }

    pub fn hasDirtyRegions(self: *const DirtyRegionManager) bool {
        for (self.dirty_rects.items) |dirty_rect| {
            if (dirty_rect.isDirty()) {
                return true;
            }
        }
        return false;
    }

    pub fn getDirtyRegions(self: *const DirtyRegionManager) []const DirtyRect {
        return self.dirty_rects.items;
    }

    pub fn shouldRedraw(self: *const DirtyRegionManager, rect: Rect) bool {
        for (self.dirty_rects.items) |dirty_rect| {
            if (dirty_rect.isDirty() and dirty_rect.intersects(rect)) {
                return true;
            }
        }
        return false;
    }

    pub fn resize(self: *DirtyRegionManager, new_size: geometry.Size) !void {
        self.screen_size = new_size;
        try self.markFullScreenDirty();
    }
};

/// Double buffering system for flicker-free rendering
pub const DoubleBuffer = struct {
    allocator: std.mem.Allocator,
    front_buffer: Buffer,
    back_buffer: Buffer,
    size: geometry.Size,

    pub fn init(allocator: std.mem.Allocator, size: geometry.Size) !DoubleBuffer {
        return DoubleBuffer{
            .allocator = allocator,
            .front_buffer = try Buffer.init(allocator, size),
            .back_buffer = try Buffer.init(allocator, size),
            .size = size,
        };
    }

    pub fn deinit(self: *DoubleBuffer) void {
        self.front_buffer.deinit();
        self.back_buffer.deinit();
    }

    pub fn getBackBuffer(self: *DoubleBuffer) *Buffer {
        return &self.back_buffer;
    }

    pub fn getFrontBuffer(self: *DoubleBuffer) *Buffer {
        return &self.front_buffer;
    }

    pub fn swap(self: *DoubleBuffer) void {
        const temp = self.front_buffer;
        self.front_buffer = self.back_buffer;
        self.back_buffer = temp;
    }

    pub fn resize(self: *DoubleBuffer, new_size: geometry.Size) !void {
        try self.front_buffer.resize(new_size);
        try self.back_buffer.resize(new_size);
        self.size = new_size;
    }

    pub fn clear(self: *DoubleBuffer) void {
        self.back_buffer.clear();
    }

    pub fn clearRegion(self: *DoubleBuffer, rect: Rect) void {
        self.back_buffer.fill(rect, Cell{});
    }
};

/// Render cache for storing rendered content
pub const RenderCache = struct {
    const CacheEntry = struct {
        key: u64,
        buffer: []Cell,
        size: geometry.Size,
        timestamp: u64,

        pub fn deinit(self: *CacheEntry, allocator: std.mem.Allocator) void {
            allocator.free(self.buffer);
        }
    };

    allocator: std.mem.Allocator,
    cache: std.HashMap(u64, CacheEntry, std.hash_map.DefaultContext(u64), std.hash_map.default_max_load_percentage),
    max_entries: usize,

    pub fn init(allocator: std.mem.Allocator, max_entries: usize) RenderCache {
        return RenderCache{
            .allocator = allocator,
            .cache = std.HashMap(u64, CacheEntry, std.hash_map.DefaultContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .max_entries = max_entries,
        };
    }

    pub fn deinit(self: *RenderCache) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.cache.deinit();
    }

    pub fn get(self: *RenderCache, key: u64) ?*const CacheEntry {
        return self.cache.getPtr(key);
    }

    pub fn put(self: *RenderCache, key: u64, buffer: []const Cell, size: geometry.Size) !void {
        // Remove oldest entry if cache is full
        if (self.cache.count() >= self.max_entries) {
            self.evictOldest();
        }

        // Create new cache entry
        const buffer_copy = try self.allocator.alloc(Cell, buffer.len);
        @memcpy(buffer_copy, buffer);

        const entry = CacheEntry{
            .key = key,
            .buffer = buffer_copy,
            .size = size,
            .timestamp = time_utils.monotonicTimestampNs(),
        };

        // Remove existing entry if it exists
        if (self.cache.getPtr(key)) |existing| {
            existing.deinit(self.allocator);
        }

        try self.cache.put(key, entry);
    }

    pub fn remove(self: *RenderCache, key: u64) void {
        if (self.cache.fetchRemove(key)) |entry| {
            entry.value.deinit(self.allocator);
        }
    }

    pub fn clear(self: *RenderCache) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.cache.clearAndFree();
    }

    fn evictOldest(self: *RenderCache) void {
        var oldest_key: ?u64 = null;
        var oldest_timestamp: u64 = std.math.maxInt(u64);

        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.timestamp < oldest_timestamp) {
                oldest_timestamp = entry.value_ptr.timestamp;
                oldest_key = entry.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            self.remove(key);
        }
    }

    pub fn generateKey(data: []const u8) u64 {
        return std.hash_map.hashString(data);
    }
};

/// Frame rate limiting and timing utilities
pub const FrameTimer = struct {
    target_fps: u32,
    frame_duration_ns: u64,
    last_frame_time: u64,
    frame_count: u64,
    start_time: u64,

    pub fn init(target_fps: u32) FrameTimer {
        const frame_duration_ns = std.time.ns_per_s / @as(u64, target_fps);
        const current_time = time_utils.monotonicTimestampNs();

        return FrameTimer{
            .target_fps = target_fps,
            .frame_duration_ns = frame_duration_ns,
            .last_frame_time = current_time,
            .frame_count = 0,
            .start_time = current_time,
        };
    }

    pub fn shouldRender(self: *FrameTimer) bool {
        const current_time = time_utils.monotonicTimestampNs();
        const elapsed = current_time - self.last_frame_time;

        return elapsed >= self.frame_duration_ns;
    }

    pub fn frameComplete(self: *FrameTimer) void {
        self.last_frame_time = time_utils.monotonicTimestampNs();
        self.frame_count += 1;
    }

    pub fn waitForNextFrame(self: *FrameTimer) void {
        const current_time = time_utils.monotonicTimestampNs();
        const elapsed = current_time - self.last_frame_time;

        if (elapsed < self.frame_duration_ns) {
            var remaining = self.frame_duration_ns - elapsed;
            if (remaining == 0) return;

            if (builtin.os.tag == .windows) {
                std.time.sleep(remaining);
                return;
            }

            const ns_per_s = std.time.ns_per_s;
            const max_seconds_chunk = @as(u64, std.math.maxInt(u32));

            while (remaining > 0) {
                const seconds_chunk = @min(remaining / ns_per_s, max_seconds_chunk);
                const nanos_chunk = if (remaining >= ns_per_s)
                    @as(u32, @intCast(remaining % ns_per_s))
                else
                    @as(u32, @intCast(remaining));

                const ts = std.c.timespec{
                    .sec = @intCast(seconds_chunk),
                    .nsec = @intCast(nanos_chunk),
                };
                _ = std.c.nanosleep(&ts, null);

                const consumed = seconds_chunk * ns_per_s + nanos_chunk;
                if (consumed == 0) break;
                remaining -= consumed;
            }
        }
    }

    pub fn getAverageFPS(self: *const FrameTimer) f64 {
        const current_time = time_utils.monotonicTimestampNs();
        const total_time = @as(f64, @floatFromInt(current_time - self.start_time)) / @as(f64, std.time.ns_per_s);

        if (total_time > 0.0) {
            return @as(f64, @floatFromInt(self.frame_count)) / total_time;
        }

        return 0.0;
    }

    pub fn getFrameCount(self: *const FrameTimer) u64 {
        return self.frame_count;
    }

    pub fn reset(self: *FrameTimer) void {
        const current_time = time_utils.monotonicTimestampNs();
        self.last_frame_time = current_time;
        self.start_time = current_time;
        self.frame_count = 0;
    }
};

/// Render statistics for performance monitoring
pub const RenderStats = struct {
    frame_count: u64 = 0,
    total_render_time_ns: u64 = 0,
    min_render_time_ns: u64 = std.math.maxInt(u64),
    max_render_time_ns: u64 = 0,
    dirty_regions_processed: u64 = 0,
    cache_hits: u64 = 0,
    cache_misses: u64 = 0,

    pub fn init() RenderStats {
        return RenderStats{};
    }

    pub fn recordFrame(self: *RenderStats, render_time_ns: u64, dirty_regions: u32) void {
        self.frame_count += 1;
        self.total_render_time_ns += render_time_ns;
        self.min_render_time_ns = @min(self.min_render_time_ns, render_time_ns);
        self.max_render_time_ns = @max(self.max_render_time_ns, render_time_ns);
        self.dirty_regions_processed += dirty_regions;
    }

    pub fn recordCacheHit(self: *RenderStats) void {
        self.cache_hits += 1;
    }

    pub fn recordCacheMiss(self: *RenderStats) void {
        self.cache_misses += 1;
    }

    pub fn getAverageRenderTime(self: *const RenderStats) f64 {
        if (self.frame_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_render_time_ns)) / @as(f64, @floatFromInt(self.frame_count));
    }

    pub fn getCacheHitRate(self: *const RenderStats) f64 {
        const total_requests = self.cache_hits + self.cache_misses;
        if (total_requests == 0) return 0.0;
        return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total_requests));
    }

    pub fn reset(self: *RenderStats) void {
        self.* = RenderStats.init();
    }

    pub fn print(self: *const RenderStats) void {
        std.debug.print("Render Statistics:\n", .{});
        std.debug.print("  Frames: {d}\n", .{self.frame_count});
        std.debug.print("  Avg render time: {d:.2}ms\n", .{self.getAverageRenderTime() / 1_000_000.0});
        std.debug.print("  Min render time: {d:.2}ms\n", .{@as(f64, @floatFromInt(self.min_render_time_ns)) / 1_000_000.0});
        std.debug.print("  Max render time: {d:.2}ms\n", .{@as(f64, @floatFromInt(self.max_render_time_ns)) / 1_000_000.0});
        std.debug.print("  Dirty regions: {d}\n", .{self.dirty_regions_processed});
        std.debug.print("  Cache hit rate: {d:.1}%\n", .{self.getCacheHitRate() * 100.0});
    }
};

/// Efficient renderer with optimizations
pub const OptimizedRenderer = struct {
    allocator: std.mem.Allocator,
    double_buffer: DoubleBuffer,
    dirty_manager: DirtyRegionManager,
    render_cache: RenderCache,
    frame_timer: FrameTimer,
    stats: RenderStats,

    pub fn init(allocator: std.mem.Allocator, size: geometry.Size, target_fps: u32) !OptimizedRenderer {
        return OptimizedRenderer{
            .allocator = allocator,
            .double_buffer = try DoubleBuffer.init(allocator, size),
            .dirty_manager = DirtyRegionManager.init(allocator, size),
            .render_cache = RenderCache.init(allocator, 100), // Max 100 cache entries
            .frame_timer = FrameTimer.init(target_fps),
            .stats = RenderStats.init(),
        };
    }

    pub fn deinit(self: *OptimizedRenderer) void {
        self.double_buffer.deinit();
        self.dirty_manager.deinit();
        self.render_cache.deinit();
    }

    pub fn markDirty(self: *OptimizedRenderer, rect: Rect) !void {
        try self.dirty_manager.markDirty(rect);
    }

    pub fn shouldRender(self: *OptimizedRenderer) bool {
        return self.frame_timer.shouldRender() and self.dirty_manager.hasDirtyRegions();
    }

    pub fn beginFrame(self: *OptimizedRenderer) *Buffer {
        // Only clear dirty regions instead of the entire buffer
        for (self.dirty_manager.getDirtyRegions()) |dirty_rect| {
            if (dirty_rect.isDirty()) {
                self.double_buffer.clearRegion(dirty_rect.rect);
            }
        }

        return self.double_buffer.getBackBuffer();
    }

    pub fn endFrame(self: *OptimizedRenderer) void {
        const render_start = time_utils.monotonicTimestampNs();

        // Swap buffers
        self.double_buffer.swap();

        // Record frame statistics
        const render_time = time_utils.monotonicTimestampNs() - render_start;
        self.stats.recordFrame(render_time, @as(u32, @intCast(self.dirty_manager.dirty_rects.items.len)));

        // Clear dirty regions
        self.dirty_manager.clearDirty();

        // Update frame timer
        self.frame_timer.frameComplete();
    }

    pub fn resize(self: *OptimizedRenderer, new_size: geometry.Size) !void {
        try self.double_buffer.resize(new_size);
        try self.dirty_manager.resize(new_size);
        self.render_cache.clear();
    }

    pub fn getStats(self: *const OptimizedRenderer) *const RenderStats {
        return &self.stats;
    }

    pub fn getFPS(self: *const OptimizedRenderer) f64 {
        return self.frame_timer.getAverageFPS();
    }

    pub fn waitForNextFrame(self: *OptimizedRenderer) void {
        self.frame_timer.waitForNextFrame();
    }
};

test "Dirty region management" {
    const allocator = std.testing.allocator;
    var manager = DirtyRegionManager.init(allocator, geometry.Size.init(80, 24));
    defer manager.deinit();

    // Test marking dirty regions
    try manager.markDirty(Rect.init(0, 0, 10, 5));
    try std.testing.expect(manager.hasDirtyRegions());

    // Test clearing dirty regions
    manager.clearDirty();
    try std.testing.expect(!manager.hasDirtyRegions());
}

test "Double buffer" {
    const allocator = std.testing.allocator;
    var double_buffer = try DoubleBuffer.init(allocator, geometry.Size.init(10, 10));
    defer double_buffer.deinit();

    const back_buffer = double_buffer.getBackBuffer();
    try std.testing.expect(back_buffer.size.width == 10);
    try std.testing.expect(back_buffer.size.height == 10);

    double_buffer.swap();
    // After swap, the previous back buffer becomes the front buffer
}

test "Frame timer" {
    var timer = FrameTimer.init(60); // 60 FPS

    // Initially should be ready to render
    try std.testing.expect(timer.shouldRender());

    timer.frameComplete();
    try std.testing.expect(timer.getFrameCount() == 1);
}

test "Render cache" {
    const allocator = std.testing.allocator;
    var cache = RenderCache.init(allocator, 10);
    defer cache.deinit();

    const test_buffer = [_]Cell{Cell{}} ** 10;
    try cache.put(123, &test_buffer, geometry.Size.init(10, 1));

    const cached_entry = cache.get(123);
    try std.testing.expect(cached_entry != null);
    try std.testing.expect(cached_entry.?.buffer.len == 10);
}

test "Render statistics" {
    var stats = RenderStats.init();

    stats.recordFrame(16_000_000, 5); // 16ms frame time, 5 dirty regions
    try std.testing.expect(stats.frame_count == 1);
    try std.testing.expect(stats.getAverageRenderTime() == 16_000_000.0);

    stats.recordCacheHit();
    stats.recordCacheMiss();
    try std.testing.expect(stats.getCacheHitRate() == 0.5);
}
