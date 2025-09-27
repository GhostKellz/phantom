//! RichText - Styled text with inline formatting
//! Supports markdown-like syntax and inline style formatting

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Style = style.Style;

const RichText = @This();

content: []const FormatSegment,
base_style: Style,
wrap_mode: WrapMode = .word,
line_spacing: u16 = 0,

pub const WrapMode = enum {
    none,
    word,
    character,
};

pub const FormatSegment = struct {
    text: []const u8,
    style: Style,
};

pub const MarkdownStyle = struct {
    normal: Style,
    bold: Style,
    italic: Style,
    code: Style,
    link: Style,
    header1: Style,
    header2: Style,
    header3: Style,

    pub fn defaultDark() MarkdownStyle {
        return MarkdownStyle{
            .normal = Style.default().withFg(.white),
            .bold = Style.default().withFg(.white).withBold(),
            .italic = Style.default().withFg(.white).withItalic(),
            .code = Style.default().withFg(.green).withBg(.black),
            .link = Style.default().withFg(.blue).withUnderline(),
            .header1 = Style.default().withFg(.yellow).withBold(),
            .header2 = Style.default().withFg(.cyan).withBold(),
            .header3 = Style.default().withFg(.magenta).withBold(),
        };
    }

    pub fn defaultLight() MarkdownStyle {
        return MarkdownStyle{
            .normal = Style.default().withFg(.black),
            .bold = Style.default().withFg(.black).withBold(),
            .italic = Style.default().withFg(.black).withItalic(),
            .code = Style.default().withFg(.red).withBg(.bright_white),
            .link = Style.default().withFg(.blue).withUnderline(),
            .header1 = Style.default().withFg(.black).withBold(),
            .header2 = Style.default().withFg(.black).withBold(),
            .header3 = Style.default().withFg(.black).withBold(),
        };
    }
};

/// Create RichText from pre-formatted segments
pub fn init(content: []const FormatSegment, base_style: Style) RichText {
    return RichText{
        .content = content,
        .base_style = base_style,
    };
}

/// Create RichText from markdown-like text
pub fn fromMarkdown(allocator: Allocator, markdown_text: []const u8, markdown_style: MarkdownStyle) !RichText {
    const segments = try parseMarkdown(allocator, markdown_text, markdown_style);
    return RichText{
        .content = segments,
        .base_style = markdown_style.normal,
    };
}

/// Create RichText with custom wrap mode
pub fn withWrapMode(content: []const FormatSegment, base_style: Style, wrap_mode: WrapMode) RichText {
    return RichText{
        .content = content,
        .base_style = base_style,
        .wrap_mode = wrap_mode,
    };
}

/// Create RichText with line spacing
pub fn withLineSpacing(content: []const FormatSegment, base_style: Style, line_spacing: u16) RichText {
    return RichText{
        .content = content,
        .base_style = base_style,
        .line_spacing = line_spacing,
    };
}

/// Parse markdown-like text into format segments
fn parseMarkdown(allocator: Allocator, text: []const u8, markdown_style: MarkdownStyle) ![]FormatSegment {
    var segments = std.array_list.AlignedManaged(FormatSegment, null).init(allocator);
    var i: usize = 0;

    while (i < text.len) {
        // Check for headers (must be at start of line)
        if (i == 0 or (i > 0 and text[i - 1] == '\n')) {
            if (text[i] == '#') {
                const header_result = try parseHeader(text[i..], markdown_style);
                try segments.append(header_result.segment);
                i += header_result.consumed;
                continue;
            }
        }

        // Check for bold **text**
        if (i + 1 < text.len and text[i] == '*' and text[i + 1] == '*') {
            const bold_result = try parseBold(text[i..], markdown_style);
            if (bold_result.segment.text.len > 0) {
                try segments.append(bold_result.segment);
                i += bold_result.consumed;
                continue;
            }
        }

        // Check for italic *text*
        if (text[i] == '*') {
            const italic_result = try parseItalic(text[i..], markdown_style);
            if (italic_result.segment.text.len > 0) {
                try segments.append(italic_result.segment);
                i += italic_result.consumed;
                continue;
            }
        }

        // Check for code `text`
        if (text[i] == '`') {
            const code_result = try parseCode(text[i..], markdown_style);
            if (code_result.segment.text.len > 0) {
                try segments.append(code_result.segment);
                i += code_result.consumed;
                continue;
            }
        }

        // Regular text - find next formatting marker
        const start = i;
        while (i < text.len and text[i] != '*' and text[i] != '`' and
               !(i == 0 or text[i - 1] == '\n') and text[i] != '#') {
            i += 1;
        }

        if (i > start) {
            try segments.append(FormatSegment{
                .text = text[start..i],
                .style = markdown_style.normal,
            });
        }
    }

    return segments.toOwnedSlice();
}

