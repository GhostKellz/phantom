//! ListView - Efficient list rendering with virtualization
//! Displays large lists efficiently by only rendering visible items

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;
const Rect = geometry.Rect;
const Style = style.Style;

const ListView = @This();

items: []const ListItem,
selected_index: ?usize = null,
scroll_offset: usize = 0,
item_height: u16 = 1,
show_selection: bool = true,
selection_style: Style,
item_style: Style,
alternate_style: ?Style = null,

pub const ListItem = struct {
    text: []const u8,
    data: ?*anyopaque = null,
    style: ?Style = null,
    selectable: bool = true,
};

/// Create a ListView with items and styling
pub fn init(items: []const ListItem, item_style: Style, selection_style: Style) ListView {
    return ListView{
        .items = items,
        .item_style = item_style,
        .selection_style = selection_style,
    };
}

/// Create a ListView with alternating row colors
pub fn withAlternateStyle(items: []const ListItem, item_style: Style, alternate_style: Style, selection_style: Style) ListView {
    return ListView{
        .items = items,
        .item_style = item_style,
        .alternate_style = alternate_style,
        .selection_style = selection_style,
    };
}

/// Create a ListView with custom item height
pub fn withItemHeight(items: []const ListItem, item_height: u16, item_style: Style, selection_style: Style) ListView {
    return ListView{
        .items = items,
        .item_height = item_height,
        .item_style = item_style,
        .selection_style = selection_style,
    };
}

/// Create a ListView without selection highlighting
pub fn withoutSelection(items: []const ListItem, item_style: Style) ListView {
    return ListView{
        .items = items,
        .show_selection = false,
        .item_style = item_style,
        .selection_style = item_style,
    };
}

/// Get the currently selected item
pub fn getSelectedItem(self: *const ListView) ?ListItem {
    if (self.selected_index) |index| {
        if (index < self.items.len) {
            return self.items[index];
        }
    }
    return null;
}

/// Set the selected index
pub fn setSelectedIndex(self: *ListView, index: ?usize) void {
    if (index) |idx| {
        if (idx < self.items.len) {
            self.selected_index = idx;
            self.ensureVisible(idx);
        }
    } else {
        self.selected_index = null;
    }
}

/// Move selection up
pub fn selectPrevious(self: *ListView) bool {
    if (self.items.len == 0) return false;

    if (self.selected_index) |current| {
        if (current > 0) {
            // Find previous selectable item
            var new_index = current - 1;
            while (true) {
                if (self.items[new_index].selectable) {
                    self.setSelectedIndex(new_index);
                    return true;
                }
                if (new_index == 0) break;
                new_index -= 1;
            }
        }
    } else {
        // Select last selectable item
        var i = self.items.len;
        while (i > 0) {
            i -= 1;
            if (self.items[i].selectable) {
                self.setSelectedIndex(i);
                return true;
            }
        }
    }
    return false;
}

/// Move selection down
pub fn selectNext(self: *ListView) bool {
    if (self.items.len == 0) return false;

    if (self.selected_index) |current| {
        if (current + 1 < self.items.len) {
            // Find next selectable item
            for (self.items[current + 1..], current + 1..) |item, i| {
                if (item.selectable) {
                    self.setSelectedIndex(i);
                    return true;
                }
            }
        }
    } else {
        // Select first selectable item
        for (self.items, 0..) |item, i| {
            if (item.selectable) {
                self.setSelectedIndex(i);
                return true;
            }
        }
    }
    return false;
}

/// Ensure the given index is visible in the viewport
fn ensureVisible(self: *ListView, index: usize) void {
    if (index < self.scroll_offset) {
        self.scroll_offset = index;
    }
    // Note: We'll calculate the max visible items in draw() since we need viewport height
}

/// Calculate the range of visible items for the given viewport
fn getVisibleRange(self: *const ListView, viewport_height: u16) struct { start: usize, end: usize, max_visible: usize } {
    const max_visible = @as(usize, @intCast(viewport_height)) / @as(usize, @intCast(self.item_height));
    const start = self.scroll_offset;
    const end = @min(start + max_visible, self.items.len);
    return .{ .start = start, .end = end, .max_visible = max_visible };
}

/// Scroll to make the selected item visible
pub fn scrollToSelection(self: *ListView, viewport_height: u16) void {
    if (self.selected_index) |selected| {
        const visible = self.getVisibleRange(viewport_height);

        if (selected < self.scroll_offset) {
            self.scroll_offset = selected;
        } else if (selected >= self.scroll_offset + visible.max_visible) {
            self.scroll_offset = if (selected >= visible.max_visible)
                selected - visible.max_visible + 1
            else
                0;
        }
    }
}

/// Scroll by the given amount
pub fn scroll(self: *ListView, delta: i32) void {
    if (delta < 0) {
        const abs_delta = @as(usize, @intCast(-delta));
        self.scroll_offset = if (self.scroll_offset >= abs_delta)
            self.scroll_offset - abs_delta
        else
            0;
    } else {
        const new_offset = self.scroll_offset + @as(usize, @intCast(delta));
        const max_offset = if (self.items.len > 0) self.items.len - 1 else 0;
        self.scroll_offset = @min(new_offset, max_offset);
    }
}

