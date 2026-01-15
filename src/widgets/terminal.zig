//! Terminal widget scaffold for PTY-backed sessions.
//! Provides basic scrollback buffering and placeholder rendering while
//! the full terminal pipeline is under construction.
const std = @import("std");
const ArrayList = std.array_list.Managed;
const style = @import("../style.zig");
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const geometry = @import("../geometry.zig");
const Rect = geometry.Rect;
const Size = geometry.Size;
const Event = @import("../event.zig").Event;
const Key = @import("../event/types.zig").Key;
const parser = @import("../terminal/Parser.zig");
const term_session = @import("../terminal/session/mod.zig");
const async_mod = @import("../async/mod.zig");
const AsyncRuntime = async_mod.runtime.AsyncRuntime;
const clipboard = @import("../clipboard.zig");

const Style = style.Style;
const Color = style.Color;
const TerminalParser = parser.TerminalParser;

/// Error domain for the terminal widget scaffold.
pub const Error = error{
    InvalidScrollbackLimit,
    InvalidRuntime,
    SelectionOutOfRange,
    NoSelection,
    UnsupportedCodepoint,
    ClipboardFailed,
};

/// Configuration for the terminal widget.
pub const Config = struct {
    /// Scrollback capacity (in number of lines) retained in memory.
    scrollback_limit: usize = 10_000,

    /// Style applied to rendered terminal text.
    text_style: Style = Style.default(),

    /// Style used for placeholder/banner content when no data is available.
    placeholder_style: Style = Style.default().withFg(Color.bright_black),

    /// Optional placeholder banner text.
    placeholder_text: ?[]const u8 = null,

    /// Optional async runtime used for PTY-backed sessions.
    runtime: ?*AsyncRuntime = null,

    /// Optional PTY configuration automatically spawned on init when provided.
    session_config: ?term_session.Config = null,

    /// Automatically spawn the configured PTY session during initialization.
    auto_spawn: bool = false,

    pub fn validate(self: Config) !void {
        if (self.scrollback_limit == 0) {
            return Error.InvalidScrollbackLimit;
        }
        if (self.auto_spawn and (self.runtime == null or self.session_config == null)) {
            return Error.InvalidRuntime;
        }
    }
};

const default_placeholder = "Terminal session inactive";
const tab_size: usize = 4;
const ansi_basic_colors = [_]Color{
    Color.black,
    Color.red,
    Color.green,
    Color.yellow,
    Color.blue,
    Color.magenta,
    Color.cyan,
    Color.white,
};

const ansi_bright_colors = [_]Color{
    Color.bright_black,
    Color.bright_red,
    Color.bright_green,
    Color.bright_yellow,
    Color.bright_blue,
    Color.bright_magenta,
    Color.bright_cyan,
    Color.bright_white,
};

