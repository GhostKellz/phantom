//! Terminal widget scaffold for PTY-backed sessions.
//! Uses a unified mutable line model with bounded cursor semantics.
const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.array_list.Managed;
const style = @import("../style.zig");
const Widget = @import("../widget.zig").Widget;
const SizeConstraints = @import("../widget.zig").SizeConstraints;
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
const time_utils = @import("../time/utils.zig");
const Scrollbar = @import("scrollbar.zig").Scrollbar;

const Style = style.Style;
const Color = style.Color;
const TerminalParser = parser.TerminalParser;

pub const Error = error{
    InvalidScrollbackLimit,
    InvalidRuntime,
    SelectionOutOfRange,
    NoSelection,
    UnsupportedCodepoint,
    ClipboardFailed,
};

pub const Config = struct {
    scrollback_limit: usize = 10_000,
    text_style: Style = Style.default(),
    placeholder_style: Style = Style.default().withFg(Color.bright_black),
    placeholder_text: ?[]const u8 = null,
    runtime: ?*AsyncRuntime = null,
    session_config: ?term_session.Config = null,
    auto_spawn: bool = false,
    auto_follow: bool = true,
    enable_bracketed_paste: bool = true,

    pub fn validate(self: Config) !void {
        if (self.scrollback_limit == 0) return Error.InvalidScrollbackLimit;
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

    const ScreenState = struct {
        lines: ArrayList([]Cell),
        cursor_row: usize,
        cursor_col: usize,
        selection: ?Selection,
        saved_cursor: ?CursorPosition,
        scroll_offset: usize,
        scroll_region_top: usize,
        scroll_region_bottom: ?usize,
        cursor_visible: bool,
    };

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
    owns_session: bool = false,
    parser: TerminalParser,
    lines: ArrayList([]Cell),
    current_style: Style,
    cursor_row: usize = 0,
    cursor_col: usize = 0,
    selection: ?Selection = null,
    repaint_requested: bool = false,
    pending_exit: ?term_session.ExitStatus = null,
    saved_cursor: ?CursorPosition = null,
    scroll_offset: usize = 0,
    scroll_region_top: usize = 0,
    scroll_region_bottom: ?usize = null,
    cursor_visible: bool = true,
    is_focused: bool = false,
    alternate_screen: bool = false,
    bracketed_paste_enabled: bool = false,
    mouse_reporting_enabled: bool = false,
    mouse_motion_enabled: bool = false,
    mouse_any_event_enabled: bool = false,
    show_scrollbar: bool = true,
    saved_primary: ?ScreenState = null,

    pub const Status = struct {
        cursor: CursorPosition,
        line_count: usize,
        scroll_offset: usize,
        auto_follow: bool,
        alternate_screen: bool,
        has_selection: bool,
        bracketed_paste_enabled: bool,
        mouse_reporting_enabled: bool,
        has_session: bool,
    };

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
            .owns_session = false,
            .parser = TerminalParser.init(allocator),
            .lines = ArrayList([]Cell).init(allocator),
            .current_style = config.text_style,
            .cursor_row = 0,
            .cursor_col = 0,
            .selection = null,
            .repaint_requested = true,
            .pending_exit = null,
            .saved_cursor = null,
            .scroll_offset = 0,
            .scroll_region_top = 0,
            .scroll_region_bottom = null,
            .cursor_visible = true,
            .is_focused = false,
            .alternate_screen = false,
            .bracketed_paste_enabled = false,
            .mouse_reporting_enabled = false,
            .mouse_motion_enabled = false,
            .mouse_any_event_enabled = false,
            .show_scrollbar = true,
            .saved_primary = null,
        };
        try self.appendEmptyLine();

        if (config.auto_spawn) {
            try self.ensureSession();
        }

        return self;
    }

    pub fn deinit(widget_ptr: *Widget) void {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        self.cleanupSession();
        self.freeLines();
        if (self.saved_primary) |*saved| {
            self.freeScreenLines(&saved.lines);
            self.saved_primary = null;
        }
        self.parser.deinit();
        self.allocator.destroy(self);
    }

    pub fn hasPendingExit(self: *const Self) bool {
        return self.pending_exit != null;
    }

    pub fn focus(self: *Self) void {
        self.is_focused = true;
        self.repaint_requested = true;
    }

    pub fn blur(self: *Self) void {
        self.is_focused = false;
        self.repaint_requested = true;
    }

    pub fn isAutoFollow(self: *const Self) bool {
        return self.config.auto_follow;
    }

    pub fn status(self: *const Self) Status {
        return .{
            .cursor = .{ .line = self.cursor_row, .column = self.cursor_col },
            .line_count = self.visibleLineCount(),
            .scroll_offset = self.scroll_offset,
            .auto_follow = self.config.auto_follow,
            .alternate_screen = self.alternate_screen,
            .has_selection = self.selection != null,
            .bracketed_paste_enabled = self.bracketed_paste_enabled,
            .mouse_reporting_enabled = self.mouse_reporting_enabled,
            .has_session = self.session != null,
        };
    }

    pub fn scrollbarState(self: *const Self, viewport_length: usize) @import("scrollbar.zig").ScrollbarState {
        var scrollbar_state = @import("scrollbar.zig").ScrollbarState.init(self.totalLineCount());
        _ = scrollbar_state.setPosition(self.scroll_offset);
        _ = scrollbar_state.setViewportLength(viewport_length);
        _ = scrollbar_state.setContentLength(self.totalLineCount());
        return scrollbar_state;
    }

    pub fn setShowScrollbar(self: *Self, enabled: bool) void {
        self.show_scrollbar = enabled;
        self.repaint_requested = true;
    }

    pub fn paste(self: *Self, text: []const u8) bool {
        if (text.len == 0) return false;
        if (self.config.enable_bracketed_paste and self.bracketedPasteEnabled()) {
            var framed = ArrayList(u8).init(self.allocator);
            defer framed.deinit();
            framed.appendSlice("\x1b[200~") catch return false;
            framed.appendSlice(text) catch return false;
            framed.appendSlice("\x1b[201~") catch return false;
            return self.sendSequence(framed.items);
        }
        return self.sendSequence(text);
    }

    pub fn selectAll(self: *Self) !void {
        const visible_count = self.visibleLineCount();
        if (visible_count == 0) return;
        const last_line = visible_count - 1;
        const last_len = self.lines.items[last_line].len;
        try self.setSelection(.{ .line = 0, .column = 0 }, .{ .line = last_line, .column = last_len });
    }

    pub fn bracketedPasteEnabled(self: *const Self) bool {
        return self.bracketed_paste_enabled;
    }

    pub fn mouseReportingEnabled(self: *const Self) bool {
        return self.mouse_reporting_enabled;
    }

    pub fn mouseMotionEnabled(self: *const Self) bool {
        return self.mouse_motion_enabled;
    }

    pub fn mouseAnyEventEnabled(self: *const Self) bool {
        return self.mouse_any_event_enabled;
    }

    pub fn scrollOffset(self: *const Self) usize {
        return self.scroll_offset;
    }

    pub fn spawn(self: *Self, config: term_session.Config) !void {
        self.session_config = config;
        try self.startSession(config);
    }

    pub fn attachSession(self: *Self, session: *term_session.Session, metrics: ?*term_session.Metrics) void {
        self.cleanupSession();
        self.session = session;
        self.session_metrics = metrics;
        self.owns_session = false;
        self.pending_exit = null;
        self.saved_cursor = null;
        self.scroll_offset = 0;
        self.scroll_region_top = 0;
        self.scroll_region_bottom = null;
        self.cursor_visible = true;
        self.mouse_motion_enabled = false;
        self.mouse_any_event_enabled = false;
        self.restorePrimaryScreenIfNeeded();
        self.resetLines();
        self.selection = null;
        self.repaint_requested = true;
    }

    pub fn detach(self: *Self) void {
        self.cleanupSession();
    }

    pub fn write(self: *Self, bytes: []const u8) !usize {
        if (bytes.len == 0) return 0;
        try self.ensureSession();
        const session_ptr = self.session orelse return error.InvalidRuntime;
        return session_ptr.write(bytes);
    }

    pub fn feed(self: *Self, chunk: []const u8) !void {
        if (chunk.len == 0) return;

        const events = try self.parser.parse(chunk);
        defer self.allocator.free(events);

        for (events) |event| {
            try self.applyEvent(event);
        }

        self.repaint_requested = true;
    }

    pub fn getScrollback(self: *const Self) []const []const Cell {
        return self.lines.items[0..self.visibleLineCount()];
    }

    pub fn setSelection(self: *Self, start: CursorPosition, end: CursorPosition) !void {
        const start_validated = try self.validateCursor(start);
        const end_validated = try self.validateCursor(end);
        const normalized = normalizeSelection(start_validated, end_validated);
        self.selection = if (cursorEqual(normalized.start, normalized.end)) null else normalized;
        self.repaint_requested = true;
    }

    pub fn clearSelection(self: *Self) void {
        if (self.selection != null) {
            self.selection = null;
            self.repaint_requested = true;
        }
    }

    pub fn hasSelection(self: *const Self) bool {
        return self.selection != null;
    }

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

            if (line_index != selection.end.line) try output.append('\n');
        }

        return output.toOwnedSlice();
    }

    pub fn allText(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        var output = ArrayList(u8).init(allocator);
        errdefer output.deinit();

        const visible_count = self.visibleLineCount();
        var line_index: usize = 0;
        while (line_index < visible_count) : (line_index += 1) {
            const line = self.lines.items[line_index];
            for (line) |cell| try appendCellUtf8(&output, cell);
            if (line_index + 1 < visible_count) try output.append('\n');
        }

        return output.toOwnedSlice();
    }

    pub fn copySelectionToClipboard(self: *Self, manager: *clipboard.ClipboardManager) !void {
        const text = try self.selectionText(self.allocator);
        defer self.allocator.free(text);
        if (!manager.copy(text)) return Error.ClipboardFailed;
    }

    pub fn clearScrollback(self: *Self) void {
        self.restorePrimaryScreenIfNeeded();
        self.resetLines();
        self.saved_cursor = null;
        self.scroll_offset = 0;
        self.scroll_region_top = 0;
        self.scroll_region_bottom = null;
        self.cursor_visible = true;
        self.selection = null;
        self.repaint_requested = true;
    }

    pub fn setAutoFollow(self: *Self, enabled: bool) void {
        self.config.auto_follow = enabled;
        if (enabled) self.scroll_offset = 0;
        self.repaint_requested = true;
    }

    pub fn scrollLines(self: *Self, delta: isize) void {
        const total_lines = self.totalLineCount();
        const max_offset = if (total_lines > 0) total_lines - 1 else 0;

        if (delta < 0) {
            const amount: usize = @intCast(-delta);
            self.scroll_offset = self.scroll_offset -| amount;
        } else if (delta > 0) {
            const amount: usize = @intCast(delta);
            self.scroll_offset = @min(self.scroll_offset + amount, max_offset);
        }

        self.config.auto_follow = self.scroll_offset == 0;
        self.repaint_requested = true;
    }

    pub fn scrollToBottom(self: *Self) void {
        self.scroll_offset = 0;
        self.config.auto_follow = true;
        self.repaint_requested = true;
    }

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
        self.owns_session = true;
        self.pending_exit = null;
        self.saved_cursor = null;
        self.scroll_offset = 0;
        self.scroll_region_top = 0;
        self.scroll_region_bottom = null;
        self.cursor_visible = true;
        self.mouse_motion_enabled = false;
        self.mouse_any_event_enabled = false;
        self.restorePrimaryScreenIfNeeded();
        self.resetLines();
        self.selection = null;
        self.repaint_requested = true;
    }

    fn pumpSessionEvents(self: *Self) void {
        const session_ptr = self.session orelse return;
        const channel = session_ptr.channel();
        var saw_data = false;

        while (true) {
            const maybe_event = channel.tryReceive() catch break;
            const event = maybe_event orelse break;

            switch (event) {
                .data => |payload| {
                    self.feed(payload) catch {};
                    saw_data = true;
                    self.repaint_requested = true;
                },
                .exit => |exit_status| {
                    self.pending_exit = exit_status;
                    self.repaint_requested = true;
                },
            }

            session_ptr.recycleEvent(event);
        }

        if (saw_data and self.config.auto_follow) self.scroll_offset = 0;
    }

    fn render(widget_ptr: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        self.pumpSessionEvents();
        if (area.width == 0 or area.height == 0) return;

        const has_scrollbar = self.show_scrollbar and self.totalLineCount() > area.height and area.width > 1;
        const render_area = if (has_scrollbar)
            Rect.init(area.x, area.y, area.width - 1, area.height)
        else
            area;

        buffer.fill(area, Cell{});

        const total_lines = self.totalLineCount();
        const visible_lines = @min(total_lines, @as(usize, render_area.height));
        const max_start = total_lines -| visible_lines;
        const start_index = max_start -| self.scroll_offset;
        const end_index = @min(start_index + visible_lines, total_lines);

        var y: u16 = 0;
        var idx = start_index;
        while (idx < end_index and y < render_area.height) : (idx += 1) {
            const line = self.lines.items[idx];
            var x: usize = 0;
            while (x < line.len and x < render_area.width) : (x += 1) {
                var cell = line[x];
                if (self.isCellSelected(idx, x)) cell.style.attributes.reverse = true;
                buffer.setCell(render_area.x + @as(u16, @intCast(x)), render_area.y + y, cell);
            }
            y += 1;
        }

        if (total_lines == 0) {
            const placeholder = self.config.placeholder_text orelse default_placeholder;
            buffer.writeText(render_area.x, render_area.y, placeholder, self.config.placeholder_style);
        }

        if (self.pending_exit) |exit_status| {
            var msg_buf: [64]u8 = undefined;
            const msg = switch (exit_status) {
                .still_running => "session running",
                .exited => |code| std.fmt.bufPrint(&msg_buf, "process exited (code {d})", .{code}) catch "process exited",
                .signal => |sig| std.fmt.bufPrint(&msg_buf, "terminated by signal {d}", .{sig}) catch "terminated",
            };
            buffer.writeText(render_area.x, render_area.y + render_area.height - 1, msg, self.config.placeholder_style);
        }

        if (render_area.height > 0 and (!self.config.auto_follow or self.scroll_offset > 0 or self.alternate_screen)) {
            var hint_buf: [96]u8 = undefined;
            const hint = std.fmt.bufPrint(
                &hint_buf,
                "[{s} scroll {d}{s}]",
                .{
                    if (self.config.auto_follow) "follow" else "manual",
                    self.scroll_offset,
                    if (self.alternate_screen) " alt" else "",
                },
            ) catch "[manual]";
            buffer.writeText(render_area.x, render_area.y, hint, self.config.placeholder_style);
        }

        if (self.is_focused and self.cursor_visible and self.cursor_row >= start_index and self.cursor_row < end_index and render_area.width > 0) {
            const cursor_y = render_area.y + @as(u16, @intCast(self.cursor_row - start_index));
            const cursor_x = render_area.x + @as(u16, @intCast(@min(self.cursor_col, @as(usize, render_area.width - 1))));
            if (buffer.getCell(cursor_x, cursor_y)) |existing| {
                var cursor_cell = existing.*;
                cursor_cell.style.attributes.reverse = true;
                buffer.setCell(cursor_x, cursor_y, cursor_cell);
            } else {
                var cursor_cell = Cell{ .style = self.config.text_style };
                cursor_cell.style.attributes.reverse = true;
                buffer.setCell(cursor_x, cursor_y, cursor_cell);
            }
        }

        if (has_scrollbar) {
            const scrollbar = Scrollbar.init(.vertical_right);
            var scrollbar_state = self.scrollbarState(render_area.height);
            scrollbar.render(buffer, area, &scrollbar_state);
        }

        self.repaint_requested = false;
    }

    fn handleEvent(widget_ptr: *Widget, event: Event) bool {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        switch (event) {
            .key => |key| return self.handleKeyEvent(key),
            .mouse => |mouse| return self.handleMouseEvent(mouse),
            .tick => _ = self.poll(),
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
        }
    }

    fn sendSequence(self: *Self, seq: []const u8) bool {
        if (seq.len == 0) return false;
        if (self.selection != null) self.clearSelection();
        _ = self.write(seq) catch return false;
        return true;
    }

    fn sendControl(self: *Self, code: u8) bool {
        return self.sendSequence(&[_]u8{code});
    }

    fn handleMouseEvent(self: *Self, mouse: @import("../event.zig").MouseEvent) bool {
        if (!self.mouse_reporting_enabled or !self.is_focused) return false;

        var seq_buf: [32]u8 = undefined;
        var button_code: u8 = switch (mouse.button) {
            .left => if (mouse.pressed) 0 else 3,
            .middle => if (mouse.pressed) 1 else 3,
            .right => if (mouse.pressed) 2 else 3,
            .wheel_up => 64,
            .wheel_down => 65,
        };
        button_code += modifierBits(mouse.modifiers);
        if (self.mouseMotionEnabledForEvent(mouse)) button_code += 32;
        const x = @min(mouse.position.x, 222) + 1;
        const y = @min(mouse.position.y, 222) + 1;
        const suffix = if (mouse.pressed or mouse.button == .wheel_up or mouse.button == .wheel_down or self.mouseMotionEnabledForEvent(mouse)) "M" else "m";
        const seq = std.fmt.bufPrint(&seq_buf, "\x1b[<{};{};{}{s}", .{ button_code, x, y, suffix }) catch return false;
        return self.sendSequence(seq);
    }

    fn resize(widget_ptr: *Widget, area: Rect) void {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        if (self.session) |session_ptr| {
            session_ptr.resize(area.width, area.height) catch {};
        }
    }

    fn getConstraints(widget_ptr: *Widget) SizeConstraints {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        _ = self;
        return SizeConstraints{ .min_width = 10, .min_height = 4 };
    }

    fn canFocus(widget_ptr: *Widget) bool {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        return self.session != null or self.config.auto_spawn or self.session_config != null;
    }

    fn focusWidget(widget_ptr: *Widget) void {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        self.focus();
    }

    fn blurWidget(widget_ptr: *Widget) void {
        const self: *Self = @fieldParentPtr("widget", widget_ptr);
        self.blur();
    }

    fn applyEvent(self: *Self, event: anytype) !void {
        switch (event) {
            .char => |payload| {
                const codepoint: u21 = payload.unicode orelse @as(u21, payload.value);
                try self.appendCodepoint(codepoint);
            },
            .linefeed => try self.advanceLine(),
            .carriage_return => self.cursor_col = 0,
            .backspace => self.backspace(),
            .delete => self.deleteAtCursor(),
            .tab => try self.appendTab(),
            .cursor_up => |payload| self.moveCursorUp(parserCount(payload.count)),
            .cursor_down => |payload| try self.moveCursorDown(parserCount(payload.count)),
            .cursor_left => |payload| self.moveCursorLeft(parserCount(payload.count)),
            .cursor_right => |payload| self.moveCursorRight(parserCount(payload.count)),
            .cursor_next_line => |payload| try self.moveCursorNextLine(parserCount(payload.count)),
            .cursor_prev_line => |payload| self.moveCursorPrevLine(parserCount(payload.count)),
            .cursor_column => |payload| self.setCursorColumn(parserCount(payload.column)),
            .cursor_line => |payload| try self.moveCursorToLine(parserCount(payload.line)),
            .cursor_position => |payload| {
                try self.moveCursorToLine(parserCount(payload.row));
                self.setCursorColumn(parserCount(payload.col));
            },
            .save_cursor => self.saved_cursor = .{ .line = self.cursor_row, .column = self.cursor_col },
            .restore_cursor => if (self.saved_cursor) |saved| {
                try self.ensureLineExists(saved.line);
                self.cursor_row = saved.line;
                self.cursor_col = @min(saved.column, self.lines.items[self.cursor_row].len);
            },
            .insert_lines => |payload| try self.insertLines(parserCount(payload.count)),
            .delete_lines => |payload| self.deleteLines(parserCount(payload.count)),
            .delete_chars => |payload| try self.deleteChars(parserCount(payload.count)),
            .erase_chars => |payload| try self.eraseChars(parserCount(payload.count)),
            .scroll_up => |payload| self.scrollBufferUp(parserCount(payload.count)),
            .scroll_down => |payload| try self.scrollBufferDown(parserCount(payload.count)),
            .scroll_region => |payload| self.setScrollRegion(parserCount(payload.top), parserCount(payload.bottom)),
            .mode_setting => |payload| try self.applyModeSetting(payload),
            .attributes => |seq| self.applyAttributes(seq),
            .erase_line => |payload| try self.eraseLine(payload.mode),
            .erase_display => self.resetState(),
            .reset_terminal => self.resetState(),
            else => {},
        }
    }

    fn applyAttributes(self: *Self, sequence: parser.ParsedEvent.AttributeSequence) void {
        for (sequence.changes) |change| {
            switch (change) {
                .reset => self.current_style = self.config.text_style,
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

    fn applyModeSetting(self: *Self, mode: parser.ParsedEvent.ModeSetting) !void {
        if (!mode.private) return;

        switch (mode.mode) {
            25 => self.cursor_visible = mode.enable,
            1000, 1006 => self.mouse_reporting_enabled = mode.enable,
            1002 => {
                self.mouse_reporting_enabled = mode.enable;
                self.mouse_motion_enabled = mode.enable;
                if (!mode.enable) self.mouse_any_event_enabled = false;
            },
            1003 => {
                self.mouse_reporting_enabled = mode.enable;
                self.mouse_motion_enabled = mode.enable;
                self.mouse_any_event_enabled = mode.enable;
            },
            2004 => self.bracketed_paste_enabled = mode.enable,
            47, 1047, 1049 => {
                if (mode.enable) {
                    try self.enterAlternateScreen();
                } else {
                    self.exitAlternateScreen();
                }
            },
            else => {},
        }
    }

    fn setScrollRegion(self: *Self, top_1_based: usize, bottom_1_based: usize) void {
        if (top_1_based == 0 or bottom_1_based == 0 or bottom_1_based < top_1_based) {
            self.scroll_region_top = 0;
            self.scroll_region_bottom = null;
            return;
        }

        self.scroll_region_top = top_1_based - 1;
        self.scroll_region_bottom = bottom_1_based - 1;
        self.cursor_row = @min(@max(self.cursor_row, self.scroll_region_top), self.regionBottomIndex());
        self.cursor_col = @min(self.cursor_col, self.currentLineLen());
    }

    fn moveCursorUp(self: *Self, count: usize) void {
        const top = self.regionTopIndex();
        self.cursor_row = if (self.cursor_row > top) @max(top, self.cursor_row -| count) else self.cursor_row;
        self.cursor_col = @min(self.cursor_col, self.currentLineLen());
    }

    fn moveCursorDown(self: *Self, count: usize) !void {
        const target = self.cursor_row + count;
        try self.ensureLineExists(target);
        self.cursor_row = @min(target, self.regionBottomIndex());
        self.cursor_col = @min(self.cursor_col, self.currentLineLen());
    }

    fn moveCursorLeft(self: *Self, count: usize) void {
        self.cursor_col -|= count;
    }

    fn moveCursorRight(self: *Self, count: usize) void {
        self.cursor_col = @min(self.cursor_col + count, self.currentLineLen());
    }

    fn moveCursorNextLine(self: *Self, count: usize) !void {
        try self.moveCursorDown(count);
        self.cursor_col = 0;
    }

    fn moveCursorPrevLine(self: *Self, count: usize) void {
        self.moveCursorUp(count);
        self.cursor_col = 0;
    }

    fn setCursorColumn(self: *Self, column_1_based: usize) void {
        const target = if (column_1_based == 0) 0 else column_1_based - 1;
        self.cursor_col = @min(target, self.currentLineLen());
    }

    fn moveCursorToLine(self: *Self, line_1_based: usize) !void {
        const target = line_1_based -| 1;
        try self.ensureLineExists(target);
        self.cursor_row = @min(@max(target, self.regionTopIndex()), self.regionBottomIndex());
        self.cursor_col = @min(self.cursor_col, self.currentLineLen());
    }

    fn insertLines(self: *Self, count: usize) !void {
        self.clearSelection();
        const insert_index = @min(@max(self.cursor_row, self.regionTopIndex()), self.regionBottomIndex());
        const region_bottom = self.regionBottomIndex();
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            const empty = try self.allocator.alloc(Cell, 0);
            try self.lines.insert(insert_index, empty);
            if (self.lines.items.len - 1 > region_bottom) {
                const removed = self.lines.orderedRemove(region_bottom + 1);
                self.allocator.free(removed);
            }
        }
        self.trimToLimit();
    }

    fn deleteLines(self: *Self, count: usize) void {
        self.clearSelection();
        const delete_index = @min(@max(self.cursor_row, self.regionTopIndex()), self.regionBottomIndex());
        const region_bottom = self.regionBottomIndex();
        var remaining = count;
        while (remaining > 0 and self.lines.items.len > 0) : (remaining -= 1) {
            const index = @min(delete_index, self.lines.items.len - 1);
            const removed = self.lines.orderedRemove(index);
            self.allocator.free(removed);

            const empty = self.allocator.alloc(Cell, 0) catch break;
            const append_index = @min(region_bottom, self.lines.items.len);
            self.lines.insert(append_index, empty) catch {
                self.allocator.free(empty);
                break;
            };

            if (self.lines.items.len == 0) {
                self.appendEmptyLine() catch {};
            }
        }
        if (self.cursor_row >= self.lines.items.len) self.cursor_row = self.lines.items.len - 1;
        self.cursor_col = @min(self.cursor_col, self.currentLineLen());
    }

    fn deleteChars(self: *Self, count: usize) !void {
        var remaining = count;
        while (remaining > 0 and self.cursor_col < self.currentLineLen()) : (remaining -= 1) {
            try self.removeCharAt(self.cursor_row, self.cursor_col);
        }
    }

    fn eraseChars(self: *Self, count: usize) !void {
        var line = try self.mutableLine(self.cursor_row);
        const end = @min(self.cursor_col + count, line.len);
        var idx = self.cursor_col;
        while (idx < end) : (idx += 1) {
            line[idx] = Cell{ .char = ' ', .style = self.current_style };
        }
    }

    fn scrollBufferUp(self: *Self, count: usize) void {
        self.clearSelection();
        self.deleteLinesWithinRegion(count);
    }

    fn scrollBufferDown(self: *Self, count: usize) !void {
        self.clearSelection();
        try self.insertLinesWithinRegion(count);
    }

    fn appendCodepoint(self: *Self, codepoint: u21) !void {
        var line = try self.mutableLine(self.cursor_row);
        const cell = Cell{ .char = codepoint, .style = self.current_style };

        if (self.cursor_col < line.len) {
            line[self.cursor_col] = cell;
            self.cursor_col += 1;
            return;
        }

        if (self.cursor_col > line.len) {
            try self.resizeLine(self.cursor_row, self.cursor_col);
            line = try self.mutableLine(self.cursor_row);
            var idx = line.len;
            while (idx < self.cursor_col) : (idx += 1) {
                line[idx] = Cell{ .char = ' ', .style = self.config.text_style };
            }
        }

        try self.resizeLine(self.cursor_row, self.cursor_col + 1);
        line = try self.mutableLine(self.cursor_row);
        line[self.cursor_col] = cell;
        self.cursor_col += 1;
    }

    fn appendTab(self: *Self) !void {
        const spaces_needed = tab_size - (self.cursor_col % tab_size);
        var idx: usize = 0;
        while (idx < spaces_needed) : (idx += 1) try self.appendCodepoint(' ');
    }

    fn backspace(self: *Self) void {
        if (self.cursor_col == 0) return;
        self.cursor_col -= 1;
        self.removeCharAt(self.cursor_row, self.cursor_col) catch {};
    }

    fn deleteAtCursor(self: *Self) void {
        self.removeCharAt(self.cursor_row, self.cursor_col) catch {};
    }

    fn advanceLine(self: *Self) !void {
        const next_row = self.cursor_row + 1;
        try self.ensureLineExists(next_row);
        self.cursor_row = next_row;
        self.cursor_col = 0;
        self.trimToLimit();
    }

    fn eraseLine(self: *Self, mode: u8) !void {
        const line_len = self.currentLineLen();
        switch (mode) {
            0 => try self.truncateLine(self.cursor_row, @min(self.cursor_col, line_len)),
            1 => {
                try self.removePrefix(self.cursor_row, @min(self.cursor_col, line_len));
                self.cursor_col = 0;
            },
            else => try self.clearLine(self.cursor_row),
        }
        self.repaint_requested = true;
    }

    fn resetState(self: *Self) void {
        self.clearScrollback();
        self.current_style = self.config.text_style;
        self.repaint_requested = true;
    }

    fn validateCursor(self: *const Self, cursor: CursorPosition) !CursorPosition {
        if (cursor.line >= self.visibleLineCount()) return Error.SelectionOutOfRange;
        const line_slice = try self.getLineSlice(cursor.line);
        if (cursor.column > line_slice.len) return Error.SelectionOutOfRange;
        return cursor;
    }

    fn getLineSlice(self: *const Self, line_index: usize) ![]const Cell {
        if (line_index >= self.visibleLineCount()) return Error.SelectionOutOfRange;
        return self.lines.items[line_index];
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
        return if (cursorLessThan(end, start)) .{ .start = end, .end = start } else .{ .start = start, .end = end };
    }

    fn isCellSelected(self: *const Self, line_index: usize, column: usize) bool {
        const selection = self.selection orelse return false;
        const pos = CursorPosition{ .line = line_index, .column = column };
        if (cursorLessThan(pos, selection.start)) return false;
        if (!cursorLessThan(pos, selection.end)) return false;
        return true;
    }

    fn parserCount(value: anytype) usize {
        return if (value <= 0) 0 else @intCast(value);
    }

    fn visibleLineCount(self: *const Self) usize {
        if (self.lines.items.len == 0) return 0;
        const last = self.lines.items[self.lines.items.len - 1];
        if (last.len == 0) return self.lines.items.len - 1;
        return self.lines.items.len;
    }

    fn totalLineCount(self: *const Self) usize {
        return self.visibleLineCount();
    }

    fn currentLineLen(self: *const Self) usize {
        return self.lines.items[self.cursor_row].len;
    }

    fn regionTopIndex(self: *const Self) usize {
        return @min(self.scroll_region_top, self.lines.items.len -| 1);
    }

    fn regionBottomIndex(self: *const Self) usize {
        if (self.scroll_region_bottom) |bottom| {
            return @min(bottom, self.lines.items.len -| 1);
        }
        return self.lines.items.len -| 1;
    }

    fn ensureLineExists(self: *Self, row: usize) !void {
        while (self.lines.items.len <= row) {
            try self.appendEmptyLine();
        }
    }

    fn appendEmptyLine(self: *Self) !void {
        const empty = try self.allocator.alloc(Cell, 0);
        try self.lines.append(empty);
    }

    fn freeLines(self: *Self) void {
        for (self.lines.items) |line| self.allocator.free(line);
        self.lines.deinit();
    }

    fn freeScreenLines(self: *Self, lines: *ArrayList([]Cell)) void {
        for (lines.items) |line| self.allocator.free(line);
        lines.deinit();
    }

    fn resetLines(self: *Self) void {
        self.freeLines();
        self.lines = ArrayList([]Cell).init(self.allocator);
        self.appendEmptyLine() catch unreachable;
        self.cursor_row = 0;
        self.cursor_col = 0;
    }

    fn cloneLines(self: *Self) !ArrayList([]Cell) {
        var cloned = ArrayList([]Cell).init(self.allocator);
        errdefer self.freeScreenLines(&cloned);

        for (self.lines.items) |line| {
            const duped = try self.allocator.dupe(Cell, line);
            try cloned.append(duped);
        }
        return cloned;
    }

    fn enterAlternateScreen(self: *Self) !void {
        if (self.alternate_screen) return;

        self.saved_primary = .{
            .lines = try self.cloneLines(),
            .cursor_row = self.cursor_row,
            .cursor_col = self.cursor_col,
            .selection = self.selection,
            .saved_cursor = self.saved_cursor,
            .scroll_offset = self.scroll_offset,
            .scroll_region_top = self.scroll_region_top,
            .scroll_region_bottom = self.scroll_region_bottom,
            .cursor_visible = self.cursor_visible,
        };
        self.alternate_screen = true;
        self.resetLines();
        self.selection = null;
        self.saved_cursor = null;
        self.scroll_offset = 0;
        self.scroll_region_top = 0;
        self.scroll_region_bottom = null;
    }

    fn exitAlternateScreen(self: *Self) void {
        self.restorePrimaryScreenIfNeeded();
    }

    fn restorePrimaryScreenIfNeeded(self: *Self) void {
        if (!self.alternate_screen) return;
        if (self.saved_primary) |saved| {
            self.freeLines();
            self.lines = saved.lines;
            self.cursor_row = saved.cursor_row;
            self.cursor_col = saved.cursor_col;
            self.selection = saved.selection;
            self.saved_cursor = saved.saved_cursor;
            self.scroll_offset = saved.scroll_offset;
            self.scroll_region_top = saved.scroll_region_top;
            self.scroll_region_bottom = saved.scroll_region_bottom;
            self.cursor_visible = saved.cursor_visible;
            self.saved_primary = null;
        }
        self.alternate_screen = false;
    }

    fn mutableLine(self: *Self, row: usize) ![]Cell {
        try self.ensureLineExists(row);
        return self.lines.items[row];
    }

    fn resizeLine(self: *Self, row: usize, new_len: usize) !void {
        const old = try self.mutableLine(row);
        const resized = try self.allocator.alloc(Cell, new_len);
        const copy_len = @min(old.len, resized.len);
        if (copy_len > 0) @memcpy(resized[0..copy_len], old[0..copy_len]);
        if (new_len > copy_len) {
            var idx = copy_len;
            while (idx < new_len) : (idx += 1) resized[idx] = Cell{};
        }
        self.allocator.free(old);
        self.lines.items[row] = resized;
    }

    fn clearLine(self: *Self, row: usize) !void {
        try self.resizeLine(row, 0);
    }

    fn truncateLine(self: *Self, row: usize, new_len: usize) !void {
        try self.resizeLine(row, new_len);
    }

    fn removePrefix(self: *Self, row: usize, count: usize) !void {
        const old = try self.mutableLine(row);
        const clamped = @min(count, old.len);
        const new_len = old.len - clamped;
        const replaced = try self.allocator.alloc(Cell, new_len);
        if (new_len > 0) @memcpy(replaced[0..new_len], old[clamped..]);
        self.allocator.free(old);
        self.lines.items[row] = replaced;
    }

    fn removeCharAt(self: *Self, row: usize, index: usize) !void {
        const old = try self.mutableLine(row);
        if (index >= old.len) return;
        const new_len = old.len - 1;
        const replaced = try self.allocator.alloc(Cell, new_len);
        if (index > 0) @memcpy(replaced[0..index], old[0..index]);
        if (index < new_len) @memcpy(replaced[index..new_len], old[index + 1 ..]);
        self.allocator.free(old);
        self.lines.items[row] = replaced;
        if (self.cursor_col > self.lines.items[row].len) self.cursor_col = self.lines.items[row].len;
    }

    fn trimToLimit(self: *Self) void {
        while (self.visibleLineCount() > self.config.scrollback_limit and self.lines.items.len > 1) {
            self.dropTopLine();
        }
    }

    fn insertLinesWithinRegion(self: *Self, count: usize) !void {
        const original_row = self.cursor_row;
        try self.insertLines(count);
        self.cursor_row = @min(original_row, self.lines.items.len - 1);
    }

    fn deleteLinesWithinRegion(self: *Self, count: usize) void {
        const original_row = self.cursor_row;
        self.deleteLines(count);
        self.cursor_row = @min(original_row, self.lines.items.len - 1);
    }

    fn dropTopLine(self: *Self) void {
        const removed = self.lines.orderedRemove(0);
        self.allocator.free(removed);

        if (self.lines.items.len == 0) self.appendEmptyLine() catch unreachable;

        if (self.cursor_row > 0) self.cursor_row -= 1 else self.cursor_row = 0;
        if (self.saved_cursor) |*saved| {
            if (saved.line == 0) {
                self.saved_cursor = null;
            } else {
                saved.line -= 1;
            }
        }
        if (self.selection) |*sel| {
            if (sel.start.line == 0 or sel.end.line == 0) {
                self.selection = null;
            } else {
                sel.start.line -= 1;
                sel.end.line -= 1;
            }
        }
        self.scroll_offset = self.scroll_offset -| 1;
    }

    fn cleanupSession(self: *Self) void {
        if (self.session) |session_ptr| {
            if (self.owns_session) session_ptr.deinit();
            self.session = null;
        }
        if (self.session_metrics) |metrics_ptr| {
            if (self.owns_session) self.allocator.destroy(metrics_ptr);
            self.session_metrics = null;
        }

        self.owns_session = false;
        self.pending_exit = null;
        self.selection = null;
        self.mouse_motion_enabled = false;
        self.mouse_any_event_enabled = false;
    }

    fn modifierBits(modifiers: @import("../event.zig").Modifiers) u8 {
        var bits: u8 = 0;
        if (modifiers.shift) bits += 4;
        if (modifiers.alt) bits += 8;
        if (modifiers.ctrl) bits += 16;
        return bits;
    }

    fn mouseMotionEnabledForEvent(self: *const Self, mouse: @import("../event.zig").MouseEvent) bool {
        if (!self.mouse_motion_enabled) return false;
        if (self.mouse_any_event_enabled) return true;
        return mouse.pressed and mouse.button != .wheel_up and mouse.button != .wheel_down;
    }
};

const testing = std.testing;

test "Terminal widget buffers plain text" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("hello\nworld\n");

    const scroll = widget.getScrollback();
    try testing.expectEqual(@as(usize, 2), scroll.len);
    try testing.expectEqual('h', scroll[0][0].char);
    try testing.expectEqual('w', scroll[1][0].char);

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
    try testing.expect(std.meta.eql(scroll[0][0].style.fg.?, Color.red));
    try testing.expect(std.meta.eql(scroll[0][1].style.fg.?, Color.red));
}