const ParseResult = struct {
    segment: FormatSegment,
    consumed: usize,
};

fn parseHeader(text: []const u8, markdown_style: MarkdownStyle) !ParseResult {
    var level: u8 = 0;
    var i: usize = 0;

    // Count # characters
    while (i < text.len and text[i] == '#' and level < 3) {
        level += 1;
        i += 1;
    }

    // Skip space after #
    if (i < text.len and text[i] == ' ') {
        i += 1;
    }

    // Find end of line
    const start = i;
    while (i < text.len and text[i] != '\n') {
        i += 1;
    }

    const header_style = switch (level) {
        1 => markdown_style.header1,
        2 => markdown_style.header2,
        3 => markdown_style.header3,
        else => markdown_style.normal,
    };

    return ParseResult{
        .segment = FormatSegment{
            .text = text[start..i],
            .style = header_style,
        },
        .consumed = i,
    };
}

fn parseBold(text: []const u8, markdown_style: MarkdownStyle) !ParseResult {
    if (text.len < 4) { // Need at least **x*
        return ParseResult{
            .segment = FormatSegment{ .text = "", .style = markdown_style.normal },
            .consumed = 0,
        };
    }

    // Find closing **
    var i: usize = 2; // Skip opening **
    while (i + 1 < text.len) {
        if (text[i] == '*' and text[i + 1] == '*') {
            return ParseResult{
                .segment = FormatSegment{
                    .text = text[2..i],
                    .style = markdown_style.bold,
                },
                .consumed = i + 2,
            };
        }
        i += 1;
    }

    return ParseResult{
        .segment = FormatSegment{ .text = "", .style = markdown_style.normal },
        .consumed = 0,
    };
}

fn parseItalic(text: []const u8, markdown_style: MarkdownStyle) !ParseResult {
    if (text.len < 3) { // Need at least *x*
        return ParseResult{
            .segment = FormatSegment{ .text = "", .style = markdown_style.normal },
            .consumed = 0,
        };
    }

    // Find closing *
    var i: usize = 1; // Skip opening *
    while (i < text.len) {
        if (text[i] == '*') {
            return ParseResult{
                .segment = FormatSegment{
                    .text = text[1..i],
                    .style = markdown_style.italic,
                },
                .consumed = i + 1,
            };
        }
        i += 1;
    }

    return ParseResult{
        .segment = FormatSegment{ .text = "", .style = markdown_style.normal },
        .consumed = 0,
    };
}

fn parseCode(text: []const u8, markdown_style: MarkdownStyle) !ParseResult {
    if (text.len < 3) { // Need at least `x`
        return ParseResult{
            .segment = FormatSegment{ .text = "", .style = markdown_style.normal },
            .consumed = 0,
        };
    }

    // Find closing `
    var i: usize = 1; // Skip opening `
    while (i < text.len) {
        if (text[i] == '`') {
            return ParseResult{
                .segment = FormatSegment{
                    .text = text[1..i],
                    .style = markdown_style.code,
                },
                .consumed = i + 1,
            };
        }
        i += 1;
    }

    return ParseResult{
        .segment = FormatSegment{ .text = "", .style = markdown_style.normal },
        .consumed = 0,
    };
}

/// Layout text into lines with wrapping
fn layoutText(self: *const RichText, allocator: Allocator, width: u16) ![][]RenderedSegment {
    var lines = std.array_list.AlignedManaged(std.array_list.AlignedManaged(RenderedSegment, null), null).init(allocator);
    var current_line = std.array_list.AlignedManaged(RenderedSegment, null).init(allocator);
    var current_x: u16 = 0;

    for (self.content) |segment| {
        switch (self.wrap_mode) {
            .none => {
                // Split only on existing newlines
                var line_iterator = std.mem.splitScalar(u8, segment.text, '\n');
                var first_line = true;

                while (line_iterator.next()) |line| {
                    if (!first_line) {
                        // Start new line
                        try lines.append(current_line);
                        current_line = std.array_list.AlignedManaged(RenderedSegment, null).init(allocator);
                        current_x = 0;
                    }

                    if (line.len > 0) {
                        try current_line.append(RenderedSegment{
                            .text = line,
                            .style = segment.style,
                            .x = current_x,
                        });
                        current_x += @intCast(line.len);
                    }

                    first_line = false;
                }
            },
            .word => {
                try self.layoutWordsInSegment(allocator, &lines, &current_line, &current_x, segment, width);
            },
            .character => {
                try self.layoutCharactersInSegment(allocator, &lines, &current_line, &current_x, segment, width);
            },
        }
    }

    // Add final line
    if (current_line.items.len > 0) {
        try lines.append(current_line);
    }

    return lines.toOwnedSlice();
}

const RenderedSegment = struct {
    text: []const u8,
    style: Style,
    x: u16,
};

