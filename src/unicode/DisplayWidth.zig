//! DisplayWidth - Proper Unicode width handling for terminal display
//! Provides accurate character width calculation using gcode library

const std = @import("std");
const gcode = @import("gcode");
const GcodeIntegration = @import("GcodeIntegration.zig");

/// Unicode display width calculator using gcode library
pub const DisplayWidth = struct {
    gcode_display_width: GcodeIntegration.GcodeDisplayWidth,

    pub fn init(gcode_cache: *GcodeIntegration.GcodeGraphemeCache) DisplayWidth {
        return DisplayWidth{
            .gcode_display_width = GcodeIntegration.GcodeDisplayWidth.init(gcode_cache),
        };
    }

    /// Get display width of a string in terminal columns
    pub fn getStringWidth(self: *DisplayWidth, text: []const u8) !u32 {
        return self.gcode_display_width.getStringWidth(text);
    }

    /// Get width of a single Unicode codepoint using gcode
    pub fn getCodepointWidth(self: *DisplayWidth, codepoint: u21) u8 {
        return self.gcode_display_width.getCodepointWidth(codepoint);
    }

    /// Check if codepoint is wide character using gcode
    pub fn isWideCharacter(self: *DisplayWidth, codepoint: u21) bool {
        return self.gcode_display_width.isWideCharacter(codepoint);
    }

    /// Check if codepoint is zero-width using gcode
    pub fn isZeroWidth(self: *DisplayWidth, codepoint: u21) bool {
        return self.gcode_display_width.isZeroWidth(codepoint);
    }

    /// Truncate string to fit within a specific display width
    pub fn truncateToWidth(self: *DisplayWidth, text: []const u8, max_width: u32, allocator: std.mem.Allocator) ![]u8 {
        return self.gcode_display_width.truncateToWidth(text, max_width, allocator);
    }

    /// Pad string to a specific width with specified character
    pub fn padToWidth(self: *DisplayWidth, text: []const u8, target_width: u32, padding_char: u8, allocator: std.mem.Allocator) ![]u8 {
        return self.gcode_display_width.padToWidth(text, target_width, padding_char, allocator);
    }

    /// Center text within specified width
    pub fn centerText(self: *DisplayWidth, text: []const u8, target_width: u32, allocator: std.mem.Allocator) ![]u8 {
        return self.gcode_display_width.centerText(text, target_width, allocator);
    }

    /// Advanced text wrapping with word boundaries
    pub fn wrapTextAdvanced(self: *DisplayWidth, text: []const u8, max_width: u32, allocator: std.mem.Allocator) ![][]u8 {
        return self.gcode_display_width.wrapTextAdvanced(text, max_width, allocator);
    }

    /// Pad string to a specific width with alignment
    pub fn padToWidthWithAlignment(self: *DisplayWidth, text: []const u8, target_width: u32, alignment: TextAlignment, allocator: std.mem.Allocator) ![]u8 {
        const current_width = try self.getStringWidth(text);

        if (current_width >= target_width) {
            return allocator.dupe(u8, text);
        }

        return switch (alignment) {
            .left => self.padToWidth(text, target_width, ' ', allocator),
            .right => blk: {
                const padding_needed = target_width - current_width;
                var result = std.ArrayList(u8).init(allocator);
                try result.appendNTimes(' ', padding_needed);
                try result.appendSlice(text);
                break :blk result.toOwnedSlice();
            },
            .center => self.centerText(text, target_width, allocator),
        };
    }

    /// Wrap text to fit within specified width (simple line breaking)
    pub fn wrapText(self: *DisplayWidth, text: []const u8, max_width: u32, allocator: std.mem.Allocator) ![][]u8 {
        var lines = std.ArrayList([]u8).init(allocator);
        var remaining = text;

        while (remaining.len > 0) {
            const truncated = try self.truncateToWidth(remaining, max_width, allocator);
            try lines.append(truncated);

            // Move to next part
            if (truncated.len == remaining.len) {
                break; // Processed all text
            }
            remaining = remaining[truncated.len..];

            // Skip leading whitespace on continuation lines
            while (remaining.len > 0 and remaining[0] == ' ') {
                remaining = remaining[1..];
            }
        }

        return lines.toOwnedSlice();
    }

    /// Calculate text metrics for layout purposes
    pub fn getTextMetrics(self: *DisplayWidth, text: []const u8) !TextMetrics {
        const width = try self.getStringWidth(text);

        // Count lines
        var line_count: u32 = 1;
        for (text) |byte| {
            if (byte == '\n') {
                line_count += 1;
            }
        }

        // Find maximum line width
        var max_line_width: u32 = 0;
        var lines_iter = std.mem.split(u8, text, "\n");
        while (lines_iter.next()) |line| {
            const line_width = try self.getStringWidth(line);
            max_line_width = @max(max_line_width, line_width);
        }

        return TextMetrics{
            .total_width = width,
            .max_line_width = max_line_width,
            .line_count = line_count,
        };
    }

    /// Split text at specific width boundary with gcode precision
    pub fn splitTextAtWidth(self: *DisplayWidth, text: []const u8, max_width: u32) !TextSplit {
        return self.gcode_display_width.grapheme_cache.splitTextAtWidth(text, max_width);
    }
};

