//! ListView widget with virtualization for efficient large list rendering
//! Perfect for LSP completion menus, file lists, diagnostic lists, etc.
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const Key = @import("../event.zig").Key;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// List item with rich content
pub const ListViewItem = struct {
    text: []const u8,
    secondary_text: ?[]const u8 = null,  // Right-aligned secondary text
    icon: ?u21 = null,                    // Optional icon/glyph
    metadata: ?*anyopaque = null,         // User data
    style: Style = Style.default(),
};

/// Render function for custom list items
pub const RenderFn = *const fn (
    buffer: *Buffer,
    area: Rect,
    item: *const ListViewItem,
    selected: bool,
    hovered: bool,
) void;

/// ListView with virtualization - only renders visible items
pub const ListView = struct {
    widget: Widget,
    allocator: std.mem.Allocator,

    /// All items (can be millions)
    items: std.ArrayList(ListViewItem),

    /// Selected index
    selected_index: ?usize,

    /// Hovered index (for mouse)
    hovered_index: ?usize,

    /// Scroll offset (first visible item)
    scroll_offset: usize,

    /// Styles
    item_style: Style,
    selected_style: Style,
    hovered_style: Style,
    icon_style: Style,
    secondary_style: Style,

    /// Virtualization settings
    viewport_height: u16,
    item_height: u16 = 1,  // Lines per item

    /// Custom render function (optional)
    custom_render: ?RenderFn = null,

    /// Filter/search
    filter: ?[]const u8 = null,
    filtered_indices: ?std.ArrayList(usize) = null,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*ListView {
        const list = try allocator.create(ListView);
        list.* = ListView{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .items = .{},
            .selected_index = null,
            .hovered_index = null,
            .scroll_offset = 0,
            .item_style = Style.default(),
            .selected_style = Style.default().withBg(style.Color.blue),
            .hovered_style = Style.default().withBg(style.Color.bright_black),
            .icon_style = Style.default().withFg(style.Color.bright_cyan),
            .secondary_style = Style.default().withFg(style.Color.bright_black),
            .viewport_height = 10,
        };
        return list;
    }

    pub fn addItem(self: *ListView, item: ListViewItem) !void {
        try self.items.append(self.allocator, item);

        // Select first item if none selected
        if (self.selected_index == null and self.items.items.len > 0) {
            self.selected_index = 0;
        }
    }

    pub fn addItemText(self: *ListView, text: []const u8) !void {
        const owned_text = try self.allocator.dupe(u8, text);
        try self.addItem(ListViewItem{ .text = owned_text });
    }

    pub fn addItemWithIcon(self: *ListView, text: []const u8, icon: u21) !void {
        const owned_text = try self.allocator.dupe(u8, text);
        try self.addItem(ListViewItem{ .text = owned_text, .icon = icon });
    }

    pub fn clear(self: *ListView) void {
        // Free owned strings
        for (self.items.items) |item| {
            self.allocator.free(item.text);
            if (item.secondary_text) |sec| {
                self.allocator.free(sec);
            }
        }
        self.items.clearAndFree(self.allocator);
        self.selected_index = null;
        self.hovered_index = null;
        self.scroll_offset = 0;

        // Clear filter
        if (self.filter) |f| {
            self.allocator.free(f);
            self.filter = null;
        }
        if (self.filtered_indices) |*fi| {
            fi.deinit(self.allocator);
            self.filtered_indices = null;
        }
    }

    pub fn selectNext(self: *ListView) void {
        const item_count = self.getVisibleItemCount();
        if (item_count == 0) return;

        if (self.selected_index) |idx| {
            if (idx + 1 < item_count) {
                self.selected_index = idx + 1;
            }
        } else {
            self.selected_index = 0;
        }

        self.ensureSelectedVisible();
    }

    pub fn selectPrevious(self: *ListView) void {
        const item_count = self.getVisibleItemCount();
        if (item_count == 0) return;

        if (self.selected_index) |idx| {
            if (idx > 0) {
                self.selected_index = idx - 1;
            }
        } else {
            self.selected_index = 0;
        }

        self.ensureSelectedVisible();
    }

    pub fn selectFirst(self: *ListView) void {
        if (self.getVisibleItemCount() > 0) {
            self.selected_index = 0;
            self.scroll_offset = 0;
        }
    }

    pub fn selectLast(self: *ListView) void {
        const item_count = self.getVisibleItemCount();
        if (item_count > 0) {
            self.selected_index = item_count - 1;
            self.ensureSelectedVisible();
        }
    }

    pub fn getSelectedItem(self: *const ListView) ?*const ListViewItem {
        if (self.selected_index) |idx| {
            return self.getVisibleItem(idx);
        }
        return null;
    }

    pub fn setFilter(self: *ListView, filter: []const u8) !void {
        // Free old filter
        if (self.filter) |old| {
            self.allocator.free(old);
        }

        if (filter.len == 0) {
            self.filter = null;
            if (self.filtered_indices) |*fi| {
                fi.deinit(self.allocator);
                self.filtered_indices = null;
            }
            return;
        }

        self.filter = try self.allocator.dupe(u8, filter);

        // Build filtered indices
        if (self.filtered_indices == null) {
            self.filtered_indices = .{};
        } else {
            self.filtered_indices.?.clearRetainingCapacity();
        }

        for (self.items.items, 0..) |item, i| {
            if (std.mem.indexOf(u8, item.text, filter) != null) {
                try self.filtered_indices.?.append(self.allocator, i);
            }
        }

        // Reset selection
        if (self.getVisibleItemCount() > 0) {
            self.selected_index = 0;
            self.scroll_offset = 0;
        } else {
            self.selected_index = null;
        }
    }

    fn getVisibleItemCount(self: *const ListView) usize {
        if (self.filtered_indices) |fi| {
            return fi.items.len;
        }
        return self.items.items.len;
    }

    fn getVisibleItem(self: *const ListView, index: usize) ?*const ListViewItem {
        if (self.filtered_indices) |fi| {
            if (index >= fi.items.len) return null;
            const real_index = fi.items[index];
            if (real_index >= self.items.items.len) return null;
            return &self.items.items[real_index];
        }

        if (index >= self.items.items.len) return null;
        return &self.items.items[index];
    }

    fn ensureSelectedVisible(self: *ListView) void {
        if (self.selected_index) |selected| {
            // Calculate visible range
            const visible_count = self.viewport_height / self.item_height;

            if (selected < self.scroll_offset) {
                // Selected item is above viewport
                self.scroll_offset = selected;
            } else if (selected >= self.scroll_offset + visible_count) {
                // Selected item is below viewport
                self.scroll_offset = selected -| (visible_count - 1);
            }
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *ListView = @fieldParentPtr("widget", widget);

        if (area.height == 0 or area.width == 0) return;

        self.viewport_height = area.height;

        const item_count = self.getVisibleItemCount();
        if (item_count == 0) {
            // Render "No items" message
            const msg = if (self.filter != null) "No matches" else "No items";
            buffer.writeText(area.x, area.y, msg, Style.default().withFg(style.Color.bright_black));
            return;
        }

        // Calculate visible range (virtualization!)
        const visible_count = area.height / self.item_height;
        const end_index = @min(self.scroll_offset + visible_count, item_count);

        // Render only visible items
        var y: u16 = 0;
        var item_index = self.scroll_offset;
        while (item_index < end_index) : (item_index += 1) {
            const item = self.getVisibleItem(item_index) orelse continue;

            const is_selected = self.selected_index == item_index;
            const is_hovered = self.hovered_index == item_index;

            const item_area = Rect.init(area.x, area.y + y, area.width, self.item_height);

            if (self.custom_render) |render_fn| {
                render_fn(buffer, item_area, item, is_selected, is_hovered);
            } else {
                self.renderDefaultItem(buffer, item_area, item, is_selected, is_hovered);
            }

            y += self.item_height;
        }
    }

    fn renderDefaultItem(
        self: *ListView,
        buffer: *Buffer,
        area: Rect,
        item: *const ListViewItem,
        selected: bool,
        hovered: bool,
    ) void {
        // Determine background style
        const bg_style = if (selected)
            self.selected_style
        else if (hovered)
            self.hovered_style
        else
            self.item_style;

        // Fill background
        buffer.fill(area, Cell.withStyle(bg_style));

        var x = area.x;

        // Render icon if present
        if (item.icon) |icon| {
            buffer.setCell(x, area.y, Cell.init(icon, self.icon_style));
            x += 2; // Icon + space
        }

        // Render main text
        buffer.writeText(x, area.y, item.text, bg_style);

        // Render secondary text (right-aligned) if present
        if (item.secondary_text) |sec_text| {
            if (sec_text.len < area.width) {
                const sec_x = area.x + area.width - @as(u16, @intCast(sec_text.len));
                buffer.writeText(sec_x, area.y, sec_text, self.secondary_style);
            }
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *ListView = @fieldParentPtr("widget", widget);

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
                    .home => {
                        self.selectFirst();
                        return true;
                    },
                    .end => {
                        self.selectLast();
                        return true;
                    },
                    .page_up => {
                        const page_size = self.viewport_height / self.item_height;
                        var i: usize = 0;
                        while (i < page_size) : (i += 1) {
                            self.selectPrevious();
                        }
                        return true;
                    },
                    .page_down => {
                        const page_size = self.viewport_height / self.item_height;
                        var i: usize = 0;
                        while (i < page_size) : (i += 1) {
                            self.selectNext();
                        }
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
                            'g' => {
                                self.selectFirst();
                                return true;
                            },
                            'G' => {
                                self.selectLast();
                                return true;
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                // Handle scroll events
                if (mouse.button == .wheel_up) {
                    self.selectPrevious();
                    return true;
                }
                if (mouse.button == .wheel_down) {
                    self.selectNext();
                    return true;
                }
                return false;
            },
            else => {},
        }

        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *ListView = @fieldParentPtr("widget", widget);
        self.viewport_height = area.height;
        self.ensureSelectedVisible();
    }

    fn deinit(widget: *Widget) void {
        const self: *ListView = @fieldParentPtr("widget", widget);

        self.clear();

        if (self.filtered_indices) |*fi| {
            fi.deinit(self.allocator);
        }

        self.items.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

test "ListView creation" {
    const allocator = std.testing.allocator;

    const list = try ListView.init(allocator);
    defer list.widget.vtable.deinit(&list.widget);

    try std.testing.expect(list.items.items.len == 0);
}

test "ListView virtualization" {
    const allocator = std.testing.allocator;

    const list = try ListView.init(allocator);
    defer list.widget.vtable.deinit(&list.widget);

    // Add 1000 items
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const text = try std.fmt.allocPrint(allocator, "Item {d}", .{i});
        try list.addItem(ListViewItem{ .text = text });
    }

    try std.testing.expect(list.items.items.len == 1000);
    try std.testing.expect(list.selected_index.? == 0);
}

test "ListView filtering" {
    const allocator = std.testing.allocator;

    const list = try ListView.init(allocator);
    defer list.widget.vtable.deinit(&list.widget);

    try list.addItemText("apple");
    try list.addItemText("banana");
    try list.addItemText("apricot");

    // Filter for "ap"
    try list.setFilter("ap");

    try std.testing.expect(list.getVisibleItemCount() == 2);
}