test "Terminal widget applies cursor motion and overwrite sequences" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("abcd\x1b[2D!\n");
    const text = try widget.allText(testing.allocator);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("ab!d", text);
}

test "Terminal widget supports save restore cursor and delete chars" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("abcd\x1b[s\x1b[1GZ\x1b[u\x1b[P!\n");
    const text = try widget.allText(testing.allocator);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("Zbc!", text);
}

test "Terminal widget cursor position can rewrite prior buffered line" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("one\ntwo\x1b[1;2HZ");
    const text = try widget.allText(testing.allocator);
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "oZe") != null);
}

test "Terminal widget delete lines shifts later rows upward" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("one\ntwo\nthree\n");
    try widget.feed("\x1b[2;1H\x1b[M");

    const text = try widget.allText(testing.allocator);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("one\nthree", text);
}

test "Terminal widget delete lines respects scroll region" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("one\ntwo\nthree\nfour\n");
    try widget.feed("\x1b[2;3r\x1b[2;1H\x1b[M");

    const text = try widget.allText(testing.allocator);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("one\nthree\n\nfour", text);
}

test "Terminal widget insert lines creates blank row at cursor" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("one\ntwo\n");
    try widget.feed("\x1b[2;1H\x1b[L");

    const scroll = widget.getScrollback();
    try testing.expectEqual(@as(usize, 3), scroll.len);
    try testing.expectEqual(@as(usize, 0), scroll[1].len);
}

