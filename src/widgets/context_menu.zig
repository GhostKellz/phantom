//! Context menu widget for right-click menus
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

/// Context menu item
pub const MenuItem = struct {
    text: []const u8,
    action: MenuAction,
    enabled: bool = true,
    is_separator: bool = false,
    shortcut: ?[]const u8 = null,
    style: Style = Style.default(),
    
    pub const MenuAction = enum {
        copy,
        paste,
        cut,
        delete,
        select_all,
        undo,
        redo,
        find,
        replace,
        save,
        open,
        new,
        close,
        quit,
        custom,
    };
    
    pub fn separator() MenuItem {
        return MenuItem{
            .text = "",
            .action = .custom,
            .is_separator = true,
            .enabled = false,
        };
    }
    
    pub fn init(text: []const u8, action: MenuAction) MenuItem {
        return MenuItem{
            .text = text,
            .action = action,
        };
    }
    
    pub fn withShortcut(text: []const u8, action: MenuAction, shortcut: []const u8) MenuItem {
        return MenuItem{
            .text = text,
            .action = action,
            .shortcut = shortcut,
        };
    }
    
    pub fn withEnabled(text: []const u8, action: MenuAction, enabled: bool) MenuItem {
        return MenuItem{
            .text = text,
            .action = action,
            .enabled = enabled,
        };
    }
};

/// Context menu callback function type
pub const OnMenuActionFn = *const fn (menu: *ContextMenu, action: MenuItem.MenuAction) void;

