//! Unicode support and text utilities for Phantom TUI
const std = @import("std");

/// Unicode character width calculation
pub const UnicodeWidth = struct {
    /// Calculate the display width of a Unicode codepoint
    pub fn codepointWidth(codepoint: u21) u8 {
        // ASCII printable characters
        if (codepoint >= 0x20 and codepoint <= 0x7E) {
            return 1;
        }
        
        // Control characters (including newline, tab, etc.)
        if (codepoint < 0x20 or codepoint == 0x7F) {
            return 0;
        }
        
        // Common Unicode ranges
        if (isWideCharacter(codepoint)) {
            return 2;
        }
        
        // Zero-width characters
        if (isZeroWidth(codepoint)) {
            return 0;
        }
        
        // Default to 1 for most characters
        return 1;
    }
    
    /// Calculate the display width of a UTF-8 string
    pub fn stringWidth(text: []const u8) !u16 {
        var width: u16 = 0;
        var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        
        while (iter.nextCodepoint()) |codepoint| {
            width += codepointWidth(codepoint);
        }
        
        return width;
    }
    
    /// Calculate the display width of a UTF-8 string up to a maximum width
    pub fn stringWidthTruncated(text: []const u8, max_width: u16) !struct { width: u16, byte_count: usize } {
        var width: u16 = 0;
        var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        var byte_count: usize = 0;
        
        while (iter.nextCodepoint()) |codepoint| {
            const char_width = codepointWidth(codepoint);
            if (width + char_width > max_width) {
                break;
            }
            width += char_width;
            byte_count = iter.i;
        }
        
        return .{ .width = width, .byte_count = byte_count };
    }
    
    /// Check if a character is wide (takes 2 terminal columns)
    fn isWideCharacter(codepoint: u21) bool {
        // East Asian Wide characters (simplified check)
        if (codepoint >= 0x1100 and codepoint <= 0x115F) return true; // Hangul Jamo
        if (codepoint >= 0x2E80 and codepoint <= 0x2EFF) return true; // CJK Radicals Supplement
        if (codepoint >= 0x2F00 and codepoint <= 0x2FDF) return true; // Kangxi Radicals
        if (codepoint >= 0x2FF0 and codepoint <= 0x2FFF) return true; // Ideographic Description Characters
        if (codepoint >= 0x3000 and codepoint <= 0x303F) return true; // CJK Symbols and Punctuation
        if (codepoint >= 0x3040 and codepoint <= 0x309F) return true; // Hiragana
        if (codepoint >= 0x30A0 and codepoint <= 0x30FF) return true; // Katakana
        if (codepoint >= 0x3100 and codepoint <= 0x312F) return true; // Bopomofo
        if (codepoint >= 0x3130 and codepoint <= 0x318F) return true; // Hangul Compatibility Jamo
        if (codepoint >= 0x3190 and codepoint <= 0x319F) return true; // Kanbun
        if (codepoint >= 0x31A0 and codepoint <= 0x31BF) return true; // Bopomofo Extended
        if (codepoint >= 0x31C0 and codepoint <= 0x31EF) return true; // CJK Strokes
        if (codepoint >= 0x31F0 and codepoint <= 0x31FF) return true; // Katakana Phonetic Extensions
        if (codepoint >= 0x3200 and codepoint <= 0x32FF) return true; // Enclosed CJK Letters and Months
        if (codepoint >= 0x3300 and codepoint <= 0x33FF) return true; // CJK Compatibility
        if (codepoint >= 0x3400 and codepoint <= 0x4DBF) return true; // CJK Unified Ideographs Extension A
        if (codepoint >= 0x4E00 and codepoint <= 0x9FFF) return true; // CJK Unified Ideographs
        if (codepoint >= 0xA000 and codepoint <= 0xA48F) return true; // Yi Syllables
        if (codepoint >= 0xA490 and codepoint <= 0xA4CF) return true; // Yi Radicals
        if (codepoint >= 0xAC00 and codepoint <= 0xD7AF) return true; // Hangul Syllables
        if (codepoint >= 0xF900 and codepoint <= 0xFAFF) return true; // CJK Compatibility Ideographs
        if (codepoint >= 0xFE10 and codepoint <= 0xFE19) return true; // Vertical Forms
        if (codepoint >= 0xFE30 and codepoint <= 0xFE4F) return true; // CJK Compatibility Forms
        if (codepoint >= 0xFE50 and codepoint <= 0xFE6F) return true; // Small Form Variants
        if (codepoint >= 0xFE70 and codepoint <= 0xFEFF) return true; // Arabic Presentation Forms-B
        if (codepoint >= 0xFF00 and codepoint <= 0xFFEF) return true; // Halfwidth and Fullwidth Forms
        if (codepoint >= 0x20000 and codepoint <= 0x2A6DF) return true; // CJK Unified Ideographs Extension B
        if (codepoint >= 0x2A700 and codepoint <= 0x2B73F) return true; // CJK Unified Ideographs Extension C
        if (codepoint >= 0x2B740 and codepoint <= 0x2B81F) return true; // CJK Unified Ideographs Extension D
        if (codepoint >= 0x2B820 and codepoint <= 0x2CEAF) return true; // CJK Unified Ideographs Extension E
        if (codepoint >= 0x2CEB0 and codepoint <= 0x2EBEF) return true; // CJK Unified Ideographs Extension F
        
        // Emoji (simplified check for common emoji ranges)
        if (codepoint >= 0x1F300 and codepoint <= 0x1F5FF) return true; // Miscellaneous Symbols and Pictographs
        if (codepoint >= 0x1F600 and codepoint <= 0x1F64F) return true; // Emoticons
        if (codepoint >= 0x1F680 and codepoint <= 0x1F6FF) return true; // Transport and Map Symbols
        if (codepoint >= 0x1F700 and codepoint <= 0x1F77F) return true; // Alchemical Symbols
        if (codepoint >= 0x1F780 and codepoint <= 0x1F7FF) return true; // Geometric Shapes Extended
        if (codepoint >= 0x1F800 and codepoint <= 0x1F8FF) return true; // Supplemental Arrows-C
        if (codepoint >= 0x1F900 and codepoint <= 0x1F9FF) return true; // Supplemental Symbols and Pictographs
        
        return false;
    }
    
    /// Check if a character is zero-width
    fn isZeroWidth(codepoint: u21) bool {
        // Zero Width Space
        if (codepoint == 0x200B) return true;
        
        // Zero Width Non-Joiner
        if (codepoint == 0x200C) return true;
        
        // Zero Width Joiner
        if (codepoint == 0x200D) return true;
        
        // Combining characters (simplified check)
        if (codepoint >= 0x0300 and codepoint <= 0x036F) return true; // Combining Diacritical Marks
        if (codepoint >= 0x0483 and codepoint <= 0x0489) return true; // Combining Cyrillic
        if (codepoint >= 0x0591 and codepoint <= 0x05BD) return true; // Hebrew combining marks
        if (codepoint >= 0x05BF and codepoint <= 0x05BF) return true;
        if (codepoint >= 0x05C1 and codepoint <= 0x05C2) return true;
        if (codepoint >= 0x05C4 and codepoint <= 0x05C5) return true;
        if (codepoint >= 0x05C7 and codepoint <= 0x05C7) return true;
        if (codepoint >= 0x0610 and codepoint <= 0x061A) return true; // Arabic combining marks
        if (codepoint >= 0x064B and codepoint <= 0x065F) return true;
        if (codepoint >= 0x0670 and codepoint <= 0x0670) return true;
        if (codepoint >= 0x06D6 and codepoint <= 0x06DC) return true;
        if (codepoint >= 0x06DF and codepoint <= 0x06E4) return true;
        if (codepoint >= 0x06E7 and codepoint <= 0x06E8) return true;
        if (codepoint >= 0x06EA and codepoint <= 0x06ED) return true;
        
        return false;
    }
};

