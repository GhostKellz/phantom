//! Advanced Glyph Cache with GPU optimization support
//! Designed for Phantom TUI + Grim editor performance
//! Uses LRU eviction and supports GPU texture atlas for future GPU backend

const std = @import("std");
const zfont = @import("zfont");
const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
cache_entries: std.AutoHashMap(GlyphKey, *CacheEntry),
lru_list: std.DoublyLinkedList,
max_cache_size: usize,
current_cache_size: usize,
gpu_cache: ?GPUGlyphCache,
statistics: CacheStatistics,
timer: std.time.Timer,

pub const GlyphKey = struct {
    codepoint: u21,
    font_id: usize,
    size: u16,
    style_flags: StyleFlags,

    pub const StyleFlags = packed struct {
        bold: bool = false,
        italic: bool = false,
        underline: bool = false,
        strikethrough: bool = false,
    };

    pub fn hash(self: GlyphKey) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&self.codepoint));
        hasher.update(std.mem.asBytes(&self.font_id));
        hasher.update(std.mem.asBytes(&self.size));
        hasher.update(std.mem.asBytes(&self.style_flags));
        return hasher.final();
    }

    pub fn eql(a: GlyphKey, b: GlyphKey) bool {
        return a.codepoint == b.codepoint and
               a.font_id == b.font_id and
               a.size == b.size and
               std.meta.eql(a.style_flags, b.style_flags);
    }
};

pub const CacheEntry = struct {
    glyph_data: GlyphData,
    lru_node: std.DoublyLinkedList.Node,
    key: GlyphKey,
    size_bytes: usize,
    last_access_time: i64,
    access_count: u64,
};

pub const GlyphData = struct {
    bitmap: []u8,
    width: u32,
    height: u32,
    advance: f32,
    bearing_x: i32,
    bearing_y: i32,
    texture_id: ?u32 = null, // For GPU rendering
    atlas_x: u16 = 0,        // Position in texture atlas
    atlas_y: u16 = 0,
};

pub const CacheStatistics = struct {
    hits: u64 = 0,
    misses: u64 = 0,
    evictions: u64 = 0,
    total_size_bytes: usize = 0,

    pub fn hitRate(self: CacheStatistics) f32 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.hits)) / @as(f32, @floatFromInt(total));
    }
};

/// GPU-accelerated glyph cache for terminal rendering
pub const GPUGlyphCache = struct {
    texture_atlas: TextureAtlas,
    allocator: Allocator,
    enabled: bool,

    const AtlasPosition = struct {
        x: u16,
        y: u16,
    };

    const TextureAtlas = struct {
        width: u32 = 2048,  // 2K texture atlas
        height: u32 = 2048,
        current_x: u32 = 0,
        current_y: u32 = 0,
        row_height: u32 = 0,
        data: []u8,

        pub fn init(allocator: Allocator, width: u32, height: u32) !TextureAtlas {
            return TextureAtlas{
                .width = width,
                .height = height,
                .data = try allocator.alloc(u8, width * height * 4), // RGBA
            };
        }

        pub fn deinit(self: *TextureAtlas, allocator: Allocator) void {
            allocator.free(self.data);
        }

        pub fn allocateSpace(self: *TextureAtlas, width: u32, height: u32) ?AtlasPosition {
            // Try to fit in current row
            if (self.current_x + width <= self.width and self.current_y + height <= self.height) {
                const result = AtlasPosition{
                    .x = @as(u16, @intCast(self.current_x)),
                    .y = @as(u16, @intCast(self.current_y)),
                };
                self.current_x += width;
                self.row_height = @max(self.row_height, height);
                return result;
            }

            // Move to next row
            if (self.current_y + self.row_height + height <= self.height) {
                self.current_y += self.row_height;
                self.current_x = 0;
                self.row_height = 0;
                return self.allocateSpace(width, height);
            }

            // Atlas is full
            return null;
        }

        pub fn uploadGlyph(self: *TextureAtlas, glyph: *const GlyphData) !void {
            // Copy glyph bitmap to atlas
            for (0..glyph.height) |y| {
                const src_offset = y * glyph.width;
                const dst_offset = ((glyph.atlas_y + @as(u16, @intCast(y))) * self.width + glyph.atlas_x) * 4;

                for (0..glyph.width) |x| {
                    const alpha = glyph.bitmap[src_offset + x];
                    // RGBA format
                    self.data[dst_offset + x * 4 + 0] = 255; // R
                    self.data[dst_offset + x * 4 + 1] = 255; // G
                    self.data[dst_offset + x * 4 + 2] = 255; // B
                    self.data[dst_offset + x * 4 + 3] = alpha; // A
                }
            }
        }
    };

    pub fn init(allocator: Allocator) !GPUGlyphCache {
        return GPUGlyphCache{
            .texture_atlas = try TextureAtlas.init(allocator, 2048, 2048),
            .allocator = allocator,
            .enabled = true,
        };
    }

    pub fn deinit(self: *GPUGlyphCache) void {
        self.texture_atlas.deinit(self.allocator);
    }

    pub fn uploadGlyph(self: *GPUGlyphCache, key: GlyphKey, glyph: *GlyphData) !bool {
        _ = key; // For future use in tracking

        // Allocate space in texture atlas
        if (self.texture_atlas.allocateSpace(glyph.width, glyph.height)) |pos| {
            glyph.atlas_x = pos.x;
            glyph.atlas_y = pos.y;
            try self.texture_atlas.uploadGlyph(glyph);
            return true;
        }

        return false; // Atlas full
    }
};

