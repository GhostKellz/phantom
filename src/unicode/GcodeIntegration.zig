//! Gcode Unicode Integration Module
//! Production-ready Unicode processing using the gcode library
//! Provides high-performance Unicode operations optimized for terminal emulators

const std = @import("std");
const gcode = @import("gcode");
const Allocator = std.mem.Allocator;

/// Enhanced GraphemeCache using gcode for production-quality Unicode support
pub const GcodeGraphemeCache = struct {
    allocator: Allocator,
    cache: CacheType,
    max_cache_size: usize = 10000,

    const CacheType = std.HashMap(u32, GraphemeInfo, HashContext, std.hash_map.default_max_load_percentage);

    const HashContext = struct {
        pub fn hash(self: @This(), key: u32) u64 {
            _ = self;
            return std.hash_map.hashInt(key);
        }

        pub fn eql(self: @This(), a: u32, b: u32) bool {
            _ = self;
            return a == b;
        }
    };

    pub fn init(allocator: Allocator) GcodeGraphemeCache {
        return GcodeGraphemeCache{
            .allocator = allocator,
            .cache = CacheType.init(allocator),
        };
    }

    pub fn deinit(self: *GcodeGraphemeCache) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.cluster);
            self.allocator.free(entry.value_ptr.codepoints);
        }
        self.cache.deinit();
    }

    /// Get grapheme clusters from a string using gcode
    pub fn getGraphemes(self: *GcodeGraphemeCache, text: []const u8) ![]GraphemeCluster {
        var clusters = std.ArrayList(GraphemeCluster).init(self.allocator);

        var iterator = gcode.graphemeIterator(text);
        while (iterator.next()) |cluster_bytes| {
            const cluster = try self.getOrCreateCluster(cluster_bytes);
            try clusters.append(cluster);
        }

        return clusters.toOwnedSlice();
    }

    /// Get text width using gcode's optimized algorithm
    pub fn getTextWidth(self: *GcodeGraphemeCache, text: []const u8) !u32 {
        _ = self;
        return @as(u32, @intCast(gcode.stringWidth(text)));
    }

    /// Split text at width boundary using gcode
    pub fn splitTextAtWidth(self: *GcodeGraphemeCache, text: []const u8, max_width: u32) !TextSplit {
        var current_width: u32 = 0;
        var byte_position: usize = 0;

        var iterator = gcode.graphemeIterator(text);
        while (iterator.next()) |cluster_bytes| {
            const cluster = try self.getOrCreateCluster(cluster_bytes);

            if (current_width + cluster.width > max_width) {
                break;
            }

            current_width += cluster.width;
            byte_position += cluster_bytes.len;
        }

        return TextSplit{
            .before = text[0..byte_position],
            .after = text[byte_position..],
            .width = current_width,
        };
    }

    /// Get or create a cached grapheme cluster
    fn getOrCreateCluster(self: *GcodeGraphemeCache, cluster_bytes: []const u8) !GraphemeCluster {
        const hash = std.hash_map.hashString(cluster_bytes);

        if (self.cache.get(hash)) |info| {
            return GraphemeCluster{
                .bytes = info.cluster,
                .width = info.width,
                .codepoints = info.codepoints,
            };
        }

        // Create new cluster info
        const info = try self.analyzeCluster(cluster_bytes);

        // Manage cache size
        if (self.cache.count() >= self.max_cache_size) {
            try self.evictOldEntries();
        }

        try self.cache.put(hash, info);

        return GraphemeCluster{
            .bytes = info.cluster,
            .width = info.width,
            .codepoints = info.codepoints,
        };
    }

    /// Analyze a grapheme cluster using gcode
    fn analyzeCluster(self: *GcodeGraphemeCache, cluster_bytes: []const u8) !GraphemeInfo {
        var codepoints = std.ArrayList(u21).init(self.allocator);
        defer codepoints.deinit();

        // Decode UTF-8 to get codepoints using gcode utilities
        var cp_iterator = gcode.codePointIterator(cluster_bytes);
        while (cp_iterator.next()) |cp_info| {
            try codepoints.append(cp_info.code);
        }

        // Calculate display width using gcode
        const width = self.calculateWidthWithGcode(codepoints.items);

        return GraphemeInfo{
            .cluster = try self.allocator.dupe(u8, cluster_bytes),
            .width = width,
            .codepoints = try codepoints.toOwnedSlice(),
        };
    }

    /// Calculate width using gcode's precise algorithms
    fn calculateWidthWithGcode(self: *GcodeGraphemeCache, codepoints: []const u21) u8 {
        _ = self;

        if (codepoints.len == 0) return 0;

        // For single codepoints, use gcode directly
        if (codepoints.len == 1) {
            return gcode.getWidth(codepoints[0]);
        }

        // For grapheme clusters, use more sophisticated logic
        var total_width: u8 = 0;
        var has_base = false;

        for (codepoints) |cp| {
            if (gcode.isZeroWidth(cp)) {
                // Zero-width characters don't contribute to width
                continue;
            } else {
                has_base = true;
                total_width = @max(total_width, gcode.getWidth(cp));
            }
        }

        // If no base character found, assume width 1
        if (!has_base) {
            return 1;
        }

        return total_width;
    }

    /// Evict old cache entries
    fn evictOldEntries(self: *GcodeGraphemeCache) !void {
        // Simple eviction: remove half the entries
        const target_size = self.max_cache_size / 2;
        var removed_count: usize = 0;

        var iterator = self.cache.iterator();
        var keys_to_remove = std.ArrayList(u32).init(self.allocator);
        defer keys_to_remove.deinit();

        while (iterator.next()) |entry| {
            if (removed_count >= target_size) break;
            try keys_to_remove.append(entry.key_ptr.*);
            removed_count += 1;
        }

        for (keys_to_remove.items) |key| {
            if (self.cache.fetchRemove(key)) |entry| {
                self.allocator.free(entry.value.cluster);
                self.allocator.free(entry.value.codepoints);
            }
        }
    }

    /// Clear the cache
    pub fn clearCache(self: *GcodeGraphemeCache) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.cluster);
            self.allocator.free(entry.value_ptr.codepoints);
        }
        self.cache.clearRetainingCapacity();
    }
};

