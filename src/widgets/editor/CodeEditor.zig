const std = @import("std");
const widget_mod = @import("../../widget.zig");
const Widget = widget_mod.Widget;
const SizeConstraints = widget_mod.SizeConstraints;
const Buffer = @import("../../terminal.zig").Buffer;
const Rect = @import("../../geometry.zig").Rect;
const Event = @import("../../event.zig").Event;
const textarea_mod = @import("../textarea.zig");
const style_mod = @import("../../style.zig");

const Color = style_mod.Color;

pub const Config = struct {
    placeholder: ?[]const u8 = null,
    show_line_numbers: bool = true,
    read_only: bool = false,
    word_wrap: bool = false,
};

pub const CodeEditor = struct {
    pub const SearchDirection = textarea_mod.TextArea.SearchDirection;

    pub const DiagnosticSeverity = enum {
        info,
        warning,
        err,
    };

    pub const CursorPosition = struct {
        line: usize,
        column: usize,
    };

    pub const SearchMatch = CursorPosition;

    pub const SelectionRange = struct {
        start: CursorPosition,
        end: CursorPosition,
    };

    pub const Diagnostic = struct {
        line: usize,
        message: []const u8,
        severity: DiagnosticSeverity = .info,
    };

    widget: Widget,
    allocator: std.mem.Allocator,
    textarea: *textarea_mod.TextArea,
    diagnostic_items: std.ArrayList(Diagnostic),
    syntax_name: ?[]const u8 = null,
    show_status_gutter: bool = true,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
        .getConstraints = getConstraints,
        .canFocus = canFocus,
        .focus = focusWidget,
        .blur = blurWidget,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !*CodeEditor {
        const self = try allocator.create(CodeEditor);
        errdefer allocator.destroy(self);

        const textarea = try textarea_mod.TextArea.init(allocator);
        errdefer textarea.widget.deinit();

        try textarea.setShowLineNumbers(config.show_line_numbers);
        try textarea.setWordWrap(config.word_wrap);
        textarea.setReadOnly(config.read_only);
        if (config.placeholder) |placeholder| {
            try textarea.setPlaceholder(placeholder);
        }

        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .textarea = textarea,
            .diagnostic_items = .empty,
            .syntax_name = null,
            .show_status_gutter = true,
        };
        return self;
    }

    pub fn setText(self: *CodeEditor, text: []const u8) !void {
        try self.textarea.setText(text);
    }

    pub fn getText(self: *CodeEditor) ![]const u8 {
        return self.textarea.getText();
    }

    pub fn setReadOnly(self: *CodeEditor, enabled: bool) void {
        self.textarea.setReadOnly(enabled);
    }

    pub fn isReadOnly(self: *const CodeEditor) bool {
        return self.textarea.isReadOnly();
    }

    pub fn setPlaceholder(self: *CodeEditor, placeholder: []const u8) !void {
        try self.textarea.setPlaceholder(placeholder);
    }

    pub fn setShowLineNumbers(self: *CodeEditor, enabled: bool) !void {
        try self.textarea.setShowLineNumbers(enabled);
    }

    pub fn lineCount(self: *const CodeEditor) usize {
        return self.textarea.lineCount();
    }

    pub fn cursorPosition(self: *const CodeEditor) CursorPosition {
        const cursor = self.textarea.cursorPosition();
        return .{
            .line = cursor.line,
            .column = cursor.column,
        };
    }

    pub fn moveCursorTo(self: *CodeEditor, line: usize, column: usize) void {
        self.textarea.moveCursorTo(line, column);
    }

    pub fn gotoLine(self: *CodeEditor, line_1_based: usize) void {
        self.textarea.gotoLine(line_1_based);
    }

    pub fn findText(self: *CodeEditor, needle: []const u8) ?SearchMatch {
        const match = self.textarea.findText(needle) orelse return null;
        return .{
            .line = match.line,
            .column = match.column,
        };
    }

    pub fn findAndMoveCursor(self: *CodeEditor, needle: []const u8) bool {
        const match = self.findText(needle) orelse return false;
        self.moveCursorTo(match.line, match.column);
        return true;
    }

    pub fn findNext(self: *CodeEditor, needle: []const u8) ?SearchMatch {
        const cursor = self.textarea.cursorPosition();
        const match = self.textarea.findTextFrom(needle, .{
            .line = cursor.line,
            .column = cursor.column + 1,
        }, .forward) orelse return null;
        return .{ .line = match.line, .column = match.column };
    }

    pub fn findPrevious(self: *CodeEditor, needle: []const u8) ?SearchMatch {
        const cursor = self.textarea.cursorPosition();
        const start_column = if (cursor.column > 0) cursor.column else 0;
        const match = self.textarea.findTextFrom(needle, .{
            .line = cursor.line,
            .column = start_column,
        }, .backward) orelse return null;
        return .{ .line = match.line, .column = match.column };
    }

    pub fn findAndMove(self: *CodeEditor, needle: []const u8, direction: SearchDirection) bool {
        const match = switch (direction) {
            .forward => self.findNext(needle),
            .backward => self.findPrevious(needle),
        } orelse return false;
        self.moveCursorTo(match.line, match.column);
        return true;
    }

    pub fn hasSelection(self: *const CodeEditor) bool {
        return self.textarea.hasSelection();
    }

    pub fn selectionRange(self: *const CodeEditor) ?SelectionRange {
        const selection = self.textarea.selectionRange() orelse return null;
        return .{
            .start = .{ .line = selection.start.line, .column = selection.start.column },
            .end = .{ .line = selection.end.line, .column = selection.end.column },
        };
    }

    pub fn setSelectionRange(self: *CodeEditor, start: CursorPosition, end: CursorPosition) void {
        self.textarea.setSelectionRange(.{ .line = start.line, .column = start.column }, .{ .line = end.line, .column = end.column });
    }

    pub fn clearSelection(self: *CodeEditor) void {
        self.textarea.clearSelectionRange();
    }

    pub fn statusSummary(self: *const CodeEditor, allocator: std.mem.Allocator) ![]u8 {
        const cursor = self.cursorPosition();
        return std.fmt.allocPrint(allocator, "line {d}, col {d}, lines {d}{s}{s}{s}", .{
            cursor.line + 1,
            cursor.column + 1,
            self.lineCount(),
            if (self.hasSelection()) ", selection" else "",
            if (self.syntax_name != null) ", syntax " else "",
            if (self.syntax_name) |name| name else "",
        });
    }

    pub fn setSyntaxName(self: *CodeEditor, syntax_name: ?[]const u8) !void {
        if (self.syntax_name) |existing| self.allocator.free(existing);
        self.syntax_name = if (syntax_name) |name| try self.allocator.dupe(u8, name) else null;
    }

    pub fn syntaxName(self: *const CodeEditor) ?[]const u8 {
        return self.syntax_name;
    }

    pub fn setShowStatusGutter(self: *CodeEditor, enabled: bool) void {
        self.show_status_gutter = enabled;
    }

    pub fn setDiagnostics(self: *CodeEditor, new_diagnostics: []const Diagnostic) !void {
        for (self.diagnostic_items.items) |diag| self.allocator.free(diag.message);
        self.diagnostic_items.clearAndFree(self.allocator);
        for (new_diagnostics) |diagnostic| {
            try self.diagnostic_items.append(self.allocator, .{
                .line = diagnostic.line,
                .message = try self.allocator.dupe(u8, diagnostic.message),
                .severity = diagnostic.severity,
            });
        }
    }

    pub fn diagnostics(self: *const CodeEditor) []const Diagnostic {
        return self.diagnostic_items.items;
    }

    pub fn diagnosticsOnLine(self: *const CodeEditor, line: usize) usize {
        var count: usize = 0;
        for (self.diagnostic_items.items) |diagnostic| {
            if (diagnostic.line == line) count += 1;
        }
        return count;
    }

    pub fn firstDiagnostic(self: *const CodeEditor) ?Diagnostic {
        if (self.diagnostic_items.items.len == 0) return null;
        return self.diagnostic_items.items[0];
    }

    pub fn diagnosticOnLine(self: *const CodeEditor, line: usize) ?Diagnostic {
        var best: ?Diagnostic = null;
        for (self.diagnostic_items.items) |diagnostic| {
            if (diagnostic.line != line) continue;
            if (best == null or diagnosticRank(diagnostic.severity) > diagnosticRank(best.?.severity)) {
                best = diagnostic;
            }
        }
        return best;
    }

    pub fn focus(self: *CodeEditor) void {
        self.textarea.focus();
    }

    pub fn blur(self: *CodeEditor) void {
        self.textarea.blur();
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *CodeEditor = @fieldParentPtr("widget", widget);
        self.textarea.widget.render(buffer, area);

        self.renderDiagnosticGutter(buffer, area);

        if (!self.show_status_gutter or area.height == 0 or area.width < 2) return;
        if (self.firstDiagnostic()) |diagnostic| {
            const marker_style = diagnosticMarkerStyle(self, diagnostic.severity);
            const marker = switch (diagnostic.severity) {
                .info => "i",
                .warning => "!",
                .err => "x",
            };
            buffer.writeText(area.x + area.width - 1, area.y, marker, marker_style);
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *CodeEditor = @fieldParentPtr("widget", widget);
        return self.textarea.widget.handleEvent(event);
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *CodeEditor = @fieldParentPtr("widget", widget);
        self.textarea.widget.resize(area);
    }

    fn getConstraints(widget: *Widget) SizeConstraints {
        const self: *CodeEditor = @fieldParentPtr("widget", widget);
        return self.textarea.widget.getConstraints();
    }

    fn canFocus(widget: *Widget) bool {
        const self: *CodeEditor = @fieldParentPtr("widget", widget);
        return self.textarea.widget.canFocus();
    }

    fn focusWidget(widget: *Widget) void {
        const self: *CodeEditor = @fieldParentPtr("widget", widget);
        self.focus();
    }

    fn blurWidget(widget: *Widget) void {
        const self: *CodeEditor = @fieldParentPtr("widget", widget);
        self.blur();
    }

    fn deinit(widget: *Widget) void {
        const self: *CodeEditor = @fieldParentPtr("widget", widget);
        for (self.diagnostic_items.items) |diagnostic| self.allocator.free(diagnostic.message);
        self.diagnostic_items.deinit(self.allocator);
        if (self.syntax_name) |name| self.allocator.free(name);
        self.textarea.widget.deinit();
        self.allocator.destroy(self);
    }

    fn renderDiagnosticGutter(self: *CodeEditor, buffer: *Buffer, area: Rect) void {
        if (area.width <= 3 or area.height <= 2 or !self.textarea.show_line_numbers) return;

        const line_count = self.textarea.lines.items.len;
        var line_number_width: u16 = 1;
        var digits = line_count;
        while (digits >= 10) {
            line_number_width += 1;
            digits /= 10;
        }
        const gutter_x = area.x + 1 + line_number_width;
        const visible_lines = @min(@as(usize, area.height - 2), self.textarea.lines.items.len -| self.textarea.scroll_offset_line);

        var row: usize = 0;
        while (row < visible_lines) : (row += 1) {
            const line_index = self.textarea.scroll_offset_line + row;
            if (self.diagnosticOnLine(line_index)) |diagnostic| {
                const marker = diagnosticMarker(diagnostic.severity);
                const marker_style = diagnosticMarkerStyle(self, diagnostic.severity);
                buffer.writeText(gutter_x, area.y + 1 + @as(u16, @intCast(row)), marker, marker_style);
            }
        }
    }

    fn diagnosticMarker(severity: DiagnosticSeverity) []const u8 {
        return switch (severity) {
            .info => "i",
            .warning => "!",
            .err => "x",
        };
    }

    fn diagnosticMarkerStyle(self: *CodeEditor, severity: DiagnosticSeverity) @import("../../style.zig").Style {
        return switch (severity) {
            .info => self.textarea.placeholder_style.withFg(Color.cyan),
            .warning => self.textarea.placeholder_style.withFg(Color.yellow),
            .err => self.textarea.placeholder_style.withFg(Color.red),
        };
    }

    fn diagnosticRank(severity: DiagnosticSeverity) u8 {
        return switch (severity) {
            .info => 0,
            .warning => 1,
            .err => 2,
        };
    }
};

