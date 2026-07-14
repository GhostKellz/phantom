//! Text - an ordered collection of `Line`s: the top-level rich-text value.
//!
//! `Text` owns its lines (each line owns its span array). Content slices are
//! borrowed by default; `fromRawOwned` duplicates the source string once and
//! owns that backing buffer so the `Text` is self-contained.
const std = @import("std");
const style_mod = @import("../style.zig");
const Span = @import("Span.zig");
const Line = @import("Line.zig");

const Style = style_mod.Style;

const Text = @This();

pub const Alignment = Line.Alignment;

allocator: std.mem.Allocator,
lines: std.ArrayList(Line) = .empty,
/// Base style merged under every line/span.
style: Style = .{},
/// Default alignment for lines that don't specify their own.
alignment: Alignment = .left,
/// Owned copy of the source string when built via `fromRawOwned`; freed on deinit.
owned_backing: ?[]u8 = null,

pub fn init(allocator: std.mem.Allocator) Text {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *Text) void {
    for (self.lines.items) |*line| line.deinit();
    self.lines.deinit(self.allocator);
    if (self.owned_backing) |buf| self.allocator.free(buf);
}

/// Split `content` on '\n' into borrowed single-span lines (zero-copy).
pub fn fromRaw(allocator: std.mem.Allocator, content: []const u8) !Text {
    var text = Text.init(allocator);
    errdefer text.deinit();
    try appendRawLines(&text, content);
    return text;
}

/// Like `fromRaw` but duplicates `content` so the `Text` owns its backing string.
pub fn fromRawOwned(allocator: std.mem.Allocator, content: []const u8) !Text {
    var text = Text.init(allocator);
    errdefer text.deinit();
    const backing = try allocator.dupe(u8, content);
    text.owned_backing = backing;
    try appendRawLines(&text, backing);
    return text;
}

fn appendRawLines(self: *Text, content: []const u8) !void {
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |raw_line| {
        var line = Line.init(self.allocator);
        errdefer line.deinit();
        try line.appendRaw(raw_line);
        try self.lines.append(self.allocator, line);
    }
}

/// Append an already-built line (takes ownership of its allocations).
pub fn append(self: *Text, line: Line) !void {
    try self.lines.append(self.allocator, line);
}

/// Create, append, and return a pointer to a fresh empty line for building.
pub fn addLine(self: *Text) !*Line {
    try self.lines.append(self.allocator, Line.init(self.allocator));
    return &self.lines.items[self.lines.items.len - 1];
}

/// Set the default alignment (fluent).
pub fn withAlignment(self: *Text, text_alignment: Alignment) *Text {
    self.alignment = text_alignment;
    return self;
}

/// Set the base style (fluent).
pub fn withStyle(self: *Text, text_style: Style) *Text {
    self.style = text_style;
    return self;
}

/// Number of lines.
pub fn height(self: Text) usize {
    return self.lines.items.len;
}

/// Width of the widest line in terminal columns.
pub fn width(self: Text) usize {
    var max: usize = 0;
    for (self.lines.items) |line| {
        const w = line.width();
        if (w > max) max = w;
    }
    return max;
}

/// Borrowed view of the lines.
pub fn items(self: Text) []const Line {
    return self.lines.items;
}

test "Text fromRaw splits on newlines" {
    const allocator = std.testing.allocator;
    var text = try Text.fromRaw(allocator, "hello\nworldly\nhi");
    defer text.deinit();

    try std.testing.expectEqual(@as(usize, 3), text.height());
    try std.testing.expectEqual(@as(usize, 7), text.width()); // "worldly"
}

test "Text fromRawOwned survives source mutation" {
    const allocator = std.testing.allocator;
    var src: std.ArrayList(u8) = .empty;
    defer src.deinit(allocator);
    try src.appendSlice(allocator, "a\nbb");

    var text = try Text.fromRawOwned(allocator, src.items);
    defer text.deinit();

    // Corrupt the original buffer; owned Text must be unaffected.
    @memset(src.items, 'X');
    try std.testing.expectEqual(@as(usize, 2), text.height());
    try std.testing.expectEqualStrings("bb", text.items()[1].items()[0].content);
}

test "Text addLine builds multi-span content" {
    const allocator = std.testing.allocator;
    var text = Text.init(allocator);
    defer text.deinit();

    const line = try text.addLine();
    try line.appendRaw("key: ");
    try line.appendStyled("value", Style.default().withBold());

    try std.testing.expectEqual(@as(usize, 1), text.height());
    try std.testing.expectEqual(@as(usize, 10), text.width());
}