test "Terminal selection extracts text" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("abcdef\n");
    try widget.setSelection(.{ .line = 0, .column = 2 }, .{ .line = 0, .column = 5 });
    const text = try widget.selectionText(testing.allocator);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("cde", text);
}

test "Terminal trims scrollback to configured limit" {
    var widget = try Terminal.init(testing.allocator, .{ .scrollback_limit = 2 });
    defer widget.widget.deinit();

    try widget.feed("one\ntwo\nthree\n");
    const scroll = widget.getScrollback();
    try testing.expectEqual(@as(usize, 2), scroll.len);
    try testing.expectEqual('t', scroll[0][0].char);
    try testing.expectEqual('t', scroll[1][0].char);
}

test "Terminal placeholder renders when idle" {
    var widget = try Terminal.init(testing.allocator, .{ .placeholder_text = "idle terminal" });
    defer widget.widget.deinit();

    var buffer = try Buffer.init(testing.allocator, Size.init(20, 4));
    defer buffer.deinit();
    widget.widget.render(&buffer, Rect.init(0, 0, 20, 4));
    try testing.expectEqual('i', buffer.getCell(0, 0).?.char);
}

test "Terminal keeps active line visible when scrollback exceeds viewport" {
    var widget = try Terminal.init(testing.allocator, .{ .scrollback_limit = 8 });
    defer widget.widget.deinit();

    try widget.feed("one\ntwo\nthree\nfour");
    var buffer = try Buffer.init(testing.allocator, Size.init(16, 2));
    defer buffer.deinit();
    widget.widget.render(&buffer, Rect.init(0, 0, 16, 2));
    try testing.expectEqual('t', buffer.getCell(0, 0).?.char);
    try testing.expectEqual('f', buffer.getCell(0, 1).?.char);
}

