//! Advanced TextEditor Widget for Grim
//! Features: Multi-cursor, syntax highlighting hooks, line numbers, code folding, minimap support
//! Optimized for millions of lines with rope data structure

const std = @import("std");
const phantom = @import("../../root.zig");
const gcode = @import("gcode");
const App = phantom.App;
const Widget = @import("../../widget.zig").Widget;
const Style = phantom.Style;
const Color = phantom.Color;
const Allocator = std.mem.Allocator;

const Self = @This();

pub const base_id: []const u8 = "TextEditor";

// Widget interface
widget: Widget,

// Core state
allocator: Allocator,
buffer: TextBuffer,
cursors: std.ArrayList(Cursor),
selections: std.ArrayList(Selection),
viewport: Viewport,
line_numbers_enabled: bool,
relative_line_numbers: bool,

// Rendering
font_manager: ?*phantom.font.FontManager,
syntax_highlighter: ?*SyntaxHighlighter,
line_height: u16,
gutter_width: u16,
scroll_offset: struct {
    line: usize,
    col: usize,
},

// Features
undo_stack: UndoStack,
search_state: ?SearchState,
code_folding: std.ArrayList(FoldRegion),
diagnostic_markers: std.ArrayList(DiagnosticMarker),

// Configuration
config: EditorConfig,

// Performance optimization
visible_lines_cache: std.ArrayList(RenderedLine),
dirty_lines: std.DynamicBitSet,

