//! Tabs widget for tabbed interfaces
//!
//! Perfect for multi-document editors, settings panels, etc.
const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
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
    pub const State = struct {
        active_index: usize = 0,
        visible_start: usize = 0,
    };

    widget: Widget,
    allocator: std.mem.Allocator,
    tabs: std.ArrayList(Tab),
    active_index: usize = 0,
    visible_start: usize = 0,
    tab_bar_position: TabBarPosition = .top,
    tab_bar_height: u16 = 1,
    tab_bar_width: u16 = 20,

    // Styling
    active_tab_style: Style,
    inactive_tab_style: Style,
    tab_bar_style: Style,
    is_focused: bool = false,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
        .resize = resize,
        .canFocus = canFocus,
        .focus = focusWidget,
        .blur = blurWidget,
    };

    pub fn init(allocator: std.mem.Allocator) !*Tabs {
        const tabs = try allocator.create(Tabs);
        tabs.* = Tabs{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .tabs = .empty,
            .active_tab_style = Style.default()
                .withFg(Color.white)
                .withBg(Color.blue)
                .withBold(),
            .inactive_tab_style = Style.default()
                .withFg(Color.bright_black)
                .withBg(Color.black),
            .tab_bar_style = Style.default()
                .withBg(Color.black),
            .is_focused = false,
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

    pub fn state(self: *const Tabs) State {
        return .{ .active_index = self.active_index, .visible_start = self.visible_start };
    }

    pub fn applyState(self: *Tabs, new_state: State) void {
        self.visible_start = new_state.visible_start;
        self.setActiveTab(new_state.active_index);
    }

    pub fn setTabBarWidth(self: *Tabs, width: u16) void {
        self.tab_bar_width = @max(@as(u16, 1), width);
    }

    fn renderTabBar(self: *Tabs, buffer: anytype, area: Rect) void {
        buffer.fill(area, Cell.withStyle(self.tab_bar_style));
        if (area.width == 0 or self.tabs.items.len == 0) return;

        self.ensureVisibleWindow(area.width);

        var x = area.x;
        const y = area.y;
        const right_edge = area.x + area.width;
        const show_left_overflow = self.visible_start > 0;
        const visible_end = self.computeVisibleEnd(area.width);
        const show_right_overflow = visible_end < self.tabs.items.len;

        if (show_left_overflow and x < right_edge) {
            buffer.writeText(x, y, "<", self.tab_bar_style.withFg(Color.bright_black));
            x += 1;
        }

        var i = self.visible_start;
        while (i < visible_end and x < right_edge) : (i += 1) {
            const tab = self.tabs.items[i];
            const is_active = i == self.active_index;
            const tab_style = if (is_active)
                if (self.is_focused) self.active_tab_style else self.active_tab_style.withBg(Color.bright_black)
            else
                self.inactive_tab_style;

            const owned_tab_text = self.tabLabel(tab) catch null;
            const tab_text = owned_tab_text orelse " ";
            defer if (owned_tab_text) |value| self.allocator.free(value);

            const available = right_edge - x - @as(u16, if (show_right_overflow) 1 else 0);
            if (available == 0) break;

            const render_len = @min(@as(u16, @intCast(tab_text.len)), available);
            if (render_len == 0) break;
            buffer.writeText(x, y, tab_text[0..render_len], tab_style);
            x += render_len;

            if (i + 1 < visible_end and x < right_edge - @as(u16, if (show_right_overflow) 1 else 0)) {
                buffer.writeText(x, y, "|", self.tab_bar_style);
                x += 1;
            }
        }

        if (show_right_overflow and x < right_edge) {
            buffer.writeText(right_edge - 1, y, ">", self.tab_bar_style.withFg(Color.bright_black));
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
                .width = @min(self.tab_bar_width, area.width),
                .height = area.height,
            },
            .right => Rect{
                .x = area.x + area.width - @min(self.tab_bar_width, area.width),
                .y = area.y,
                .width = @min(self.tab_bar_width, area.width),
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
                .x = area.x + @min(self.tab_bar_width, area.width),
                .y = area.y,
                .width = if (area.width > self.tab_bar_width) area.width - self.tab_bar_width else 0,
                .height = area.height,
            },
            .right => Rect{
                .x = area.x,
                .y = area.y,
                .width = if (area.width > self.tab_bar_width) area.width - self.tab_bar_width else 0,
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
                    .tab => {
                        self.nextTab();
                        return true;
                    },
                    .shift_tab => {
                        self.prevTab();
                        return true;
                    },
                    .left => {
                        self.prevTab();
                        return true;
                    },
                    .right => {
                        self.nextTab();
                        return true;
                    },
                    .home => {
                        self.setActiveTab(0);
                        return true;
                    },
                    .end => {
                        if (self.tabs.items.len > 0) {
                            self.setActiveTab(self.tabs.items.len - 1);
                        }
                        return true;
                    },
                    .ctrl_w => {
                        self.closeActiveTab();
                        return true;
                    },
                    .char => |c| {
                        if (c >= '1' and c <= '9') {
                            self.setActiveTab(@as(usize, c - '1'));
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
        if (self.tab_bar_position == .top or self.tab_bar_position == .bottom) {
            self.ensureVisibleWindow(new_area.width);
        }

        // Notify active tab of resize
        if (self.active_index < self.tabs.items.len) {
            const active_tab = self.tabs.items[self.active_index];
            active_tab.widget.resize(new_area);
        }
    }

    fn canFocus(widget: *Widget) bool {
        const self: *Tabs = @fieldParentPtr("widget", widget);
        return self.tabs.items.len > 0;
    }

    fn focusWidget(widget: *Widget) void {
        const self: *Tabs = @fieldParentPtr("widget", widget);
        self.is_focused = true;
    }

    fn blurWidget(widget: *Widget) void {
        const self: *Tabs = @fieldParentPtr("widget", widget);
        self.is_focused = false;
    }

    fn deinit(widget: *Widget) void {
        const self: *Tabs = @fieldParentPtr("widget", widget);
        self.tabs.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    fn tabLabel(self: *Tabs, tab: Tab) ![]u8 {
        const close_marker = if (tab.closeable) " [x]" else "";
        return std.fmt.allocPrint(self.allocator, " {s}{s} ", .{ tab.label, close_marker });
    }

    fn tabRenderWidth(self: *Tabs, index: usize) usize {
        if (index >= self.tabs.items.len) return 0;
        const tab = self.tabs.items[index];
        const extra: usize = if (tab.closeable) 6 else 2;
        return tab.label.len + extra;
    }

    fn windowReservedWidth(self: *Tabs, area_width: u16) usize {
        _ = self;
        if (area_width == 0) return 0;
        return 2;
    }

    fn computeVisibleEnd(self: *Tabs, area_width: u16) usize {
        if (self.tabs.items.len == 0 or area_width == 0) return self.visible_start;
        const reserved = self.windowReservedWidth(area_width);
        const budget = @as(usize, area_width) -| reserved;
        var used: usize = 0;
        var index = self.visible_start;
        while (index < self.tabs.items.len) : (index += 1) {
            const separator: usize = if (index > self.visible_start) 1 else 0;
            const needed = self.tabRenderWidth(index) + separator;
            if (used > 0 and used + needed > budget) break;
            if (used == 0 and needed > budget and budget > 0) {
                return index + 1;
            }
            if (needed > budget and budget == 0) break;
            used += needed;
        }
        return if (index == self.visible_start and self.visible_start < self.tabs.items.len) self.visible_start + 1 else index;
    }

    fn ensureVisibleWindow(self: *Tabs, area_width: u16) void {
        if (self.tabs.items.len == 0) {
            self.visible_start = 0;
            return;
        }
        if (self.visible_start >= self.tabs.items.len) {
            self.visible_start = self.tabs.items.len - 1;
        }
        if (self.active_index < self.visible_start) {
            self.visible_start = self.active_index;
        }

        while (true) {
            const visible_end = self.computeVisibleEnd(area_width);
            if (self.active_index < visible_end) break;
            if (self.visible_start >= self.active_index) break;
            self.visible_start += 1;
        }

        while (self.visible_start > 0) {
            const previous_start = self.visible_start - 1;
            const current_start = self.visible_start;
            self.visible_start = previous_start;
            const visible_end = self.computeVisibleEnd(area_width);
            if (self.active_index >= visible_end) {
                self.visible_start = current_start;
                break;
            }
            if (visible_end == self.tabs.items.len) continue;
            if (current_start == previous_start) break;
        }
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

test "Tabs window keeps active tab visible when overflowing" {
    const allocator = std.testing.allocator;
    const tabs = try Tabs.init(allocator);
    defer tabs.widget.deinit();

    const Dummy = struct {
        widget: Widget,
        const dummy_vtable = Widget.WidgetVTable{
            .render = render,
            .deinit = deinit,
        };

        fn init() @This() {
            return .{ .widget = .{ .vtable = &dummy_vtable } };
        }

        fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
            _ = widget;
            _ = buffer;
            _ = area;
        }

        fn deinit(widget: *Widget) void {
            _ = widget;
        }
    };

    var dummy = Dummy.init();
    inline for (.{ "alpha", "beta", "gamma", "delta", "epsilon" }) |label| {
        try tabs.addFixedTab(label, &dummy.widget);
    }

    tabs.setActiveTab(4);
    var buffer = try Buffer.init(allocator, .{ .width = 18, .height = 2 });
    defer buffer.deinit();
    tabs.widget.render(&buffer, Rect.init(0, 0, 18, 2));

    try std.testing.expect(tabs.visible_start > 0);
    try std.testing.expectEqual('<', buffer.getCell(0, 0).?.char);
}