test "Terminal widget supports manual scroll offset and auto-follow reset" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("one\ntwo\nthree\nfour\n");
    widget.scrollLines(2);
    try testing.expect(!widget.isAutoFollow());

    var buffer = try Buffer.init(testing.allocator, Size.init(16, 2));
    defer buffer.deinit();
    widget.widget.render(&buffer, Rect.init(0, 0, 16, 2));
    try testing.expectEqual('o', buffer.getCell(0, 0).?.char);
    try testing.expectEqual('t', buffer.getCell(0, 1).?.char);

    widget.scrollToBottom();
    try testing.expect(widget.isAutoFollow());
}

test "Terminal widget renders scroll hint when manual scroll is active" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("one\ntwo\nthree\nfour\n");
    widget.scrollLines(1);

    var buffer = try Buffer.init(testing.allocator, Size.init(24, 3));
    defer buffer.deinit();
    widget.widget.render(&buffer, Rect.init(0, 0, 24, 3));
    try testing.expectEqual('[', buffer.getCell(0, 0).?.char);
}

test "Terminal widget alternate screen restores primary content" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("one\ntwo\n");
    try widget.feed("\x1b[?1049halt\n");

    const alt_text = try widget.allText(testing.allocator);
    defer testing.allocator.free(alt_text);
    try testing.expect(std.mem.indexOf(u8, alt_text, "alt") != null);

    try widget.feed("\x1b[?1049l");
    const text = try widget.allText(testing.allocator);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("one\ntwo", text);
}

