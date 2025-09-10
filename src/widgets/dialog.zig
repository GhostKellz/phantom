//! Dialog widget for modal dialogs and popups
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const Key = @import("../event.zig").Key;
const MouseEvent = @import("../event.zig").MouseEvent;
const MouseButton = @import("../event.zig").MouseButton;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Position = geometry.Position;
const Style = style.Style;

/// Dialog button configuration
pub const DialogButton = struct {
    text: []const u8,
    action: DialogAction,
    style: Style = Style.default(),
    is_default: bool = false,
    
    pub const DialogAction = enum {
        ok,
        cancel,
        yes,
        no,
        close,
        custom,
    };
};

/// Dialog callback function type
pub const OnDialogActionFn = *const fn (dialog: *Dialog, action: DialogButton.DialogAction) void;

/// Dialog types
pub const DialogType = enum {
    info,
    warning,
    error,
    confirm,
    input,
    custom,
};

/// Dialog widget for modal dialogs and popups
pub const Dialog = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    
    // Content
    title: []const u8,
    message: []const u8,
    dialog_type: DialogType,
    
    // Buttons
    buttons: std.ArrayList(DialogButton),
    selected_button: usize = 0,
    
    // Input (for input dialogs)
    input_widget: ?*@import("input.zig").Input = null,
    input_value: []const u8 = "",
    
    // Styling
    title_style: Style,
    message_style: Style,
    button_style: Style,
    selected_button_style: Style,
    border_style: Style,
    background_style: Style,
    overlay_style: Style,
    
    // Configuration
    is_modal: bool = true,
    show_close_button: bool = true,
    min_width: u16 = 30,
    min_height: u16 = 8,
    
    // State
    is_visible: bool = false,
    is_focused: bool = false,
    
    // Callbacks
    on_action: ?OnDialogActionFn = null,
    
    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),
    content_area: Rect = Rect.init(0, 0, 0, 0),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator, title: []const u8, message: []const u8, dialog_type: DialogType) !*Dialog {
        const dialog = try allocator.create(Dialog);
        dialog.* = Dialog{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .title = try allocator.dupe(u8, title),
            .message = try allocator.dupe(u8, message),
            .dialog_type = dialog_type,
            .buttons = std.ArrayList(DialogButton){},
            .title_style = Style.default().withFg(style.Color.bright_white).withBold(),
            .message_style = Style.default().withFg(style.Color.white),
            .button_style = Style.default().withFg(style.Color.white).withBg(style.Color.blue),
            .selected_button_style = Style.default().withFg(style.Color.white).withBg(style.Color.bright_blue).withBold(),
            .border_style = Style.default().withFg(style.Color.bright_blue),
            .background_style = Style.default().withBg(style.Color.black),
            .overlay_style = Style.default().withBg(style.Color.bright_black),
        };
        
        // Add default buttons based on dialog type
        try dialog.addDefaultButtons();
        
        return dialog;
    }

    pub fn show(self: *Dialog) void {
        self.is_visible = true;
        self.is_focused = true;
    }

    pub fn hide(self: *Dialog) void {
        self.is_visible = false;
        self.is_focused = false;
    }

    pub fn setTitle(self: *Dialog, title: []const u8) !void {
        self.allocator.free(self.title);
        self.title = try self.allocator.dupe(u8, title);
    }

    pub fn setMessage(self: *Dialog, message: []const u8) !void {
        self.allocator.free(self.message);
        self.message = try self.allocator.dupe(u8, message);
    }

    pub fn addButton(self: *Dialog, button: DialogButton) !void {
        var owned_button = button;
        owned_button.text = try self.allocator.dupe(u8, button.text);
        try self.buttons.append(self.allocator, owned_button);
    }

    pub fn clearButtons(self: *Dialog) void {
        for (self.buttons.items) |button| {
            self.allocator.free(button.text);
        }
        self.buttons.clearAndFree(self.allocator);
    }

    pub fn setInputWidget(self: *Dialog, input_widget: *@import("input.zig").Input) void {
        self.input_widget = input_widget;
    }

    pub fn getInputValue(self: *const Dialog) []const u8 {
        if (self.input_widget) |input| {
            return input.getText();
        }
        return self.input_value;
    }

    pub fn setOnAction(self: *Dialog, callback: OnDialogActionFn) void {
        self.on_action = callback;
    }

    pub fn setModal(self: *Dialog, is_modal: bool) void {
        self.is_modal = is_modal;
    }

    pub fn setShowCloseButton(self: *Dialog, show: bool) void {
        self.show_close_button = show;
    }

    pub fn setMinSize(self: *Dialog, width: u16, height: u16) void {
        self.min_width = width;
        self.min_height = height;
    }

    pub fn selectNextButton(self: *Dialog) void {
        if (self.buttons.items.len > 0) {
            self.selected_button = (self.selected_button + 1) % self.buttons.items.len;
        }
    }

    pub fn selectPrevButton(self: *Dialog) void {
        if (self.buttons.items.len > 0) {
            self.selected_button = if (self.selected_button == 0) 
                self.buttons.items.len - 1 
            else 
                self.selected_button - 1;
        }
    }

    pub fn activateSelectedButton(self: *Dialog) void {
        if (self.selected_button < self.buttons.items.len) {
            const button = self.buttons.items[self.selected_button];
            if (self.on_action) |callback| {
                callback(self, button.action);
            }
        }
    }

    fn addDefaultButtons(self: *Dialog) !void {
        switch (self.dialog_type) {
            .info => {
                try self.addButton(DialogButton{
                    .text = "OK",
                    .action = .ok,
                    .is_default = true,
                });
            },
            .warning => {
                try self.addButton(DialogButton{
                    .text = "OK",
                    .action = .ok,
                    .is_default = true,
                });
            },
            .error => {
                try self.addButton(DialogButton{
                    .text = "OK",
                    .action = .ok,
                    .is_default = true,
                });
            },
            .confirm => {
                try self.addButton(DialogButton{
                    .text = "Yes",
                    .action = .yes,
                    .is_default = true,
                });
                try self.addButton(DialogButton{
                    .text = "No",
                    .action = .no,
                });
            },
            .input => {
                try self.addButton(DialogButton{
                    .text = "OK",
                    .action = .ok,
                    .is_default = true,
                });
                try self.addButton(DialogButton{
                    .text = "Cancel",
                    .action = .cancel,
                });
            },
            .custom => {
                // No default buttons for custom dialogs
            },
        }
    }

    fn calculateSize(self: *Dialog, available_area: Rect) Rect {
        // Calculate required size based on content
        var required_width = @max(self.min_width, @as(u16, @intCast(self.title.len + 4)));
        var required_height = self.min_height;
        
        // Account for message text (with word wrapping)
        const message_lines = self.calculateMessageLines(@max(required_width - 4, 20));
        required_height = @max(required_height, @as(u16, @intCast(message_lines + 6))); // Title + buttons + borders
        
        // Account for buttons
        var button_width: u16 = 0;
        for (self.buttons.items) |button| {
            button_width += @as(u16, @intCast(button.text.len + 4)); // Button text + padding
        }
        if (self.buttons.items.len > 1) {
            button_width += @as(u16, @intCast((self.buttons.items.len - 1) * 2)); // Spacing between buttons
        }
        required_width = @max(required_width, button_width + 4);
        
        // Account for input widget
        if (self.input_widget != null) {
            required_height += 3; // Input field + spacing
        }
        
        // Center dialog in available area
        const dialog_width = @min(required_width, available_area.width);
        const dialog_height = @min(required_height, available_area.height);
        
        const x = available_area.x + (available_area.width - dialog_width) / 2;
        const y = available_area.y + (available_area.height - dialog_height) / 2;
        
        return Rect.init(x, y, dialog_width, dialog_height);
    }

    fn calculateMessageLines(self: *Dialog, width: u16) u16 {
        if (width == 0) return 1;
        
        var lines: u16 = 1;
        var current_line_len: u16 = 0;
        
        for (self.message) |char| {
            if (char == '\n') {
                lines += 1;
                current_line_len = 0;
            } else {
                current_line_len += 1;
                if (current_line_len >= width) {
                    lines += 1;
                    current_line_len = 0;
                }
            }
        }
        
        return lines;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Dialog = @fieldParentPtr("widget", widget);
        
        if (!self.is_visible) return;
        
        // Calculate dialog size and position
        self.area = self.calculateSize(area);
        
        // Render modal overlay if modal
        if (self.is_modal) {
            for (0..area.height) |y| {
                for (0..area.width) |x| {
                    const cell = Cell.init(' ', self.overlay_style);
                    buffer.setCell(area.x + @as(u16, @intCast(x)), area.y + @as(u16, @intCast(y)), cell);
                }
            }
        }
        
        // Render dialog background
        buffer.fill(self.area, Cell.withStyle(self.background_style));
        
        // Render border
        self.renderBorder(buffer);
        
        // Calculate content area
        self.content_area = Rect.init(
            self.area.x + 2,
            self.area.y + 1,
            self.area.width - 4,
            self.area.height - 2
        );
        
        var current_y = self.content_area.y;
        
        // Render title
        if (self.title.len > 0) {
            const title_x = self.content_area.x + (self.content_area.width - @as(u16, @intCast(self.title.len))) / 2;
            buffer.writeText(title_x, current_y, self.title, self.title_style);
            current_y += 2;
        }
        
        // Render message
        current_y = self.renderMessage(buffer, current_y);
        current_y += 1;
        
        // Render input widget if present
        if (self.input_widget) |input| {
            const input_area = Rect.init(
                self.content_area.x,
                current_y,
                self.content_area.width,
                1
            );
            input.widget.vtable.render(&input.widget, buffer, input_area);
            current_y += 2;
        }
        
        // Render buttons
        self.renderButtons(buffer, current_y);
        
        // Render close button if enabled
        if (self.show_close_button) {
            buffer.setCell(self.area.x + self.area.width - 2, self.area.y, Cell.init('×', self.border_style));
        }
    }

    fn renderBorder(self: *Dialog, buffer: *Buffer) void {
        const area = self.area;
        
        // Top and bottom borders
        for (0..area.width) |x| {
            const x_pos = area.x + @as(u16, @intCast(x));
            buffer.setCell(x_pos, area.y, Cell.init('─', self.border_style));
            buffer.setCell(x_pos, area.y + area.height - 1, Cell.init('─', self.border_style));
        }
        
        // Left and right borders
        for (0..area.height) |y| {
            const y_pos = area.y + @as(u16, @intCast(y));
            buffer.setCell(area.x, y_pos, Cell.init('│', self.border_style));
            buffer.setCell(area.x + area.width - 1, y_pos, Cell.init('│', self.border_style));
        }
        
        // Corners
        buffer.setCell(area.x, area.y, Cell.init('┌', self.border_style));
        buffer.setCell(area.x + area.width - 1, area.y, Cell.init('┐', self.border_style));
        buffer.setCell(area.x, area.y + area.height - 1, Cell.init('└', self.border_style));
        buffer.setCell(area.x + area.width - 1, area.y + area.height - 1, Cell.init('┘', self.border_style));
    }

    fn renderMessage(self: *Dialog, buffer: *Buffer, start_y: u16) u16 {
        var current_y = start_y;
        var current_line_start: usize = 0;
        var current_line_len: usize = 0;
        
        for (self.message, 0..) |char, i| {
            if (char == '\n' or current_line_len >= self.content_area.width) {
                // Render current line
                if (current_line_len > 0) {
                    const line_text = self.message[current_line_start..current_line_start + current_line_len];
                    buffer.writeText(self.content_area.x, current_y, line_text, self.message_style);
                    current_y += 1;
                }
                
                current_line_start = i + 1;
                current_line_len = 0;
                
                if (char != '\n') {
                    current_line_len = 1;
                }
            } else {
                current_line_len += 1;
            }
        }
        
        // Render final line
        if (current_line_len > 0) {
            const line_text = self.message[current_line_start..current_line_start + current_line_len];
            buffer.writeText(self.content_area.x, current_y, line_text, self.message_style);
            current_y += 1;
        }
        
        return current_y;
    }

    fn renderButtons(self: *Dialog, buffer: *Buffer, y: u16) void {
        if (self.buttons.items.len == 0) return;
        
        // Calculate total button width
        var total_width: u16 = 0;
        for (self.buttons.items) |button| {
            total_width += @as(u16, @intCast(button.text.len + 4)); // Button text + padding
        }
        total_width += @as(u16, @intCast((self.buttons.items.len - 1) * 2)); // Spacing between buttons
        
        // Center buttons
        var button_x = self.content_area.x + (self.content_area.width - total_width) / 2;
        
        for (self.buttons.items, 0..) |button, i| {
            const button_width = @as(u16, @intCast(button.text.len + 4));
            const is_selected = i == self.selected_button;
            
            const button_style = if (is_selected) self.selected_button_style else self.button_style;
            
            // Render button background
            buffer.fill(Rect.init(button_x, y, button_width, 1), Cell.withStyle(button_style));
            
            // Render button text
            const text_x = button_x + 2;
            buffer.writeText(text_x, y, button.text, button_style);
            
            // Render button border
            buffer.setCell(button_x, y, Cell.init('[', button_style));
            buffer.setCell(button_x + button_width - 1, y, Cell.init(']', button_style));
            
            button_x += button_width + 2;
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Dialog = @fieldParentPtr("widget", widget);
        
        if (!self.is_visible or !self.is_focused) return false;
        
        // Forward events to input widget if present and focused
        if (self.input_widget) |input| {
            if (input.is_focused) {
                return input.widget.vtable.handleEvent(&input.widget, event);
            }
        }
        
        switch (event) {
            .key => |key| {
                switch (key) {
                    .left => {
                        self.selectPrevButton();
                        return true;
                    },
                    .right => {
                        self.selectNextButton();
                        return true;
                    },
                    .tab => {
                        // Toggle focus between input and buttons
                        if (self.input_widget) |input| {
                            input.is_focused = !input.is_focused;
                        }
                        return true;
                    },
                    .enter => {
                        self.activateSelectedButton();
                        return true;
                    },
                    .escape => {
                        if (self.on_action) |callback| {
                            callback(self, .cancel);
                        }
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                if (mouse.button == .left and mouse.pressed) {
                    const pos = mouse.position;
                    
                    // Check if click is on close button
                    if (self.show_close_button and 
                        pos.x == self.area.x + self.area.width - 2 and 
                        pos.y == self.area.y) {
                        if (self.on_action) |callback| {
                            callback(self, .close);
                        }
                        return true;
                    }
                    
                    // Check if click is on a button
                    if (self.detectButtonClick(pos)) |button_action| {
                        if (self.on_action) |callback| {
                            callback(self, button_action);
                        }
                        return true;
                    }
                    
                    // Check if click is outside dialog (close if modal)
                    if (self.is_modal and 
                        (pos.x < self.area.x or pos.x >= self.area.x + self.area.width or
                         pos.y < self.area.y or pos.y >= self.area.y + self.area.height)) {
                        if (self.on_action) |callback| {
                            callback(self, .cancel);
                        }
                        return true;
                    }
                }
            },
            else => {},
        }
        
        return false;
    }
    
    fn detectButtonClick(self: *Dialog, pos: Position) ?DialogAction {
        if (self.buttons.items.len == 0) return null;
        
        // Calculate button positions (same logic as in render)
        const button_area_height: u16 = 3;
        const button_start_y = self.area.y + self.area.height - button_area_height - 1;
        
        // Calculate total width needed for all buttons
        var total_button_width: u16 = 0;
        for (self.buttons.items) |button| {
            total_button_width += @as(u16, @intCast(button.text.len)) + 4; // 2 spaces padding on each side
        }
        total_button_width += @as(u16, @intCast(self.buttons.items.len - 1)) * 2; // 2 spaces between buttons
        
        const button_start_x = self.area.x + (self.area.width - total_button_width) / 2;
        
        // Check each button
        var current_x = button_start_x;
        for (self.buttons.items) |button| {
            const button_width = @as(u16, @intCast(button.text.len)) + 4;
            
            if (pos.x >= current_x and pos.x < current_x + button_width and
                pos.y >= button_start_y and pos.y < button_start_y + button_area_height) {
                return button.action;
            }
            
            current_x += button_width + 2; // Move to next button position
        }
        
        return null;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *Dialog = @fieldParentPtr("widget", widget);
        // Dialog size is calculated dynamically in render
        _ = area;
        
        // Update input widget area if present
        if (self.input_widget) |input| {
            input.widget.vtable.resize(&input.widget, self.content_area);
        }
    }

    fn deinit(widget: *Widget) void {
        const self: *Dialog = @fieldParentPtr("widget", widget);
        
        self.allocator.free(self.title);
        self.allocator.free(self.message);
        
        for (self.buttons.items) |button| {
            self.allocator.free(button.text);
        }
        self.buttons.deinit(self.allocator);
        
        self.allocator.destroy(self);
    }
};

// Helper functions for creating common dialogs
pub fn createInfoDialog(allocator: std.mem.Allocator, title: []const u8, message: []const u8) !*Dialog {
    return Dialog.init(allocator, title, message, .info);
}

pub fn createWarningDialog(allocator: std.mem.Allocator, title: []const u8, message: []const u8) !*Dialog {
    return Dialog.init(allocator, title, message, .warning);
}

pub fn createErrorDialog(allocator: std.mem.Allocator, title: []const u8, message: []const u8) !*Dialog {
    return Dialog.init(allocator, title, message, .error);
}

pub fn createConfirmDialog(allocator: std.mem.Allocator, title: []const u8, message: []const u8) !*Dialog {
    return Dialog.init(allocator, title, message, .confirm);
}

pub fn createInputDialog(allocator: std.mem.Allocator, title: []const u8, message: []const u8) !*Dialog {
    const dialog = try Dialog.init(allocator, title, message, .input);
    
    // Create input widget
    const input_widget = try @import("input.zig").Input.init(allocator);
    dialog.setInputWidget(input_widget);
    
    return dialog;
}

// Example dialog callback
fn exampleDialogCallback(dialog: *Dialog, action: DialogButton.DialogAction) void {
    switch (action) {
        .ok => {
            std.debug.print("Dialog OK pressed\n", .{});
            if (dialog.dialog_type == .input) {
                const input_value = dialog.getInputValue();
                std.debug.print("Input value: '{}'\n", .{input_value});
            }
            dialog.hide();
        },
        .cancel => {
            std.debug.print("Dialog cancelled\n", .{});
            dialog.hide();
        },
        .yes => {
            std.debug.print("Dialog Yes pressed\n", .{});
            dialog.hide();
        },
        .no => {
            std.debug.print("Dialog No pressed\n", .{});
            dialog.hide();
        },
        .close => {
            std.debug.print("Dialog closed\n", .{});
            dialog.hide();
        },
        .custom => {
            std.debug.print("Custom dialog action\n", .{});
        },
    }
}

test "Dialog widget creation" {
    const allocator = std.testing.allocator;

    const dialog = try Dialog.init(allocator, "Test Dialog", "This is a test message", .info);
    defer dialog.widget.deinit();

    try std.testing.expectEqualStrings("Test Dialog", dialog.title);
    try std.testing.expectEqualStrings("This is a test message", dialog.message);
    try std.testing.expect(dialog.dialog_type == .info);
}

test "Dialog button management" {
    const allocator = std.testing.allocator;

    const dialog = try Dialog.init(allocator, "Test", "Message", .custom);
    defer dialog.widget.deinit();

    try dialog.addButton(DialogButton{
        .text = "Custom Button",
        .action = .custom,
    });

    try std.testing.expect(dialog.buttons.items.len == 1);
    try std.testing.expectEqualStrings("Custom Button", dialog.buttons.items[0].text);
}