/// Text wrapping utilities
pub const TextWrap = struct {
    /// Wrap text to fit within a given width
    pub fn wrapText(allocator: std.mem.Allocator, text: []const u8, width: u16) !std.ArrayList([]const u8) {
        var lines = std.ArrayList([]const u8).init(allocator);
        
        if (width == 0) {
            try lines.append(try allocator.dupe(u8, ""));
            return lines;
        }
        
        var line_iter = std.mem.split(u8, text, "\n");
        while (line_iter.next()) |line| {
            try wrapLine(allocator, &lines, line, width);
        }
        
        return lines;
    }
    
    fn wrapLine(allocator: std.mem.Allocator, lines: *std.ArrayList([]const u8), line: []const u8, width: u16) !void {
        var start: usize = 0;
        var iter = std.unicode.Utf8Iterator{ .bytes = line, .i = 0 };
        var current_width: u16 = 0;
        var last_space: ?usize = null;
        var last_space_width: u16 = 0;
        
        while (iter.nextCodepoint()) |codepoint| {
            const char_width = UnicodeWidth.codepointWidth(codepoint);
            
            // Check if adding this character would exceed the width
            if (current_width + char_width > width) {
                // Try to break at the last space
                if (last_space) |space_pos| {
                    const wrapped_line = try allocator.dupe(u8, line[start..space_pos]);
                    try lines.append(wrapped_line);
                    start = space_pos + 1; // Skip the space
                    current_width = try UnicodeWidth.stringWidth(line[start..iter.i]);
                    last_space = null;
                } else {
                    // No space to break at, force break
                    const prev_i = iter.i - std.unicode.utf8ByteSequenceLength(codepoint) catch 1;
                    if (prev_i > start) {
                        const wrapped_line = try allocator.dupe(u8, line[start..prev_i]);
                        try lines.append(wrapped_line);
                        start = prev_i;
                        current_width = char_width;
                    } else {
                        // Single character is too wide, include it anyway
                        current_width += char_width;
                    }
                }
            } else {
                current_width += char_width;
            }
            
            // Track the last space for word wrapping
            if (codepoint == ' ') {
                last_space = iter.i;
                last_space_width = current_width;
            }
        }
        
        // Add the remaining text
        if (start < line.len) {
            const wrapped_line = try allocator.dupe(u8, line[start..]);
            try lines.append(wrapped_line);
        } else if (line.len == 0) {
            // Empty line
            try lines.append(try allocator.dupe(u8, ""));
        }
    }
};