/// Enhanced display width calculator using gcode
pub const GcodeDisplayWidth = struct {
    grapheme_cache: *GcodeGraphemeCache,

    pub fn init(grapheme_cache: *GcodeGraphemeCache) GcodeDisplayWidth {
        return GcodeDisplayWidth{
            .grapheme_cache = grapheme_cache,
        };
    }

    /// Get display width using gcode's optimized algorithm
    pub fn getStringWidth(self: *GcodeDisplayWidth, text: []const u8) !u32 {
        return self.grapheme_cache.getTextWidth(text);
    }

    /// Get width of a single codepoint using gcode
    pub fn getCodepointWidth(self: *GcodeDisplayWidth, codepoint: u21) u8 {
        _ = self;
        return gcode.getWidth(codepoint);
    }

    /// Check if codepoint is wide using gcode
    pub fn isWideCharacter(self: *GcodeDisplayWidth, codepoint: u21) bool {
        _ = self;
        return gcode.isWide(codepoint);
    }

    /// Check if codepoint is zero-width using gcode
    pub fn isZeroWidth(self: *GcodeDisplayWidth, codepoint: u21) bool {
        _ = self;
        return gcode.isZeroWidth(codepoint);
    }

    /// Advanced text wrapping with word boundaries using gcode
    pub fn wrapTextAdvanced(self: *GcodeDisplayWidth, text: []const u8, max_width: u32, allocator: std.mem.Allocator) ![][]u8 {
        var lines = std.ArrayList([]u8).init(allocator);
        var remaining = text;

        while (remaining.len > 0) {
            const break_point = try self.findOptimalBreakPoint(remaining, max_width);

            if (break_point.position == 0) {
                // Can't fit even one character, break anyway
                const next_cluster = try self.getNextGraphemeCluster(remaining);
                try lines.append(try allocator.dupe(u8, next_cluster));
                remaining = remaining[next_cluster.len..];
            } else {
                try lines.append(try allocator.dupe(u8, remaining[0..break_point.position]));
                remaining = remaining[break_point.position..];
            }

            // Skip leading whitespace on continuation lines
            while (remaining.len > 0 and remaining[0] == ' ') {
                remaining = remaining[1..];
            }
        }

        return lines.toOwnedSlice();
    }

    /// Find optimal break point considering word boundaries using gcode's word iterator
    fn findOptimalBreakPoint(self: *GcodeDisplayWidth, text: []const u8, max_width: u32) !BreakPoint {
        const split = try self.grapheme_cache.splitTextAtWidth(text, max_width);

        // Look for word boundaries near the break point using gcode's word iterator
        var break_pos = split.before.len;
        var is_word_break = false;

        // Use gcode's word boundary detection
        if (break_pos < text.len) {
            var word_iter = gcode.wordIterator(text[0..split.before.len + 1]);
            var last_word_end: usize = 0;

            while (word_iter.next()) |word| {
                const word_start = word.bytes.ptr - text.ptr;
                const word_end = word_start + word.bytes.len;

                if (word_end <= split.before.len) {
                    last_word_end = word_end;
                } else {
                    break;
                }
            }

            // If we found a good word boundary, use it
            if (last_word_end > 0 and last_word_end < split.before.len) {
                break_pos = last_word_end;
                is_word_break = true;
            }
        }

        const actual_width = try self.getStringWidth(text[0..break_pos]);

        return BreakPoint{
            .position = break_pos,
            .width = actual_width,
            .is_word_break = is_word_break,
        };
    }

    /// Get the next grapheme cluster from text
    fn getNextGraphemeCluster(self: *GcodeDisplayWidth, text: []const u8) ![]const u8 {
        _ = self;
        var iterator = gcode.graphemeIterator(text);
        if (iterator.next()) |cluster| {
            return cluster;
        }
        return "";
    }

    /// Truncate text to fit within specified width using gcode
    pub fn truncateToWidth(self: *GcodeDisplayWidth, text: []const u8, max_width: u32, allocator: std.mem.Allocator) ![]u8 {
        const split = try self.grapheme_cache.splitTextAtWidth(text, max_width);
        return allocator.dupe(u8, split.before);
    }

    /// Pad text to specified width using gcode for width calculation
    pub fn padToWidth(self: *GcodeDisplayWidth, text: []const u8, target_width: u32, padding_char: u8, allocator: std.mem.Allocator) ![]u8 {
        const current_width = try self.getStringWidth(text);

        if (current_width >= target_width) {
            return allocator.dupe(u8, text);
        }

        const padding_needed = target_width - current_width;
        var result = std.ArrayList(u8).init(allocator);

        try result.appendSlice(text);
        try result.appendNTimes(padding_char, padding_needed);

        return result.toOwnedSlice();
    }

    /// Center text within specified width using gcode
    pub fn centerText(self: *GcodeDisplayWidth, text: []const u8, target_width: u32, allocator: std.mem.Allocator) ![]u8 {
        const current_width = try self.getStringWidth(text);

        if (current_width >= target_width) {
            return allocator.dupe(u8, text);
        }

        const total_padding = target_width - current_width;
        const left_padding = total_padding / 2;
        const right_padding = total_padding - left_padding;

        var result = std.ArrayList(u8).init(allocator);

        try result.appendNTimes(' ', left_padding);
        try result.appendSlice(text);
        try result.appendNTimes(' ', right_padding);

        return result.toOwnedSlice();
    }
};