fn layoutWordsInSegment(
    self: *const RichText,
    allocator: Allocator,
    lines: *std.array_list.AlignedManaged(std.array_list.AlignedManaged(RenderedSegment, null), null),
    current_line: *std.array_list.AlignedManaged(RenderedSegment, null),
    current_x: *u16,
    segment: FormatSegment,
    width: u16
) !void {
    _ = self;
    var line_iterator = std.mem.splitScalar(u8, segment.text, '\n');
    var first_line = true;

    while (line_iterator.next()) |paragraph| {
        if (!first_line) {
            // Start new line
            try lines.append(current_line.*);
            current_line.* = std.array_list.AlignedManaged(RenderedSegment, null).init(allocator);
            current_x.* = 0;
        }

        if (paragraph.len > 0) {
            var word_iterator = std.mem.tokenizeAny(u8, paragraph, " \t");

            while (word_iterator.next()) |word| {
                const space_needed = if (current_x.* == 0) word.len else current_x.* + 1 + word.len;

                if (space_needed <= width) {
                    // Word fits on current line
                    if (current_x.* > 0) {
                        try current_line.append(RenderedSegment{
                            .text = " ",
                            .style = segment.style,
                            .x = current_x.*,
                        });
                        current_x.* += 1;
                    }

                    try current_line.append(RenderedSegment{
                        .text = word,
                        .style = segment.style,
                        .x = current_x.*,
                    });
                    current_x.* += @intCast(word.len);
                } else {
                    // Start new line
                    try lines.append(current_line.*);
                    current_line.* = std.array_list.AlignedManaged(RenderedSegment, null).init(allocator);

                    try current_line.append(RenderedSegment{
                        .text = word,
                        .style = segment.style,
                        .x = 0,
                    });
                    current_x.* = @intCast(word.len);
                }
            }
        }

        first_line = false;
    }
}

fn layoutCharactersInSegment(
    self: *const RichText,
    allocator: Allocator,
    lines: *std.array_list.AlignedManaged(std.array_list.AlignedManaged(RenderedSegment, null), null),
    current_line: *std.array_list.AlignedManaged(RenderedSegment, null),
    current_x: *u16,
    segment: FormatSegment,
    width: u16
) !void {
    _ = self;
    var line_iterator = std.mem.splitScalar(u8, segment.text, '\n');
    var first_line = true;

    while (line_iterator.next()) |paragraph| {
        if (!first_line) {
            // Start new line
            try lines.append(current_line.*);
            current_line.* = std.array_list.AlignedManaged(RenderedSegment, null).init(allocator);
            current_x.* = 0;
        }

        var i: usize = 0;
        while (i < paragraph.len) {
            const chars_remaining = width - current_x.*;
            if (chars_remaining == 0) {
                // Start new line
                try lines.append(current_line.*);
                current_line.* = std.array_list.AlignedManaged(RenderedSegment, null).init(allocator);
                current_x.* = 0;
                continue;
            }

            const chunk_end = @min(i + chars_remaining, paragraph.len);
            try current_line.append(RenderedSegment{
                .text = paragraph[i..chunk_end],
                .style = segment.style,
                .x = current_x.*,
            });

            current_x.* += @intCast(chunk_end - i);
            i = chunk_end;
        }

        first_line = false;
    }
}

/// Get the widget interface for this RichText
pub fn widget(self: *const RichText) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const RichText = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *const RichText = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const RichText, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const width = ctx.getWidth();
    const height = ctx.getHeight();

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(width, height)
    );

    // Layout text into lines
    const lines = try self.layoutText(ctx.arena, width);
    defer ctx.arena.free(lines);

    // Draw lines
    var y: u16 = 0;
    for (lines) |line| {
        if (y >= height) break;

        for (line.items) |rendered_segment| {
            _ = surface.writeText(rendered_segment.x, y, rendered_segment.text, rendered_segment.style);
        }

        y += 1 + self.line_spacing;
    }

    return surface;
}

pub fn handleEvent(self: *const RichText, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    _ = self;
    // RichText is typically read-only
    return ctx.createCommandList();
}

test "RichText markdown parsing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const markdown_text = "# Header\nThis is **bold** and *italic* text with `code`.";
    const rich_text = try RichText.fromMarkdown(arena.allocator(), markdown_text, MarkdownStyle.defaultDark());

    // Should have multiple segments
    try std.testing.expect(rich_text.content.len > 1);
}

test "RichText creation from segments" {
    const segments = [_]FormatSegment{
        .{ .text = "Normal ", .style = Style.default() },
        .{ .text = "Bold", .style = Style.default().withBold() },
        .{ .text = " Text", .style = Style.default() },
    };

    const rich_text = RichText.init(&segments, Style.default());
    try std.testing.expectEqual(@as(usize, 3), rich_text.content.len);
}