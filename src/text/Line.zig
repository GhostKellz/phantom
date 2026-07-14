//! Line - an ordered sequence of `Span`s rendered on a single row.
//!
//! A `Line` owns its span array (via `allocator`) but the spans' `content`
//! slices are borrowed by default. Use `Text.fromRawOwned` when the backing
//! string must be owned. A line carries an optional base `style` (merged under
//! each span) and an optional `alignment` that overrides the paragraph default.
const std = @import("std");
const style_mod = @import("../style.zig");
const Span = @import("Span.zig");

const Style = style_mod.Style;

const Line = @This();

pub const Alignment = enum { left, center, right };

allocator: std.mem.Allocator,
spans: std.ArrayList(Span) = .empty,
/// Base style merged *under* each span's own style at render time.
style: Style = .{},
/// Per-line alignment override; falls back to the paragraph alignment when null.
alignment: ?Alignment = null,

pub fn init(allocator: std.mem.Allocator) Line {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *Line) void {
    self.spans.deinit(self.allocator);
}

/// Convenience: a line holding a single unstyled span borrowing `content`.
pub fn fromRaw(allocator: std.mem.Allocator, content: []const u8) !Line {
    var line = Line.init(allocator);
    try line.append(Span.raw(content));
    return line;
}

/// Append an already-built span.
pub fn append(self: *Line, span: Span) !void {
    try self.spans.append(self.allocator, span);
}

/// Append an unstyled span borrowing `content`.
pub fn appendRaw(self: *Line, content: []const u8) !void {
    try self.append(Span.raw(content));
}

/// Append a styled span borrowing `content`.
pub fn appendStyled(self: *Line, content: []const u8, span_style: Style) !void {
    try self.append(Span.styled(content, span_style));
}

/// Set the base line style (fluent).
pub fn withStyle(self: *Line, line_style: Style) *Line {
    self.style = line_style;
    return self;
}

/// Set the line alignment (fluent).
pub fn withAlignment(self: *Line, line_alignment: Alignment) *Line {
    self.alignment = line_alignment;
    return self;
}

/// Total display width of all spans in terminal columns.
pub fn width(self: Line) usize {
    var total: usize = 0;
    for (self.spans.items) |span| total += span.width();
    return total;
}

/// Borrowed view of the spans.
pub fn items(self: Line) []const Span {
    return self.spans.items;
}

test "Line width sums spans" {
    const allocator = std.testing.allocator;
    var line = Line.init(allocator);
    defer line.deinit();

    try line.appendRaw("foo");
    try line.appendStyled("bar!", Style.default().withBold());

    try std.testing.expectEqual(@as(usize, 7), line.width());
    try std.testing.expectEqual(@as(usize, 2), line.items().len);
    try std.testing.expect(line.items()[1].style.attributes.bold);
}

test "Line fromRaw and alignment override" {
    const allocator = std.testing.allocator;
    var line = try Line.fromRaw(allocator, "hello");
    defer line.deinit();

    try std.testing.expectEqual(@as(usize, 5), line.width());
    try std.testing.expect(line.alignment == null);
    _ = line.withAlignment(.center);
    try std.testing.expect(line.alignment.? == .center);
}