test "CodeEditor initializes with line numbers" {
    const allocator = std.testing.allocator;
    const editor = try CodeEditor.init(allocator, .{});
    defer editor.widget.deinit();

    const text = try editor.getText();
    defer allocator.free(text);
    try std.testing.expectEqualStrings("", text);
}

test "CodeEditor exposes cursor and search helpers" {
    const allocator = std.testing.allocator;
    const editor = try CodeEditor.init(allocator, .{});
    defer editor.widget.deinit();

    try editor.setText("alpha\nbeta needle\ngamma");

    try std.testing.expectEqual(@as(usize, 3), editor.lineCount());

    const match = editor.findText("needle");
    try std.testing.expect(match != null);
    try std.testing.expectEqual(@as(usize, 1), match.?.line);
    try std.testing.expectEqual(@as(usize, 5), match.?.column);

    try std.testing.expect(editor.findAndMoveCursor("needle"));
    const cursor = editor.cursorPosition();
    try std.testing.expectEqual(@as(usize, 1), cursor.line);
    try std.testing.expectEqual(@as(usize, 5), cursor.column);
}

test "CodeEditor goto line and directional search helpers" {
    const allocator = std.testing.allocator;
    const editor = try CodeEditor.init(allocator, .{});
    defer editor.widget.deinit();

    try editor.setText("alpha\nneedle beta\nneedle gamma");
    editor.gotoLine(2);
    var cursor = editor.cursorPosition();
    try std.testing.expectEqual(@as(usize, 1), cursor.line);

    try std.testing.expect(editor.findAndMove("needle", .forward));
    cursor = editor.cursorPosition();
    try std.testing.expectEqual(@as(usize, 2), cursor.line);

    try std.testing.expect(editor.findAndMove("needle", .backward));
    cursor = editor.cursorPosition();
    try std.testing.expectEqual(@as(usize, 1), cursor.line);
}