pub const Terminal = struct {
    const Self = @This();

    pub const CursorPosition = struct {
        line: usize,
        column: usize,
    };

    pub const Selection = struct {
        start: CursorPosition,
        end: CursorPosition,
    };

    widget: Widget,
    allocator: std.mem.Allocator,
    config: Config,
    runtime: ?*AsyncRuntime = null,
    session: ?*term_session.Session = null,
    session_metrics: ?*term_session.Metrics = null,
    session_config: ?term_session.Config = null,
    parser: TerminalParser,
    scrollback: ArrayList([]Cell),
    line_buffer: ArrayList(Cell),
    current_style: Style,
    cursor_col: usize = 0,
    selection: ?Selection = null,
    repaint_requested: bool = false,
    pending_exit: ?term_session.ExitStatus = null,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
        .getConstraints = getConstraints,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !*Self {
        try config.validate();

        const self = try allocator.create(Self);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .config = config,
            .runtime = config.runtime,
            .session = null,
            .session_metrics = null,
            .session_config = config.session_config,
            .parser = TerminalParser.init(allocator),
            .scrollback = ArrayList([]Cell).init(allocator),
            .line_buffer = ArrayList(Cell).init(allocator),
            .current_style = config.text_style,
            .cursor_col = 0,
            .repaint_requested = true,
            .pending_exit = null,
        };

        if (config.auto_spawn) {
            try self.ensureSession();
        }

        return self;
    }

    pub fn deinit(widget_ptr: *Widget) void {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        self.cleanupSession();
        self.freeScrollback();
        self.line_buffer.deinit();
        self.parser.deinit();
        self.allocator.destroy(self);
    }

    /// Spawn (or replace) the underlying PTY session.
    pub fn spawn(self: *Self, config: term_session.Config) !void {
        self.session_config = config;
        try self.startSession(config);
    }

    /// Detach and destroy the active PTY session.
    pub fn detach(self: *Self) void {
        self.cleanupSession();
    }

    /// Write raw bytes to the active PTY session, spawning it if necessary.
    pub fn write(self: *Self, bytes: []const u8) !usize {
        if (bytes.len == 0) return 0;
        try self.ensureSession();
        const session_ptr = self.session orelse return error.InvalidRuntime;
        return session_ptr.write(bytes);
    }

    /// Append raw bytes into the terminal scrollback (parser integration stub).
    pub fn feed(self: *Self, chunk: []const u8) !void {
        if (chunk.len == 0) return;

        const events = try self.parser.parse(chunk);
        defer self.allocator.free(events);

        for (events) |event| {
            try self.applyEvent(event);
        }

        self.repaint_requested = true;
    }

    /// Retrieve a read-only slice of buffered scrollback lines.
    pub fn getScrollback(self: *const Self) []const []const Cell {
        return self.scrollback.items;
    }

    /// Set the active text selection (inclusive start, exclusive end).
    pub fn setSelection(self: *Self, start: CursorPosition, end: CursorPosition) !void {
        const start_validated = try self.validateCursor(start);
        const end_validated = try self.validateCursor(end);
        const normalized = normalizeSelection(start_validated, end_validated);

        if (cursorEqual(normalized.start, normalized.end)) {
            self.selection = null;
        } else {
            self.selection = normalized;
        }
        self.repaint_requested = true;
    }

    /// Clear any active selection.
    pub fn clearSelection(self: *Self) void {
        if (self.selection != null) {
            self.selection = null;
            self.repaint_requested = true;
        }
    }

    /// Determine whether a selection is active.
    pub fn hasSelection(self: *const Self) bool {
        return self.selection != null;
    }

    /// Return the selected text as UTF-8 (caller owns the returned slice).
    pub fn selectionText(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const selection = self.selection orelse return Error.NoSelection;

        var output = ArrayList(u8).init(allocator);
        errdefer output.deinit();

        var line_index = selection.start.line;
        while (line_index <= selection.end.line) : (line_index += 1) {
            const line = try self.getLineSlice(line_index);
            const start_column = if (line_index == selection.start.line) selection.start.column else 0;
            const end_column = if (line_index == selection.end.line) selection.end.column else line.len;

            const clamped_start = @min(start_column, line.len);
            const clamped_end = @min(end_column, line.len);

            var column = clamped_start;
            while (column < clamped_end) : (column += 1) {
                try appendCellUtf8(&output, line[column]);
            }

            if (line_index != selection.end.line) {
                try output.append('\n');
            }
        }

        return output.toOwnedSlice();
    }

    /// Copy the current selection to the provided clipboard manager.
    pub fn copySelectionToClipboard(self: *Self, manager: *clipboard.ClipboardManager) !void {
        const text = try self.selectionText(self.allocator);
        defer self.allocator.free(text);
        if (!manager.copy(text)) {
            return Error.ClipboardFailed;
        }
    }

    pub fn clearScrollback(self: *Self) void {
        self.freeScrollback();
        self.scrollback = ArrayList([]Cell).init(self.allocator);
        self.clearCurrentLine();
        self.selection = null;
        self.repaint_requested = true;
    }

    /// Process pending session data and report whether a repaint is needed.
    pub fn poll(self: *Self) bool {
        self.pumpSessionEvents();
        return self.repaint_requested;
    }

    fn ensureSession(self: *Self) !void {
        if (self.session != null) return;
        const config = self.session_config orelse return Error.InvalidRuntime;
        try self.startSession(config);
    }

    fn startSession(self: *Self, config: term_session.Config) !void {
        const runtime = self.runtime orelse return Error.InvalidRuntime;
        self.cleanupSession();

        const metrics_ptr = try self.allocator.create(term_session.Metrics);
        metrics_ptr.* = term_session.Metrics{};
        errdefer self.allocator.destroy(metrics_ptr);

        const session_ptr = try term_session.Session.init(self.allocator, runtime, config, metrics_ptr);
        errdefer session_ptr.deinit();

        try session_ptr.start();

        self.session = session_ptr;
        self.session_metrics = metrics_ptr;
        self.session_config = config;
        self.pending_exit = null;
        self.clearCurrentLine();
        self.selection = null;
        self.repaint_requested = true;
    }

    fn pumpSessionEvents(self: *Self) void {
        const session_ptr = self.session orelse return;
        const channel = session_ptr.channel();

        while (true) {
            const maybe_event = channel.tryReceive() catch break;
            const event = maybe_event orelse break;

            switch (event) {
                .data => |payload| {
                    self.feed(payload) catch {};
                    self.repaint_requested = true;
                },
                .exit => |status| {
                    self.pending_exit = status;
                    self.repaint_requested = true;
                },
            }

            session_ptr.recycleEvent(event);
        }
    }

    fn applyAttributes(self: *Self, sequence: parser.ParsedEvent.AttributeSequence) void {
        for (sequence.changes) |change| {
            switch (change) {
                .reset => {
                    self.current_style = self.config.text_style;
                },
                .bold => |enabled| self.current_style.attributes.bold = enabled,
                .dim => |enabled| self.current_style.attributes.dim = enabled,
                .italic => |enabled| self.current_style.attributes.italic = enabled,
                .underline => |enabled| self.current_style.attributes.underline = enabled,
                .blink => |enabled| self.current_style.attributes.blink = enabled,
                .reverse => |enabled| self.current_style.attributes.reverse = enabled,
                .strikethrough => |enabled| self.current_style.attributes.strikethrough = enabled,
                .fg_color => |value| self.current_style.fg = self.mapColor(value),
                .bg_color => |value| self.current_style.bg = self.mapColor(value),
                else => {},
            }
        }
    }

    fn mapColor(self: *Self, value: parser.ColorValue) ?Color {
        _ = self;
        return switch (value) {
            .default => null,
            .color_8 => |idx| blk: {
                const index = @as(usize, @intCast(idx));
                if (index >= ansi_basic_colors.len) break :blk null;
                break :blk ansi_basic_colors[index];
            },
            .color_8_bright => |idx| blk: {
                const index = @as(usize, @intCast(idx));
                if (index >= ansi_bright_colors.len) break :blk null;
                break :blk ansi_bright_colors[index];
            },
            .color_256 => |idx| Color{ .indexed = idx },
            .rgb => |rgb| Color.fromRgb(rgb.r, rgb.g, rgb.b),
        };
    }

    fn eraseLine(self: *Self, mode: u8) void {
        _ = mode;
        self.clearCurrentLine();
        self.repaint_requested = true;
    }

    fn resetState(self: *Self) void {
        self.clearScrollback();
        self.current_style = self.config.text_style;
        self.repaint_requested = true;
    }

    fn validateCursor(self: *const Self, cursor: CursorPosition) !CursorPosition {
        if (cursor.line > self.scrollback.items.len) {
            return Error.SelectionOutOfRange;
        }

        const line_slice = try self.getLineSlice(cursor.line);
        if (cursor.column > line_slice.len) {
            return Error.SelectionOutOfRange;
        }

        return cursor;
    }

    fn getLineSlice(self: *const Self, line_index: usize) ![]const Cell {
        if (line_index < self.scrollback.items.len) {
            return self.scrollback.items[line_index];
        }
        if (line_index == self.scrollback.items.len) {
            return self.line_buffer.items;
        }
        return Error.SelectionOutOfRange;
    }

    fn appendCellUtf8(list: *ArrayList(u8), cell: Cell) !void {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cell.char, &buf) catch return Error.UnsupportedCodepoint;
        try list.appendSlice(buf[0..len]);
    }

    fn cursorLessThan(a: CursorPosition, b: CursorPosition) bool {
        if (a.line < b.line) return true;
        if (a.line > b.line) return false;
        return a.column < b.column;
    }

    fn cursorEqual(a: CursorPosition, b: CursorPosition) bool {
        return a.line == b.line and a.column == b.column;
    }

    fn normalizeSelection(start: CursorPosition, end: CursorPosition) Selection {
        if (cursorLessThan(end, start)) {
            return Selection{ .start = end, .end = start };
        }
        return Selection{ .start = start, .end = end };
    }

    fn isCellSelected(self: *const Self, line_index: usize, column: usize) bool {
        const selection = self.selection orelse return false;
        const pos = CursorPosition{ .line = line_index, .column = column };
        if (cursorLessThan(pos, selection.start)) return false;
        if (!cursorLessThan(pos, selection.end)) return false;
        return true;
    }

    fn render(widget_ptr: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        self.pumpSessionEvents();
        if (area.width == 0 or area.height == 0) return;

        buffer.fill(area, Cell{});

        var y: u16 = 0;
        const max_rows = @as(usize, area.height);
        const available_lines = self.scrollback.items.len;
        const start_index = if (available_lines > max_rows)
            available_lines - max_rows
        else
            0;

        var idx = start_index;
        while (idx < available_lines and y < area.height) : (idx += 1) {
            const line = self.scrollback.items[idx];
            const max_width = @as(usize, area.width);
            var x: usize = 0;
            while (x < line.len and x < max_width) : (x += 1) {
                const cell = line[x];
                if (self.isCellSelected(idx, x)) {
                    var highlighted = cell;
                    highlighted.style.attributes.reverse = true;
                    buffer.setCell(area.x + @as(u16, @intCast(x)), area.y + y, highlighted);
                } else {
                    buffer.setCell(area.x + @as(u16, @intCast(x)), area.y + y, cell);
                }
            }
            y += 1;
        }

        if (y < area.height and self.line_buffer.items.len > 0) {
            const max_width = @as(usize, area.width);
            for (self.line_buffer.items, 0..) |cell, x| {
                if (x >= max_width) break;
                if (self.isCellSelected(available_lines, x)) {
                    var highlighted = cell;
                    highlighted.style.attributes.reverse = true;
                    buffer.setCell(area.x + @as(u16, @intCast(x)), area.y + y, highlighted);
                } else {
                    buffer.setCell(area.x + @as(u16, @intCast(x)), area.y + y, cell);
                }
            }
            y += 1;
        }

        if (start_index == available_lines and self.line_buffer.items.len == 0) {
            const placeholder = self.config.placeholder_text orelse default_placeholder;
            buffer.writeText(area.x, area.y, placeholder, self.config.placeholder_style);
        }

        if (self.pending_exit) |status| {
            if (area.height > 0) {
                var msg_buf: [64]u8 = undefined;
                var msg_slice: []const u8 = "";
                switch (status) {
                    .still_running => msg_slice = "session running",
                    .exited => |code| msg_slice = std.fmt.bufPrint(&msg_buf, "process exited (code {d})", .{code}) catch "process exited",
                    .signal => |sig| msg_slice = std.fmt.bufPrint(&msg_buf, "terminated by signal {d}", .{sig}) catch "terminated",
                }
                buffer.writeText(area.x, area.y + area.height - 1, msg_slice, self.config.placeholder_style);
            }
        }

        self.repaint_requested = false;
    }

    fn handleEvent(widget_ptr: *Widget, event: Event) bool {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        switch (event) {
            .key => |key| {
                return self.handleKeyEvent(key);
            },
            .tick => {
                // Allow host application to use tick events to drive redraws.
                _ = self.poll();
            },
            else => {},
        }
        return false;
    }

    fn handleKeyEvent(self: *Self, key: Key) bool {
        switch (key) {
            .char => |codepoint| {
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(codepoint, &buf) catch return false;
                return self.sendSequence(buf[0..len]);
            },
            .enter => return self.sendSequence("\r"),
            .tab, .ctrl_i => return self.sendSequence("\t"),
            .shift_tab => return self.sendSequence("\x1b[Z"),
            .backspace => return self.sendControl(0x7f),
            .ctrl_h => return self.sendControl(0x08),
            .delete => return self.sendSequence("\x1b[3~"),
            .insert => return self.sendSequence("\x1b[2~"),
            .escape => return self.sendControl(0x1b),
            .up => return self.sendSequence("\x1b[A"),
            .down => return self.sendSequence("\x1b[B"),
            .right => return self.sendSequence("\x1b[C"),
            .left => return self.sendSequence("\x1b[D"),
            .home => return self.sendSequence("\x1b[H"),
            .end => return self.sendSequence("\x1b[F"),
            .page_up => return self.sendSequence("\x1b[5~"),
            .page_down => return self.sendSequence("\x1b[6~"),
            .ctrl_a => return self.sendControl(0x01),
            .ctrl_b => return self.sendControl(0x02),
            .ctrl_c => return self.sendControl(0x03),
            .ctrl_d => return self.sendControl(0x04),
            .ctrl_e => return self.sendControl(0x05),
            .ctrl_f => return self.sendControl(0x06),
            .ctrl_g => return self.sendControl(0x07),
            .ctrl_j => return self.sendControl(0x0a),
            .ctrl_k => return self.sendControl(0x0b),
            .ctrl_l => return self.sendControl(0x0c),
            .ctrl_m => return self.sendControl(0x0d),
            .ctrl_n => return self.sendControl(0x0e),
            .ctrl_o => return self.sendControl(0x0f),
            .ctrl_p => return self.sendControl(0x10),
            .ctrl_q => return self.sendControl(0x11),
            .ctrl_r => return self.sendControl(0x12),
            .ctrl_s => return self.sendControl(0x13),
            .ctrl_t => return self.sendControl(0x14),
            .ctrl_u => return self.sendControl(0x15),
            .ctrl_v => return self.sendControl(0x16),
            .ctrl_w => return self.sendControl(0x17),
            .ctrl_x => return self.sendControl(0x18),
            .ctrl_y => return self.sendControl(0x19),
            .ctrl_z => return self.sendControl(0x1a),
            .f1 => return self.sendSequence("\x1bOP"),
            .f2 => return self.sendSequence("\x1bOQ"),
            .f3 => return self.sendSequence("\x1bOR"),
            .f4 => return self.sendSequence("\x1bOS"),
            .f5 => return self.sendSequence("\x1b[15~"),
            .f6 => return self.sendSequence("\x1b[17~"),
            .f7 => return self.sendSequence("\x1b[18~"),
            .f8 => return self.sendSequence("\x1b[19~"),
            .f9 => return self.sendSequence("\x1b[20~"),
            .f10 => return self.sendSequence("\x1b[21~"),
            .f11 => return self.sendSequence("\x1b[23~"),
            .f12 => return self.sendSequence("\x1b[24~"),
            else => return false,
        }
    }

    fn sendSequence(self: *Self, seq: []const u8) bool {
        if (seq.len == 0) return false;
        if (self.selection != null) {
            self.clearSelection();
        }
        self.write(seq) catch return false;
        return true;
    }

    fn sendControl(self: *Self, code: u8) bool {
        return self.sendSequence(&[_]u8{code});
    }

    fn resize(widget_ptr: *Widget, _area: Rect) void {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        if (self.session) |session_ptr| {
            session_ptr.resize(_area.width, _area.height) catch {};
        }
    }

    fn getConstraints(widget_ptr: *Widget) Widget.SizeConstraints {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        _ = self;
        return Widget.SizeConstraints{ .min_width = 10, .min_height = 4 };
    }

    fn applyEvent(self: *Self, event: anytype) !void {
        switch (event) {
            .char => |payload| {
                const codepoint: u21 = payload.unicode orelse @as(u21, payload.value);
                try self.appendCodepoint(codepoint);
            },
            .linefeed => try self.commitLine(),
            .carriage_return => self.cursor_col = 0,
            .backspace => self.backspace(),
            .delete => self.deleteAtCursor(),
            .tab => try self.appendTab(),
            .attributes => |seq| self.applyAttributes(seq),
            .erase_line => |payload| self.eraseLine(payload.mode),
            .erase_display => self.resetState(),
            .reset_terminal => self.resetState(),
            else => {},
        }
    }

    fn appendCodepoint(self: *Self, codepoint: u21) !void {
        const cell = Cell{ .char = codepoint, .style = self.current_style };
        if (self.cursor_col < self.line_buffer.items.len) {
            self.line_buffer.items[self.cursor_col] = cell;
        } else {
            try self.line_buffer.append(cell);
        }
        self.cursor_col += 1;
    }

    fn appendTab(self: *Self) !void {
        const spaces_needed = tab_size - (self.cursor_col % tab_size);
        var idx: usize = 0;
        while (idx < spaces_needed) : (idx += 1) {
            try self.appendCodepoint(' ');
        }
    }

    fn backspace(self: *Self) void {
        if (self.cursor_col == 0) return;
        self.cursor_col -= 1;
        if (self.cursor_col < self.line_buffer.items.len) {
            _ = self.line_buffer.orderedRemove(self.cursor_col);
        }
    }

    fn deleteAtCursor(self: *Self) void {
        if (self.cursor_col < self.line_buffer.items.len) {
            _ = self.line_buffer.orderedRemove(self.cursor_col);
        }
    }

    fn commitLine(self: *Self) !void {
        const copy = try self.allocator.dupe(Cell, self.line_buffer.items);
        try self.scrollback.append(copy);
        self.trimScrollback();
        self.clearCurrentLine();
    }

    fn clearCurrentLine(self: *Self) void {
        self.line_buffer.clearRetainingCapacity();
        self.cursor_col = 0;
    }

    fn trimScrollback(self: *Self) void {
        while (self.scrollback.items.len > self.config.scrollback_limit) {
            const oldest = self.scrollback.orderedRemove(0);
            self.allocator.free(oldest);
            if (self.selection) |*sel| {
                if (sel.start.line == 0) {
                    self.selection = null;
                } else {
                    sel.start.line -= 1;
                    sel.end.line -= 1;
                }
            }
        }
    }

    fn freeScrollback(self: *Self) void {
        for (self.scrollback.items) |line| {
            self.allocator.free(line);
        }
        self.scrollback.deinit();
    }

    fn cleanupSession(self: *Self) void {
        if (self.session) |session_ptr| {
            session_ptr.deinit();
            self.session = null;
        }

        if (self.session_metrics) |metrics_ptr| {
            self.allocator.destroy(metrics_ptr);
            self.session_metrics = null;
        }

        self.pending_exit = null;
        self.selection = null;
    }
};

