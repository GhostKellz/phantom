//! Markdown Viewer Widget - CommonMark rendering for TUI
//! Perfect for LSP hover documentation, help text, README display
//! Supports syntax highlighting integration with Grove

const std = @import("std");
const phantom = @import("../root.zig");
const Widget = phantom.Widget;
const Buffer = phantom.Buffer;
const Cell = phantom.Cell;
const Event = phantom.Event;
const Key = phantom.Key;
const Rect = phantom.Rect;
const Style = phantom.Style;
const Color = phantom.Color;

/// Markdown block type
pub const MarkdownBlockKind = enum {
    paragraph,
    heading,      // # Heading
    code_block,   // ```code```
    quote,        // > Quote
    list_item,    // - Item or 1. Item
    horizontal_rule, // ---
};

/// Markdown inline style
pub const InlineStyle = struct {
    bold: bool = false,
    italic: bool = false,
    code: bool = false,       // `code`
    link: bool = false,
    strikethrough: bool = false,

    pub fn toStyle(self: InlineStyle, base: Style) Style {
        var s = base;
        if (self.bold) s = s.withBold();
        if (self.italic) s = s.withItalic();
        if (self.code) s = s.withFg(Color.cyan);
        if (self.link) s = s.withFg(Color.blue).withUnderline();
        if (self.strikethrough) s = s.withStrikethrough();
        return s;
    }
};

/// Markdown block
pub const MarkdownBlock = struct {
    kind: MarkdownBlockKind,
    content: []const u8,
    level: usize = 0,         // Heading level (1-6) or list indent
    language: ?[]const u8 = null, // Code block language
    ordered: bool = false,    // Ordered vs unordered list
};

/// Configuration for Markdown viewer
pub const MarkdownConfig = struct {
    /// Enable syntax highlighting in code blocks (requires Grove)
    syntax_highlight: bool = false,

    /// Show line numbers in code blocks
    show_line_numbers: bool = false,

    /// Wrap long lines
    wrap_text: bool = true,

    /// Styles
    heading1_style: Style = Style.default().withFg(Color.cyan).withBold(),
    heading2_style: Style = Style.default().withFg(Color.cyan),
    heading3_style: Style = Style.default().withFg(Color.blue).withBold(),
    code_style: Style = Style.default().withFg(Color.green),
    code_block_style: Style = Style.default().withFg(Color.bright_black),
    quote_style: Style = Style.default().withFg(Color.yellow).withItalic(),
    link_style: Style = Style.default().withFg(Color.blue).withUnderline(),
    list_marker_style: Style = Style.default().withFg(Color.bright_cyan),
    normal_style: Style = Style.default(),

    /// Characters
    quote_char: u21 = '│',
    list_bullet: u21 = '•',
    code_block_border: u21 = '─',

    pub fn default() MarkdownConfig {
        return .{};
    }
};

/// Custom error types
pub const Error = error{
    ParseError,
    InvalidMarkdown,
} || std.mem.Allocator.Error;