pub const CacheConfig = struct {
    max_size_bytes: usize = 128 * 1024 * 1024, // 128MB default
    enable_gpu_cache: bool = false,
    lru_enabled: bool = true,
};

pub fn init(allocator: Allocator, config: CacheConfig) !Self {
    var cache = Self{
        .allocator = allocator,
        .cache_entries = std.AutoHashMap(GlyphKey, *CacheEntry).init(allocator),
        .lru_list = .{},
        .max_cache_size = config.max_size_bytes,
        .current_cache_size = 0,
        .gpu_cache = null,
        .statistics = .{},
        .timer = try std.time.Timer.start(),
    };

    // Initialize GPU cache if enabled
    if (config.enable_gpu_cache) {
        cache.gpu_cache = try GPUGlyphCache.init(allocator);
    }

    return cache;
}

pub fn deinit(self: *Self) void {
    // Free all glyph data
    var iterator = self.cache_entries.iterator();
    while (iterator.next()) |entry| {
        self.allocator.free(entry.value_ptr.*.glyph_data.bitmap);
        self.allocator.destroy(entry.value_ptr.*);
    }
    self.cache_entries.deinit();

    // Clean up GPU cache
    if (self.gpu_cache) |*gpu_cache| {
        gpu_cache.deinit();
    }
}

pub fn get(self: *Self, key: GlyphKey) ?*const GlyphData {
    if (self.cache_entries.get(key)) |entry| {
        // Update LRU
        self.touchEntry(entry);

        // Update statistics
        self.statistics.hits += 1;

        return &entry.glyph_data;
    }

    self.statistics.misses += 1;
    return null;
}

pub fn put(self: *Self, key: GlyphKey, glyph_data: GlyphData) !void {
    const size_bytes = glyph_data.bitmap.len;

    // Evict entries if necessary
    while (self.current_cache_size + size_bytes > self.max_cache_size) {
        try self.evictLRU();
    }

    // Create cache entry with embedded node
    const entry = try self.allocator.create(CacheEntry);
    entry.* = CacheEntry{
        .glyph_data = glyph_data,
        .lru_node = .{},
        .key = key,
        .size_bytes = size_bytes,
        .last_access_time = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms)),
        .access_count = 1,
    };

    // Add to LRU list
    self.lru_list.append(&entry.lru_node);

    try self.cache_entries.put(key, entry);
    self.current_cache_size += size_bytes;
    self.statistics.total_size_bytes = self.current_cache_size;

    // Upload to GPU cache if available
    if (self.gpu_cache) |*gpu_cache| {
        var glyph_copy = glyph_data;
        _ = gpu_cache.uploadGlyph(key, &glyph_copy) catch |err| {
            std.log.warn("Failed to upload glyph to GPU cache: {}", .{err});
        };
    }
}

pub fn contains(self: *Self, key: GlyphKey) bool {
    return self.cache_entries.contains(key);
}

pub fn remove(self: *Self, key: GlyphKey) void {
    if (self.cache_entries.fetchRemove(key)) |kv| {
        const entry = kv.value;

        // Free bitmap
        self.allocator.free(entry.glyph_data.bitmap);

        // Remove from LRU list
        self.lru_list.remove(&entry.lru_node);

        // Update size
        self.current_cache_size -= entry.size_bytes;
        self.statistics.total_size_bytes = self.current_cache_size;

        // Free entry
        self.allocator.destroy(entry);
    }
}