test "Terminal widget private mode hides cursor rendering" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("abc\x1b[?25l");
    var buffer = try Buffer.init(testing.allocator, Size.init(8, 2));
    defer buffer.deinit();

    widget.widget.render(&buffer, Rect.init(0, 0, 8, 2));
    const cursor_cell = buffer.getCell(3, 0).?;
    try testing.expect(!cursor_cell.style.attributes.reverse);
}

test "Terminal widget renders visible cursor in viewport" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    try widget.feed("abc");
    var buffer = try Buffer.init(testing.allocator, Size.init(8, 2));
    defer buffer.deinit();

    widget.widget.render(&buffer, Rect.init(0, 0, 8, 2));
    const cursor_cell = buffer.getCell(3, 0).?;
    try testing.expect(cursor_cell.style.attributes.reverse);
}

test "Terminal trim rebases saved cursor and clears invalid selection" {
    var widget = try Terminal.init(testing.allocator, .{ .scrollback_limit = 2 });
    defer widget.widget.deinit();

    try widget.feed("one\ntwo\n");
    try widget.feed("\x1b[1;2H\x1b[s");
    try widget.setSelection(.{ .line = 0, .column = 0 }, .{ .line = 1, .column = 1 });
    try widget.feed("three\n");

    try testing.expect(widget.saved_cursor != null);
    try testing.expectEqual(@as(usize, 0), widget.saved_cursor.?.line);
    try testing.expect(!widget.hasSelection());
}

