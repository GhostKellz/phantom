//! TextArea widget for multiline text input
const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const Key = @import("../event.zig").Key;
const MouseEvent = @import("../event.zig").MouseEvent;
const MouseButton = @import("../event.zig").MouseButton;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const clipboard = @import("../clipboard.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// TextArea change callback function type
pub const OnChangeFn = *const fn (textarea: *TextArea, text: []const u8) void;
pub const OnSubmitFn = *const fn (textarea: *TextArea, text: []const u8) void;

/// Line of text with wrapping information
const TextLine = struct {
    allocator: std.mem.Allocator,
    content: std.ArrayList(u8),
    wrapped_lines: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) TextLine {
        return TextLine{
            .allocator = allocator,
            .content = .empty,
            .wrapped_lines = .empty,
        };
    }

    pub fn deinit(self: *TextLine) void {
        for (self.wrapped_lines.items) |line| {
            self.allocator.free(line);
        }
        self.wrapped_lines.deinit(self.allocator);
        self.content.deinit(self.allocator);
    }

    pub fn updateWrapping(self: *TextLine, width: u16) !void {
        // Clear existing wrapped lines
        for (self.wrapped_lines.items) |line| {
            self.allocator.free(line);
        }
        self.wrapped_lines.clearAndFree(self.allocator);

        if (width == 0) return;

        const text = self.content.items;
        var start: usize = 0;

        while (start < text.len) {
            const end = @min(start + width, text.len);
            const line = try self.allocator.dupe(u8, text[start..end]);
            try self.wrapped_lines.append(self.allocator, line);
            start = end;
        }

        // Ensure at least one line exists
        if (self.wrapped_lines.items.len == 0) {
            const empty_line = try self.allocator.dupe(u8, "");
            try self.wrapped_lines.append(self.allocator, empty_line);
        }
    }
};