test "CodeEditor diagnostics and syntax metadata" {
    const allocator = std.testing.allocator;
    const editor = try CodeEditor.init(allocator, .{});
    defer editor.widget.deinit();

    try editor.setSyntaxName("zig");
    try editor.setDiagnostics(&.{
        .{ .line = 0, .message = "Missing docs", .severity = .warning },
        .{ .line = 2, .message = "Unused var", .severity = .err },
    });

    try std.testing.expect(editor.syntaxName() != null);
    try std.testing.expectEqualStrings("zig", editor.syntaxName().?);
    try std.testing.expectEqual(@as(usize, 2), editor.diagnostics().len);
    try std.testing.expectEqual(@as(usize, 1), editor.diagnosticsOnLine(0));
}

test "CodeEditor renders per-line diagnostic gutter markers" {
    const allocator = std.testing.allocator;
    const editor = try CodeEditor.init(allocator, .{});
    defer editor.widget.deinit();

    try editor.setText("one\ntwo\nthree");
    try editor.setDiagnostics(&.{
        .{ .line = 1, .message = "Warn", .severity = .warning },
        .{ .line = 2, .message = "Err", .severity = .err },
    });

    var buffer = try Buffer.init(allocator, .{ .width = 20, .height = 6 });
    defer buffer.deinit();
    editor.widget.render(&buffer, Rect.init(0, 0, 20, 6));

    try std.testing.expectEqual('!', buffer.getCell(3, 2).?.char);
    try std.testing.expectEqual('x', buffer.getCell(3, 3).?.char);
}