/// Markdown viewer widget
pub const Markdown = struct {
    widget: Widget,
    allocator: std.mem.Allocator,

    blocks: std.ArrayList(MarkdownBlock),
    scroll_offset: usize,
    viewport_height: u16,

    config: MarkdownConfig,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator, config: MarkdownConfig) Error!*Markdown {
        const md = try allocator.create(Markdown);
        md.* = .{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .blocks = std.ArrayList(MarkdownBlock).init(allocator),
            .scroll_offset = 0,
            .viewport_height = 10,
            .config = config,
        };
        return md;
    }

    /// Set markdown content (simple parser)
    pub fn setContent(self: *Markdown, markdown: []const u8) !void {
        // Clear existing blocks
        for (self.blocks.items) |block| {
            self.allocator.free(block.content);
            if (block.language) |lang| self.allocator.free(lang);
        }
        self.blocks.clearRetainingCapacity();

        var lines = std.mem.tokenizeScalar(u8, markdown, '\n');

        var in_code_block = false;
        var code_language: ?[]const u8 = null;
        var code_lines = std.ArrayList(u8).init(self.allocator);
        defer code_lines.deinit();

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            // Code block start/end
            if (std.mem.startsWith(u8, trimmed, "```")) {
                if (in_code_block) {
                    // End code block
                    const content = try code_lines.toOwnedSlice();
                    try self.blocks.append(.{
                        .kind = .code_block,
                        .content = content,
                        .language = code_language,
                    });
                    in_code_block = false;
                    code_language = null;
                } else {
                    // Start code block
                    const lang = std.mem.trim(u8, trimmed[3..], " \t");
                    code_language = if (lang.len > 0) try self.allocator.dupe(u8, lang) else null;
                    in_code_block = true;
                }
                continue;
            }

            // Inside code block
            if (in_code_block) {
                try code_lines.appendSlice(line);
                try code_lines.append('\n');
                continue;
            }

            // Empty line
            if (trimmed.len == 0) continue;

            // Heading
            if (std.mem.startsWith(u8, trimmed, "#")) {
                var level: usize = 0;
                for (trimmed) |c| {
                    if (c == '#') level += 1 else break;
                }
                if (level <= 6) {
                    const heading_text = std.mem.trim(u8, trimmed[level..], " \t");
                    try self.blocks.append(.{
                        .kind = .heading,
                        .content = try self.allocator.dupe(u8, heading_text),
                        .level = level,
                    });
                    continue;
                }
            }

            // Horizontal rule
            if (std.mem.eql(u8, trimmed, "---") or std.mem.eql(u8, trimmed, "***")) {
                try self.blocks.append(.{
                    .kind = .horizontal_rule,
                    .content = try self.allocator.dupe(u8, ""),
                });
                continue;
            }

            // Quote
            if (std.mem.startsWith(u8, trimmed, ">")) {
                const quote_text = std.mem.trim(u8, trimmed[1..], " \t");
                try self.blocks.append(.{
                    .kind = .quote,
                    .content = try self.allocator.dupe(u8, quote_text),
                });
                continue;
            }

            // List item (unordered)
            if (trimmed.len > 2 and (trimmed[0] == '-' or trimmed[0] == '*') and trimmed[1] == ' ') {
                const item_text = std.mem.trim(u8, trimmed[2..], " \t");
                try self.blocks.append(.{
                    .kind = .list_item,
                    .content = try self.allocator.dupe(u8, item_text),
                    .ordered = false,
                });
                continue;
            }

            // List item (ordered)
            if (trimmed.len > 3 and std.ascii.isDigit(trimmed[0])) {
                const dot_idx = std.mem.indexOf(u8, trimmed, ". ");
                if (dot_idx != null and dot_idx.? < 4) {
                    const item_text = std.mem.trim(u8, trimmed[dot_idx.? + 2 ..], " \t");
                    try self.blocks.append(.{
                        .kind = .list_item,
                        .content = try self.allocator.dupe(u8, item_text),
                        .ordered = true,
                    });
                    continue;
                }
            }

            // Regular paragraph
            try self.blocks.append(.{
                .kind = .paragraph,
                .content = try self.allocator.dupe(u8, trimmed),
            });
        }

        self.scroll_offset = 0;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Markdown = @fieldParentPtr("widget", widget);

        self.viewport_height = area.height;

        if (self.blocks.items.len == 0) {
            buffer.writeText(area.x, area.y, "No content", Style.default().withFg(Color.bright_black));
            return;
        }

        var y: u16 = 0;
        var block_idx = self.scroll_offset;

        while (block_idx < self.blocks.items.len and y < area.height) : (block_idx += 1) {
            const block = self.blocks.items[block_idx];
            const lines_rendered = self.renderBlock(buffer, area.x, area.y + y, area.width, area.height - y, &block);
            y += lines_rendered;

            // Add spacing between blocks
            if (block.kind != .list_item and y < area.height) {
                y += 1;
            }
        }
    }

    fn renderBlock(self: *const Markdown, buffer: *Buffer, x: u16, y: u16, width: u16, remaining_height: u16, block: *const MarkdownBlock) u16 {
        if (remaining_height == 0) return 0;

        switch (block.kind) {
            .heading => {
                const style = switch (block.level) {
                    1 => self.config.heading1_style,
                    2 => self.config.heading2_style,
                    else => self.config.heading3_style,
                };

                // Add heading prefix
                const prefix = switch (block.level) {
                    1 => "# ",
                    2 => "## ",
                    3 => "### ",
                    else => "",
                };

                const text = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, block.content }) catch return 1;
                defer self.allocator.free(text);

                buffer.writeText(x, y, text, style);
                return 1;
            },

            .code_block => {
                var lines_used: u16 = 0;

                // Code block header (language)
                if (block.language) |lang| {
                    const header = std.fmt.allocPrint(self.allocator, "```{s}", .{lang}) catch return 1;
                    defer self.allocator.free(header);
                    buffer.writeText(x, y + lines_used, header, self.config.code_block_style);
                    lines_used += 1;
                }

                // Code lines
                var code_lines = std.mem.tokenizeScalar(u8, block.content, '\n');
                while (code_lines.next()) |line| {
                    if (lines_used >= remaining_height) break;
                    const trimmed_line = if (line.len > width) line[0..width] else line;
                    buffer.writeText(x + 2, y + lines_used, trimmed_line, self.config.code_style);
                    lines_used += 1;
                }

                return lines_used;
            },

            .quote => {
                buffer.setCell(x, y, Cell.init(self.config.quote_char, self.config.quote_style));
                buffer.writeText(x + 2, y, block.content, self.config.quote_style);
                return 1;
            },

            .list_item => {
                const marker: u21 = if (block.ordered) '•' else self.config.list_bullet;
                buffer.setCell(x, y, Cell.init(marker, self.config.list_marker_style));
                buffer.writeText(x + 2, y, block.content, self.config.normal_style);
                return 1;
            },

            .horizontal_rule => {
                var i: u16 = 0;
                while (i < width) : (i += 1) {
                    buffer.setCell(x + i, y, Cell.init(self.config.code_block_border, self.config.code_block_style));
                }
                return 1;
            },

            .paragraph => {
                // Word wrap if enabled
                if (self.config.wrap_text and block.content.len > width) {
                    var lines_used: u16 = 0;
                    var remaining = block.content;

                    while (remaining.len > 0 and lines_used < remaining_height) {
                        const chunk_len = @min(remaining.len, width);
                        const chunk = remaining[0..chunk_len];
                        buffer.writeText(x, y + lines_used, chunk, self.config.normal_style);
                        remaining = remaining[chunk_len..];
                        lines_used += 1;
                    }
                    return lines_used;
                } else {
                    const text = if (block.content.len > width) block.content[0..width] else block.content;
                    buffer.writeText(x, y, text, self.config.normal_style);
                    return 1;
                }
            },
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Markdown = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key| {
                switch (key) {
                    .up, .char => |c| {
                        if (key == .up or (key == .char and c == 'k')) {
                            if (self.scroll_offset > 0) {
                                self.scroll_offset -= 1;
                            }
                            return true;
                        }
                    },
                    .down => {
                        if (self.scroll_offset + self.viewport_height < self.blocks.items.len) {
                            self.scroll_offset += 1;
                        }
                        return true;
                    },
                    .page_up => {
                        self.scroll_offset -|= self.viewport_height;
                        return true;
                    },
                    .page_down => {
                        self.scroll_offset = @min(
                            self.scroll_offset + self.viewport_height,
                            self.blocks.items.len -| self.viewport_height,
                        );
                        return true;
                    },
                    .home => {
                        self.scroll_offset = 0;
                        return true;
                    },
                    .end => {
                        self.scroll_offset = self.blocks.items.len -| self.viewport_height;
                        return true;
                    },
                    else => {
                        if (key == .char) {
                            const c = key.char;
                            if (c == 'j') {
                                if (self.scroll_offset + self.viewport_height < self.blocks.items.len) {
                                    self.scroll_offset += 1;
                                }
                                return true;
                            }
                        }
                    },
                }
            },
            .mouse => |mouse| {
                if (mouse.button == .wheel_up and self.scroll_offset > 0) {
                    self.scroll_offset -= 1;
                    return true;
                }
                if (mouse.button == .wheel_down) {
                    if (self.scroll_offset + self.viewport_height < self.blocks.items.len) {
                        self.scroll_offset += 1;
                    }
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *Markdown = @fieldParentPtr("widget", widget);
        self.viewport_height = area.height;
    }

    fn deinit(widget: *Widget) void {
        const self: *Markdown = @fieldParentPtr("widget", widget);

        for (self.blocks.items) |block| {
            self.allocator.free(block.content);
            if (block.language) |lang| self.allocator.free(lang);
        }
        self.blocks.deinit();

        self.allocator.destroy(self);
    }
};

