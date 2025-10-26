//! Button widget for clickable actions
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

const Rect = geometry.Rect;
const Style = style.Style;

/// Button click callback function type
pub const OnClickFn = *const fn (button: *Button) void;

/// Button widget for clickable actions
pub const Button = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    text: []const u8,
    normal_style: Style,
    hover_style: Style,
    pressed_style: Style,
    focused_style: Style,
    disabled_style: Style,
    
    // State
    is_hovered: bool = false,
    is_pressed: bool = false,
    is_focused: bool = false,
    is_disabled: bool = false,
    
    // Callback
    on_click: ?OnClickFn = null,
    
    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator, text: []const u8) !*Button {
        const button = try allocator.create(Button);
        button.* = Button{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .text = try allocator.dupe(u8, text),
            .normal_style = Style.default(),
            .hover_style = Style.default().withBg(style.Color.blue),
            .pressed_style = Style.default().withBg(style.Color.cyan),
            .focused_style = Style.default().withBg(style.Color.green),
            .disabled_style = Style.default().withFg(style.Color.bright_black),
        };
        return button;
    }

    pub fn setText(self: *Button, text: []const u8) !void {
        self.allocator.free(self.text);
        self.text = try self.allocator.dupe(u8, text);
    }

    pub fn setNormalStyle(self: *Button, normal_style: Style) void {
        self.normal_style = normal_style;
    }

    pub fn setHoverStyle(self: *Button, hover_style: Style) void {
        self.hover_style = hover_style;
    }

    pub fn setPressedStyle(self: *Button, pressed_style: Style) void {
        self.pressed_style = pressed_style;
    }

    pub fn setFocusedStyle(self: *Button, focused_style: Style) void {
        self.focused_style = focused_style;
    }

    pub fn setDisabledStyle(self: *Button, disabled_style: Style) void {
        self.disabled_style = disabled_style;
    }

    pub fn setOnClick(self: *Button, callback: OnClickFn) void {
        self.on_click = callback;
    }

    pub fn setDisabled(self: *Button, disabled: bool) void {
        self.is_disabled = disabled;
    }

    pub fn click(self: *Button) void {
        if (self.is_disabled) return;
        if (self.on_click) |callback| {
            callback(self);
        }
    }

    fn getCurrentStyle(self: *const Button) Style {
        if (self.is_disabled) return self.disabled_style;
        if (self.is_pressed) return self.pressed_style;
        if (self.is_hovered) return self.hover_style;
        if (self.is_focused) return self.focused_style;
        return self.normal_style;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Button = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;

        const current_style = self.getCurrentStyle();
        
        // Fill button background
        buffer.fill(area, Cell.withStyle(current_style));
        
        // Calculate text position (center the text)
        const text_len = std.unicode.utf8CountCodepoints(self.text) catch self.text.len;
        const text_x = if (area.width > text_len) 
            area.x + @as(u16, @intCast((area.width - text_len) / 2))
        else 
            area.x;
        const text_y = area.y + area.height / 2;
        
        // Render button text
        if (text_y < area.y + area.height) {
            buffer.writeText(text_x, text_y, self.text, current_style);
        }
        
        // Draw button border (simple box drawing)
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
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Button = @fieldParentPtr("widget", widget);
        
        if (self.is_disabled) return false;

        switch (event) {
            .key => |key| {
                if (self.is_focused) {
                    switch (key) {
                        .enter, .char => |c| {
                            if (key == .enter or c == ' ') {
                                self.click();
                                return true;
                            }
                        },
                        .tab => {
                            self.is_focused = false;
                            return false; // Let focus move to next widget
                        },
                        else => {},
                    }
                }
            },
            .mouse => |mouse| {
                const pos = mouse.position;
                const in_bounds = pos.x >= self.area.x and pos.x < self.area.x + self.area.width and
                                pos.y >= self.area.y and pos.y < self.area.y + self.area.height;
                
                if (in_bounds) {
                    switch (mouse.button) {
                        .left => {
                            if (mouse.pressed) {
                                self.is_pressed = true;
                                self.is_focused = true;
                                return true;
                            } else {
                                if (self.is_pressed) {
                                    self.is_pressed = false;
                                    self.click();
                                    return true;
                                }
                            }
                        },
                        else => {},
                    }
                    
                    if (!self.is_hovered) {
                        self.is_hovered = true;
                        return true;
                    }
                } else {
                    if (self.is_hovered) {
                        self.is_hovered = false;
                        self.is_pressed = false;
                        return true;
                    }
                }
            },
            else => {},
        }

        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *Button = @fieldParentPtr("widget", widget);
        self.area = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *Button = @fieldParentPtr("widget", widget);
        self.allocator.free(self.text);
        self.allocator.destroy(self);
    }
};

// Example callback function
fn exampleCallback(button: *Button) void {
    std.debug.print("Button '{}' clicked!\n", .{button.text});
}

test "Button widget creation" {
    const allocator = std.testing.allocator;

    const button = try Button.init(allocator, "Click me!");
    defer button.widget.deinit();

    try std.testing.expectEqualStrings("Click me!", button.text);
    try std.testing.expect(!button.is_disabled);
    try std.testing.expect(!button.is_focused);
}

test "Button widget text setting" {
    const allocator = std.testing.allocator;

    const button = try Button.init(allocator, "Original");
    defer button.widget.deinit();

    try button.setText("New Text");
    try std.testing.expectEqualStrings("New Text", button.text);
}

test "Button widget state management" {
    const allocator = std.testing.allocator;

    const button = try Button.init(allocator, "Test");
    defer button.widget.deinit();

    button.setDisabled(true);
    try std.testing.expect(button.is_disabled);

    button.setDisabled(false);
    try std.testing.expect(!button.is_disabled);
}