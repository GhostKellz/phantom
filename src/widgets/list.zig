//! List widget for displaying selectable items
const std = @import("std");
const ArrayList = std.array_list.Managed;
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const Key = @import("../event.zig").Key;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// List item structure
pub const ListItem = struct {
    text: []const u8,
    style: Style = Style.default(),

    pub fn init(text: []const u8) ListItem {
        return ListItem{ .text = text };
    }

    pub fn withStyle(text: []const u8, item_style: Style) ListItem {
        return ListItem{ .text = text, .style = item_style };
    }
};

/// List widget for displaying selectable items
pub const List = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    items: ArrayList(ListItem),
    selected_index: ?usize,
    scroll_offset: usize,
    item_style: Style,
    selected_style: Style,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*List {
        const list = try allocator.create(List);
        list.* = List{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .items = ArrayList(ListItem).init(allocator),
            .selected_index = null,
            .scroll_offset = 0,
            .item_style = Style.default(),
            .selected_style = Style.default().withBg(style.Color.blue),
        };
        return list;
    }

    pub fn addItem(self: *List, item: ListItem) !void {
        try self.items.append(item);

        // Select first item if none selected
        if (self.selected_index == null and self.items.items.len > 0) {
            self.selected_index = 0;
        }
    }

    pub fn addItems(self: *List, items: []const ListItem) !void {
        for (items) |item| {
            try self.addItem(item);
        }
    }

    pub fn addItemText(self: *List, text: []const u8) !void {
        const owned_text = try self.allocator.dupe(u8, text);
        try self.addItem(ListItem.init(owned_text));
    }

    pub fn clear(self: *List) void {
        // Free owned strings
        for (self.items.items) |item| {
            self.allocator.free(item.text);
        }
        self.items.clearRetainingCapacity(); // Keep capacity, items are now empty
        self.selected_index = null;
        self.scroll_offset = 0;
    }

    pub fn selectNext(self: *List) void {
        if (self.items.items.len == 0) return;

        if (self.selected_index) |idx| {
            if (idx + 1 < self.items.items.len) {
                self.selected_index = idx + 1;
            }
        } else {
            self.selected_index = 0;
        }
    }

    pub fn selectPrevious(self: *List) void {
        if (self.items.items.len == 0) return;

        if (self.selected_index) |idx| {
            if (idx > 0) {
                self.selected_index = idx - 1;
            }
        } else {
            self.selected_index = 0;
        }
    }

    pub fn getSelectedItem(self: *const List) ?ListItem {
        if (self.selected_index) |idx| {
            if (idx < self.items.items.len) {
                return self.items.items[idx];
            }
        }
        return null;
    }

    pub fn setItemStyle(self: *List, item_style: Style) void {
        self.item_style = item_style;
    }

    pub fn setSelectedStyle(self: *List, selected_style: Style) void {
        self.selected_style = selected_style;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *List = @fieldParentPtr("widget", widget);

        if (area.height == 0 or area.width == 0) return;

        // Adjust scroll offset to keep selected item visible
        if (self.selected_index) |selected| {
            if (selected < self.scroll_offset) {
                self.scroll_offset = selected;
            } else if (selected >= self.scroll_offset + area.height) {
                self.scroll_offset = selected - area.height + 1;
            }
        }

        // Render visible items
        var y: u16 = 0;
        while (y < area.height and self.scroll_offset + y < self.items.items.len) : (y += 1) {
            const item_index = self.scroll_offset + y;
            const item = self.items.items[item_index];

            // Determine style for this item
            const item_style = if (self.selected_index == item_index)
                self.selected_style
            else
                self.item_style;

            // Fill the entire row with the background color
            buffer.fill(Rect.init(area.x, area.y + y, area.width, 1), Cell.withStyle(item_style));

            // Render item text
            buffer.writeText(area.x, area.y + y, item.text, item_style);
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *List = @fieldParentPtr("widget", widget);

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
                    .char => |c| {
                        switch (c) {
                            'j' => {
                                self.selectNext();
                                return true;
                            },
                            'k' => {
                                self.selectPrevious();
                                return true;
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }

        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        _ = widget;
        _ = area;
        // List widget doesn't need special resize handling
    }

    fn deinit(widget: *Widget) void {
        const self: *List = @fieldParentPtr("widget", widget);

        // Free all item texts
        for (self.items.items) |item| {
            self.allocator.free(item.text);
        }

        self.items.deinit();
        self.allocator.destroy(self);
    }
};

test "List widget creation" {
    const allocator = std.testing.allocator;

    const list = try List.init(allocator);
    defer list.widget.deinit();

    try std.testing.expect(list.items.items.len == 0);
    try std.testing.expect(list.selected_index == null);
}

test "List widget item management" {
    const allocator = std.testing.allocator;

    const list = try List.init(allocator);
    defer list.widget.deinit();

    try list.addItemText("Item 1");
    try list.addItemText("Item 2");
    try list.addItemText("Item 3");

    try std.testing.expect(list.items.items.len == 3);
    try std.testing.expect(list.selected_index.? == 0);

    list.selectNext();
    try std.testing.expect(list.selected_index.? == 1);

    list.selectPrevious();
    try std.testing.expect(list.selected_index.? == 0);
}