/// BiDi text support using gcode's BiDi implementation
pub const GcodeBiDi = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) GcodeBiDi {
        return GcodeBiDi{
            .allocator = allocator,
        };
    }

    /// Reorder text for display using gcode's BiDi algorithm
    pub fn reorderForDisplay(self: *GcodeBiDi, text: []const u8) ![]u8 {
        return gcode.reorderForDisplay(text, self.allocator);
    }

    /// Calculate cursor position in visual order from logical position
    pub fn visualToLogical(self: *GcodeBiDi, text: []const u8, visual_pos: usize) !usize {
        _ = self;
        return gcode.visualToLogical(text, visual_pos);
    }

    /// Get text direction using gcode
    pub fn getTextDirection(self: *GcodeBiDi, text: []const u8) gcode.Direction {
        _ = self;
        var context = gcode.BiDiContext.init();
        defer context.deinit();

        return context.analyze(text);
    }
};

// Data structures
const GraphemeInfo = struct {
    cluster: []u8,
    width: u8,
    codepoints: []u21,
};

pub const GraphemeCluster = struct {
    bytes: []const u8,
    width: u8,
    codepoints: []const u21,
};

pub const TextSplit = struct {
    before: []const u8,
    after: []const u8,
    width: u32,
};

pub const BreakPoint = struct {
    position: usize,
    width: u32,
    is_word_break: bool,
};