test "Terminal widget auto-spawn integrates with PTY session" {
    const allocator = testing.allocator;
    var runtime = try AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    const command = switch (builtin.os.tag) {
        .windows => &.{ "cmd.exe", "/C", "echo phantom-auto" },
        else => &.{ "/bin/sh", "-c", "printf phantom-auto" },
    };

    var widget = try Terminal.init(allocator, .{
        .runtime = runtime,
        .session_config = .{ .command = command, .columns = 80, .rows = 24 },
        .auto_spawn = true,
    });
    defer widget.widget.deinit();

    var saw_output = false;
    var saw_exit = false;
    var iterations: usize = 0;
    while ((!saw_output or !saw_exit) and iterations < 400) : (iterations += 1) {
        _ = widget.poll();
        const text = try widget.allText(testing.allocator);
        defer testing.allocator.free(text);
        if (std.mem.indexOf(u8, text, "phantom-auto") != null) saw_output = true;
        if (widget.hasPendingExit()) saw_exit = true else time_utils.sleepMs(5);
    }

    try testing.expect(saw_output);
    try testing.expect(saw_exit);
}

test "Terminal widget attached manager session preserves external ownership" {
    const allocator = testing.allocator;
    var runtime = try AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    var manager = try term_session.Manager.init(allocator, runtime);
    defer manager.deinit();

    const command = switch (builtin.os.tag) {
        .windows => &.{ "cmd.exe", "/C", "echo phantom-attached" },
        else => &.{ "/bin/sh", "-c", "printf phantom-attached" },
    };

    const handle = try manager.spawn(.{ .command = command, .columns = 80, .rows = 24 });
    defer manager.release(handle);

    var widget = try Terminal.init(allocator, .{ .runtime = runtime });
    defer widget.widget.deinit();
    widget.attachSession(try manager.getSession(handle), try manager.metrics(handle));

    var saw_output = false;
    var saw_exit = false;
    var iterations: usize = 0;
    while ((!saw_output or !saw_exit) and iterations < 400) : (iterations += 1) {
        _ = widget.poll();
        const text = try widget.allText(testing.allocator);
        defer testing.allocator.free(text);
        if (std.mem.indexOf(u8, text, "phantom-attached") != null) saw_output = true;
        if (widget.hasPendingExit()) saw_exit = true else time_utils.sleepMs(5);
    }

    try testing.expect(saw_output);
    try testing.expect(saw_exit);
    try testing.expectEqual(@as(usize, 1), manager.sessionCount());
}