/// TextArea widget for multiline text input
pub const TextArea = struct {
    pub const CursorPosition = struct {
        line: usize,
        column: usize,
    };

    pub const SelectionRange = struct {
        start: CursorPosition,
        end: CursorPosition,
    };

    pub const SearchDirection = enum {
        forward,
        backward,
    };

    widget: Widget,
    allocator: std.mem.Allocator,

    // Text content
    lines: std.ArrayList(TextLine),
    placeholder: []const u8,

    // Cursor position
    cursor_line: usize = 0,
    cursor_col: usize = 0,

    // Selection
    selection_start_line: ?usize = null,
    selection_start_col: ?usize = null,

    // Scrolling
    scroll_offset_line: usize = 0,
    scroll_offset_col: usize = 0,

    // Styling
    normal_style: Style,
    focused_style: Style,
    placeholder_style: Style,
    selection_style: Style,
    line_number_style: Style,

    // Configuration
    is_focused: bool = false,
    word_wrap: bool = true,
    show_line_numbers: bool = false,
    read_only: bool = false,
    max_lines: ?usize = null,
    tab_size: usize = 4,

    // Callbacks
    on_change: ?OnChangeFn = null,
    on_submit: ?OnSubmitFn = null,

    // Clipboard
    clipboard_manager: ?*clipboard.ClipboardManager = null,

    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
        .canFocus = canFocus,
        .focus = focusWidget,
        .blur = blurWidget,
    };

    pub fn init(allocator: std.mem.Allocator) !*TextArea {
        const textarea = try allocator.create(TextArea);
        var lines = std.ArrayList(TextLine).empty;
        try lines.append(allocator, TextLine.init(allocator));

        textarea.* = TextArea{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .lines = lines,
            .placeholder = "",
            .normal_style = Style.default(),
            .focused_style = Style.default().withBg(style.Color.blue),
            .placeholder_style = Style.default().withFg(style.Color.bright_black),
            .selection_style = Style.default().withBg(style.Color.cyan),
            .line_number_style = Style.default().withFg(style.Color.yellow),
        };
        return textarea;
    }

    pub fn setPlaceholder(self: *TextArea, placeholder: []const u8) !void {
        self.placeholder = try self.allocator.dupe(u8, placeholder);
    }

    pub fn setText(self: *TextArea, text: []const u8) !void {
        // Clear existing lines
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.clearAndFree(self.allocator);

        // Split text into lines
        var lines_iter = std.mem.splitSequence(u8, text, "\n");
        while (lines_iter.next()) |line_text| {
            var line = TextLine.init(self.allocator);
            try line.content.appendSlice(self.allocator, line_text);
            try self.lines.append(self.allocator, line);
        }

        // Ensure at least one line exists
        if (self.lines.items.len == 0) {
            try self.lines.append(self.allocator, TextLine.init(self.allocator));
        }

        self.cursor_line = @min(self.cursor_line, self.lines.items.len - 1);
        self.cursor_col = @min(self.cursor_col, self.lines.items[self.cursor_line].content.items.len);
        self.selection_start_line = null;
        self.selection_start_col = null;

        try self.updateWrapping();
        self.updateScrollOffset();
        self.notifyChange();
    }

    pub fn getText(self: *const TextArea) ![]const u8 {
        var result = std.ArrayList(u8).empty;

        for (self.lines.items, 0..) |line, i| {
            try result.appendSlice(self.allocator, line.content.items);
            if (i < self.lines.items.len - 1) {
                try result.append(self.allocator, '\n');
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    pub fn setWordWrap(self: *TextArea, word_wrap: bool) !void {
        self.word_wrap = word_wrap;
        try self.updateWrapping();
    }

    pub fn setShowLineNumbers(self: *TextArea, show: bool) !void {
        self.show_line_numbers = show;
        try self.updateWrapping();
    }

    pub fn setReadOnly(self: *TextArea, read_only: bool) void {
        self.read_only = read_only;
    }

    pub fn isReadOnly(self: *const TextArea) bool {
        return self.read_only;
    }

    pub fn setMaxLines(self: *TextArea, max_lines: ?usize) void {
        self.max_lines = max_lines;
    }

    pub fn setTabSize(self: *TextArea, tab_size: usize) void {
        self.tab_size = tab_size;
    }

    pub fn setOnChange(self: *TextArea, callback: OnChangeFn) void {
        self.on_change = callback;
    }

    pub fn setOnSubmit(self: *TextArea, callback: OnSubmitFn) void {
        self.on_submit = callback;
    }

    pub fn lineCount(self: *const TextArea) usize {
        return self.lines.items.len;
    }

    pub fn cursorPosition(self: *const TextArea) CursorPosition {
        return .{
            .line = self.cursor_line,
            .column = self.cursor_col,
        };
    }

    pub fn hasSelection(self: *const TextArea) bool {
        return self.selection_start_line != null and self.selection_start_col != null and
            (self.selection_start_line.? != self.cursor_line or self.selection_start_col.? != self.cursor_col);
    }

    pub fn selectionRange(self: *const TextArea) ?SelectionRange {
        const start_line = self.selection_start_line orelse return null;
        const start_col = self.selection_start_col orelse return null;

        const anchor = CursorPosition{ .line = start_line, .column = start_col };
        const cursor = self.cursorPosition();
        if (anchor.line < cursor.line or (anchor.line == cursor.line and anchor.column <= cursor.column)) {
            return .{ .start = anchor, .end = cursor };
        }

        return .{ .start = cursor, .end = anchor };
    }

    pub fn moveCursorTo(self: *TextArea, line: usize, column: usize) void {
        if (self.lines.items.len == 0) return;
        self.cursor_line = @min(line, self.lines.items.len - 1);
        self.cursor_col = @min(column, self.lines.items[self.cursor_line].content.items.len);
        self.updateScrollOffset();
    }

    pub fn gotoLine(self: *TextArea, line_1_based: usize) void {
        const target = line_1_based -| 1;
        self.moveCursorTo(target, self.cursor_col);
    }

    pub fn clearSelectionRange(self: *TextArea) void {
        self.selection_start_line = null;
        self.selection_start_col = null;
    }

    pub fn setSelectionRange(self: *TextArea, start: CursorPosition, end: CursorPosition) void {
        if (self.lines.items.len == 0) {
            self.clearSelectionRange();
            return;
        }

        const clamped_start = self.clampCursor(start);
        const clamped_end = self.clampCursor(end);
        self.selection_start_line = clamped_start.line;
        self.selection_start_col = clamped_start.column;
        self.cursor_line = clamped_end.line;
        self.cursor_col = clamped_end.column;
        self.updateScrollOffset();
    }

    pub fn findText(self: *const TextArea, needle: []const u8) ?CursorPosition {
        if (needle.len == 0) return null;

        for (self.lines.items, 0..) |line, line_index| {
            if (std.mem.indexOf(u8, line.content.items, needle)) |column| {
                return .{ .line = line_index, .column = column };
            }
        }

        return null;
    }

    pub fn findTextFrom(self: *const TextArea, needle: []const u8, start: CursorPosition, direction: SearchDirection) ?CursorPosition {
        if (needle.len == 0 or self.lines.items.len == 0) return null;

        const clamped = self.clampCursor(start);

        switch (direction) {
            .forward => {
                var line_index = clamped.line;
                while (line_index < self.lines.items.len) : (line_index += 1) {
                    const line = self.lines.items[line_index].content.items;
                    const start_column = if (line_index == clamped.line) @min(clamped.column, line.len) else 0;
                    if (std.mem.indexOfPos(u8, line, start_column, needle)) |column| {
                        return .{ .line = line_index, .column = column };
                    }
                }
            },
            .backward => {
                var line_index = clamped.line + 1;
                while (line_index > 0) {
                    line_index -= 1;
                    const line = self.lines.items[line_index].content.items;
                    const end_column = if (line_index == clamped.line) @min(clamped.column, line.len) else line.len;
                    if (std.mem.lastIndexOf(u8, line[0..end_column], needle)) |column| {
                        return .{ .line = line_index, .column = column };
                    }
                }
            },
        }

        return null;
    }

    pub fn focus(self: *TextArea) void {
        self.is_focused = true;
    }

    pub fn blur(self: *TextArea) void {
        self.is_focused = false;
        self.selection_start_line = null;
        self.selection_start_col = null;
    }

    fn canFocus(widget: *Widget) bool {
        _ = widget;
        return true;
    }

    fn focusWidget(widget: *Widget) void {
        const self: *TextArea = @fieldParentPtr("widget", widget);
        self.focus();
    }

    fn blurWidget(widget: *Widget) void {
        const self: *TextArea = @fieldParentPtr("widget", widget);
        self.blur();
    }

    pub fn clear(self: *TextArea) !void {
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.clearAndFree(self.allocator);

        try self.lines.append(self.allocator, TextLine.init(self.allocator));

        self.cursor_line = 0;
        self.cursor_col = 0;
        self.selection_start_line = null;
        self.selection_start_col = null;
        self.scroll_offset_line = 0;
        self.scroll_offset_col = 0;

        try self.updateWrapping();
        self.notifyChange();
    }

    pub fn selectAll(self: *TextArea) void {
        self.selection_start_line = 0;
        self.selection_start_col = 0;
        self.cursor_line = self.lines.items.len - 1;
        self.cursor_col = self.lines.items[self.cursor_line].content.items.len;
    }

    fn notifyChange(self: *TextArea) void {
        if (self.on_change) |callback| {
            const text = self.getText() catch return;
            defer self.allocator.free(text);
            callback(self, text);
        }
    }

    fn notifySubmit(self: *TextArea) void {
        if (self.on_submit) |callback| {
            const text = self.getText() catch return;
            defer self.allocator.free(text);
            callback(self, text);
        }
    }

    fn clampCursor(self: *const TextArea, cursor: CursorPosition) CursorPosition {
        if (self.lines.items.len == 0) return .{ .line = 0, .column = 0 };
        const line = @min(cursor.line, self.lines.items.len - 1);
        return .{
            .line = line,
            .column = @min(cursor.column, self.lines.items[line].content.items.len),
        };
    }

    fn updateWrapping(self: *TextArea) !void {
        if (!self.word_wrap) return;

        const text_width = self.getTextWidth();
        for (self.lines.items) |*line| {
            try line.updateWrapping(text_width);
        }
    }

    fn getTextWidth(self: *const TextArea) u16 {
        var width = self.area.width;
        if (width > 2) width -= 2; // Account for border
        if (self.show_line_numbers) {
            const line_num_width = self.getLineNumberWidth();
            if (width > line_num_width + 1) width -= line_num_width + 1;
        }
        return width;
    }

    fn getLineNumberWidth(self: *const TextArea) u16 {
        const line_count = self.lines.items.len;
        var width: u16 = 1;
        var num = line_count;
        while (num >= 10) {
            width += 1;
            num /= 10;
        }
        return width;
    }

    fn insertChar(self: *TextArea, c: u21) !void {
        if (self.read_only) return;

        const current_line = &self.lines.items[self.cursor_line];

        // Convert unicode codepoint to UTF-8
        var utf8_bytes: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(c, &utf8_bytes) catch return;

        // Insert character at cursor position
        try current_line.content.insertSlice(self.allocator, self.cursor_col, utf8_bytes[0..len]);
        self.cursor_col += len;

        try self.updateWrapping();
        self.updateScrollOffset();
        self.notifyChange();
    }

    fn insertNewline(self: *TextArea) !void {
        if (self.read_only) return;

        if (self.max_lines) |max| {
            if (self.lines.items.len >= max) return;
        }

        const current_line = &self.lines.items[self.cursor_line];

        // Split the current line at cursor position
        const remaining_text = current_line.content.items[self.cursor_col..];
        const new_line_text = try self.allocator.dupe(u8, remaining_text);

        // Truncate current line
        current_line.content.shrinkRetainingCapacity(self.cursor_col);

        // Create new line
        var new_line = TextLine.init(self.allocator);
        try new_line.content.appendSlice(self.allocator, new_line_text);

        // Insert new line after current line
        try self.lines.insert(self.allocator, self.cursor_line + 1, new_line);

        // Move cursor to beginning of new line
        self.cursor_line += 1;
        self.cursor_col = 0;

        self.allocator.free(new_line_text);

        try self.updateWrapping();
        self.updateScrollOffset();
        self.notifyChange();
    }

    fn deleteChar(self: *TextArea) !void {
        if (self.read_only) return;

        if (self.cursor_col > 0) {
            // Delete character before cursor
            const current_line = &self.lines.items[self.cursor_line];
            _ = current_line.content.orderedRemove(self.cursor_col - 1);
            self.cursor_col -= 1;
        } else if (self.cursor_line > 0) {
            // Join with previous line
            const current_line = self.lines.items[self.cursor_line];
            const prev_line = &self.lines.items[self.cursor_line - 1];

            self.cursor_col = prev_line.content.items.len;
            try prev_line.content.appendSlice(self.allocator, current_line.content.items);

            // Remove current line
            var line_to_remove = self.lines.orderedRemove(self.cursor_line);
            line_to_remove.deinit();
            self.cursor_line -= 1;
        }

        try self.updateWrapping();
        self.updateScrollOffset();
        self.notifyChange();
    }

    fn moveCursorUp(self: *TextArea) void {
        if (self.cursor_line > 0) {
            self.cursor_line -= 1;
            const line_len = self.lines.items[self.cursor_line].content.items.len;
            self.cursor_col = @min(self.cursor_col, line_len);
            self.updateScrollOffset();
        }
    }

    fn moveCursorDown(self: *TextArea) void {
        if (self.cursor_line < self.lines.items.len - 1) {
            self.cursor_line += 1;
            const line_len = self.lines.items[self.cursor_line].content.items.len;
            self.cursor_col = @min(self.cursor_col, line_len);
            self.updateScrollOffset();
        }
    }

    fn moveCursorLeft(self: *TextArea) void {
        if (self.cursor_col > 0) {
            self.cursor_col -= 1;
        } else if (self.cursor_line > 0) {
            self.cursor_line -= 1;
            self.cursor_col = self.lines.items[self.cursor_line].content.items.len;
        }
        self.updateScrollOffset();
    }

    fn moveCursorRight(self: *TextArea) void {
        const line_len = self.lines.items[self.cursor_line].content.items.len;
        if (self.cursor_col < line_len) {
            self.cursor_col += 1;
        } else if (self.cursor_line < self.lines.items.len - 1) {
            self.cursor_line += 1;
            self.cursor_col = 0;
        }
        self.updateScrollOffset();
    }

    fn moveCursorHome(self: *TextArea) void {
        self.cursor_col = 0;
        self.updateScrollOffset();
    }

    fn moveCursorEnd(self: *TextArea) void {
        self.cursor_col = self.lines.items[self.cursor_line].content.items.len;
        self.updateScrollOffset();
    }

    fn updateScrollOffset(self: *TextArea) void {
        const visible_height = if (self.area.height > 2) self.area.height - 2 else 0;
        const visible_width = self.getTextWidth();

        // Vertical scrolling
        if (self.cursor_line < self.scroll_offset_line) {
            self.scroll_offset_line = self.cursor_line;
        } else if (self.cursor_line >= self.scroll_offset_line + visible_height) {
            self.scroll_offset_line = self.cursor_line - visible_height + 1;
        }

        // Horizontal scrolling
        if (self.cursor_col < self.scroll_offset_col) {
            self.scroll_offset_col = self.cursor_col;
        } else if (self.cursor_col >= self.scroll_offset_col + visible_width) {
            self.scroll_offset_col = self.cursor_col - visible_width + 1;
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *TextArea = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;

        const current_style = if (self.is_focused) self.focused_style else self.normal_style;

        // Fill background
        buffer.fill(area, Cell.withStyle(current_style));

        // Draw border
        if (area.width > 2 and area.height > 2) {
            // Top and bottom borders
            var x = area.x;
            while (x < area.x + area.width) : (x += 1) {
                buffer.setCell(x, area.y, Cell.init('─', current_style));
                buffer.setCell(x, area.y + area.height - 1, Cell.init('─', current_style));
            }

            // Left and right borders
            var y = area.y;
            while (y < area.y + area.height) : (y += 1) {
                buffer.setCell(area.x, y, Cell.init('│', current_style));
                buffer.setCell(area.x + area.width - 1, y, Cell.init('│', current_style));
            }

            // Corners
            buffer.setCell(area.x, area.y, Cell.init('┌', current_style));
            buffer.setCell(area.x + area.width - 1, area.y, Cell.init('┐', current_style));
            buffer.setCell(area.x, area.y + area.height - 1, Cell.init('└', current_style));
            buffer.setCell(area.x + area.width - 1, area.y + area.height - 1, Cell.init('┘', current_style));
        }

        // Render text content
        if (area.width > 2 and area.height > 2) {
            var text_area = Rect.init(area.x + 1, area.y + 1, area.width - 2, area.height - 2);

            // Account for line numbers
            var line_num_width: u16 = 0;
            if (self.show_line_numbers) {
                line_num_width = self.getLineNumberWidth() + 1;
                text_area.x += line_num_width;
                text_area.width -= line_num_width;
            }

            // Render visible lines
            var y: u16 = 0;
            while (y < text_area.height and self.scroll_offset_line + y < self.lines.items.len) : (y += 1) {
                const line_index = self.scroll_offset_line + y;
                const line = &self.lines.items[line_index];
                const render_y = text_area.y + y;

                // Render line number
                if (self.show_line_numbers) {
                    const line_num_str = std.fmt.allocPrint(self.allocator, "{d}", .{line_index + 1}) catch continue;
                    defer self.allocator.free(line_num_str);

                    const line_num_x = area.x + 1 + line_num_width - line_num_str.len - 1;
                    buffer.writeText(@as(u16, @intCast(line_num_x)), render_y, line_num_str, self.line_number_style);
                }

                // Render line content
                const line_content = line.content.items;
                if (line_content.len > self.scroll_offset_col) {
                    const visible_start = self.scroll_offset_col;
                    const visible_end = @min(visible_start + text_area.width, line_content.len);

                    if (visible_start < visible_end) {
                        const visible_text = line_content[visible_start..visible_end];
                        buffer.writeText(text_area.x, render_y, visible_text, current_style);
                    }
                }

                // Render cursor
                if (self.is_focused and line_index == self.cursor_line and self.cursor_col >= self.scroll_offset_col) {
                    const cursor_x = text_area.x + @as(u16, @intCast(self.cursor_col - self.scroll_offset_col));
                    if (cursor_x < text_area.x + text_area.width) {
                        buffer.setCell(cursor_x, render_y, Cell.init('_', current_style.withBg(style.Color.white)));
                    }
                }
            }

            // Show placeholder if empty
            if (self.lines.items.len == 1 and self.lines.items[0].content.items.len == 0 and self.placeholder.len > 0) {
                const visible_len = @min(self.placeholder.len, text_area.width);
                buffer.writeText(text_area.x, text_area.y, self.placeholder[0..visible_len], self.placeholder_style);
            }
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *TextArea = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key| {
                if (self.is_focused) {
                    switch (key) {
                        .char => |c| {
                            if (c >= 32 and c <= 126) { // Printable ASCII
                                self.insertChar(c) catch {};
                                return true;
                            }
                        },
                        .enter => {
                            self.insertNewline() catch {};
                            return true;
                        },
                        .backspace => {
                            self.deleteChar() catch {};
                            return true;
                        },
                        .up => {
                            self.moveCursorUp();
                            return true;
                        },
                        .down => {
                            self.moveCursorDown();
                            return true;
                        },
                        .left => {
                            self.moveCursorLeft();
                            return true;
                        },
                        .right => {
                            self.moveCursorRight();
                            return true;
                        },
                        .home => {
                            self.moveCursorHome();
                            return true;
                        },
                        .end => {
                            self.moveCursorEnd();
                            return true;
                        },
                        .tab => {
                            self.is_focused = false;
                            return false; // Let focus move to next widget
                        },
                        .ctrl_a => {
                            self.selectAll();
                            return true;
                        },
                        .ctrl_s => {
                            self.notifySubmit();
                            return true;
                        },
                        else => {},
                    }
                }
            },
            .mouse => |mouse| {
                const pos = mouse.position;
                const in_bounds = pos.x >= self.area.x and pos.x < self.area.x + self.area.width and
                    pos.y >= self.area.y and pos.y < self.area.y + self.area.height;

                if (in_bounds and mouse.button == .left and mouse.pressed) {
                    self.is_focused = true;

                    // Calculate cursor position from mouse click
                    if (self.area.width > 2 and self.area.height > 2) {
                        const text_y = pos.y - (self.area.y + 1);
                        const text_x = pos.x - (self.area.x + 1);

                        // Account for line numbers
                        var adjusted_x = text_x;
                        if (self.show_line_numbers) {
                            const line_num_width = self.getLineNumberWidth() + 1;
                            if (adjusted_x >= line_num_width) {
                                adjusted_x -= line_num_width;
                            } else {
                                adjusted_x = 0;
                            }
                        }

                        const new_line = @min(self.scroll_offset_line + text_y, self.lines.items.len - 1);
                        const line_len = self.lines.items[new_line].content.items.len;
                        const new_col = @min(self.scroll_offset_col + adjusted_x, line_len);

                        self.cursor_line = new_line;
                        self.cursor_col = new_col;
                        self.selection_start_line = null;
                        self.selection_start_col = null;
                    }

                    return true;
                } else if (!in_bounds and mouse.button == .left and mouse.pressed) {
                    self.is_focused = false;
                    return false;
                }
            },
            else => {},
        }

        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *TextArea = @fieldParentPtr("widget", widget);
        self.area = area;
        self.updateWrapping() catch {};
        self.updateScrollOffset();
    }

    fn deinit(widget: *Widget) void {
        const self: *TextArea = @fieldParentPtr("widget", widget);

        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.deinit(self.allocator);

        self.allocator.free(self.placeholder);
        self.allocator.destroy(self);
    }
};

test "TextArea widget creation" {
    const allocator = std.testing.allocator;

    const textarea = try TextArea.init(allocator);
    defer textarea.widget.deinit();

    try std.testing.expect(textarea.lines.items.len == 1);
    try std.testing.expect(textarea.cursor_line == 0);
    try std.testing.expect(textarea.cursor_col == 0);
    try std.testing.expect(!textarea.is_focused);
}

test "TextArea widget text manipulation" {
    const allocator = std.testing.allocator;

    const textarea = try TextArea.init(allocator);
    defer textarea.widget.deinit();

    try textarea.setText("Line 1\nLine 2\nLine 3");
    try std.testing.expect(textarea.lines.items.len == 3);

    const text = try textarea.getText();
    defer allocator.free(text);
    try std.testing.expectEqualStrings("Line 1\nLine 2\nLine 3", text);
}
