//! Snapshot test harness: render a `Widget` to an off-screen `Buffer` and
//! serialize it to a plain-text string for golden assertions.
//!
//! Rows are joined with '\n' and trailing spaces on each row are trimmed so
//! snapshots stay readable and stable across insignificant padding. Wide-glyph
//! trailing cells (blanked by the renderer) collapse naturally via the trim.
const std = @import("std");
const terminal = @import("../terminal.zig");
const geometry = @import("../geometry.zig");
const Widget = @import("../widget.zig").Widget;

const Buffer = terminal.Buffer;
const Size = geometry.Size;
const Rect = geometry.Rect;

/// Render `widget` into a `width`x`height` buffer and return the trimmed text.
/// Caller owns the returned slice.
pub fn renderToString(
    allocator: std.mem.Allocator,
    widget: *Widget,
    width: u16,
    height: u16,
) ![]u8 {
    var buffer = try Buffer.init(allocator, Size.init(width, height));
    defer buffer.deinit();
    widget.render(&buffer, Rect.init(0, 0, width, height));
    return bufferToString(allocator, &buffer);
}

/// Serialize an existing buffer to a trimmed, newline-joined string.
/// Caller owns the returned slice.
pub fn bufferToString(allocator: std.mem.Allocator, buffer: *const Buffer) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var y: u16 = 0;
    while (y < buffer.size.height) : (y += 1) {
        var row: std.ArrayList(u8) = .empty;
        defer row.deinit(allocator);

        var x: u16 = 0;
        while (x < buffer.size.width) : (x += 1) {
            const cell = buffer.getCell(x, y) orelse continue;
            var utf8: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(cell.char, &utf8) catch blk: {
                utf8[0] = ' ';
                break :blk 1;
            };
            try row.appendSlice(allocator, utf8[0..n]);
        }

        // Trim trailing spaces for stable snapshots.
        const trimmed = std.mem.trimEnd(u8, row.items, " ");
        try out.appendSlice(allocator, trimmed);
        if (y + 1 < buffer.size.height) try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

/// Assert that rendering `widget` equals `expected`. Emits a readable diff.
pub fn expectRender(
    allocator: std.mem.Allocator,
    widget: *Widget,
    width: u16,
    height: u16,
    expected: []const u8,
) !void {
    const actual = try renderToString(allocator, widget, width, height);
    defer allocator.free(actual);
    std.testing.expectEqualStrings(expected, actual) catch |err| {
        std.debug.print("\n--- snapshot mismatch ({d}x{d}) ---\n{s}\n---\n", .{ width, height, actual });
        return err;
    };
}

const testing = std.testing;

test "bufferToString trims trailing spaces and joins rows" {
    var buffer = try Buffer.init(testing.allocator, Size.init(5, 2));
    defer buffer.deinit();
    buffer.writeText(0, 0, "hi", .{});
    buffer.writeText(0, 1, "yo", .{});

    const s = try bufferToString(testing.allocator, &buffer);
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("hi\nyo", s);
}
