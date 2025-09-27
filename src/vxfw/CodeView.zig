//! CodeView - Syntax-highlighted code display widget
//! Displays source code with syntax highlighting and line numbers

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Style = style.Style;

const CodeView = @This();

source_code: []const u8,
language: Language,
theme: SyntaxTheme,
show_line_numbers: bool = true,
line_number_style: Style,
current_line: ?u32 = null,
scroll_offset: Point = Point{ .x = 0, .y = 0 },

pub const Language = enum {
    none,
    zig,
    c,
    cpp,
    javascript,
    typescript,
    python,
    rust,
    go,
    json,
    markdown,
};

pub const SyntaxTheme = struct {
    default: Style,
    keyword: Style,
    string: Style,
    comment: Style,
    number: Style,
    operator: Style,
    function: Style,
    type: Style,
    builtin: Style,

    pub fn defaultDark() SyntaxTheme {
        return SyntaxTheme{
            .default = Style.default().withFg(.white),
            .keyword = Style.default().withFg(.blue).withBold(),
            .string = Style.default().withFg(.green),
            .comment = Style.default().withFg(.bright_black).withItalic(),
            .number = Style.default().withFg(.cyan),
            .operator = Style.default().withFg(.yellow),
            .function = Style.default().withFg(.magenta),
            .type = Style.default().withFg(.red),
            .builtin = Style.default().withFg(.bright_blue),
        };
    }

    pub fn defaultLight() SyntaxTheme {
        return SyntaxTheme{
            .default = Style.default().withFg(.black),
            .keyword = Style.default().withFg(.blue).withBold(),
            .string = Style.default().withFg(.green),
            .comment = Style.default().withFg(.bright_black).withItalic(),
            .number = Style.default().withFg(.red),
            .operator = Style.default().withFg(.black),
            .function = Style.default().withFg(.magenta),
            .type = Style.default().withFg(.blue),
            .builtin = Style.default().withFg(.cyan),
        };
    }
};

pub const Token = struct {
    text: []const u8,
    style: Style,
    start: usize,
    end: usize,
};

/// Create a CodeView with source code and language
pub fn init(source_code: []const u8, language: Language, theme: SyntaxTheme) CodeView {
    return CodeView{
        .source_code = source_code,
        .language = language,
        .theme = theme,
        .line_number_style = Style.default().withFg(.bright_black),
    };
}

/// Create a CodeView without line numbers
pub fn withoutLineNumbers(source_code: []const u8, language: Language, theme: SyntaxTheme) CodeView {
    return CodeView{
        .source_code = source_code,
        .language = language,
        .theme = theme,
        .show_line_numbers = false,
        .line_number_style = Style.default(),
    };
}

/// Create a CodeView with current line highlighting
pub fn withCurrentLine(source_code: []const u8, language: Language, theme: SyntaxTheme, current_line: u32) CodeView {
    return CodeView{
        .source_code = source_code,
        .language = language,
        .theme = theme,
        .current_line = current_line,
        .line_number_style = Style.default().withFg(.bright_black),
    };
}

/// Set the current line for highlighting
pub fn setCurrentLine(self: *CodeView, line: ?u32) void {
    self.current_line = line;
}

/// Set scroll position
pub fn setScrollPosition(self: *CodeView, x: i16, y: i16) void {
    self.scroll_offset = Point{ .x = x, .y = y };
}

/// Split source code into lines
fn getLines(self: *const CodeView, allocator: Allocator) ![][]const u8 {
    var lines = std.array_list.AlignedManaged([]const u8, null).init(allocator);
    var iterator = std.mem.splitScalar(u8, self.source_code, '\n');

    while (iterator.next()) |line| {
        try lines.append(line);
    }

    return lines.toOwnedSlice();
}

/// Calculate line number width
fn getLineNumberWidth(self: *const CodeView) u16 {
    if (!self.show_line_numbers) return 0;

    const line_count = std.mem.count(u8, self.source_code, "\n") + 1;
    const digits = if (line_count <= 1) 1 else std.math.log10_int(line_count) + 1;
    return @as(u16, @intCast(digits + 2)); // digits + space + separator
}