pub fn clear(self: *Self) void {
    var iterator = self.cache_entries.iterator();
    while (iterator.next()) |entry| {
        self.allocator.free(entry.value_ptr.*.glyph_data.bitmap);
        self.allocator.destroy(entry.value_ptr.*);
    }

    self.cache_entries.clearRetainingCapacity();
    self.lru_list = .{};
    self.current_cache_size = 0;
    self.statistics = .{};
}

pub fn getStatistics(self: *const Self) CacheStatistics {
    return self.statistics;
}

fn touchEntry(self: *Self, entry: *CacheEntry) void {
    // Move to end of LRU list (most recently used)
    self.lru_list.remove(&entry.lru_node);
    self.lru_list.append(&entry.lru_node);

    entry.last_access_time = @as(i64, @intCast(self.timer.read() / std.time.ns_per_ms));
    entry.access_count += 1;
}

fn evictLRU(self: *Self) !void {
    // Remove least recently used entry (head of list)
    if (self.lru_list.first) |node| {
        // Use @fieldParentPtr to get from Node to CacheEntry
        const entry: *CacheEntry = @fieldParentPtr("lru_node", node);
        const key = entry.key;
        self.remove(key);
        self.statistics.evictions += 1;
    } else {
        return error.CacheEmpty;
    }
}

/// Preload commonly used glyphs (ASCII, numbers, common symbols)
pub fn preloadCommonGlyphs(self: *Self, font_id: usize, size: u16, render_fn: *const fn (u21) anyerror!GlyphData) !void {
    // ASCII printable characters
    var codepoint: u21 = 32; // Space
    while (codepoint <= 126) : (codepoint += 1) {
        const key = GlyphKey{
            .codepoint = codepoint,
            .font_id = font_id,
            .size = size,
            .style_flags = .{},
        };

        if (!self.contains(key)) {
            const glyph_data = try render_fn(codepoint);
            try self.put(key, glyph_data);
        }
    }

    // Common Unicode symbols
    const common_symbols = [_]u21{
        0x2022, // Bullet
        0x2013, // En dash
        0x2014, // Em dash
        0x2026, // Ellipsis
        0x00A0, // Non-breaking space
        0x2192, // Right arrow
        0x2190, // Left arrow
        0x2191, // Up arrow
        0x2193, // Down arrow
    };

    for (common_symbols) |cp| {
        const key = GlyphKey{
            .codepoint = cp,
            .font_id = font_id,
            .size = size,
            .style_flags = .{},
        };

        if (!self.contains(key)) {
            const glyph_data = try render_fn(cp);
            try self.put(key, glyph_data);
        }
    }
}

test "GlyphCache basic operations" {
    const allocator = std.testing.allocator;

    const config = CacheConfig{
        .max_size_bytes = 1024 * 1024, // 1MB
        .enable_gpu_cache = false,
    };

    var cache = try init(allocator, config);
    defer cache.deinit();

    // Create test glyph
    const glyph_data = GlyphData{
        .bitmap = try allocator.alloc(u8, 100),
        .width = 10,
        .height = 10,
        .advance = 10.0,
        .bearing_x = 0,
        .bearing_y = 0,
    };

    const key = GlyphKey{
        .codepoint = 'A',
        .font_id = 1,
        .size = 14,
        .style_flags = .{},
    };

    // Put and get
    try cache.put(key, glyph_data);
    const retrieved = cache.get(key);
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.width == 10);

    // Statistics
    const stats = cache.getStatistics();
    try std.testing.expect(stats.hits == 1);
    try std.testing.expect(stats.misses == 0);
}

test "GlyphCache LRU eviction" {
    const allocator = std.testing.allocator;

    const config = CacheConfig{
        .max_size_bytes = 200, // Very small cache
        .enable_gpu_cache = false,
    };

    var cache = try init(allocator, config);
    defer cache.deinit();

    // Add multiple glyphs that exceed cache size
    var i: u21 = 0;
    while (i < 5) : (i += 1) {
        const glyph_data = GlyphData{
            .bitmap = try allocator.alloc(u8, 50),
            .width = 5,
            .height = 10,
            .advance = 5.0,
            .bearing_x = 0,
            .bearing_y = 0,
        };

        const key = GlyphKey{
            .codepoint = 'A' + i,
            .font_id = 1,
            .size = 14,
            .style_flags = .{},
        };

        try cache.put(key, glyph_data);
    }

    // Should have evicted some entries
    const stats = cache.getStatistics();
    try std.testing.expect(stats.evictions > 0);
    try std.testing.expect(cache.current_cache_size <= config.max_size_bytes);
}
