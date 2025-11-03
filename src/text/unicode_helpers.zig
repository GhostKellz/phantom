//! Unicode Helpers - Convenience wrappers around gcode
//! Provides easy-to-use helpers for common Unicode operations

const std = @import("std");
const gcode = @import("gcode");

/// Calculate display width of a string
pub fn stringWidth(text: []const u8) usize {
    var width: usize = 0;
    var iter = gcode.GraphemeIterator.init(text);

    while (iter.next()) |grapheme| {
        width += gcode.graphemeWidth(grapheme);
    }

    return width;
}

/// Iterate over grapheme clusters
pub const GraphemeIterator = gcode.GraphemeIterator;

/// Check if a codepoint is a word boundary
pub fn isWordBoundary(codepoint: u21) bool {
    return gcode.isWordBoundary(codepoint);
}

/// Get the width category of a codepoint
pub fn charWidth(codepoint: u21) u2 {
    return gcode.charWidth(codepoint);
}

/// Check if text is right-to-left (BiDi)
pub fn isRTL(text: []const u8) bool {
    return gcode.isRTL(text);
}

// Tests
test "stringWidth calculation" {
    const testing = std.testing;

    // ASCII
    try testing.expectEqual(@as(usize, 5), stringWidth("hello"));

    // Wide characters (CJK)
    // Note: Actual width depends on gcode implementation
    const width = stringWidth("你好");
    try testing.expect(width >= 2);
}

test "GraphemeIterator" {
    const testing = std.testing;

    var iter = GraphemeIterator.init("hello");
    var count: usize = 0;

    while (iter.next()) |_| {
        count += 1;
    }

    try testing.expectEqual(@as(usize, 5), count);
}