/// Simple tokenizer for basic syntax highlighting
fn tokenizeLine(self: *const CodeView, allocator: Allocator, line: []const u8) ![]Token {
    var tokens = std.array_list.AlignedManaged(Token, null).init(allocator);

    if (line.len == 0) {
        return tokens.toOwnedSlice();
    }

    switch (self.language) {
        .none => {
            try tokens.append(Token{
                .text = line,
                .style = self.theme.default,
                .start = 0,
                .end = line.len,
            });
        },
        .zig => try self.tokenizeZig(allocator, &tokens, line),
        .c, .cpp => try self.tokenizeC(allocator, &tokens, line),
        .javascript, .typescript => try self.tokenizeJavaScript(allocator, &tokens, line),
        .python => try self.tokenizePython(allocator, &tokens, line),
        .rust => try self.tokenizeRust(allocator, &tokens, line),
        .go => try self.tokenizeGo(allocator, &tokens, line),
        .json => try self.tokenizeJson(allocator, &tokens, line),
        .markdown => try self.tokenizeMarkdown(allocator, &tokens, line),
    }

    return tokens.toOwnedSlice();
}

/// Tokenize Zig source code
fn tokenizeZig(self: *const CodeView, allocator: Allocator, tokens: *std.array_list.AlignedManaged(Token, null), line: []const u8) !void {
    _ = allocator;
    const zig_keywords = [_][]const u8{
        "const", "var", "fn", "pub", "if", "else", "while", "for", "switch", "return",
        "try", "catch", "defer", "errdefer", "struct", "enum", "union", "error",
        "comptime", "inline", "extern", "export", "packed", "align", "allowzero",
        "volatile", "callconv", "async", "await", "suspend", "resume", "nosuspend",
        "and", "or", "orelse", "unreachable", "break", "continue", "test", "usingnamespace",
    };

    const zig_builtins = [_][]const u8{
        "@import", "@cImport", "@embedFile", "@intCast", "@floatCast", "@ptrCast",
        "@alignCast", "@sizeOf", "@typeOf", "@TypeOf", "@bitCast", "@as", "@fieldParentPtr",
    };

    var i: usize = 0;
    while (i < line.len) {
        // Skip whitespace
        if (std.ascii.isWhitespace(line[i])) {
            const start = i;
            while (i < line.len and std.ascii.isWhitespace(line[i])) i += 1;
            try tokens.append(Token{
                .text = line[start..i],
                .style = self.theme.default,
                .start = start,
                .end = i,
            });
            continue;
        }

        // String literals
        if (line[i] == '"') {
            const start = i;
            i += 1;
            while (i < line.len and line[i] != '"') {
                if (line[i] == '\\' and i + 1 < line.len) i += 1;
                i += 1;
            }
            if (i < line.len) i += 1; // Include closing quote
            try tokens.append(Token{
                .text = line[start..i],
                .style = self.theme.string,
                .start = start,
                .end = i,
            });
            continue;
        }

        // Comments
        if (i + 1 < line.len and line[i] == '/' and line[i + 1] == '/') {
            try tokens.append(Token{
                .text = line[i..],
                .style = self.theme.comment,
                .start = i,
                .end = line.len,
            });
            break;
        }

        // Numbers
        if (std.ascii.isDigit(line[i])) {
            const start = i;
            while (i < line.len and (std.ascii.isAlphaNumeric(line[i]) or line[i] == '.' or line[i] == '_')) i += 1;
            try tokens.append(Token{
                .text = line[start..i],
                .style = self.theme.number,
                .start = start,
                .end = i,
            });
            continue;
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(line[i]) or line[i] == '_' or line[i] == '@') {
            const start = i;
            while (i < line.len and (std.ascii.isAlphaNumeric(line[i]) or line[i] == '_')) i += 1;

            const word = line[start..i];
            var word_style = self.theme.default;

            // Check if it's a keyword
            for (zig_keywords) |keyword| {
                if (std.mem.eql(u8, word, keyword)) {
                    word_style = self.theme.keyword;
                    break;
                }
            }

            // Check if it's a builtin
            if (word_style.eq(self.theme.default)) {
                for (zig_builtins) |builtin| {
                    if (std.mem.startsWith(u8, word, builtin)) {
                        word_style = self.theme.builtin;
                        break;
                    }
                }
            }

            try tokens.append(Token{
                .text = word,
                .style = word_style,
                .start = start,
                .end = i,
            });
            continue;
        }

        // Operators and punctuation
        const start = i;
        i += 1;
        try tokens.append(Token{
            .text = line[start..i],
            .style = self.theme.operator,
            .start = start,
            .end = i,
        });
    }
}

