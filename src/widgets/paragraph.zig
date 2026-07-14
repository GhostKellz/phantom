//! Paragraph - block text composition over `text.Text`.
//!
//! Renders a rich `text.Text` value with configurable wrapping (none/word/
//! character), horizontal/vertical alignment, inner padding, a scroll offset,
//! and a base style. Widths are grapheme-cluster aware so CJK and emoji lay out
//! correctly. This mirrors ratatui's `Paragraph` widget.
const std = @import("std");
const gcode = @import("gcode");

const Widget = @import("../widget.zig").Widget;
const terminal = @import("../terminal.zig");
const Buffer = terminal.Buffer;
const Cell = terminal.Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");
const text_mod = @import("../text/mod.zig");

const Rect = geometry.Rect;
const Style = style_mod.Style;
const Text = text_mod.Text;
const Line = text_mod.Line;

/// How text that exceeds the available width is handled.
pub const WrapMode = enum {
    /// No wrapping; long lines are clipped and reachable via horizontal scroll.
    none,
    /// Break between words, falling back to character breaks for over-long words.
    word,
    /// Break at any grapheme boundary that overflows the width.
    character,
};

/// Horizontal alignment of each display row within the inner area.
pub const Alignment = text_mod.Alignment;

/// Inner padding (in cells) between the widget area and its text.
pub const Padding = struct {
    top: u16 = 0,
    right: u16 = 0,
    bottom: u16 = 0,
    left: u16 = 0,

    pub fn all(value: u16) Padding {
        return .{ .top = value, .right = value, .bottom = value, .left = value };
    }

    pub fn symmetric(vertical: u16, horizontal: u16) Padding {
        return .{ .top = vertical, .bottom = vertical, .left = horizontal, .right = horizontal };
    }
};

/// Scroll offset in cells (columns, rows).
pub const Scroll = struct {
    x: u16 = 0,
    y: u16 = 0,
};

