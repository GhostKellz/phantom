//! Syntax highlighting widget using Grove Tree-sitter integration

const std = @import("std");
const phantom = @import("../root.zig");
const grove = phantom.grove;

const Rect = phantom.Rect;
const Color = phantom.Color;
const Style = phantom.Style;
const Buffer = phantom.Buffer;

pub const SyntaxHighlight = struct {
    allocator: std.mem.Allocator,
    source_code: []const u8,
    language: grove.Languages,
    parser: ?*grove.Parser = null,
    tree: ?*grove.Tree = null,
    highlight_engine: ?*grove.Highlight.HighlightEngine = null,
    highlights: []grove.Highlight.HighlightSpan = &[_]grove.Highlight.HighlightSpan{},

    show_line_numbers: bool = true,
    line_number_width: u16 = 4,
    scroll_offset_y: usize = 0,
    scroll_offset_x: usize = 0,

    pub const HighlightRules = struct {
        pub const default_rules = [_]grove.Highlight.HighlightRule{
            .{ .capture = "keyword", .class = "keyword" },
            .{ .capture = "function", .class = "function" },
            .{ .capture = "function.call", .class = "function" },
            .{ .capture = "function.builtin", .class = "function" },
            .{ .capture = "type", .class = "type" },
            .{ .capture = "type.builtin", .class = "type" },
            .{ .capture = "string", .class = "string" },
            .{ .capture = "number", .class = "number" },
            .{ .capture = "comment", .class = "comment" },
            .{ .capture = "variable", .class = "variable" },
            .{ .capture = "variable.builtin", .class = "variable" },
            .{ .capture = "variable.parameter", .class = "variable" },
            .{ .capture = "operator", .class = "operator" },
            .{ .capture = "punctuation", .class = "punctuation" },
            .{ .capture = "punctuation.bracket", .class = "punctuation" },
            .{ .capture = "constant", .class = "number" },
            .{ .capture = "constant.builtin", .class = "number" },
            .{ .capture = "property", .class = "variable" },
            .{ .capture = "tag", .class = "keyword" },
            .{ .capture = "attribute", .class = "variable" },
        };
    };

    pub fn init(allocator: std.mem.Allocator, source_code: []const u8, language: grove.Languages) !SyntaxHighlight {
        return SyntaxHighlight{
            .allocator = allocator,
            .source_code = source_code,
            .language = language,
        };
    }

    pub fn deinit(self: *SyntaxHighlight) void {
        if (self.highlights.len > 0) {
            self.allocator.free(self.highlights);
        }
        if (self.highlight_engine) |engine| {
            engine.deinit();
            self.allocator.destroy(engine);
        }
        if (self.tree) |tree| {
            tree.deinit();
            self.allocator.destroy(tree);
        }
        if (self.parser) |parser| {
            parser.deinit();
            self.allocator.destroy(parser);
        }
    }

    /// Parse and highlight the source code with a custom query
    pub fn parseWithQuery(self: *SyntaxHighlight, query_source: []const u8, rules: []const grove.Highlight.HighlightRule) !void {
        const lang = try self.language.get();

        var parser = try grove.Parser.init(self.allocator);
        errdefer parser.deinit();

        try parser.setLanguage(lang);

        var tree = try parser.parseUtf8(null, self.source_code);
        errdefer tree.deinit();

        var engine = try grove.Highlight.HighlightEngine.init(
            self.allocator,
            lang,
            query_source,
            rules,
        );
        errdefer engine.deinit();

        const root = tree.rootNode() orelse return error.NoRootNode;
        const highlights = try engine.highlight(root);

        self.parser = try self.allocator.create(grove.Parser);
        self.parser.?.* = parser;

        self.tree = try self.allocator.create(grove.Tree);
        self.tree.?.* = tree;

        self.highlight_engine = try self.allocator.create(grove.Highlight.HighlightEngine);
        self.highlight_engine.?.* = engine;

        self.highlights = highlights;
    }

    /// Parse without highlighting (fallback when no query available)
    pub fn parseWithoutHighlighting(self: *SyntaxHighlight) !void {
        const lang = try self.language.get();

        var parser = try grove.Parser.init(self.allocator);
        errdefer parser.deinit();

        try parser.setLanguage(lang);

        var tree = try parser.parseUtf8(null, self.source_code);
        errdefer tree.deinit();

        self.parser = try self.allocator.create(grove.Parser);
        self.parser.?.* = parser;

        self.tree = try self.allocator.create(grove.Tree);
        self.tree.?.* = tree;
    }

    /// Builder: Show/hide line numbers
    pub fn setShowLineNumbers(self: *SyntaxHighlight, show: bool) *SyntaxHighlight {
        self.show_line_numbers = show;
        return self;
    }

    /// Builder: Set line number column width
    pub fn setLineNumberWidth(self: *SyntaxHighlight, width: u16) *SyntaxHighlight {
        self.line_number_width = width;
        return self;
    }

    /// Builder: Set vertical scroll offset
    pub fn setScrollY(self: *SyntaxHighlight, offset: usize) *SyntaxHighlight {
        self.scroll_offset_y = offset;
        return self;
    }

    /// Builder: Set horizontal scroll offset
    pub fn setScrollX(self: *SyntaxHighlight, offset: usize) *SyntaxHighlight {
        self.scroll_offset_x = offset;
        return self;
    }

    /// Get color for a highlight class
    fn getColorForClass(class: []const u8) Color {
        if (std.mem.eql(u8, class, "keyword")) return Color.magenta;
        if (std.mem.eql(u8, class, "function")) return Color.blue;
        if (std.mem.eql(u8, class, "type")) return Color.cyan;
        if (std.mem.eql(u8, class, "string")) return Color.green;
        if (std.mem.eql(u8, class, "number")) return Color.yellow;
        if (std.mem.eql(u8, class, "comment")) return Color.bright_black;
        if (std.mem.eql(u8, class, "variable")) return Color.white;
        if (std.mem.eql(u8, class, "operator")) return Color.red;
        return Color.white; // Default
    }

    /// Render the syntax highlighted code
    pub fn render(self: *SyntaxHighlight, buffer: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        const content_x = if (self.show_line_numbers) area.x + self.line_number_width + 1 else area.x;
        const content_width = if (self.show_line_numbers)
            @max(0, area.width -| self.line_number_width -| 1)
        else
            area.width;

        var line_iter = std.mem.splitScalar(u8, self.source_code, '\n');
        var line_num: usize = 0;
        var current_y: u16 = area.y;
        var byte_offset: u32 = 0;

        while (line_iter.next()) |line| : (line_num += 1) {
            const line_start = byte_offset;
            const line_end = byte_offset + @as(u32, @intCast(line.len));
            byte_offset = line_end + 1; // +1 for newline

            if (line_num < self.scroll_offset_y) continue;
            if (current_y >= area.y + area.height) break;

            // Render line number
            if (self.show_line_numbers) {
                const line_num_str = std.fmt.allocPrint(
                    self.allocator,
                    "{d:>4} ",
                    .{line_num + 1},
                ) catch "???? ";
                defer if (!std.mem.eql(u8, line_num_str, "???? ")) self.allocator.free(line_num_str);

                const line_num_style = Style.default().withFg(Color.bright_black);
                buffer.writeText(area.x, current_y, line_num_str[0..@min(line_num_str.len, self.line_number_width)], line_num_style);
            }

            // Render code line with syntax highlighting
            if (line.len > 0 and content_width > 0) {
                const visible_start = self.scroll_offset_x;
                if (visible_start < line.len) {
                    const visible_line = line[visible_start..];
                    const render_len = @min(visible_line.len, content_width);

                    if (self.highlights.len > 0) {
                        // Render with highlighting
                        var col: usize = 0;
                        while (col < render_len) : (col += 1) {
                            const byte_pos = line_start + visible_start + col;

                            const color = self.getColorForByte(@intCast(byte_pos));
                            const style = Style.default().withFg(color);

                            buffer.writeText(content_x + @as(u16, @intCast(col)), current_y, visible_line[col..col + 1], style);
                        }
                    } else {
                        // Fallback: plain text
                        const code_style = Style.default().withFg(Color.white);
                        buffer.writeText(content_x, current_y, visible_line[0..render_len], code_style);
                    }
                }
            }

            current_y += 1;
        }
    }

    /// Find the highlight span containing a byte position
    fn getColorForByte(self: *const SyntaxHighlight, byte_pos: u32) Color {
        for (self.highlights) |span| {
            if (byte_pos >= span.start_byte and byte_pos < span.end_byte) {
                return getColorForClass(span.class);
            }
        }
        return Color.white;
    }
};