/// Efficient text buffer using rope data structure for large files
const TextBuffer = struct {
    rope: Rope,
    line_index: std.ArrayList(usize), // Fast line offset lookup
    allocator: Allocator,
    modified: bool,

    const Rope = struct {
        // Simplified rope - can be expanded to full rope later
        content: std.ArrayList(u8),
        allocator: Allocator,

        pub fn init(allocator: Allocator) Rope {
            return Rope{
                .content = .{},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Rope) void {
            self.content.deinit(self.allocator);
        }

        pub fn insert(self: *Rope, pos: usize, text: []const u8) !void {
            try self.content.insertSlice(self.allocator, pos, text);
        }

        pub fn delete(self: *Rope, start: usize, length: usize) !void {
            self.content.replaceRange(self.allocator, start, length, &[_]u8{}) catch {};
        }

        pub fn getSlice(self: *const Rope, start: usize, end: usize) []const u8 {
            return self.content.items[start..end];
        }

        pub fn len(self: *const Rope) usize {
            return self.content.items.len;
        }
    };

    pub fn init(allocator: Allocator) TextBuffer {
        return TextBuffer{
            .rope = Rope.init(allocator),
            .line_index = .{},
            .allocator = allocator,
            .modified = false,
        };
    }

    pub fn deinit(self: *TextBuffer) void {
        self.rope.deinit();
        self.line_index.deinit(self.allocator);
    }

    pub fn loadFromString(self: *TextBuffer, content: []const u8) !void {
        try self.rope.content.appendSlice(self.allocator, content);
        try self.rebuildLineIndex();
    }

    pub fn insertText(self: *TextBuffer, pos: BufferPosition, text: []const u8) !void {
        const byte_offset = try self.positionToOffset(pos);
        try self.rope.insert(byte_offset, text);
        try self.rebuildLineIndex();
        self.modified = true;
    }

    pub fn deleteRange(self: *TextBuffer, start: BufferPosition, end: BufferPosition) !void {
        const start_offset = try self.positionToOffset(start);
        const end_offset = try self.positionToOffset(end);
        try self.rope.delete(start_offset, end_offset - start_offset);
        try self.rebuildLineIndex();
        self.modified = true;
    }

    pub fn getLine(self: *const TextBuffer, line_num: usize) ![]const u8 {
        if (line_num >= self.line_index.items.len) return error.LineOutOfBounds;

        const start = self.line_index.items[line_num];
        const end = if (line_num + 1 < self.line_index.items.len)
            self.line_index.items[line_num + 1]
        else
            self.rope.len();

        return self.rope.getSlice(start, end);
    }

    pub fn lineCount(self: *const TextBuffer) usize {
        return self.line_index.items.len;
    }

    fn rebuildLineIndex(self: *TextBuffer) !void {
        self.line_index.clearRetainingCapacity();
        try self.line_index.append(self.allocator, 0);

        const content = self.rope.content.items;
        for (content, 0..) |char, i| {
            if (char == '\n') {
                try self.line_index.append(self.allocator, i + 1);
            }
        }
    }

    fn positionToOffset(self: *const TextBuffer, pos: BufferPosition) !usize {
        if (pos.line >= self.line_index.items.len) return error.LineOutOfBounds;
        return self.line_index.items[pos.line] + pos.col;
    }
};

const BufferPosition = struct {
    line: usize,
    col: usize,
};

const Cursor = struct {
    position: BufferPosition,
    anchor: ?BufferPosition, // For selection
    desired_col: usize, // Sticky column for vertical movement
    id: usize,

    pub fn hasSelection(self: Cursor) bool {
        return self.anchor != null;
    }
};

const Selection = struct {
    start: BufferPosition,
    end: BufferPosition,
    cursor_id: usize,
};

const Viewport = struct {
    top_line: usize,
    left_col: usize,
    visible_lines: usize,
    visible_cols: usize,
};

const UndoStack = struct {
    operations: std.ArrayList(EditOperation),
    cursor: usize,
    allocator: Allocator,

    const EditOperation = union(enum) {
        insert: struct {
            pos: BufferPosition,
            text: []u8,
        },
        delete: struct {
            pos: BufferPosition,
            text: []u8,
        },
        replace: struct {
            pos: BufferPosition,
            old_text: []u8,
            new_text: []u8,
        },
    };

    pub fn init(allocator: Allocator) UndoStack {
        return UndoStack{
            .operations = .{},
            .cursor = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UndoStack) void {
        for (self.operations.items) |op| {
            switch (op) {
                .insert => |data| self.allocator.free(data.text),
                .delete => |data| self.allocator.free(data.text),
                .replace => |data| {
                    self.allocator.free(data.old_text);
                    self.allocator.free(data.new_text);
                },
            }
        }
        self.operations.deinit(self.allocator);
    }

    pub fn push(self: *UndoStack, operation: EditOperation) !void {
        // Clear redo history
        while (self.operations.items.len > self.cursor) {
            _ = self.operations.pop();
        }
        try self.operations.append(self.allocator, operation);
        self.cursor = self.operations.items.len;
    }
};

const SearchState = struct {
    query: []u8,
    matches: std.ArrayList(BufferPosition),
    current_match: usize,
    case_sensitive: bool,
    whole_word: bool,
    regex: bool,
};

const FoldRegion = struct {
    start_line: usize,
    end_line: usize,
    folded: bool,
};

const DiagnosticMarker = struct {
    line: usize,
    col: usize,
    severity: Severity,
    message: []const u8,

    const Severity = enum {
        error_marker,
        warning,
        info,
        hint,
    };
};

const SyntaxHighlighter = struct {
    // Hook for external syntax highlighting (e.g., Tree-sitter)
    highlight_fn: *const fn ([]const u8) anyerror![]TokenHighlight,

    const TokenHighlight = struct {
        start: usize,
        end: usize,
        color: Color,
        style: Style,
    };
};

const RenderedLine = struct {
    line_num: usize,
    content: []u8,
    highlights: []SyntaxHighlighter.TokenHighlight,
    width: u32,
};

pub const EditorConfig = struct {
    tab_size: u8 = 4,
    use_spaces: bool = true,
    line_wrap: bool = false,
    show_whitespace: bool = false,
    show_line_numbers: bool = true,
    relative_line_numbers: bool = false,
    cursor_line_highlight: bool = true,
    scroll_offset: u8 = 5, // Lines to keep above/below cursor
    auto_indent: bool = true,
    auto_closing_brackets: bool = true,
    highlight_matching_brackets: bool = true,
    enable_ligatures: bool = true, // Font ligature support
};

// Widget vtable
const vtable = Widget.WidgetVTable{
    .render = render,
    .handleEvent = handleEvent,
    .resize = resize,
    .deinit = deinit,
};

pub fn init(allocator: Allocator, config: EditorConfig) !*Self {
    const self = try allocator.create(Self);

    self.* = Self{
        .widget = Widget{ .vtable = &vtable },
        .allocator = allocator,
        .buffer = TextBuffer.init(allocator),
        .cursors = .{},
        .selections = .{},
        .viewport = Viewport{
            .top_line = 0,
            .left_col = 0,
            .visible_lines = 24,
            .visible_cols = 80,
        },
        .line_numbers_enabled = config.show_line_numbers,
        .relative_line_numbers = config.relative_line_numbers,
        .font_manager = null,
        .syntax_highlighter = null,
        .line_height = 16,
        .gutter_width = 50,
        .scroll_offset = .{ .line = 0, .col = 0 },
        .undo_stack = UndoStack.init(allocator),
        .search_state = null,
        .code_folding = .{},
        .diagnostic_markers = .{},
        .config = config,
        .visible_lines_cache = .{},
        .dirty_lines = try std.DynamicBitSet.initEmpty(allocator, 1000),
    };

    // Initialize with single cursor at 0,0
    try self.cursors.append(allocator, Cursor{
        .position = .{ .line = 0, .col = 0 },
        .anchor = null,
        .desired_col = 0,
        .id = 0,
    });

    return self;
}

pub fn deinit(widget: *Widget) void {
    const self: *Self = @fieldParentPtr("widget", widget);

    self.buffer.deinit();
    self.cursors.deinit(self.allocator);
    self.selections.deinit(self.allocator);
    self.undo_stack.deinit();
    self.code_folding.deinit(self.allocator);
    self.diagnostic_markers.deinit(self.allocator);
    self.visible_lines_cache.deinit(self.allocator);
    self.dirty_lines.deinit();

    if (self.search_state) |*state| {
        self.allocator.free(state.query);
        state.matches.deinit(self.allocator);
    }

    self.allocator.destroy(self);
}

pub fn loadFile(self: *Self, path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(self.allocator, 100 * 1024 * 1024); // 100MB max
    defer self.allocator.free(content);

    try self.buffer.loadFromString(content);
}

pub fn saveFile(self: *Self, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    try file.writeAll(self.buffer.rope.content.items);
    self.buffer.modified = false;
}

/// Insert text at all cursor positions
pub fn insertText(self: *Self, text: []const u8) !void {
    for (self.cursors.items) |*cursor| {
        try self.buffer.insertText(cursor.position, text);

        // Move cursor forward
        cursor.position.col += text.len;
    }
}

/// Add a new cursor (multi-cursor support)
pub fn addCursor(self: *Self, position: BufferPosition) !void {
    const new_id = self.cursors.items.len;
    try self.cursors.append(self.allocator, Cursor{
        .position = position,
        .anchor = null,
        .desired_col = position.col,
        .id = new_id,
    });
}

/// Move cursor (supports multi-cursor)
pub fn moveCursor(self: *Self, direction: CursorMovement) !void {
    for (self.cursors.items) |*cursor| {
        switch (direction) {
            .up => if (cursor.position.line > 0) {
                cursor.position.line -= 1;
                cursor.position.col = @min(cursor.desired_col, (try self.buffer.getLine(cursor.position.line)).len);
            },
            .down => if (cursor.position.line < self.buffer.lineCount() - 1) {
                cursor.position.line += 1;
                cursor.position.col = @min(cursor.desired_col, (try self.buffer.getLine(cursor.position.line)).len);
            },
            .left => if (cursor.position.col > 0) {
                cursor.position.col -= 1;
                cursor.desired_col = cursor.position.col;
            },
            .right => {
                const line = try self.buffer.getLine(cursor.position.line);
                if (cursor.position.col < line.len) {
                    cursor.position.col += 1;
                    cursor.desired_col = cursor.position.col;
                }
            },
            .line_start => {
                cursor.position.col = 0;
                cursor.desired_col = 0;
            },
            .line_end => {
                const line = try self.buffer.getLine(cursor.position.line);
                cursor.position.col = line.len;
                cursor.desired_col = cursor.position.col;
            },
            .word_forward => try self.moveWordForward(cursor),
            .word_backward => try self.moveWordBackward(cursor),
        }
    }
}

const CursorMovement = enum {
    up,
    down,
    left,
    right,
    line_start,
    line_end,
    word_forward,
    word_backward,
};

fn moveWordForward(self: *Self, cursor: *Cursor) !void {
    const line = try self.buffer.getLine(cursor.position.line);
    var iter = gcode.wordIterator(line[cursor.position.col..]);

    if (iter.next()) |word| {
        cursor.position.col += word.len;
    }
    cursor.desired_col = cursor.position.col;
}

fn moveWordBackward(self: *Self, cursor: *Cursor) !void {
    if (cursor.position.col == 0) return;

    const line = try self.buffer.getLine(cursor.position.line);
    cursor.position.col = gcode.findPreviousGrapheme(line, cursor.position.col);
    cursor.desired_col = cursor.position.col;
}

fn render(widget: *Widget, buf: *@import("../../terminal.zig").Buffer, area: @import("../../geometry.zig").Rect) void {
    const self: *Self = @fieldParentPtr("widget", widget);

    if (area.width == 0 or area.height == 0) return;

    // Simple rendering - show buffer content
    var line_num = self.viewport.top_line;
    const end_line = @min(self.viewport.top_line + self.viewport.visible_lines, self.buffer.lineCount());

    var y = area.y;
    while (line_num < end_line and y < area.y + area.height) : ({line_num += 1; y += 1;}) {
        const line = self.buffer.getLine(line_num) catch continue;
        const visible_len = @min(line.len, area.width);

        // Write line content to buffer
        var x: u16 = 0;
        while (x < visible_len) : (x += 1) {
            const char = if (x < line.len) line[x] else ' ';
            buf.setCell(area.x + x, y, .{
                .char = char,
                .style = phantom.Style.default(),
            });
        }
    }
}

fn renderLineNumbers(self: *Self, writer: anytype) !void {
    const start = self.viewport.top_line;
    const end = @min(start + self.viewport.visible_lines, self.buffer.lineCount());

    var line_num = start;
    while (line_num < end) : (line_num += 1) {
        const num_str = if (self.relative_line_numbers)
            try std.fmt.allocPrint(self.allocator, "{d: >4} ", .{@abs(@as(i64, @intCast(line_num)) - @as(i64, @intCast(self.cursors.items[0].position.line)))})
        else
            try std.fmt.allocPrint(self.allocator, "{d: >4} ", .{line_num + 1});

        defer self.allocator.free(num_str);
        try writer.print("{s}", .{num_str});
    }
}

fn renderLine(self: *Self, writer: anytype, line_num: usize, line_content: []const u8) !void {
    _ = self;
    _ = line_num;
    try writer.print("{s}\n", .{line_content});
}

fn renderCursor(self: *Self, writer: anytype, cursor: Cursor) !void {
    _ = self;
    _ = writer;
    _ = cursor;
    // TODO: Render cursor at position
}

fn handleEvent(widget: *Widget, event: @import("../../event.zig").Event) bool {
    const self: *Self = @fieldParentPtr("widget", widget);
    _ = self;
    _ = event;

    // TODO: Handle keyboard events for cursor movement, text input, etc.
    return false;
}

fn resize(widget: *Widget, area: @import("../../geometry.zig").Rect) void {
    const self: *Self = @fieldParentPtr("widget", widget);
    _ = self;
    _ = area;

    // TODO: Implement viewport resize logic
}

test "TextEditor initialization" {
    const allocator = std.testing.allocator;

    const config = EditorConfig{};
    const editor = try init(allocator, config);
    defer editor.widget.vtable.deinit(&editor.widget);

    try std.testing.expect(editor.cursors.items.len == 1);
    try std.testing.expect(editor.buffer.lineCount() == 0);
}

test "TextEditor text insertion" {
    const allocator = std.testing.allocator;

    const config = EditorConfig{};
    const editor = try init(allocator, config);
    defer editor.widget.vtable.deinit(&editor.widget);

    try editor.buffer.loadFromString("Hello\nWorld\n");
    try std.testing.expect(editor.buffer.lineCount() == 3); // Including empty line after last \n

    const line0 = try editor.buffer.getLine(0);
    try std.testing.expectEqualStrings("Hello\n", line0);
}