/// Basic tokenizers for other languages (simplified implementations)
fn tokenizeC(self: *const CodeView, allocator: Allocator, tokens: *std.array_list.AlignedManaged(Token, null), line: []const u8) !void {
    // Simplified C tokenizer - could be expanded
    try tokens.append(Token{
        .text = line,
        .style = self.theme.default,
        .start = 0,
        .end = line.len,
    });
    _ = allocator;
}

fn tokenizeJavaScript(self: *const CodeView, allocator: Allocator, tokens: *std.array_list.AlignedManaged(Token, null), line: []const u8) !void {
    try tokens.append(Token{
        .text = line,
        .style = self.theme.default,
        .start = 0,
        .end = line.len,
    });
    _ = allocator;
}

fn tokenizePython(self: *const CodeView, allocator: Allocator, tokens: *std.array_list.AlignedManaged(Token, null), line: []const u8) !void {
    try tokens.append(Token{
        .text = line,
        .style = self.theme.default,
        .start = 0,
        .end = line.len,
    });
    _ = allocator;
}

fn tokenizeRust(self: *const CodeView, allocator: Allocator, tokens: *std.array_list.AlignedManaged(Token, null), line: []const u8) !void {
    try tokens.append(Token{
        .text = line,
        .style = self.theme.default,
        .start = 0,
        .end = line.len,
    });
    _ = allocator;
}

fn tokenizeGo(self: *const CodeView, allocator: Allocator, tokens: *std.array_list.AlignedManaged(Token, null), line: []const u8) !void {
    try tokens.append(Token{
        .text = line,
        .style = self.theme.default,
        .start = 0,
        .end = line.len,
    });
    _ = allocator;
}

fn tokenizeJson(self: *const CodeView, allocator: Allocator, tokens: *std.array_list.AlignedManaged(Token, null), line: []const u8) !void {
    try tokens.append(Token{
        .text = line,
        .style = self.theme.default,
        .start = 0,
        .end = line.len,
    });
    _ = allocator;
}

fn tokenizeMarkdown(self: *const CodeView, allocator: Allocator, tokens: *std.array_list.AlignedManaged(Token, null), line: []const u8) !void {
    try tokens.append(Token{
        .text = line,
        .style = self.theme.default,
        .start = 0,
        .end = line.len,
    });
    _ = allocator;
}