/// Text alignment utilities
pub const TextAlign = struct {
    pub const Alignment = enum {
        left,
        center,
        right,
    };
    
    /// Align text within a given width
    pub fn alignText(allocator: std.mem.Allocator, text: []const u8, width: u16, alignment: Alignment) ![]const u8 {
        const text_width = try UnicodeWidth.stringWidth(text);
        
        if (text_width >= width) {
            return allocator.dupe(u8, text);
        }
        
        const padding = width - text_width;
        
        return switch (alignment) {
            .left => try std.fmt.allocPrint(allocator, "{s}{s}", .{ text, " " ** padding }),
            .right => try std.fmt.allocPrint(allocator, "{s}{s}", .{ " " ** padding, text }),
            .center => blk: {
                const left_padding = padding / 2;
                const right_padding = padding - left_padding;
                break :blk try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ 
                    " " ** left_padding, 
                    text, 
                    " " ** right_padding 
                });
            },
        };
    }
};

/// Efficient string rendering with Unicode support
pub const StringRenderer = struct {
    /// Render a string with proper Unicode width handling
    pub fn renderString(text: []const u8, max_width: u16) !struct { text: []const u8, width: u16 } {
        if (max_width == 0) {
            return .{ .text = "", .width = 0 };
        }
        
        const result = try UnicodeWidth.stringWidthTruncated(text, max_width);
        return .{ 
            .text = text[0..result.byte_count], 
            .width = result.width 
        };
    }
    
    /// Render a string with ellipsis if truncated
    pub fn renderStringWithEllipsis(allocator: std.mem.Allocator, text: []const u8, max_width: u16) ![]const u8 {
        if (max_width == 0) {
            return allocator.dupe(u8, "");
        }
        
        const text_width = try UnicodeWidth.stringWidth(text);
        
        if (text_width <= max_width) {
            return allocator.dupe(u8, text);
        }
        
        // Reserve space for ellipsis
        if (max_width < 3) {
            return allocator.dupe(u8, "."[0..@min(max_width, 1)]);
        }
        
        const available_width = max_width - 3; // Reserve 3 characters for "..."
        const result = try UnicodeWidth.stringWidthTruncated(text, available_width);
        
        return try std.fmt.allocPrint(allocator, "{s}...", .{text[0..result.byte_count]});
    }
};