// Tests
test "Markdown basic operations" {
    const testing = std.testing;

    const md = try Markdown.init(testing.allocator, MarkdownConfig.default());
    defer md.widget.vtable.deinit(&md.widget);

    try md.setContent("# Hello World\n\nThis is a test.");

    try testing.expect(md.blocks.items.len > 0);
}

test "Markdown heading parsing" {
    const testing = std.testing;

    const md = try Markdown.init(testing.allocator, MarkdownConfig.default());
    defer md.widget.vtable.deinit(&md.widget);

    try md.setContent("# Heading 1\n## Heading 2\n### Heading 3");

    try testing.expectEqual(@as(usize, 3), md.blocks.items.len);
    try testing.expectEqual(MarkdownBlockKind.heading, md.blocks.items[0].kind);
    try testing.expectEqual(@as(usize, 1), md.blocks.items[0].level);
}

test "Markdown code block parsing" {
    const testing = std.testing;

    const md = try Markdown.init(testing.allocator, MarkdownConfig.default());
    defer md.widget.vtable.deinit(&md.widget);

    try md.setContent("```zig\nconst x = 42;\n```");

    var found_code = false;
    for (md.blocks.items) |block| {
        if (block.kind == .code_block) {
            found_code = true;
            try testing.expect(block.language != null);
            try testing.expectEqualStrings("zig", block.language.?);
        }
    }
    try testing.expect(found_code);
}