/// Get the widget interface for this CodeView
pub fn widget(self: *const CodeView) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const CodeView = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *CodeView = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const CodeView, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const width = ctx.getWidth();
    const height = ctx.getHeight();

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(width, height)
    );

    // Get source lines
    const lines = try self.getLines(ctx.arena);
    defer ctx.arena.free(lines);

    // Calculate layout
    const line_number_width = self.getLineNumberWidth();
    const code_start_x = line_number_width;
    const code_width = if (width > line_number_width) width - line_number_width else 0;

    // Draw visible lines
    const start_line = @max(0, self.scroll_offset.y);
    const end_line = @min(@as(i16, @intCast(lines.len)), self.scroll_offset.y + @as(i16, @intCast(height)));

    var y: u16 = 0;
    var line_idx = start_line;
    while (line_idx < end_line and y < height) : ({line_idx += 1; y += 1;}) {
        const line = lines[@intCast(line_idx)];
        const line_number = @as(u32, @intCast(line_idx)) + 1;

        // Draw line number
        if (self.show_line_numbers and line_number_width > 0) {
            var line_num_buffer: [16]u8 = undefined;
            const line_num_text = std.fmt.bufPrint(&line_num_buffer, "{d} ", .{line_number}) catch continue;

            const is_current = if (self.current_line) |current| line_number == current else false;
            const line_style = if (is_current)
                self.line_number_style.withBold()
            else
                self.line_number_style;

            _ = surface.writeText(0, y, line_num_text, line_style);
        }

        // Draw code with syntax highlighting
        if (code_width > 0) {
            const tokens = try self.tokenizeLine(ctx.arena, line);
            defer ctx.arena.free(tokens);

            var x: u16 = code_start_x;
            for (tokens) |token| {
                if (x >= width) break;

                const chars_written = surface.writeText(x, y, token.text, token.style);
                x += chars_written;
            }
        }
    }

    return surface;
}

pub fn handleEvent(self: *CodeView, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    switch (ctx.event) {
        .mouse => |mouse| {
            if (ctx.isMouseEvent() != null) {
                switch (mouse.button) {
                    .wheel_up => {
                        self.scroll_offset.y = @max(0, self.scroll_offset.y - 3);
                        try commands.append(.redraw);
                    },
                    .wheel_down => {
                        self.scroll_offset.y += 3;
                        try commands.append(.redraw);
                    },
                    .wheel_left => {
                        self.scroll_offset.x = @max(0, self.scroll_offset.x - 3);
                        try commands.append(.redraw);
                    },
                    .wheel_right => {
                        self.scroll_offset.x += 3;
                        try commands.append(.redraw);
                    },
                    else => {},
                }
            }
        },
        .key_press => |key| {
            if (ctx.has_focus) {
                switch (key.key) {
                    .up => {
                        self.scroll_offset.y = @max(0, self.scroll_offset.y - 1);
                        try commands.append(.redraw);
                    },
                    .down => {
                        self.scroll_offset.y += 1;
                        try commands.append(.redraw);
                    },
                    .left => {
                        self.scroll_offset.x = @max(0, self.scroll_offset.x - 1);
                        try commands.append(.redraw);
                    },
                    .right => {
                        self.scroll_offset.x += 1;
                        try commands.append(.redraw);
                    },
                    .page_up => {
                        self.scroll_offset.y = @max(0, self.scroll_offset.y - 10);
                        try commands.append(.redraw);
                    },
                    .page_down => {
                        self.scroll_offset.y += 10;
                        try commands.append(.redraw);
                    },
                    .home => {
                        self.scroll_offset.y = 0;
                        self.scroll_offset.x = 0;
                        try commands.append(.redraw);
                    },
                    else => {},
                }
            }
        },
        else => {},
    }

    return commands;
}

test "CodeView creation and basic functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const zig_code =
        \\const std = @import("std");
        \\pub fn main() void {
        \\    std.debug.print("Hello, World!\n", .{});
        \\}
    ;

    const code_view = CodeView.init(zig_code, .zig, SyntaxTheme.defaultDark());

    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        Size.init(50, 10),
        vxfw.DrawContext.SizeConstraints.fixed(50, 10),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try code_view.draw(ctx);

    // Test basic surface creation
    try std.testing.expectEqual(Size.init(50, 10), surface.size);
}

test "CodeView line number width calculation" {
    const short_code = "line1\nline2\nline3";
    const code_view = CodeView.init(short_code, .none, SyntaxTheme.defaultDark());
    try std.testing.expectEqual(@as(u16, 3), code_view.getLineNumberWidth()); // 1 digit + 2 = 3

    const no_line_numbers = CodeView.withoutLineNumbers(short_code, .none, SyntaxTheme.defaultDark());
    try std.testing.expectEqual(@as(u16, 0), no_line_numbers.getLineNumberWidth());
}