/// Context menu widget
pub const ContextMenu = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    
    // Items
    items: std.ArrayList(MenuItem),
    selected_index: usize = 0,
    
    // Styling
    item_style: Style,
    selected_style: Style,
    disabled_style: Style,
    separator_style: Style,
    border_style: Style,
    background_style: Style,
    shortcut_style: Style,
    
    // Configuration
    min_width: u16 = 10,
    show_shortcuts: bool = true,
    auto_close: bool = true,
    
    // State
    is_visible: bool = false,
    is_focused: bool = false,
    position: Position = Position.init(0, 0),
    
    // Callbacks
    on_action: ?OnMenuActionFn = null,
    
    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*ContextMenu {
        const menu = try allocator.create(ContextMenu);
        menu.* = ContextMenu{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .items = std.ArrayList(MenuItem){},
            .item_style = Style.default().withFg(style.Color.white).withBg(style.Color.black),
            .selected_style = Style.default().withFg(style.Color.white).withBg(style.Color.blue),
            .disabled_style = Style.default().withFg(style.Color.bright_black).withBg(style.Color.black),
            .separator_style = Style.default().withFg(style.Color.bright_black),
            .border_style = Style.default().withFg(style.Color.bright_blue),
            .background_style = Style.default().withBg(style.Color.black),
            .shortcut_style = Style.default().withFg(style.Color.bright_black).withBg(style.Color.black),
        };
        return menu;
    }

    pub fn addItem(self: *ContextMenu, item: MenuItem) !void {
        var owned_item = item;
        owned_item.text = try self.allocator.dupe(u8, item.text);
        if (item.shortcut) |shortcut| {
            owned_item.shortcut = try self.allocator.dupe(u8, shortcut);
        }
        try self.items.append(self.allocator, owned_item);
    }

    pub fn addSeparator(self: *ContextMenu) !void {
        try self.addItem(MenuItem.separator());
    }

    pub fn clearItems(self: *ContextMenu) void {
        for (self.items.items) |item| {
            self.allocator.free(item.text);
            if (item.shortcut) |shortcut| {
                self.allocator.free(shortcut);
            }
        }
        self.items.clearAndFree();
    }

    pub fn showAt(self: *ContextMenu, position: Position) void {
        self.position = position;
        self.is_visible = true;
        self.is_focused = true;
        self.selected_index = 0;
        
        // Find first enabled item
        self.findNextEnabledItem();
    }

    pub fn hide(self: *ContextMenu) void {
        self.is_visible = false;
        self.is_focused = false;
    }

    pub fn setOnAction(self: *ContextMenu, callback: OnMenuActionFn) void {
        self.on_action = callback;
    }

    pub fn setMinWidth(self: *ContextMenu, width: u16) void {
        self.min_width = width;
    }

    pub fn setShowShortcuts(self: *ContextMenu, show: bool) void {
        self.show_shortcuts = show;
    }

    pub fn setAutoClose(self: *ContextMenu, auto_close: bool) void {
        self.auto_close = auto_close;
    }

    pub fn selectNext(self: *ContextMenu) void {
        if (self.items.items.len == 0) return;
        
        self.selected_index = (self.selected_index + 1) % self.items.items.len;
        self.findNextEnabledItem();
    }

    pub fn selectPrevious(self: *ContextMenu) void {
        if (self.items.items.len == 0) return;
        
        self.selected_index = if (self.selected_index == 0) 
            self.items.items.len - 1 
        else 
            self.selected_index - 1;
        self.findPrevEnabledItem();
    }

    pub fn activateSelected(self: *ContextMenu) void {
        if (self.selected_index < self.items.items.len) {
            const item = self.items.items[self.selected_index];
            if (item.enabled and !item.is_separator) {
                if (self.on_action) |callback| {
                    callback(self, item.action);
                }
                
                if (self.auto_close) {
                    self.hide();
                }
            }
        }
    }

    fn findNextEnabledItem(self: *ContextMenu) void {
        var attempts: usize = 0;
        while (attempts < self.items.items.len) {
            const item = self.items.items[self.selected_index];
            if (item.enabled and !item.is_separator) {
                break;
            }
            self.selected_index = (self.selected_index + 1) % self.items.items.len;
            attempts += 1;
        }
    }

    fn findPrevEnabledItem(self: *ContextMenu) void {
        var attempts: usize = 0;
        while (attempts < self.items.items.len) {
            const item = self.items.items[self.selected_index];
            if (item.enabled and !item.is_separator) {
                break;
            }
            self.selected_index = if (self.selected_index == 0) 
                self.items.items.len - 1 
            else 
                self.selected_index - 1;
            attempts += 1;
        }
    }

    fn calculateSize(self: *ContextMenu) void {
        if (self.items.items.len == 0) {
            self.area = Rect.init(self.position.x, self.position.y, self.min_width, 2);
            return;
        }
        
        var max_width = self.min_width;
        var height: u16 = 2; // Top and bottom border
        
        for (self.items.items) |item| {
            if (item.is_separator) {
                height += 1;
            } else {
                height += 1;
                var item_width = @as(u16, @intCast(item.text.len));
                
                if (self.show_shortcuts and item.shortcut != null) {
                    item_width += @as(u16, @intCast(item.shortcut.?.len + 4)); // Spacing + shortcut
                }
                
                max_width = @max(max_width, item_width + 4); // Text + padding
            }
        }
        
        self.area = Rect.init(self.position.x, self.position.y, max_width, height);
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *ContextMenu = @fieldParentPtr("widget", widget);
        
        if (!self.is_visible) return;
        
        // Calculate menu size
        self.calculateSize();
        
        // Adjust position to fit within available area
        if (self.area.x + self.area.width > area.x + area.width) {
            self.area.x = area.x + area.width - self.area.width;
        }
        if (self.area.y + self.area.height > area.y + area.height) {
            self.area.y = area.y + area.height - self.area.height;
        }
        
        // Ensure menu stays within bounds
        self.area.x = @max(self.area.x, area.x);
        self.area.y = @max(self.area.y, area.y);
        
        // Render background
        buffer.fill(self.area, Cell.withStyle(self.background_style));
        
        // Render border
        self.renderBorder(buffer);
        
        // Render items
        var item_y = self.area.y + 1;
        for (self.items.items, 0..) |item, i| {
            if (item.is_separator) {
                self.renderSeparator(buffer, item_y);
            } else {
                const is_selected = i == self.selected_index;
                self.renderItem(buffer, item, item_y, is_selected);
            }
            item_y += 1;
        }
    }

    fn renderBorder(self: *ContextMenu, buffer: *Buffer) void {
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

    fn renderSeparator(self: *ContextMenu, buffer: *Buffer, y: u16) void {
        const start_x = self.area.x + 1;
        const end_x = self.area.x + self.area.width - 1;
        
        for (start_x..end_x) |x| {
            buffer.setCell(@as(u16, @intCast(x)), y, Cell.init('─', self.separator_style));
        }
        
        // Junction characters
        buffer.setCell(self.area.x, y, Cell.init('├', self.separator_style));
        buffer.setCell(self.area.x + self.area.width - 1, y, Cell.init('┤', self.separator_style));
    }

    fn renderItem(self: *ContextMenu, buffer: *Buffer, item: MenuItem, y: u16, is_selected: bool) void {
        const content_width = self.area.width - 2;
        const text_x = self.area.x + 2;
        
        // Choose style based on state
        var item_style = if (!item.enabled) 
            self.disabled_style 
        else if (is_selected) 
            self.selected_style 
        else 
            self.item_style;
        
        // Fill item background
        buffer.fill(Rect.init(self.area.x + 1, y, content_width, 1), Cell.withStyle(item_style));
        
        // Render item text
        buffer.writeText(text_x, y, item.text, item_style);
        
        // Render shortcut if present
        if (self.show_shortcuts and item.shortcut != null) {
            const shortcut = item.shortcut.?;
            const shortcut_x = self.area.x + self.area.width - @as(u16, @intCast(shortcut.len)) - 2;
            
            var shortcut_style = if (is_selected) 
                self.selected_style 
            else 
                self.shortcut_style;
            
            buffer.writeText(shortcut_x, y, shortcut, shortcut_style);
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *ContextMenu = @fieldParentPtr("widget", widget);
        
        if (!self.is_visible or !self.is_focused) return false;
        
        switch (event) {
            .key => |key| {
                switch (key) {
                    .up => {
                        self.selectPrevious();
                        return true;
                    },
                    .down => {
                        self.selectNext();
                        return true;
                    },
                    .enter => {
                        self.activateSelected();
                        return true;
                    },
                    .escape => {
                        self.hide();
                        return true;
                    },
                    .char => |c| {
                        // Find item that starts with this character
                        for (self.items.items, 0..) |item, i| {
                            if (item.enabled and !item.is_separator and item.text.len > 0) {
                                if (std.ascii.toLower(item.text[0]) == std.ascii.toLower(c)) {
                                    self.selected_index = i;
                                    self.activateSelected();
                                    return true;
                                }
                            }
                        }
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                if (mouse.button == .left and mouse.pressed) {
                    const pos = mouse.position;
                    
                    // Check if click is inside menu
                    if (pos.x >= self.area.x and pos.x < self.area.x + self.area.width and
                        pos.y >= self.area.y and pos.y < self.area.y + self.area.height) {
                        
                        // Find clicked item
                        const item_y = pos.y - (self.area.y + 1);
                        if (item_y < self.items.items.len) {
                            const item = self.items.items[item_y];
                            if (item.enabled and !item.is_separator) {
                                self.selected_index = item_y;
                                self.activateSelected();
                                return true;
                            }
                        }
                    } else {
                        // Click outside menu - close it
                        self.hide();
                        return true;
                    }
                }
            },
            else => {},
        }
        
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *ContextMenu = @fieldParentPtr("widget", widget);
        _ = area;
        
        // Context menu position is set when shown
        // Size is calculated dynamically in render
    }

    fn deinit(widget: *Widget) void {
        const self: *ContextMenu = @fieldParentPtr("widget", widget);
        
        for (self.items.items) |item| {
            self.allocator.free(item.text);
            if (item.shortcut) |shortcut| {
                self.allocator.free(shortcut);
            }
        }
        self.items.deinit(self.allocator);
        
        self.allocator.destroy(self);
    }
};

// Helper function to create a standard context menu
pub fn createStandardContextMenu(allocator: std.mem.Allocator) !*ContextMenu {
    const menu = try ContextMenu.init(allocator);
    
    try menu.addItem(MenuItem.withShortcut("Copy", .copy, "Ctrl+C"));
    try menu.addItem(MenuItem.withShortcut("Paste", .paste, "Ctrl+V"));
    try menu.addItem(MenuItem.withShortcut("Cut", .cut, "Ctrl+X"));
    try menu.addSeparator();
    try menu.addItem(MenuItem.withShortcut("Select All", .select_all, "Ctrl+A"));
    try menu.addSeparator();
    try menu.addItem(MenuItem.withShortcut("Find", .find, "Ctrl+F"));
    try menu.addItem(MenuItem.withShortcut("Replace", .replace, "Ctrl+H"));
    
    return menu;
}

// Helper function to create a file context menu
pub fn createFileContextMenu(allocator: std.mem.Allocator) !*ContextMenu {
    const menu = try ContextMenu.init(allocator);
    
    try menu.addItem(MenuItem.withShortcut("New", .new, "Ctrl+N"));
    try menu.addItem(MenuItem.withShortcut("Open", .open, "Ctrl+O"));
    try menu.addItem(MenuItem.withShortcut("Save", .save, "Ctrl+S"));
    try menu.addSeparator();
    try menu.addItem(MenuItem.withShortcut("Close", .close, "Ctrl+W"));
    try menu.addItem(MenuItem.withShortcut("Quit", .quit, "Ctrl+Q"));
    
    return menu;
}

// Example context menu callback
fn exampleContextMenuCallback(menu: *ContextMenu, action: MenuItem.MenuAction) void {
    switch (action) {
        .copy => std.debug.print("Copy action triggered\n", .{}),
        .paste => std.debug.print("Paste action triggered\n", .{}),
        .cut => std.debug.print("Cut action triggered\n", .{}),
        .delete => std.debug.print("Delete action triggered\n", .{}),
        .select_all => std.debug.print("Select All action triggered\n", .{}),
        .undo => std.debug.print("Undo action triggered\n", .{}),
        .redo => std.debug.print("Redo action triggered\n", .{}),
        .find => std.debug.print("Find action triggered\n", .{}),
        .replace => std.debug.print("Replace action triggered\n", .{}),
        .save => std.debug.print("Save action triggered\n", .{}),
        .open => std.debug.print("Open action triggered\n", .{}),
        .new => std.debug.print("New action triggered\n", .{}),
        .close => std.debug.print("Close action triggered\n", .{}),
        .quit => std.debug.print("Quit action triggered\n", .{}),
        .custom => std.debug.print("Custom action triggered\n", .{}),
    }
    
    _ = menu;
}

test "ContextMenu widget creation" {
    const allocator = std.testing.allocator;

    const menu = try ContextMenu.init(allocator);
    defer menu.widget.deinit();

    try std.testing.expect(menu.items.items.len == 0);
    try std.testing.expect(!menu.is_visible);
}

test "ContextMenu item management" {
    const allocator = std.testing.allocator;

    const menu = try ContextMenu.init(allocator);
    defer menu.widget.deinit();

    try menu.addItem(MenuItem.init("Copy", .copy));
    try menu.addItem(MenuItem.init("Paste", .paste));
    try menu.addSeparator();
    try menu.addItem(MenuItem.init("Cut", .cut));

    try std.testing.expect(menu.items.items.len == 4);
    try std.testing.expectEqualStrings("Copy", menu.items.items[0].text);
    try std.testing.expect(menu.items.items[2].is_separator);
}

test "Standard context menu creation" {
    const allocator = std.testing.allocator;

    const menu = try createStandardContextMenu(allocator);
    defer menu.widget.deinit();

    try std.testing.expect(menu.items.items.len > 0);
}