const testing = std.testing;

test "Terminal widget buffers plain text" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("hello\nworld\n");

    const scroll = widget.getScrollback();
    try testing.expectEqual(@as(usize, 2), scroll.len);
    var line_buf = ArrayList(u8).init(testing.allocator);
    defer line_buf.deinit();

    line_buf.clearRetainingCapacity();
    for (scroll[0]) |cell| {
        try line_buf.append(@as(u8, @intCast(cell.char)));
        try testing.expect(cell.style.eq(widget.config.text_style));
    }
    try testing.expectEqualStrings("hello", line_buf.items);

    line_buf.clearRetainingCapacity();
    for (scroll[1]) |cell| {
        try line_buf.append(@as(u8, @intCast(cell.char)));
        try testing.expect(cell.style.eq(widget.config.text_style));
    }
    try testing.expectEqualStrings("world", line_buf.items);

    var buffer = try Buffer.init(testing.allocator, Size.init(20, 4));
    defer buffer.deinit();

    widget.widget.render(&buffer, Rect.init(0, 0, 20, 4));
    try testing.expectEqual('h', buffer.getCell(0, 0).?.char);
    try testing.expectEqual('w', buffer.getCell(0, 1).?.char);
}

test "Terminal widget applies SGR foreground color" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("\x1b[31mhi\x1b[0m\n");

    const scroll = widget.getScrollback();
    try testing.expectEqual(@as(usize, 1), scroll.len);
    try testing.expectEqual(@as(usize, 2), scroll[0].len);

    const fg0 = scroll[0][0].style.fg orelse Color.default;
    const fg1 = scroll[0][1].style.fg orelse Color.default;
    try testing.expect(std.meta.eql(fg0, Color.red));
    try testing.expect(std.meta.eql(fg1, Color.red));
}

test "Terminal selection extracts text" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("abcdef\n");
    try widget.setSelection(.{ .line = 0, .column = 2 }, .{ .line = 0, .column = 5 });

    const text = try widget.selectionText(testing.allocator);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("cde", text);

    try widget.clearSelection();
    try testing.expect(!widget.hasSelection());
}
