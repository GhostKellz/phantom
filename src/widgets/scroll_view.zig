//! ScrollView widget for scrollable content areas
//! Used for LSP diagnostics, file explorers, long lists, etc.
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

/// Scrollable content container
pub const ScrollView = struct {
    widget: Widget,
    allocator: std.mem.Allocator,

    /// Child widget to scroll
    child: ?*Widget,

    /// Scroll offsets
    scroll_x: u16,
    scroll_y: u16,

    /// Content size (larger than viewport)
    content_width: u16,
    content_height: u16,

    /// Viewport size (visible area)
    viewport_width: u16,
    viewport_height: u16,

    /// Scrollbar visibility
    show_horizontal_scrollbar: bool,
    show_vertical_scrollbar: bool,

    /// Scrollbar styles
    scrollbar_style: Style,
    scrollbar_thumb_style: Style,

    /// Scroll step size
    scroll_step_x: u16,
    scroll_step_y: u16,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*ScrollView {
        const view = try allocator.create(ScrollView);
        view.* = ScrollView{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .child = null,
            .scroll_x = 0,
            .scroll_y = 0,
            .content_width = 0,
            .content_height = 0,
            .viewport_width = 0,
            .viewport_height = 0,
            .show_horizontal_scrollbar = true,
            .show_vertical_scrollbar = true,
            .scrollbar_style = Style.default().withBg(style.Color.bright_black),
            .scrollbar_thumb_style = Style.default().withBg(style.Color.white),
            .scroll_step_x = 4,
            .scroll_step_y = 1,
        };
        return view;
    }

    /// Set the child widget to display
    pub fn setChild(self: *ScrollView, child: *Widget) void {
        self.child = child;
    }

    /// Set content size (for knowing when to scroll)
    pub fn setContentSize(self: *ScrollView, width: u16, height: u16) void {
        self.content_width = width;
        self.content_height = height;
    }

    /// Scroll to specific position
    pub fn scrollTo(self: *ScrollView, x: u16, y: u16) void {
        self.scroll_x = x;
        self.scroll_y = y;
        self.clampScroll();
    }

    /// Scroll by delta
    pub fn scrollBy(self: *ScrollView, delta_x: i32, delta_y: i32) void {
        if (delta_x < 0) {
            const abs_delta = @abs(delta_x);
            if (self.scroll_x >= abs_delta) {
                self.scroll_x -= @intCast(abs_delta);
            } else {
                self.scroll_x = 0;
            }
        } else {
            self.scroll_x +|= @intCast(delta_x);
        }

        if (delta_y < 0) {
            const abs_delta = @abs(delta_y);
            if (self.scroll_y >= abs_delta) {
                self.scroll_y -= @intCast(abs_delta);
            } else {
                self.scroll_y = 0;
            }
        } else {
            self.scroll_y +|= @intCast(delta_y);
        }

        self.clampScroll();
    }

    /// Scroll up
    pub fn scrollUp(self: *ScrollView) void {
        self.scrollBy(0, -@as(i32, self.scroll_step_y));
    }

    /// Scroll down
    pub fn scrollDown(self: *ScrollView) void {
        self.scrollBy(0, @as(i32, self.scroll_step_y));
    }

    /// Scroll left
    pub fn scrollLeft(self: *ScrollView) void {
        self.scrollBy(-@as(i32, self.scroll_step_x), 0);
    }

    /// Scroll right
    pub fn scrollRight(self: *ScrollView) void {
        self.scrollBy(@as(i32, self.scroll_step_x), 0);
    }

    /// Scroll to top
    pub fn scrollToTop(self: *ScrollView) void {
        self.scroll_y = 0;
    }

    /// Scroll to bottom
    pub fn scrollToBottom(self: *ScrollView) void {
        if (self.content_height > self.viewport_height) {
            self.scroll_y = self.content_height - self.viewport_height;
        }
    }

    /// Ensure item at line is visible
    pub fn ensureLineVisible(self: *ScrollView, line: u16) void {
        if (line < self.scroll_y) {
            // Item is above viewport
            self.scroll_y = line;
        } else if (line >= self.scroll_y + self.viewport_height) {
            // Item is below viewport
            if (line >= self.viewport_height) {
                self.scroll_y = line - self.viewport_height + 1;
            } else {
                self.scroll_y = 0;
            }
        }
        self.clampScroll();
    }

    /// Clamp scroll position to valid range
    fn clampScroll(self: *ScrollView) void {
        const max_scroll_x = if (self.content_width > self.viewport_width)
            self.content_width - self.viewport_width
        else
            0;

        const max_scroll_y = if (self.content_height > self.viewport_height)
            self.content_height - self.viewport_height
        else
            0;

        self.scroll_x = @min(self.scroll_x, max_scroll_x);
        self.scroll_y = @min(self.scroll_y, max_scroll_y);
    }

    /// Set scrollbar visibility
    pub fn setScrollbars(self: *ScrollView, horizontal: bool, vertical: bool) void {
        self.show_horizontal_scrollbar = horizontal;
        self.show_vertical_scrollbar = vertical;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *ScrollView = @fieldParentPtr("widget", widget);

        if (area.width == 0 or area.height == 0) return;

        // Update viewport size
        self.viewport_width = area.width;
        self.viewport_height = area.height;

        // Reserve space for scrollbars
        const scrollbar_space_h: u16 = if (self.show_horizontal_scrollbar and self.content_height > area.height) 1 else 0;
        const scrollbar_space_v: u16 = if (self.show_vertical_scrollbar and self.content_width > area.width) 1 else 0;

        const content_area = Rect.init(
            area.x,
            area.y,
            area.width -| scrollbar_space_v,
            area.height -| scrollbar_space_h,
        );

        // Render child widget with scroll offset
        if (self.child) |child| {
            // Create scrolled area (shifted by scroll offset)
            const scrolled_area = Rect.init(
                area.x,
                area.y,
                content_area.width,
                content_area.height,
            );

            child.vtable.render(child, buffer, scrolled_area);
        }

        // Render vertical scrollbar
        if (scrollbar_space_v > 0) {
            self.renderVerticalScrollbar(buffer, area);
        }

        // Render horizontal scrollbar
        if (scrollbar_space_h > 0) {
            self.renderHorizontalScrollbar(buffer, area);
        }
    }

    fn renderVerticalScrollbar(self: *ScrollView, buffer: *Buffer, area: Rect) void {
        const scrollbar_x = area.x + area.width - 1;
        const scrollbar_height = area.height;

        // Draw scrollbar track
        var y: u16 = 0;
        while (y < scrollbar_height) : (y += 1) {
            buffer.setCell(scrollbar_x, area.y + y, Cell.init('│', self.scrollbar_style));
        }

        // Calculate thumb position and size
        if (self.content_height > 0 and scrollbar_height > 2) {
            const thumb_size = @max(1, @min(scrollbar_height,
                (scrollbar_height * scrollbar_height) / self.content_height));

            const max_scroll = if (self.content_height > scrollbar_height)
                self.content_height - scrollbar_height
            else
                1;

            const thumb_pos = if (max_scroll > 0)
                (@as(u32, self.scroll_y) * (@as(u32, scrollbar_height) - thumb_size)) / max_scroll
            else
                0;

            // Draw thumb
            var i: u16 = 0;
            while (i < thumb_size) : (i += 1) {
                const thumb_y = area.y + @as(u16, @intCast(thumb_pos)) + i;
                if (thumb_y < area.y + scrollbar_height) {
                    buffer.setCell(scrollbar_x, thumb_y, Cell.init('█', self.scrollbar_thumb_style));
                }
            }
        }
    }

    fn renderHorizontalScrollbar(self: *ScrollView, buffer: *Buffer, area: Rect) void {
        const scrollbar_y = area.y + area.height - 1;
        const scrollbar_width = area.width;

        // Draw scrollbar track
        var x: u16 = 0;
        while (x < scrollbar_width) : (x += 1) {
            buffer.setCell(area.x + x, scrollbar_y, Cell.init('─', self.scrollbar_style));
        }

        // Calculate thumb position and size
        if (self.content_width > 0 and scrollbar_width > 2) {
            const thumb_size = @max(1, @min(scrollbar_width,
                (scrollbar_width * scrollbar_width) / self.content_width));

            const max_scroll = if (self.content_width > scrollbar_width)
                self.content_width - scrollbar_width
            else
                1;

            const thumb_pos = if (max_scroll > 0)
                (@as(u32, self.scroll_x) * (@as(u32, scrollbar_width) - thumb_size)) / max_scroll
            else
                0;

            // Draw thumb
            var i: u16 = 0;
            while (i < thumb_size) : (i += 1) {
                const thumb_x = area.x + @as(u16, @intCast(thumb_pos)) + i;
                if (thumb_x < area.x + scrollbar_width) {
                    buffer.setCell(thumb_x, scrollbar_y, Cell.init('█', self.scrollbar_thumb_style));
                }
            }
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *ScrollView = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key| {
                switch (key) {
                    .up => {
                        self.scrollUp();
                        return true;
                    },
                    .down => {
                        self.scrollDown();
                        return true;
                    },
                    .left => {
                        self.scrollLeft();
                        return true;
                    },
                    .right => {
                        self.scrollRight();
                        return true;
                    },
                    .page_up => {
                        self.scrollBy(0, -@as(i32, @divTrunc(self.viewport_height, 2)));
                        return true;
                    },
                    .page_down => {
                        self.scrollBy(0, @as(i32, @divTrunc(self.viewport_height, 2)));
                        return true;
                    },
                    .home => {
                        self.scrollToTop();
                        return true;
                    },
                    .end => {
                        self.scrollToBottom();
                        return true;
                    },
                    .char => |c| {
                        switch (c) {
                            'k' => {
                                self.scrollUp();
                                return true;
                            },
                            'j' => {
                                self.scrollDown();
                                return true;
                            },
                            'h' => {
                                self.scrollLeft();
                                return true;
                            },
                            'l' => {
                                self.scrollRight();
                                return true;
                            },
                            'g' => {
                                self.scrollToTop();
                                return true;
                            },
                            'G' => {
                                self.scrollToBottom();
                                return true;
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                if (mouse.button == .wheel_up) {
                    self.scrollBy(0, -3); // Scroll 3 lines
                    return true;
                }
                if (mouse.button == .wheel_down) {
                    self.scrollBy(0, 3); // Scroll 3 lines
                    return true;
                }
                return false;
            },
            else => {},
        }

        // Forward event to child
        if (self.child) |child| {
            return child.vtable.handleEvent(child, event);
        }

        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *ScrollView = @fieldParentPtr("widget", widget);

        self.viewport_width = area.width;
        self.viewport_height = area.height;
        self.clampScroll();

        // Resize child if present
        if (self.child) |child| {
            child.vtable.resize(child, area);
        }
    }

    fn deinit(widget: *Widget) void {
        const self: *ScrollView = @fieldParentPtr("widget", widget);
        self.allocator.destroy(self);
    }
};

test "ScrollView creation" {
    const allocator = std.testing.allocator;

    const view = try ScrollView.init(allocator);
    defer view.widget.vtable.deinit(&view.widget);

    try std.testing.expect(view.scroll_x == 0);
    try std.testing.expect(view.scroll_y == 0);
}

test "ScrollView scrolling" {
    const allocator = std.testing.allocator;

    const view = try ScrollView.init(allocator);
    defer view.widget.vtable.deinit(&view.widget);

    view.setContentSize(100, 100);
    view.viewport_width = 10;
    view.viewport_height = 10;

    view.scrollDown();
    try std.testing.expect(view.scroll_y == 1);

    view.scrollUp();
    try std.testing.expect(view.scroll_y == 0);

    view.scrollToBottom();
    try std.testing.expect(view.scroll_y == 90);

    view.scrollToTop();
    try std.testing.expect(view.scroll_y == 0);
}

test "ScrollView ensure visible" {
    const allocator = std.testing.allocator;

    const view = try ScrollView.init(allocator);
    defer view.widget.vtable.deinit(&view.widget);

    view.setContentSize(100, 100);
    view.viewport_width = 10;
    view.viewport_height = 10;

    // Line 5 should be visible at scroll_y = 0
    view.ensureLineVisible(5);
    try std.testing.expect(view.scroll_y == 0);

    // Line 15 should require scrolling
    view.ensureLineVisible(15);
    try std.testing.expect(view.scroll_y >= 6);
}