pub const Paragraph = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    /// Owned rich-text content.
    content: Text,
    wrap: WrapMode = .none,
    alignment: Alignment = .left,
    base_style: Style = .{},
    padding: Padding = .{},
    scroll: Scroll = .{},

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
        .resize = resize,
    };

    /// One laid-out glyph: a grapheme cluster with its column width and style.
    const Glyph = struct {
        bytes: []const u8,
        w: u16,
        style: Style,
    };

    /// Create a paragraph with empty content.
    pub fn init(allocator: std.mem.Allocator) !*Paragraph {
        return initText(allocator, Text.init(allocator));
    }

    /// Create a paragraph that takes ownership of an existing `text.Text`.
    pub fn initText(allocator: std.mem.Allocator, content: Text) !*Paragraph {
        const self = try allocator.create(Paragraph);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .content = content,
        };
        return self;
    }

    /// Create a paragraph from a raw string (split on '\n'); owns its backing.
    pub fn fromRaw(allocator: std.mem.Allocator, raw: []const u8) !*Paragraph {
        return initText(allocator, try Text.fromRawOwned(allocator, raw));
    }

    pub fn setWrap(self: *Paragraph, mode: WrapMode) *Paragraph {
        self.wrap = mode;
        return self;
    }

    pub fn setAlignment(self: *Paragraph, alignment: Alignment) *Paragraph {
        self.alignment = alignment;
        return self;
    }

    pub fn setBaseStyle(self: *Paragraph, base_style: Style) *Paragraph {
        self.base_style = base_style;
        return self;
    }

    pub fn setPadding(self: *Paragraph, padding: Padding) *Paragraph {
        self.padding = padding;
        return self;
    }

    pub fn setScroll(self: *Paragraph, scroll: Scroll) *Paragraph {
        self.scroll = scroll;
        return self;
    }

    /// Inner area after subtracting padding. Zero-sized if padding exceeds area.
    fn innerArea(self: *const Paragraph, area: Rect) Rect {
        const px = self.padding.left + self.padding.right;
        const py = self.padding.top + self.padding.bottom;
        if (area.width <= px or area.height <= py) {
            return Rect.init(area.x, area.y, 0, 0);
        }
        return Rect.init(
            area.x + self.padding.left,
            area.y + self.padding.top,
            area.width - px,
            area.height - py,
        );
    }

    /// Number of display rows the content occupies at the given inner width,
    /// accounting for the active wrap mode. Useful for max-scroll clamping.
    /// Uses the same layout path as `render` so the counts always agree.
    pub fn contentHeight(self: *const Paragraph, inner_width: u16) usize {
        if (inner_width == 0) return 0;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var rows: std.ArrayList([]Glyph) = .empty;
        var row_aligns: std.ArrayList(Alignment) = .empty;
        for (self.content.items()) |line| {
            const line_style = self.base_style.patch(self.content.style).patch(line.style);
            const line_align = line.alignment orelse self.alignment;
            layoutLine(a, line, line_style, self.wrap, inner_width, &rows, &row_aligns, line_align) catch return rows.items.len;
        }
        return rows.items.len;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Paragraph = @fieldParentPtr("widget", widget);
        const inner = self.innerArea(area);
        if (inner.width == 0 or inner.height == 0) return;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        // Build display rows (each a slice of glyphs) across all source lines.
        var rows: std.ArrayList([]Glyph) = .empty;
        var row_aligns: std.ArrayList(Alignment) = .empty;

        for (self.content.items()) |line| {
            const line_style = self.base_style.patch(self.content.style).patch(line.style);
            const line_align = line.alignment orelse self.alignment;
            layoutLine(a, line, line_style, self.wrap, inner.width, &rows, &row_aligns, line_align) catch return;
        }

        // Vertical scroll + clip to inner height.
        var row_index: usize = self.scroll.y;
        var screen_y: u16 = inner.y;
        const max_y = inner.y + inner.height;
        while (row_index < rows.items.len and screen_y < max_y) : (row_index += 1) {
            drawRow(buffer, inner, screen_y, rows.items[row_index], row_aligns.items[row_index], self.scroll.x);
            screen_y += 1;
        }
    }

    /// Lay out one source line into one or more glyph rows appended to `rows`.
    fn layoutLine(
        a: std.mem.Allocator,
        line: Line,
        line_style: Style,
        wrap: WrapMode,
        inner_width: u16,
        rows: *std.ArrayList([]Glyph),
        row_aligns: *std.ArrayList(Alignment),
        alignment: Alignment,
    ) !void {
        // Flatten the line's spans into a glyph list.
        var glyphs: std.ArrayList(Glyph) = .empty;
        for (line.items()) |span| {
            const glyph_style = line_style.patch(span.style);
            var it = gcode.graphemeIterator(span.content);
            while (it.next()) |cluster| {
                const w: u16 = @intCast(gcode.stringWidth(cluster));
                try glyphs.append(a, .{ .bytes = cluster, .w = @max(w, 1), .style = glyph_style });
            }
        }

        if (wrap == .none) {
            try rows.append(a, try glyphs.toOwnedSlice(a));
            try row_aligns.append(a, alignment);
            return;
        }

        const items = glyphs.items;

        // An empty line still occupies one row.
        if (items.len == 0) {
            try rows.append(a, &[_]Glyph{});
            try row_aligns.append(a, alignment);
            return;
        }

        if (wrap == .character) {
            // Greedy grapheme packing: fill each row up to inner_width, always
            // making progress (an over-wide glyph occupies its own row).
            var start: usize = 0;
            while (start < items.len) {
                var end = start;
                var used: u16 = 0;
                while (end < items.len) {
                    const gw = items[end].w;
                    if (used + gw > inner_width and end > start) break;
                    used += gw;
                    end += 1;
                }
                try rows.append(a, items[start..end]);
                try row_aligns.append(a, alignment);
                start = end;
            }
            return;
        }

        // Word wrap: greedily pack whole words, keeping inter-word spaces but
        // trimming leading/trailing spaces at row breaks. Words longer than the
        // width are hard-split at grapheme boundaries.
        const rows_before = rows.items.len;
        var cur: std.ArrayList(Glyph) = .empty;
        var cur_width: u16 = 0;
        var i: usize = 0;
        while (i < items.len) {
            // Consume a run of spaces (a potential separator).
            const space_start = i;
            while (i < items.len and isSpace(items[i].bytes)) i += 1;
            const spaces = items[space_start..i];
            var space_w: u16 = 0;
            for (spaces) |s| space_w += s.w;

            // Consume the following word (run of non-spaces).
            const word_start = i;
            while (i < items.len and !isSpace(items[i].bytes)) i += 1;
            const word = items[word_start..i];
            if (word.len == 0) break; // trailing spaces: drop them
            var word_w: u16 = 0;
            for (word) |g| word_w += g.w;

            if (cur.items.len == 0) {
                // Row start: no leading separator.
                if (word_w <= inner_width) {
                    try cur.appendSlice(a, word);
                    cur_width = word_w;
                } else {
                    try hardSplit(a, word, inner_width, rows, row_aligns, alignment, &cur, &cur_width);
                }
            } else if (cur_width + space_w + word_w <= inner_width) {
                // Word (with its separator) fits on the current row.
                try cur.appendSlice(a, spaces);
                try cur.appendSlice(a, word);
                cur_width += space_w + word_w;
            } else {
                // Flush the current row and start the word on a fresh one.
                try rows.append(a, try cur.toOwnedSlice(a));
                try row_aligns.append(a, alignment);
                cur = .empty;
                cur_width = 0;
                if (word_w <= inner_width) {
                    try cur.appendSlice(a, word);
                    cur_width = word_w;
                } else {
                    try hardSplit(a, word, inner_width, rows, row_aligns, alignment, &cur, &cur_width);
                }
            }
        }

        if (cur.items.len > 0) {
            try rows.append(a, try cur.toOwnedSlice(a));
            try row_aligns.append(a, alignment);
        } else if (rows.items.len == rows_before) {
            // Line was all spaces: still occupies one (empty) row.
            try rows.append(a, &[_]Glyph{});
            try row_aligns.append(a, alignment);
        }
    }

    /// Emit an over-wide word one grapheme at a time, breaking to new rows as
    /// the width fills. Leaves the trailing partial row in `cur`/`cur_width`.
    fn hardSplit(
        a: std.mem.Allocator,
        word: []const Glyph,
        inner_width: u16,
        rows: *std.ArrayList([]Glyph),
        row_aligns: *std.ArrayList(Alignment),
        alignment: Alignment,
        cur: *std.ArrayList(Glyph),
        cur_width: *u16,
    ) !void {
        for (word) |g| {
            if (cur_width.* + g.w > inner_width and cur.items.len > 0) {
                try rows.append(a, try cur.toOwnedSlice(a));
                try row_aligns.append(a, alignment);
                cur.* = .empty;
                cur_width.* = 0;
            }
            try cur.append(a, g);
            cur_width.* += g.w;
        }
    }

    fn drawRow(
        buffer: *Buffer,
        inner: Rect,
        y: u16,
        glyphs: []const Glyph,
        alignment: Alignment,
        scroll_x: u16,
    ) void {
        var row_width: u16 = 0;
        for (glyphs) |g| row_width += g.w;

        const align_offset: i32 = switch (alignment) {
            .left => 0,
            .center => if (row_width < inner.width) @divTrunc(@as(i32, inner.width - row_width), 2) else 0,
            .right => if (row_width < inner.width) @as(i32, inner.width - row_width) else 0,
        };

        var pen: i32 = @as(i32, inner.x) + align_offset - @as(i32, scroll_x);
        const left: i32 = inner.x;
        const right: i32 = @as(i32, inner.x) + @as(i32, inner.width);

        for (glyphs) |g| {
            const cell_right = pen + g.w;
            if (pen >= left and cell_right <= right) {
                const cp = firstCodepoint(g.bytes);
                buffer.setCell(@intCast(pen), y, Cell.init(cp, g.style));
                if (g.w == 2) {
                    // Blank the trailing column of a wide glyph.
                    buffer.setCell(@intCast(pen + 1), y, Cell.init(' ', g.style));
                }
            }
            pen += g.w;
            if (pen >= right) break;
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        _ = widget;
        _ = event;
        return false; // Paragraph is non-interactive.
    }

    fn resize(widget: *Widget, new_area: Rect) void {
        _ = widget;
        _ = new_area;
    }

    fn deinit(widget: *Widget) void {
        const self: *Paragraph = @fieldParentPtr("widget", widget);
        self.content.deinit();
        self.allocator.destroy(self);
    }
};

