//! GraphemeCache - Unicode grapheme cluster handling using gcode library
//! Provides production-quality grapheme segmentation and caching

const std = @import("std");
const gcode = @import("gcode");
const GcodeIntegration = @import("GcodeIntegration.zig");

/// GraphemeCache wrapper around gcode implementation
pub const GraphemeCache = struct {
    gcode_cache: GcodeIntegration.GcodeGraphemeCache,

    pub fn init(alloc: std.mem.Allocator) GraphemeCache {
        return GraphemeCache{
            .gcode_cache = GcodeIntegration.GcodeGraphemeCache.init(alloc),
        };
    }

    pub fn deinit(self: *GraphemeCache) void {
        self.gcode_cache.deinit();
    }

    /// Get allocator for compatibility
    pub fn allocator(self: *GraphemeCache) std.mem.Allocator {
        return self.gcode_cache.allocator;
    }

    /// Get grapheme clusters from text using gcode
    pub fn getGraphemes(self: *GraphemeCache, text: []const u8) ![]GraphemeCluster {
        return self.gcode_cache.getGraphemes(text);
    }

    /// Get text width using gcode
    pub fn getTextWidth(self: *GraphemeCache, text: []const u8) !u32 {
        return self.gcode_cache.getTextWidth(text);
    }

    /// Split text at width boundary using gcode
    pub fn splitTextAtWidth(self: *GraphemeCache, text: []const u8, max_width: u32) !TextSplit {
        return self.gcode_cache.splitTextAtWidth(text, max_width);
    }

    /// Clear the cache
    pub fn clearCache(self: *GraphemeCache) void {
        self.gcode_cache.clearCache();
    }

    /// Set maximum cache size
    pub fn setMaxCacheSize(self: *GraphemeCache, max_size: usize) void {
        self.gcode_cache.max_cache_size = max_size;
    }

    /// Get cache statistics
    pub fn getCacheStats(self: *GraphemeCache) CacheStats {
        return CacheStats{
            .entries = self.gcode_cache.cache.count(),
            .max_size = self.gcode_cache.max_cache_size,
        };
    }
};

/// Re-export types from GcodeIntegration for compatibility
pub const GraphemeCluster = GcodeIntegration.GraphemeCluster;
pub const TextSplit = GcodeIntegration.TextSplit;

/// Cache statistics
pub const CacheStats = struct {
    entries: usize,
    max_size: usize,
};

// Direct gcode iterator access for advanced use cases
pub fn graphemeIterator(text: []const u8) gcode.GraphemeIterator {
    return gcode.graphemeIterator(text);
}

pub fn reverseGraphemeIterator(text: []const u8) gcode.ReverseGraphemeIterator {
    return gcode.ReverseGraphemeIterator.init(text);
}

// Grapheme boundary detection using gcode
pub fn isGraphemeBoundary(before: u21, after: u21) bool {
    return gcode.graphemeBreak(before, after);
}

// Cursor movement helpers using gcode
pub fn findPreviousGrapheme(text: []const u8, pos: usize) usize {
    return gcode.findPreviousGrapheme(text, pos);
}

pub fn findNextGrapheme(text: []const u8, pos: usize) usize {
    return gcode.findNextGrapheme(text, pos);
}

// Grapheme properties using gcode
pub fn getGraphemeProperties(codepoint: u21) gcode.Properties {
    return gcode.getProperties(codepoint);
}

pub fn getGraphemeBoundaryClass(codepoint: u21) gcode.GraphemeBoundaryClass {
    return gcode.getProperties(codepoint).grapheme_break;
}

// Tests
test "GraphemeCache with gcode integration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cache = GraphemeCache.init(arena.allocator());
    defer cache.deinit();

    // Test basic functionality
    const clusters = try cache.getGraphemes("hello");
    defer arena.allocator().free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("h", clusters[0].bytes);
    try std.testing.expectEqualStrings("e", clusters[1].bytes);

    // Test text width
    const width = try cache.getTextWidth("hello");
    try std.testing.expectEqual(@as(u32, 5), width);

    // Test text splitting
    const split = try cache.splitTextAtWidth("hello world", 5);
    try std.testing.expectEqualStrings("hello", split.before);
    try std.testing.expectEqualStrings(" world", split.after);
}

test "gcode grapheme iteration" {
    var iter = graphemeIterator("hello");

    try std.testing.expectEqualStrings("h", iter.next().?);
    try std.testing.expectEqualStrings("e", iter.next().?);
    try std.testing.expectEqualStrings("l", iter.next().?);
    try std.testing.expectEqualStrings("l", iter.next().?);
    try std.testing.expectEqualStrings("o", iter.next().?);
    try std.testing.expect(iter.next() == null);
}

test "gcode reverse grapheme iteration" {
    var iter = reverseGraphemeIterator("hello");

    try std.testing.expectEqualStrings("o", iter.prev().?);
    try std.testing.expectEqualStrings("l", iter.prev().?);
    try std.testing.expectEqualStrings("l", iter.prev().?);
    try std.testing.expectEqualStrings("e", iter.prev().?);
    try std.testing.expectEqualStrings("h", iter.prev().?);
    try std.testing.expect(iter.prev() == null);
}

test "grapheme boundary detection" {
    // Test that letter to letter is not a boundary
    try std.testing.expect(!isGraphemeBoundary('a', 'b'));

    // Test that letter to combining mark is not a boundary
    try std.testing.expect(!isGraphemeBoundary('a', 0x0300)); // Combining grave accent

    // Test that space to letter is a boundary
    try std.testing.expect(isGraphemeBoundary(' ', 'a'));
}

test "cursor movement" {
    const text = "hello";

    // Test forward movement
    try std.testing.expectEqual(@as(usize, 1), findNextGrapheme(text, 0));
    try std.testing.expectEqual(@as(usize, 2), findNextGrapheme(text, 1));
    try std.testing.expectEqual(@as(usize, 5), findNextGrapheme(text, 4));

    // Test backward movement
    try std.testing.expectEqual(@as(usize, 0), findPreviousGrapheme(text, 1));
    try std.testing.expectEqual(@as(usize, 3), findPreviousGrapheme(text, 4));
    try std.testing.expectEqual(@as(usize, 0), findPreviousGrapheme(text, 0));
}

test "cache statistics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cache = GraphemeCache.init(arena.allocator());
    defer cache.deinit();

    // Initial cache should be empty
    const initial_stats = cache.getCacheStats();
    try std.testing.expectEqual(@as(usize, 0), initial_stats.entries);

    // Process some text to populate cache
    _ = try cache.getGraphemes("hello");

    // Cache should have some entries
    const after_stats = cache.getCacheStats();
    try std.testing.expect(after_stats.entries > 0);

    // Test cache clearing
    cache.clearCache();
    const cleared_stats = cache.getCacheStats();
    try std.testing.expectEqual(@as(usize, 0), cleared_stats.entries);
}