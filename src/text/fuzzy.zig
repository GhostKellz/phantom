//! Fuzzy Search Implementation
//! High-performance fuzzy matching for file finders and command palettes
//! Used by Grim (:Files, :Buffers) and Zeke (command palette)

const std = @import("std");

/// Fuzzy match result
pub const FuzzyMatch = struct {
    score: i32,
    positions: []usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *FuzzyMatch) void {
        self.allocator.free(self.positions);
    }
};

/// Fuzzy matcher with scoring heuristics
pub const FuzzyMatcher = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FuzzyMatcher {
        return FuzzyMatcher{ .allocator = allocator };
    }

    /// Fuzzy match pattern against text
    /// Returns match with score and positions, or null if no match
    pub fn match(self: *FuzzyMatcher, pattern: []const u8, text: []const u8) !?FuzzyMatch {
        if (pattern.len == 0) {
            // Empty pattern matches everything with max score
            return FuzzyMatch{
                .score = 100,
                .positions = &[_]usize{},
                .allocator = self.allocator,
            };
        }

        if (text.len == 0) return null;

        var positions = std.ArrayList(usize).init(self.allocator);
        errdefer positions.deinit();

        var score: i32 = 0;
        var pattern_idx: usize = 0;
        var text_idx: usize = 0;
        var consecutive: i32 = 0;
        var last_match_idx: ?usize = null;

        while (pattern_idx < pattern.len and text_idx < text.len) {
            const p_char = std.ascii.toLower(pattern[pattern_idx]);
            const t_char = std.ascii.toLower(text[text_idx]);

            if (p_char == t_char) {
                try positions.append(text_idx);

                // Base score for match
                score += 1;

                // Bonus for consecutive matches
                if (last_match_idx) |last_idx| {
                    if (text_idx == last_idx + 1) {
                        consecutive += 1;
                        score += 5 + consecutive; // Increasing bonus for longer sequences
                    } else {
                        consecutive = 0;
                    }
                } else {
                    consecutive = 0;
                }

                // Bonus for matching at start
                if (text_idx == 0) {
                    score += 15;
                }

                // Bonus for matching after separator
                if (text_idx > 0 and isSeparator(text[text_idx - 1])) {
                    score += 10;
                }

                // Bonus for matching uppercase after lowercase (camelCase)
                if (text_idx > 0 and
                    std.ascii.isLower(text[text_idx - 1]) and
                    std.ascii.isUpper(text[text_idx])) {
                    score += 8;
                }

                last_match_idx = text_idx;
                pattern_idx += 1;
            }

            text_idx += 1;
        }

        // Pattern not fully matched
        if (pattern_idx != pattern.len) {
            positions.deinit();
            return null;
        }

        // Penalty for length difference (prefer shorter matches)
        const length_penalty = @as(i32, @intCast(text.len - pattern.len));
        score -= length_penalty;

        return FuzzyMatch{
            .score = score,
            .positions = try positions.toOwnedSlice(),
            .allocator = self.allocator,
        };
    }

    /// Check if character is a word separator
    fn isSeparator(c: u8) bool {
        return c == '/' or c == '\\' or c == '_' or
               c == '-' or c == ' ' or c == '.' or c == ':';
    }
};

/// Fuzzy match and sort a list of items
pub fn fuzzyFilter(
    allocator: std.mem.Allocator,
    pattern: []const u8,
    items: []const []const u8,
) ![]FuzzyFilterResult {
    var matcher = FuzzyMatcher.init(allocator);
    var results = std.ArrayList(FuzzyFilterResult).init(allocator);
    defer results.deinit();

    for (items, 0..) |item, i| {
        if (try matcher.match(pattern, item)) |fuzzy_match| {
            try results.append(FuzzyFilterResult{
                .item = item,
                .index = i,
                .score = fuzzy_match.score,
                .positions = fuzzy_match.positions,
            });
        }
    }

    const owned = try results.toOwnedSlice();

    // Sort by score (descending)
    std.mem.sort(FuzzyFilterResult, owned, {}, fuzzyFilterResultCompare);

    return owned;
}

pub const FuzzyFilterResult = struct {
    item: []const u8,
    index: usize,
    score: i32,
    positions: []usize,

    pub fn deinit(self: *FuzzyFilterResult, allocator: std.mem.Allocator) void {
        allocator.free(self.positions);
    }
};

fn fuzzyFilterResultCompare(_: void, a: FuzzyFilterResult, b: FuzzyFilterResult) bool {
    return a.score > b.score; // Higher scores first
}

// Tests
test "FuzzyMatcher basic matching" {
    const testing = std.testing;
    var matcher = FuzzyMatcher.init(testing.allocator);

    // Exact match
    var result1 = (try matcher.match("test", "test")).?;
    defer result1.deinit();
    try testing.expect(result1.score > 0);
    try testing.expectEqual(@as(usize, 4), result1.positions.len);

    // Substring match
    var result2 = (try matcher.match("te", "test")).?;
    defer result2.deinit();
    try testing.expect(result2.score > 0);
    try testing.expectEqual(@as(usize, 2), result2.positions.len);

    // Non-contiguous match
    var result3 = (try matcher.match("tt", "test")).?;
    defer result3.deinit();
    try testing.expect(result3.score > 0);
    try testing.expectEqual(@as(usize, 2), result3.positions.len);
}

test "FuzzyMatcher case insensitive" {
    const testing = std.testing;
    var matcher = FuzzyMatcher.init(testing.allocator);

    var result = (try matcher.match("TeSt", "test")).?;
    defer result.deinit();
    try testing.expect(result.score > 0);
}

test "FuzzyMatcher no match" {
    const testing = std.testing;
    var matcher = FuzzyMatcher.init(testing.allocator);

    const result = try matcher.match("xyz", "test");
    try testing.expect(result == null);
}

test "FuzzyMatcher scoring bonuses" {
    const testing = std.testing;
    var matcher = FuzzyMatcher.init(testing.allocator);

    // Match at start should score higher
    var start_match = (try matcher.match("te", "test")).?;
    defer start_match.deinit();

    var middle_match = (try matcher.match("es", "test")).?;
    defer middle_match.deinit();

    try testing.expect(start_match.score > middle_match.score);
}

test "FuzzyMatcher separator bonus" {
    const testing = std.testing;
    var matcher = FuzzyMatcher.init(testing.allocator);

    // Match after separator should score higher
    var sep_match = (try matcher.match("bar", "foo_bar")).?;
    defer sep_match.deinit();

    var no_sep_match = (try matcher.match("oba", "foo_bar")).?;
    defer no_sep_match.deinit();

    try testing.expect(sep_match.score > no_sep_match.score);
}

test "fuzzyFilter sorting" {
    const testing = std.testing;

    const items = [_][]const u8{
        "zebra.zig",
        "app.zig",
        "main.zig",
        "test_app.zig",
    };

    const results = try fuzzyFilter(testing.allocator, "app", &items);
    defer {
        for (results) |*r| {
            var result = r.*;
            result.deinit(testing.allocator);
        }
        testing.allocator.free(results);
    }

    // Should match "app.zig" and "test_app.zig"
    try testing.expectEqual(@as(usize, 2), results.len);

    // "app.zig" should score higher than "test_app.zig" (exact match at start)
    try testing.expectEqualStrings("app.zig", results[0].item);
}