fn isSpace(bytes: []const u8) bool {
    return bytes.len == 1 and bytes[0] == ' ';
}

fn firstCodepoint(bytes: []const u8) u21 {
    if (bytes.len == 0) return ' ';
    const len = std.unicode.utf8ByteSequenceLength(bytes[0]) catch return bytes[0];
    if (len > bytes.len) return bytes[0];
    return std.unicode.utf8Decode(bytes[0..len]) catch bytes[0];
}

const testing = std.testing;

test "Paragraph inner area subtracts padding" {
    const p = try Paragraph.init(testing.allocator);
    defer p.widget.deinit();
    _ = p.setPadding(Padding.all(1));
    const inner = p.innerArea(Rect.init(0, 0, 10, 5));
    try testing.expectEqual(@as(u16, 1), inner.x);
    try testing.expectEqual(@as(u16, 8), inner.width);
    try testing.expectEqual(@as(u16, 3), inner.height);
}

test "Paragraph contentHeight wraps by width" {
    const p = try Paragraph.fromRaw(testing.allocator, "abcdefghij");
    defer p.widget.deinit();
    _ = p.setWrap(.character);
    try testing.expectEqual(@as(usize, 1), p.contentHeight(10));
    try testing.expectEqual(@as(usize, 2), p.contentHeight(5));
    try testing.expectEqual(@as(usize, 4), p.contentHeight(3));
}