/// Text measurement utilities
pub const TextMeasure = struct {
    /// Count the number of lines in a text
    pub fn countLines(text: []const u8) u16 {
        var count: u16 = 1;
        for (text) |c| {
            if (c == '\n') {
                count += 1;
            }
        }
        return count;
    }
    
    /// Get the width of the longest line in a text
    pub fn getMaxLineWidth(text: []const u8) !u16 {
        var max_width: u16 = 0;
        var line_iter = std.mem.split(u8, text, "\n");
        
        while (line_iter.next()) |line| {
            const width = try UnicodeWidth.stringWidth(line);
            max_width = @max(max_width, width);
        }
        
        return max_width;
    }
    
    /// Calculate the bounding box of a text
    pub fn getBoundingBox(text: []const u8) !struct { width: u16, height: u16 } {
        const width = try getMaxLineWidth(text);
        const height = countLines(text);
        return .{ .width = width, .height = height };
    }
};

test "Unicode width calculation" {
    // ASCII characters
    try std.testing.expect(UnicodeWidth.codepointWidth('a') == 1);
    try std.testing.expect(UnicodeWidth.codepointWidth('A') == 1);
    try std.testing.expect(UnicodeWidth.codepointWidth('1') == 1);
    
    // Control characters
    try std.testing.expect(UnicodeWidth.codepointWidth('\n') == 0);
    try std.testing.expect(UnicodeWidth.codepointWidth('\t') == 0);
    
    // Test string width
    try std.testing.expect(try UnicodeWidth.stringWidth("hello") == 5);
    try std.testing.expect(try UnicodeWidth.stringWidth("") == 0);
}

test "Text wrapping" {
    const allocator = std.testing.allocator;
    
    const wrapped = try TextWrap.wrapText(allocator, "hello world", 5);
    defer {
        for (wrapped.items) |line| {
            allocator.free(line);
        }
        wrapped.deinit();
    }
    
    try std.testing.expect(wrapped.items.len == 2);
    try std.testing.expectEqualStrings("hello", wrapped.items[0]);
    try std.testing.expectEqualStrings("world", wrapped.items[1]);
}

test "Text alignment" {
    const allocator = std.testing.allocator;
    
    const left_aligned = try TextAlign.alignText(allocator, "test", 10, .left);
    defer allocator.free(left_aligned);
    try std.testing.expect(left_aligned.len == 10);
    
    const center_aligned = try TextAlign.alignText(allocator, "test", 10, .center);
    defer allocator.free(center_aligned);
    try std.testing.expect(center_aligned.len == 10);
    
    const right_aligned = try TextAlign.alignText(allocator, "test", 10, .right);
    defer allocator.free(right_aligned);
    try std.testing.expect(right_aligned.len == 10);
}

test "String rendering with ellipsis" {
    const allocator = std.testing.allocator;
    
    const short_text = try StringRenderer.renderStringWithEllipsis(allocator, "hello", 10);
    defer allocator.free(short_text);
    try std.testing.expectEqualStrings("hello", short_text);
    
    const long_text = try StringRenderer.renderStringWithEllipsis(allocator, "hello world", 8);
    defer allocator.free(long_text);
    try std.testing.expectEqualStrings("hello...", long_text);
}

test "Text measurement" {
    try std.testing.expect(TextMeasure.countLines("hello") == 1);
    try std.testing.expect(TextMeasure.countLines("hello\nworld") == 2);
    try std.testing.expect(TextMeasure.countLines("hello\nworld\n") == 3);
    
    const max_width = try TextMeasure.getMaxLineWidth("hello\nworld\nfoo");
    try std.testing.expect(max_width == 5);
    
    const bbox = try TextMeasure.getBoundingBox("hello\nworld");
    try std.testing.expect(bbox.width == 5);
    try std.testing.expect(bbox.height == 2);
}