/// Text alignment options
pub const TextAlignment = enum {
    left,
    right,
    center,
};

/// Text metrics for layout calculations
pub const TextMetrics = struct {
    total_width: u32,
    max_line_width: u32,
    line_count: u32,
};

/// Text split result
pub const TextSplit = struct {
    before: []const u8,
    after: []const u8,
    width: u32,
};

// Direct access functions using gcode (for compatibility)
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

// Grapheme cursor movement using gcode
pub fn findPreviousGrapheme(text: []const u8, pos: usize) usize {
    return gcode.findPreviousGrapheme(text, pos);
}

pub fn findNextGrapheme(text: []const u8, pos: usize) usize {
    return gcode.findNextGrapheme(text, pos);
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
test "DisplayWidth with gcode integration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var gcode_cache = GcodeIntegration.GcodeGraphemeCache.init(arena.allocator());
    defer gcode_cache.deinit();

    var display_width = DisplayWidth.init(&gcode_cache);

    // Test basic width calculation
    const width = try display_width.getStringWidth("hello");
    try std.testing.expectEqual(@as(u32, 5), width);

    // Test character classification
    try std.testing.expect(!display_width.isWideCharacter('A'));
    try std.testing.expect(display_width.isZeroWidth(0x0300)); // Combining accent

    // Test text truncation
    const truncated = try display_width.truncateToWidth("hello world", 5, arena.allocator());
    defer arena.allocator().free(truncated);
    try std.testing.expectEqualStrings("hello", truncated);
}

test "direct gcode API functions" {
    // Test direct access functions
    const width = getStringWidth("hello");
    try std.testing.expectEqual(@as(usize, 5), width);

    try std.testing.expect(!isWideCharacter('A'));
    try std.testing.expect(isZeroWidth(0x0300)); // Combining accent
    try std.testing.expect(isControlCharacter(0x1F)); // Control character
    try std.testing.expect(isDisplayableInTerminal('A'));

    // Test case conversion
    try std.testing.expectEqual(@as(u21, 'H'), toUpper('h'));
    try std.testing.expectEqual(@as(u21, 'z'), toLower('Z'));
    try std.testing.expectEqual(@as(u21, 'A'), toTitle('a'));
}

test "text metrics calculation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var gcode_cache = GcodeIntegration.GcodeGraphemeCache.init(arena.allocator());
    defer gcode_cache.deinit();

    var display_width = DisplayWidth.init(&gcode_cache);

    const metrics = try display_width.getTextMetrics("hello\nworld\ntest");
    try std.testing.expectEqual(@as(u32, 3), metrics.line_count);
    try std.testing.expectEqual(@as(u32, 5), metrics.max_line_width);
}

test "text alignment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var gcode_cache = GcodeIntegration.GcodeGraphemeCache.init(arena.allocator());
    defer gcode_cache.deinit();

    var display_width = DisplayWidth.init(&gcode_cache);

    // Test left alignment (padding)
    const left_padded = try display_width.padToWidthWithAlignment("hi", 5, .left, arena.allocator());
    defer arena.allocator().free(left_padded);
    try std.testing.expectEqualStrings("hi   ", left_padded);

    // Test center alignment
    const centered = try display_width.padToWidthWithAlignment("hi", 5, .center, arena.allocator());
    defer arena.allocator().free(centered);
    try std.testing.expectEqualStrings(" hi  ", centered);
}