//! Rich-text composition primitives: Span, Line, and Text.
//!
//! These mirror the ratatui text model (`Span`/`Line`/`Text`) and back the
//! `Paragraph` widget. They are pure data types with grapheme-aware widths and
//! borrowed-by-default content; see each type for owned-lifetime helpers.
const std = @import("std");
const gcode = @import("gcode");

pub const Span = @import("Span.zig");
pub const Line = @import("Line.zig");
pub const Text = @import("Text.zig");

/// Line/Text alignment (`left`, `center`, `right`).
pub const Alignment = Line.Alignment;

/// Grapheme-aware display width of a UTF-8 string, in terminal columns.
pub fn stringWidth(s: []const u8) usize {
    return gcode.stringWidth(s);
}

/// Fuzzy text matching utilities.
pub const fuzzy = @import("fuzzy.zig");

test {
    std.testing.refAllDecls(@This());
}
