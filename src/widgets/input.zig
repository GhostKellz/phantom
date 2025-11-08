//! Input widget for text input fields
const std = @import("std");
const ArrayList = std.array_list.Managed;
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
const theme_mod = @import("../theme/mod.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Input change callback function type
pub const OnChangeFn = *const fn (input: *Input, text: []const u8) void;
pub const OnSubmitFn = *const fn (input: *Input, text: []const u8) void;

/// Input widget for text input fields
pub const Input = struct {
    widget: Widget,
    allocator: std.mem.Allocator,

    // Text content
    text: ArrayList(u8),
    placeholder: []const u8,

    // Cursor and selection
    cursor_pos: usize = 0,
    selection_start: ?usize = null,
    scroll_offset: usize = 0,

    // Styling
    normal_style: Style,
    focused_style: Style,
    placeholder_style: Style,
    selection_style: Style,

    // State
    is_focused: bool = false,
    is_password: bool = false,
    password_char: u21 = '*',
    max_length: ?usize = null,

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
    };

    pub fn init(allocator: std.mem.Allocator) !*Input {
        const input = try allocator.create(Input);
        input.* = Input{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .text = ArrayList(u8).init(allocator),
            .placeholder = "",
            .normal_style = Style.default(),
            .focused_style = Style.default().withBg(style.Color.blue),
            .placeholder_style = Style.default().withFg(style.Color.bright_black),
            .selection_style = Style.default().withBg(style.Color.cyan),
        };
        input.applyThemeDefaults();
        return input;
    }

    fn applyThemeDefaults(self: *Input) void {
        const manager = theme_mod.ThemeManager.global() orelse return;
        const theme = manager.getActiveTheme();
        const component_key = "input.field";

        const surface = theme.getPaletteColor("surface") orelse theme.colors.background_panel;
        const surface_alt = theme.getPaletteColor("surface_alt") orelse theme.colors.background_element;

        var base_fg = theme.colors.text;
        var base_bg = surface;
        var base_attributes = style.Attributes.none();

        if (theme.getComponentStyle(component_key)) |component| {
            if (component.fg) |fg| base_fg = fg;
            if (component.bg) |bg| base_bg = bg;
            base_attributes = component.attributes;
        }

        if (theme.getComponentTypography(component_key)) |preset| {
            base_attributes = preset.attributes;
        }

        var normal_style = Style.default();
        normal_style.fg = base_fg;
        normal_style.bg = base_bg;
        normal_style.attributes = base_attributes;
        self.normal_style = normal_style;

        var focused_style = normal_style;
        focused_style.bg = surface_alt;
        focused_style.attributes.underline = true;
        self.focused_style = focused_style;

        var placeholder_style = normal_style;
        placeholder_style.fg = theme.colors.text_muted;
        placeholder_style.attributes = normal_style.attributes;
        placeholder_style.attributes.italic = true;
        self.placeholder_style = placeholder_style;

        var selection_style = Style.default();
        selection_style.bg = theme.colors.accent;
        selection_style.fg = theme.colors.background;
        selection_style.attributes = normal_style.attributes;
        self.selection_style = selection_style;
    }

    pub fn setPlaceholder(self: *Input, placeholder: []const u8) !void {
        self.placeholder = try self.allocator.dupe(u8, placeholder);
    }

    pub fn setText(self: *Input, text: []const u8) !void {
        self.text.clearAndFree();
        try self.text.appendSlice(text);
        self.cursor_pos = @min(self.cursor_pos, self.text.items.len);
        self.selection_start = null;
        self.updateScrollOffset();
        self.notifyChange();
    }

    pub fn getText(self: *const Input) []const u8 {
        return self.text.items;
    }

    pub fn setMaxLength(self: *Input, max_length: ?usize) void {
        self.max_length = max_length;
    }

    pub fn setPassword(self: *Input, is_password: bool) void {
        self.is_password = is_password;
    }

    pub fn setPasswordChar(self: *Input, password_char: u21) void {
        self.password_char = password_char;
    }

    pub fn setNormalStyle(self: *Input, normal_style: Style) void {
        self.normal_style = normal_style;
    }

    pub fn setFocusedStyle(self: *Input, focused_style: Style) void {
        self.focused_style = focused_style;
    }

    pub fn setPlaceholderStyle(self: *Input, placeholder_style: Style) void {
        self.placeholder_style = placeholder_style;
    }

    pub fn setOnChange(self: *Input, callback: OnChangeFn) void {
        self.on_change = callback;
    }

    pub fn setOnSubmit(self: *Input, callback: OnSubmitFn) void {
        self.on_submit = callback;
    }

    pub fn focus(self: *Input) void {
        self.is_focused = true;
    }

    pub fn blur(self: *Input) void {
        self.is_focused = false;
        self.selection_start = null;
    }

    pub fn clear(self: *Input) void {
        self.text.clearAndFree();
        self.cursor_pos = 0;
        self.selection_start = null;
        self.scroll_offset = 0;
        self.notifyChange();
    }

    pub fn selectAll(self: *Input) void {
        self.selection_start = 0;
        self.cursor_pos = self.text.items.len;
    }

    pub fn setClipboardManager(self: *Input, manager: *clipboard.ClipboardManager) void {
        self.clipboard_manager = manager;
    }

    pub fn copyToClipboard(self: *Input) void {
        if (self.clipboard_manager) |manager| {
            const text = self.getSelectedText();
            if (text.len > 0) {
                _ = manager.copy(text);
            }
        }
    }

    pub fn pasteFromClipboard(self: *Input) void {
        if (self.clipboard_manager) |manager| {
            if (manager.paste()) |text| {
                defer self.allocator.free(text);
                self.insertText(text) catch {};
            }
        }
    }

    pub fn cutToClipboard(self: *Input) void {
        if (self.clipboard_manager) |manager| {
            const text = self.getSelectedText();
            if (text.len > 0) {
                _ = manager.copy(text);
                self.deleteSelection();
            }
        }
    }

    pub fn getSelectedText(self: *Input) []const u8 {
        if (self.selection_start) |start| {
            const end = self.cursor_pos;
            if (start != end) {
                const selection_start = @min(start, end);
                const selection_end = @max(start, end);
                return self.text.items[selection_start..selection_end];
            }
        }
        return "";
    }

    pub fn insertText(self: *Input, text: []const u8) !void {
        if (self.selection_start != null) {
            self.deleteSelection();
        }

        for (text) |char| {
            if (char >= 32 and char <= 126) { // Printable ASCII
                try self.insertChar(char);
            }
        }
    }

    pub fn deleteSelection(self: *Input) void {
        if (self.selection_start) |start| {
            const end = self.cursor_pos;
            if (start != end) {
                const selection_start = @min(start, end);
                const selection_end = @max(start, end);

                // Remove selected text
                const new_text = self.allocator.alloc(u8, self.text.items.len - (selection_end - selection_start)) catch return;
                defer self.allocator.free(new_text);

                @memcpy(new_text[0..selection_start], self.text.items[0..selection_start]);
                @memcpy(new_text[selection_start..], self.text.items[selection_end..]);

                self.text.clearAndFree();
                self.text.appendSlice(new_text) catch return;

                self.cursor_pos = selection_start;
                self.selection_start = null;
                self.updateScrollOffset();
                self.notifyChange();
            }
        }
    }

    fn notifyChange(self: *Input) void {
        if (self.on_change) |callback| {
            callback(self, self.text.items);
        }
    }

    fn notifySubmit(self: *Input) void {
        if (self.on_submit) |callback| {
            callback(self, self.text.items);
        }
    }

    fn insertChar(self: *Input, c: u21) !void {
        if (self.max_length) |max_len| {
            if (self.text.items.len >= max_len) return;
        }

        // Convert unicode codepoint to UTF-8
        var utf8_bytes: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(c, &utf8_bytes) catch return;

        // Delete selected text first
        if (self.selection_start) |start| {
            const end = self.cursor_pos;
            const delete_start = @min(start, end);
            const delete_end = @max(start, end);

            _ = self.text.orderedRemove(delete_start);
            var i = delete_start;
            while (i < delete_end - 1) : (i += 1) {
                _ = self.text.orderedRemove(delete_start);
            }

            self.cursor_pos = delete_start;
            self.selection_start = null;
        }

        // Insert new character
        try self.text.insertSlice(self.cursor_pos, utf8_bytes[0..len]);
        self.cursor_pos += len;
        self.updateScrollOffset();
        self.notifyChange();
    }

    fn deleteChar(self: *Input) void {
        if (self.selection_start) |start| {
            // Delete selected text
            const end = self.cursor_pos;
            const delete_start = @min(start, end);
            const delete_end = @max(start, end);

            var i = delete_start;
            while (i < delete_end) : (i += 1) {
                _ = self.text.orderedRemove(delete_start);
            }

            self.cursor_pos = delete_start;
            self.selection_start = null;
        } else if (self.cursor_pos > 0) {
            // Delete character before cursor
            _ = self.text.orderedRemove(self.cursor_pos - 1);
            self.cursor_pos -= 1;
        }

        self.updateScrollOffset();
        self.notifyChange();
    }

    fn deleteCharForward(self: *Input) void {
        if (self.selection_start) |_| {
            self.deleteChar();
        } else if (self.cursor_pos < self.text.items.len) {
            _ = self.text.orderedRemove(self.cursor_pos);
            self.updateScrollOffset();
            self.notifyChange();
        }
    }

    fn moveCursorLeft(self: *Input) void {
        if (self.cursor_pos > 0) {
            self.cursor_pos -= 1;
            self.updateScrollOffset();
        }
    }

    fn moveCursorRight(self: *Input) void {
        if (self.cursor_pos < self.text.items.len) {
            self.cursor_pos += 1;
            self.updateScrollOffset();
        }
    }

    fn moveCursorHome(self: *Input) void {
        self.cursor_pos = 0;
        self.updateScrollOffset();
    }

    fn moveCursorEnd(self: *Input) void {
        self.cursor_pos = self.text.items.len;
        self.updateScrollOffset();
    }

    fn updateScrollOffset(self: *Input) void {
        const visible_width = if (self.area.width > 2) self.area.width - 2 else 0;

        if (self.cursor_pos < self.scroll_offset) {
            self.scroll_offset = self.cursor_pos;
        } else if (self.cursor_pos >= self.scroll_offset + visible_width) {
            self.scroll_offset = self.cursor_pos - visible_width + 1;
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Input = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;

        const current_style = if (self.is_focused) self.focused_style else self.normal_style;

        // Fill input background
        buffer.fill(area, Cell.withStyle(current_style));

        // Draw border
        if (area.width > 2 and area.height > 0) {
            // Top and bottom borders
            var x = area.x;
            while (x < area.x + area.width) : (x += 1) {
                buffer.setCell(x, area.y, Cell.init('─', current_style));
                if (area.height > 1) {
                    buffer.setCell(x, area.y + area.height - 1, Cell.init('─', current_style));
                }
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
            if (area.height > 1) {
                buffer.setCell(area.x, area.y + area.height - 1, Cell.init('└', current_style));
                buffer.setCell(area.x + area.width - 1, area.y + area.height - 1, Cell.init('┘', current_style));
            }
        }

        // Render text content
        if (area.width > 2 and area.height > 1) {
            const text_area = Rect.init(area.x + 1, area.y + 1, area.width - 2, area.height - 2);
            const text_y = text_area.y + text_area.height / 2;

            if (self.text.items.len == 0) {
                // Show placeholder
                if (self.placeholder.len > 0) {
                    const visible_len = @min(self.placeholder.len, text_area.width);
                    buffer.writeText(text_area.x, text_y, self.placeholder[0..visible_len], self.placeholder_style);
                }
            } else {
                // Show actual text
                const visible_start = @min(self.scroll_offset, self.text.items.len);
                const visible_end = @min(visible_start + text_area.width, self.text.items.len);

                if (visible_start < visible_end) {
                    const visible_text = self.text.items[visible_start..visible_end];

                    if (self.is_password) {
                        // Render password characters
                        var i: u16 = 0;
                        while (i < visible_text.len and i < text_area.width) : (i += 1) {
                            buffer.setCell(text_area.x + i, text_y, Cell.init(self.password_char, current_style));
                        }
                    } else {
                        buffer.writeText(text_area.x, text_y, visible_text, current_style);
                    }
                }
            }

            // Render cursor
            if (self.is_focused and self.cursor_pos >= self.scroll_offset) {
                const cursor_x = text_area.x + @as(u16, @intCast(self.cursor_pos - self.scroll_offset));
                if (cursor_x < text_area.x + text_area.width) {
                    buffer.setCell(cursor_x, text_y, Cell.init('_', current_style.withBg(style.Color.white)));
                }
            }
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Input = @fieldParentPtr("widget", widget);

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
                        .backspace => {
                            self.deleteChar();
                            return true;
                        },
                        .delete => {
                            self.deleteCharForward();
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
                        .enter => {
                            self.notifySubmit();
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
                        .ctrl_c => {
                            self.copyToClipboard();
                            return true;
                        },
                        .ctrl_v => {
                            self.pasteFromClipboard();
                            return true;
                        },
                        .ctrl_x => {
                            self.cutToClipboard();
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
                    if (self.area.width > 2 and self.area.height > 1) {
                        const text_x = pos.x - (self.area.x + 1);
                        const new_cursor_pos = @min(self.scroll_offset + text_x, self.text.items.len);
                        self.cursor_pos = new_cursor_pos;
                        self.selection_start = null;
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
        const self: *Input = @fieldParentPtr("widget", widget);
        self.area = area;
        self.updateScrollOffset();
    }

    fn deinit(widget: *Widget) void {
        const self: *Input = @fieldParentPtr("widget", widget);
        self.text.deinit();
        self.allocator.free(self.placeholder);
        self.allocator.destroy(self);
    }
};

// Example callback functions
fn exampleOnChange(input: *Input, text: []const u8) void {
    _ = input;
    std.debug.print("Input changed: '{}'\n", .{text});
}

fn exampleOnSubmit(input: *Input, text: []const u8) void {
    _ = input;
    std.debug.print("Input submitted: '{}'\n", .{text});
}

test "Input widget creation" {
    const allocator = std.testing.allocator;

    const input = try Input.init(allocator);
    defer input.widget.deinit();

    try std.testing.expect(input.text.items.len == 0);
    try std.testing.expect(input.cursor_pos == 0);
    try std.testing.expect(!input.is_focused);
}

test "Input widget text manipulation" {
    const allocator = std.testing.allocator;

    const input = try Input.init(allocator);
    defer input.widget.deinit();

    try input.setText("Hello, World!");
    try std.testing.expectEqualStrings("Hello, World!", input.getText());

    input.clear();
    try std.testing.expect(input.getText().len == 0);
}

test "Input widget cursor movement" {
    const allocator = std.testing.allocator;

    const input = try Input.init(allocator);
    defer input.widget.deinit();

    try input.setText("Hello");

    input.moveCursorHome();
    try std.testing.expect(input.cursor_pos == 0);

    input.moveCursorEnd();
    try std.testing.expect(input.cursor_pos == 5);

    input.moveCursorLeft();
    try std.testing.expect(input.cursor_pos == 4);

    input.moveCursorRight();
    try std.testing.expect(input.cursor_pos == 5);
}