test "SyntaxHighlight initialization" {
    const testing = std.testing;

    const source =
        \\pub fn main() void {
        \\    std.debug.print("Hello, World!\n", .{});
        \\}
    ;

    var highlighter = try SyntaxHighlight.init(testing.allocator, source, grove.Languages.zig);
    defer highlighter.deinit();

    try testing.expect(highlighter.source_code.len > 0);
}

test "SyntaxHighlight builder pattern" {
    const testing = std.testing;

    var highlighter = try SyntaxHighlight.init(testing.allocator, "test", grove.Languages.zig);
    defer highlighter.deinit();

    _ = highlighter.setShowLineNumbers(false)
        .setLineNumberWidth(6)
        .setScrollY(10);

    try testing.expect(!highlighter.show_line_numbers);
    try testing.expectEqual(@as(u16, 6), highlighter.line_number_width);
    try testing.expectEqual(@as(usize, 10), highlighter.scroll_offset_y);
}

test "SyntaxHighlight without highlighting" {
    const testing = std.testing;

    const source =
        \\const x = 42;
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
    ;

    var highlighter = try SyntaxHighlight.init(testing.allocator, source, grove.Languages.zig);
    defer highlighter.deinit();

    try highlighter.parseWithoutHighlighting();
    try testing.expect(highlighter.parser != null);
    try testing.expect(highlighter.tree != null);
}