const snapshot = @import("../testing/snapshot.zig");

test "Paragraph snapshot: no-wrap multiline at normal size" {
    const p = try Paragraph.fromRaw(testing.allocator, "hello\nworld");
    defer p.widget.deinit();
    try snapshot.expectRender(testing.allocator, &p.widget, 10, 3, "hello\nworld\n");
}

test "Paragraph snapshot: character wrap at small width" {
    const p = try Paragraph.fromRaw(testing.allocator, "abcdef");
    defer p.widget.deinit();
    _ = p.setWrap(.character);
    // width 3 -> "abc" / "def"
    try snapshot.expectRender(testing.allocator, &p.widget, 3, 4, "abc\ndef\n\n");
}

test "Paragraph snapshot: word wrap keeps words intact" {
    const p = try Paragraph.fromRaw(testing.allocator, "the quick brown");
    defer p.widget.deinit();
    _ = p.setWrap(.word);
    // width 9 -> "the quick" / "brown"
    try snapshot.expectRender(testing.allocator, &p.widget, 9, 4, "the quick\nbrown\n\n");
}

test "Paragraph snapshot: right and center alignment" {
    const right = try Paragraph.fromRaw(testing.allocator, "hi");
    defer right.widget.deinit();
    _ = right.setAlignment(.right);
    try snapshot.expectRender(testing.allocator, &right.widget, 5, 1, "   hi");

    const center = try Paragraph.fromRaw(testing.allocator, "hi");
    defer center.widget.deinit();
    _ = center.setAlignment(.center);
    // (5-2)/2 = 1 leading space
    try snapshot.expectRender(testing.allocator, &center.widget, 5, 1, " hi");
}

test "Paragraph snapshot: vertical scroll offset" {
    const p = try Paragraph.fromRaw(testing.allocator, "l0\nl1\nl2\nl3");
    defer p.widget.deinit();
    _ = p.setScroll(.{ .x = 0, .y = 2 });
    try snapshot.expectRender(testing.allocator, &p.widget, 4, 2, "l2\nl3");
}

test "Paragraph snapshot: oversized area leaves blank rows" {
    const p = try Paragraph.fromRaw(testing.allocator, "x");
    defer p.widget.deinit();
    // 1 char in a 4x3 area: only first row has content, rest trim to empty.
    try snapshot.expectRender(testing.allocator, &p.widget, 4, 3, "x\n\n");
}

test "Paragraph snapshot: padding insets content" {
    const p = try Paragraph.fromRaw(testing.allocator, "hi");
    defer p.widget.deinit();
    _ = p.setPadding(Padding.all(1));
    // 1-cell pad on all sides in a 4x3 area -> content at row 1, col 1.
    try snapshot.expectRender(testing.allocator, &p.widget, 4, 3, "\n hi\n");
}

test "Paragraph snapshot: wide CJK glyph occupies two columns" {
    const p = try Paragraph.fromRaw(testing.allocator, "你a");
    defer p.widget.deinit();
    // 你 is width-2 (lead cell + blanked continuation cell), then 'a'. The
    // per-cell serializer emits the blanked continuation as a space: "你 a".
    try snapshot.expectRender(testing.allocator, &p.widget, 6, 1, "你 a");
}
