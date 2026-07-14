//! Span - a styled run of text, the smallest unit of rich-text composition.
//!
//! A `Span` borrows its `content` slice by default (zero-copy). Callers that
//! need the span to outlive the source string can duplicate it with `dupe`.
//! Widths are grapheme-cluster aware via the gcode-backed unicode helpers.
const std = @import("std");
const style_mod = @import("../style.zig");
const gcode = @import("gcode");

const Style = style_mod.Style;

const Span = @This();

/// Borrowed (or owned, see `dupe`) UTF-8 text for this run.
content: []const u8,
/// Style applied to this run. Merged over the enclosing line style at render time.
style: Style = .{},

/// Create an unstyled span borrowing `content`.
pub fn raw(content: []const u8) Span {
    return .{ .content = content };
}

/// Create a styled span borrowing `content`.
pub fn styled(content: []const u8, span_style: Style) Span {
    return .{ .content = content, .style = span_style };
}

/// Display width of the span in terminal columns (grapheme-aware).
pub fn width(self: Span) usize {
    return gcode.stringWidth(self.content);
}

/// Return a copy whose `content` is owned by `allocator`. Free with `freeDupe`.
pub fn dupe(self: Span, allocator: std.mem.Allocator) !Span {
    return .{ .content = try allocator.dupe(u8, self.content), .style = self.style };
}

/// Free content allocated by `dupe`.
pub fn freeDupe(self: Span, allocator: std.mem.Allocator) void {
    allocator.free(self.content);
}

test "Span width and constructors" {
    const s = Span.raw("hello");
    try std.testing.expectEqual(@as(usize, 5), s.width());
    try std.testing.expect(s.style.eq(Style.default()));

    const styled_span = Span.styled("hi", Style.default().withBold());
    try std.testing.expect(styled_span.style.attributes.bold);
    try std.testing.expectEqual(@as(usize, 2), styled_span.width());
}

test "Span dupe owns its content" {
    const allocator = std.testing.allocator;
    var src: std.ArrayList(u8) = .empty;
    defer src.deinit(allocator);
    try src.appendSlice(allocator, "owned");

    const borrowed = Span.raw(src.items);
    const owned = try borrowed.dupe(allocator);
    defer owned.freeDupe(allocator);

    src.clearRetainingCapacity();
    try std.testing.expectEqualStrings("owned", owned.content);
}
