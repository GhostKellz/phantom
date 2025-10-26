//! Tabs widget for tabbed interfaces
//!
//! Perfect for multi-document editors, settings panels, etc.
const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Event = @import("../event.zig").Event;
const Key = @import("../event.zig").Key;
const Rect = @import("../geometry.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;

/// Tab with label and content widget
pub const Tab = struct {
    label: []const u8,
    widget: *Widget,
    closeable: bool = true,
};

/// Tab bar position
pub const TabBarPosition = enum {
    top,
    bottom,
    left,
    right,
};

/// Tabs widget for tabbed interfaces
pub const Tabs = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    tabs: std.ArrayList(Tab),
    active_index: usize = 0,
    tab_bar_position: TabBarPosition = .top,
    tab_bar_height: u16 = 1,

    // Styling
    active_tab_style: Style,
    inactive_tab_style: Style,
    tab_bar_style: Style,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
        .resize = resize,
    };

    pub fn init(allocator: std.mem.Allocator) !*Tabs {
        const tabs = try allocator.create(Tabs);
        tabs.* = Tabs{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .tabs = .{},
            .active_tab_style = Style.default()
                .withFg(Color.white)
                .withBg(Color.blue)
                .withBold(),
            .inactive_tab_style = Style.default()
                .withFg(Color.bright_black)
                .withBg(Color.black),
            .tab_bar_style = Style.default()
                .withBg(Color.black),
        };
        return tabs;
    }

    /// Add a new tab
    pub fn addTab(self: *Tabs, label: []const u8, content: *Widget) !void {
        try self.tabs.append(self.allocator, Tab{
            .label = label,
            .widget = content,
        });
    }

    /// Add a non-closeable tab
    pub fn addFixedTab(self: *Tabs, label: []const u8, content: *Widget) !void {
        try self.tabs.append(self.allocator, Tab{
            .label = label,
            .widget = content,
            .closeable = false,
        });
    }

    /// Remove a tab by index
    pub fn removeTab(self: *Tabs, index: usize) void {
        if (index >= self.tabs.items.len) return;
        _ = self.tabs.swapRemove(index);

        // Adjust active index if needed
        if (self.tabs.items.len == 0) {
            self.active_index = 0;
        } else if (self.active_index >= self.tabs.items.len) {
            self.active_index = self.tabs.items.len - 1;
        }
    }

    /// Close the currently active tab
    pub fn closeActiveTab(self: *Tabs) void {
        if (self.active_index < self.tabs.items.len) {
            const tab = self.tabs.items[self.active_index];
            if (tab.closeable) {
                self.removeTab(self.active_index);
            }
        }
    }

    /// Switch to next tab
    pub fn nextTab(self: *Tabs) void {
        if (self.tabs.items.len == 0) return;
        self.active_index = (self.active_index + 1) % self.tabs.items.len;
    }

    /// Switch to previous tab
    pub fn prevTab(self: *Tabs) void {
        if (self.tabs.items.len == 0) return;
        if (self.active_index == 0) {
            self.active_index = self.tabs.items.len - 1;
        } else {
            self.active_index -= 1;
        }
    }

    /// Switch to specific tab
    pub fn setActiveTab(self: *Tabs, index: usize) void {
        if (index < self.tabs.items.len) {
            self.active_index = index;
        }
    }

    /// Get currently active tab
    pub fn getActiveTab(self: *Tabs) ?Tab {
        if (self.active_index < self.tabs.items.len) {
            return self.tabs.items[self.active_index];
        }
        return null;
    }

    fn renderTabBar(self: *Tabs, buffer: anytype, area: Rect) void {
        // Clear tab bar area
        var x = area.x;
        const y = area.y;

        // Render each tab label
        for (self.tabs.items, 0..) |tab, i| {
            const is_active = i == self.active_index;
            const tab_style = if (is_active) self.active_tab_style else self.inactive_tab_style;

            // Tab label format: " Label " or " Label [x] "
            const close_marker = if (tab.closeable) " [x]" else "";
            const tab_text = std.fmt.allocPrint(
                self.allocator,
                " {s}{s} ",
                .{ tab.label, close_marker },
            ) catch " ";
            defer self.allocator.free(tab_text);

            // Render tab
            buffer.writeText(x, y, tab_text, tab_style);
            x += @as(u16, @intCast(tab_text.len));

            // Add separator
            if (i < self.tabs.items.len - 1) {
                buffer.writeText(x, y, "|", self.tab_bar_style);
                x += 1;
            }
        }

        // Fill remaining space
        while (x < area.x + area.width) {
            buffer.writeText(x, y, " ", self.tab_bar_style);
            x += 1;
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Tabs = @fieldParentPtr("widget", widget);

        if (self.tabs.items.len == 0) return;

        // Calculate areas for tab bar and content
        const tab_bar_area = switch (self.tab_bar_position) {
            .top => Rect{
                .x = area.x,
                .y = area.y,
                .width = area.width,
                .height = self.tab_bar_height,
            },
            .bottom => Rect{
                .x = area.x,
                .y = area.y + area.height - self.tab_bar_height,
                .width = area.width,
                .height = self.tab_bar_height,
            },
            .left => Rect{
                .x = area.x,
                .y = area.y,
                .width = 20, // Fixed width for left/right tabs
                .height = area.height,
            },
            .right => Rect{
                .x = area.x + area.width - 20,
                .y = area.y,
                .width = 20,
                .height = area.height,
            },
        };

        const content_area = switch (self.tab_bar_position) {
            .top => Rect{
                .x = area.x,
                .y = area.y + self.tab_bar_height,
                .width = area.width,
                .height = if (area.height > self.tab_bar_height) area.height - self.tab_bar_height else 0,
            },
            .bottom => Rect{
                .x = area.x,
                .y = area.y,
                .width = area.width,
                .height = if (area.height > self.tab_bar_height) area.height - self.tab_bar_height else 0,
            },
            .left => Rect{
                .x = area.x + 20,
                .y = area.y,
                .width = if (area.width > 20) area.width - 20 else 0,
                .height = area.height,
            },
            .right => Rect{
                .x = area.x,
                .y = area.y,
                .width = if (area.width > 20) area.width - 20 else 0,
                .height = area.height,
            },
        };

        // Render tab bar
        self.renderTabBar(buffer, tab_bar_area);

        // Render active tab content
        if (self.active_index < self.tabs.items.len) {
            const active_tab = self.tabs.items[self.active_index];
            active_tab.widget.render(buffer, content_area);
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Tabs = @fieldParentPtr("widget", widget);

        // Handle tab navigation keys
        switch (event) {
            .key => |key| {
                switch (key) {
                    // Ctrl+Tab - next tab
                    .tab => {
                        // TODO: Check for ctrl modifier
                        self.nextTab();
                        return true;
                    },
                    // Ctrl+W - close tab
                    .char => |c| {
                        if (c == 'w') {
                            // TODO: Check for ctrl modifier
                            self.closeActiveTab();
                            return true;
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }

        // Forward event to active tab content
        if (self.active_index < self.tabs.items.len) {
            const active_tab = self.tabs.items[self.active_index];
            return active_tab.widget.handleEvent(event);
        }

        return false;
    }

    fn resize(widget: *Widget, new_area: Rect) void {
        const self: *Tabs = @fieldParentPtr("widget", widget);

        // Notify active tab of resize
        if (self.active_index < self.tabs.items.len) {
            const active_tab = self.tabs.items[self.active_index];
            active_tab.widget.resize(new_area);
        }
    }

    fn deinit(widget: *Widget) void {
        const self: *Tabs = @fieldParentPtr("widget", widget);
        self.tabs.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

test "Tabs init and deinit" {
    const allocator = std.testing.allocator;
    const tabs = try Tabs.init(allocator);
    defer tabs.widget.deinit();

    try std.testing.expect(tabs.tabs.items.len == 0);
    try std.testing.expect(tabs.active_index == 0);
}

test "Tabs navigation" {
    const allocator = std.testing.allocator;
    const tabs = try Tabs.init(allocator);
    defer tabs.widget.deinit();

    // Navigation on empty tabs should not crash
    tabs.nextTab();
    tabs.prevTab();
}