test "Terminal widget sends key input through attached PTY session" {
    const allocator = testing.allocator;
    var runtime = try AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    var manager = try term_session.Manager.init(allocator, runtime);
    defer manager.deinit();

    const command = switch (builtin.os.tag) {
        .windows => &.{ "cmd.exe", "/Q", "/K" },
        else => &.{ "/bin/sh", "-i" },
    };

    const handle = try manager.spawn(.{ .command = command, .columns = 80, .rows = 24 });
    defer manager.release(handle);

    var widget = try Terminal.init(allocator, .{ .runtime = runtime });
    defer widget.widget.deinit();
    widget.attachSession(try manager.getSession(handle), try manager.metrics(handle));

    var warmup: usize = 0;
    while (warmup < 40) : (warmup += 1) {
        _ = widget.poll();
        time_utils.sleepMs(5);
    }

    inline for ([_]u8{ 'e', 'c', 'h', 'o', ' ', 'p', 'h', 'a', 'n', 't', 'o', 'm' }) |ch| {
        try testing.expect(widget.widget.handleEvent(.{ .key = .{ .char = ch } }));
    }
    try testing.expect(widget.widget.handleEvent(.{ .key = .enter }));

    var saw_echo = false;
    var iterations: usize = 0;
    while (!saw_echo and iterations < 400) : (iterations += 1) {
        _ = widget.poll();
        const text = try widget.allText(testing.allocator);
        defer testing.allocator.free(text);
        if (std.mem.indexOf(u8, text, "phantom") != null) saw_echo = true else time_utils.sleepMs(5);
    }

    try testing.expect(saw_echo);
}

test "Terminal widget encodes mouse modifier and motion flags" {
    var widget = try Terminal.init(testing.allocator, .{});
    defer widget.widget.deinit();

    widget.is_focused = true;
    try widget.applyModeSetting(.{ .private = true, .mode = 1003, .enable = true });

    try testing.expect(widget.mouseReportingEnabled());
    try testing.expect(widget.mouseMotionEnabled());
    try testing.expect(widget.mouseAnyEventEnabled());
    try testing.expectEqual(@as(u8, 28), Terminal.modifierBits(.{ .shift = true, .alt = true, .ctrl = true }));
    try testing.expect(widget.mouseMotionEnabledForEvent(.{
        .button = .left,
        .position = .{ .x = 2, .y = 3 },
        .pressed = true,
        .modifiers = .{},
    }));
}