/// Get the widget interface for this ListView
pub fn widget(self: *const ListView) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const ListView = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *ListView = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const ListView, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const width = ctx.getWidth();
    const height = ctx.getHeight();

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(width, height)
    );

    // Calculate visible item range
    const visible = self.getVisibleRange(height);

    // Draw visible items
    var y: u16 = 0;
    for (self.items[visible.start..visible.end], visible.start..) |item, global_index| {
        if (y + self.item_height > height) break;

        // Determine item style
        const is_selected = self.show_selection and self.selected_index == global_index;
        const base_style = if (item.style) |custom_style|
            custom_style
        else if (self.alternate_style != null and global_index % 2 == 1)
            self.alternate_style.?
        else
            self.item_style;

        const final_style = if (is_selected) self.selection_style else base_style;

        // Fill item background
        surface.fillRect(
            Rect.init(0, y, width, self.item_height),
            ' ',
            final_style
        );

        // Draw item text
        _ = surface.writeText(0, y, item.text, final_style);

        y += self.item_height;
    }

    return surface;
}

pub fn handleEvent(self: *ListView, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    switch (ctx.event) {
        .key_press => |key| {
            if (ctx.has_focus) {
                switch (key.key) {
                    .up => {
                        if (self.selectPrevious()) {
                            self.scrollToSelection(@intCast(ctx.bounds.height));
                            try commands.append(.redraw);
                        }
                    },
                    .down => {
                        if (self.selectNext()) {
                            self.scrollToSelection(@intCast(ctx.bounds.height));
                            try commands.append(.redraw);
                        }
                    },
                    .page_up => {
                        const visible = self.getVisibleRange(@intCast(ctx.bounds.height));
                        self.scroll(-@as(i32, @intCast(visible.max_visible)));
                        try commands.append(.redraw);
                    },
                    .page_down => {
                        const visible = self.getVisibleRange(@intCast(ctx.bounds.height));
                        self.scroll(@as(i32, @intCast(visible.max_visible)));
                        try commands.append(.redraw);
                    },
                    .home => {
                        self.scroll_offset = 0;
                        if (self.items.len > 0) {
                            self.setSelectedIndex(0);
                        }
                        try commands.append(.redraw);
                    },
                    .end => {
                        if (self.items.len > 0) {
                            self.setSelectedIndex(self.items.len - 1);
                            self.scrollToSelection(@intCast(ctx.bounds.height));
                        }
                        try commands.append(.redraw);
                    },
                    .enter => {
                        // Could emit a custom "item_selected" command
                        try commands.append(.redraw);
                    },
                    else => {},
                }
            }
        },
        .mouse => |mouse| {
            if (ctx.isMouseEvent() != null) {
                switch (mouse.button) {
                    .wheel_up => {
                        self.scroll(-3);
                        try commands.append(.redraw);
                    },
                    .wheel_down => {
                        self.scroll(3);
                        try commands.append(.redraw);
                    },
                    .left => {
                        if (mouse.action == .press) {
                            if (ctx.getLocalMousePosition()) |local_pos| {
                                const clicked_item = self.scroll_offset +
                                    (@as(usize, @intCast(local_pos.y)) / @as(usize, @intCast(self.item_height)));

                                if (clicked_item < self.items.len and self.items[clicked_item].selectable) {
                                    self.setSelectedIndex(clicked_item);
                                    try commands.append(.redraw);
                                }
                            }
                        }
                    },
                    else => {},
                }
            }
        },
        else => {},
    }

    return commands;
}

test "ListView creation and selection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const items = [_]ListItem{
        .{ .text = "Item 1" },
        .{ .text = "Item 2" },
        .{ .text = "Item 3", .selectable = false },
        .{ .text = "Item 4" },
    };

    var list_view = ListView.init(&items, Style.default(), Style.default().withBg(.blue));

    // Test selection
    try std.testing.expect(list_view.selectNext());
    try std.testing.expectEqual(@as(?usize, 0), list_view.selected_index);

    // Should skip non-selectable item
    try std.testing.expect(list_view.selectNext());
    try std.testing.expectEqual(@as(?usize, 1), list_view.selected_index);

    try std.testing.expect(list_view.selectNext());
    try std.testing.expectEqual(@as(?usize, 3), list_view.selected_index); // Skipped item 2
}

test "ListView visible range calculation" {
    const items = [_]ListItem{
        .{ .text = "Item 1" },
        .{ .text = "Item 2" },
        .{ .text = "Item 3" },
        .{ .text = "Item 4" },
        .{ .text = "Item 5" },
    };

    const list_view = ListView.init(&items, Style.default(), Style.default());
    const visible = list_view.getVisibleRange(3); // 3 lines tall

    try std.testing.expectEqual(@as(usize, 0), visible.start);
    try std.testing.expectEqual(@as(usize, 3), visible.end);
    try std.testing.expectEqual(@as(usize, 3), visible.max_visible);
}