// Helper functions for direct gcode integration
pub fn getStringWidth(text: []const u8) usize {
    return gcode.stringWidth(text);
}

pub fn getCodepointWidth(codepoint: u21) u8 {
    return gcode.getWidth(codepoint);
}

pub fn isWideCharacter(codepoint: u21) bool {
    return gcode.isWide(codepoint);
}

pub fn isZeroWidth(codepoint: u21) bool {
    return gcode.isZeroWidth(codepoint);
}

pub fn isControlCharacter(codepoint: u21) bool {
    return gcode.isControlCharacter(codepoint);
}

pub fn isDisplayableInTerminal(codepoint: u21) bool {
    return gcode.isDisplayableInTerminal(codepoint);
}

// Cursor movement helpers using gcode
pub fn findPreviousGrapheme(text: []const u8, pos: usize) usize {
    return gcode.findPreviousGrapheme(text, pos);
}

pub fn findNextGrapheme(text: []const u8, pos: usize) usize {
    return gcode.findNextGrapheme(text, pos);
}

// Word processing using gcode
pub fn wordIterator(text: []const u8) gcode.WordIterator {
    return gcode.wordIterator(text);
}

// Case conversion using gcode
pub fn toLower(codepoint: u21) u21 {
    return gcode.toLower(codepoint);
}

pub fn toUpper(codepoint: u21) u21 {
    return gcode.toUpper(codepoint);
}

pub fn toTitle(codepoint: u21) u21 {
    return gcode.toTitle(codepoint);
}

// Tests
test "GcodeGraphemeCache basic functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cache = GcodeGraphemeCache.init(arena.allocator());
    defer cache.deinit();

    // Test simple ASCII
    const ascii_width = try cache.getTextWidth("hello");
    try std.testing.expectEqual(@as(u32, 5), ascii_width);

    // Test text splitting
    const split = try cache.splitTextAtWidth("hello world", 5);
    try std.testing.expectEqualStrings("hello", split.before);
    try std.testing.expectEqualStrings(" world", split.after);
    try std.testing.expectEqual(@as(u32, 5), split.width);
}

test "GcodeDisplayWidth integration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cache = GcodeGraphemeCache.init(arena.allocator());
    defer cache.deinit();

    var display_width = GcodeDisplayWidth.init(&cache);

    // Test width calculation
    const width = try display_width.getStringWidth("hello");
    try std.testing.expectEqual(@as(u32, 5), width);

    // Test character classification
    try std.testing.expect(!display_width.isWideCharacter('A'));
    try std.testing.expect(display_width.isZeroWidth(0x0300)); // Combining accent
}

test "gcode direct API usage" {
    // Test direct gcode functions
    const width = getStringWidth("hello");
    try std.testing.expectEqual(@as(usize, 5), width);

    try std.testing.expect(!isWideCharacter('A'));
    try std.testing.expect(isZeroWidth(0x0300)); // Combining accent
    try std.testing.expect(isControlCharacter(0x1F)); // Control character
    try std.testing.expect(isDisplayableInTerminal('A'));
}

test "gcode grapheme iteration" {
    var iter = gcode.graphemeIterator("hello");

    try std.testing.expectEqualStrings("h", iter.next().?);
    try std.testing.expectEqualStrings("e", iter.next().?);
    try std.testing.expectEqualStrings("l", iter.next().?);
    try std.testing.expectEqualStrings("l", iter.next().?);
    try std.testing.expectEqualStrings("o", iter.next().?);
    try std.testing.expect(iter.next() == null);
}

test "gcode case conversion" {
    try std.testing.expectEqual(@as(u21, 'H'), toUpper('h'));
    try std.testing.expectEqual(@as(u21, 'z'), toLower('Z'));
    try std.testing.expectEqual(@as(u21, 'A'), toTitle('a'));
}