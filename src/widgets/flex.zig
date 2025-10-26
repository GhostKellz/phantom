//! Flexible layout system for modern UI composition
//! FlexRow and FlexColumn allow responsive, constraint-based layouts
const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Flex alignment options
pub const Alignment = enum {
    start,    // Align to start (left/top)
    center,   // Center alignment
    end,      // Align to end (right/bottom)
    stretch,  // Stretch to fill
};

/// Flex justify (spacing) options
pub const Justify = enum {
    start,          // Pack to start
    end,            // Pack to end
    center,         // Center items
    space_between,  // Space between items
    space_around,   // Space around items
    space_evenly,   // Space evenly
};

/// Flex child with sizing constraints
pub const FlexChild = struct {
    widget: *Widget,
    flex_grow: f32 = 1.0,      // How much to grow (0 = fixed size)
    flex_shrink: f32 = 1.0,    // How much to shrink
    flex_basis: ?u16 = null,   // Base size (null = auto)
    min_size: ?u16 = null,     // Minimum size
    max_size: ?u16 = null,     // Maximum size
};

/// FlexRow - Horizontal flexible layout
pub const FlexRow = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    children: std.ArrayList(FlexChild),
    gap: u16 = 0,                      // Gap between items
    alignment: Alignment = .start,      // Vertical alignment
    justify: Justify = .start,          // Horizontal distribution
    padding_x: u16 = 0,
    padding_y: u16 = 0,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*FlexRow {
        const row = try allocator.create(FlexRow);
        row.* = .{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .children = .{},
        };
        return row;
    }

    pub fn addChild(self: *FlexRow, child: FlexChild) !void {
        try self.children.append(self.allocator, child);
    }

    pub fn addChildWidget(self: *FlexRow, widget_ptr: *Widget) !void {
        try self.addChild(FlexChild{ .widget = widget_ptr });
    }

    pub fn setGap(self: *FlexRow, gap: u16) void {
        self.gap = gap;
    }

    pub fn setAlignment(self: *FlexRow, alignment: Alignment) void {
        self.alignment = alignment;
    }

    pub fn setJustify(self: *FlexRow, justify: Justify) void {
        self.justify = justify;
    }

    pub fn setPadding(self: *FlexRow, padding_x: u16, padding_y: u16) void {
        self.padding_x = padding_x;
        self.padding_y = padding_y;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *FlexRow = @fieldParentPtr("widget", widget);

        if (area.width == 0 or area.height == 0 or self.children.items.len == 0) return;

        // Account for padding
        const inner_area = Rect.init(
            area.x + self.padding_x,
            area.y + self.padding_y,
            area.width -| (self.padding_x * 2),
            area.height -| (self.padding_y * 2),
        );

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Calculate child widths
        const widths = self.calculateChildWidths(inner_area.width);
        defer self.allocator.free(widths);

        // Calculate starting x based on justify
        var x_offset = inner_area.x;
        const total_width = calculateTotalWidth(widths, self.gap);
        const extra_space = if (total_width < inner_area.width) inner_area.width - total_width else 0;

        switch (self.justify) {
            .start => {},
            .end => x_offset += extra_space,
            .center => x_offset += extra_space / 2,
            .space_between, .space_around, .space_evenly => {},
        }

        // Render children
        for (self.children.items, 0..) |child, i| {
            const child_width = widths[i];
            if (child_width == 0) continue;

            // Calculate y offset based on alignment
            const y_offset = inner_area.y;
            const child_height = inner_area.height;

            // For now, children use full height (can be refined later)
            const child_area = Rect.init(x_offset, y_offset, child_width, child_height);
            child.widget.vtable.render(child.widget, buffer, child_area);

            // Move to next position
            x_offset += child_width;

            // Add gap if not last item
            if (i < self.children.items.len - 1) {
                x_offset += self.gap;

                // Add extra space for space-between/around/evenly
                switch (self.justify) {
                    .space_between => {
                        if (self.children.items.len > 1) {
                            x_offset += @intCast(extra_space / (self.children.items.len - 1));
                        }
                    },
                    .space_around => {
                        x_offset += @intCast(extra_space / self.children.items.len);
                    },
                    .space_evenly => {
                        x_offset += @intCast(extra_space / (self.children.items.len + 1));
                    },
                    else => {},
                }
            }
        }
    }

    fn calculateChildWidths(self: *FlexRow, available_width: u16) []u16 {
        const widths = self.allocator.alloc(u16, self.children.items.len) catch return &[_]u16{};

        // Calculate gaps
        const total_gaps = if (self.children.items.len > 1)
            self.gap * @as(u16, @intCast(self.children.items.len - 1))
        else
            0;

        var remaining_width = if (available_width > total_gaps) available_width - total_gaps else 0;

        // First pass: calculate fixed sizes
        var total_flex: f32 = 0;
        for (self.children.items, 0..) |child, i| {
            if (child.flex_grow == 0 and child.flex_basis != null) {
                widths[i] = child.flex_basis.?;
                remaining_width -|= widths[i];
            } else {
                total_flex += child.flex_grow;
            }
        }

        // Second pass: distribute remaining space
        if (total_flex > 0 and remaining_width > 0) {
            for (self.children.items, 0..) |child, i| {
                if (child.flex_grow > 0) {
                    const flex_width = @as(u16, @intFromFloat(
                        @as(f32, @floatFromInt(remaining_width)) * (child.flex_grow / total_flex)
                    ));

                    // Apply min/max constraints
                    var final_width = flex_width;
                    if (child.min_size) |min| final_width = @max(final_width, min);
                    if (child.max_size) |max| final_width = @min(final_width, max);

                    widths[i] = final_width;
                }
            }
        }

        return widths;
    }

    fn calculateTotalWidth(widths: []const u16, gap: u16) u16 {
        var total: u16 = 0;
        for (widths) |w| {
            total +|= w;
        }
        if (widths.len > 1) {
            total +|= gap * @as(u16, @intCast(widths.len - 1));
        }
        return total;
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *FlexRow = @fieldParentPtr("widget", widget);

        // Forward to children
        for (self.children.items) |child| {
            if (child.widget.handleEvent(event)) {
                return true;
            }
        }
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *FlexRow = @fieldParentPtr("widget", widget);

        // Resize all children
        for (self.children.items) |child| {
            child.widget.resize(area);
        }
    }

    fn deinit(widget: *Widget) void {
        const self: *FlexRow = @fieldParentPtr("widget", widget);
        self.children.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

/// FlexColumn - Vertical flexible layout
pub const FlexColumn = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    children: std.ArrayList(FlexChild),
    gap: u16 = 0,                      // Gap between items
    alignment: Alignment = .start,      // Horizontal alignment
    justify: Justify = .start,          // Vertical distribution
    padding_x: u16 = 0,
    padding_y: u16 = 0,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*FlexColumn {
        const col = try allocator.create(FlexColumn);
        col.* = .{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .children = .{},
        };
        return col;
    }

    pub fn addChild(self: *FlexColumn, child: FlexChild) !void {
        try self.children.append(self.allocator, child);
    }

    pub fn addChildWidget(self: *FlexColumn, widget_ptr: *Widget) !void {
        try self.addChild(FlexChild{ .widget = widget_ptr });
    }

    pub fn setGap(self: *FlexColumn, gap: u16) void {
        self.gap = gap;
    }

    pub fn setAlignment(self: *FlexColumn, alignment: Alignment) void {
        self.alignment = alignment;
    }

    pub fn setJustify(self: *FlexColumn, justify: Justify) void {
        self.justify = justify;
    }

    pub fn setPadding(self: *FlexColumn, padding_x: u16, padding_y: u16) void {
        self.padding_x = padding_x;
        self.padding_y = padding_y;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *FlexColumn = @fieldParentPtr("widget", widget);

        if (area.width == 0 or area.height == 0 or self.children.items.len == 0) return;

        // Account for padding
        const inner_area = Rect.init(
            area.x + self.padding_x,
            area.y + self.padding_y,
            area.width -| (self.padding_x * 2),
            area.height -| (self.padding_y * 2),
        );

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Calculate child heights
        const heights = self.calculateChildHeights(inner_area.height);
        defer self.allocator.free(heights);

        // Calculate starting y based on justify
        var y_offset = inner_area.y;
        const total_height = calculateTotalHeight(heights, self.gap);
        const extra_space = if (total_height < inner_area.height) inner_area.height - total_height else 0;

        switch (self.justify) {
            .start => {},
            .end => y_offset += @intCast(extra_space),
            .center => y_offset += @intCast(extra_space / 2),
            .space_between, .space_around, .space_evenly => {},
        }

        // Render children
        for (self.children.items, 0..) |child, i| {
            const child_height = heights[i];
            if (child_height == 0) continue;

            // For now, children use full width (can be refined later)
            const child_area = Rect.init(inner_area.x, y_offset, inner_area.width, child_height);
            child.widget.vtable.render(child.widget, buffer, child_area);

            // Move to next position
            y_offset += child_height;

            // Add gap if not last item
            if (i < self.children.items.len - 1) {
                y_offset += self.gap;

                // Add extra space for space-between/around/evenly
                switch (self.justify) {
                    .space_between => {
                        if (self.children.items.len > 1) {
                            y_offset += @intCast(extra_space / (self.children.items.len - 1));
                        }
                    },
                    .space_around => {
                        y_offset += @intCast(extra_space / self.children.items.len);
                    },
                    .space_evenly => {
                        y_offset += @intCast(extra_space / (self.children.items.len + 1));
                    },
                    else => {},
                }
            }
        }
    }

    fn calculateChildHeights(self: *FlexColumn, available_height: u16) []u16 {
        const heights = self.allocator.alloc(u16, self.children.items.len) catch return &[_]u16{};

        // Calculate gaps
        const total_gaps = if (self.children.items.len > 1)
            self.gap * @as(u16, @intCast(self.children.items.len - 1))
        else
            0;

        var remaining_height = if (available_height > total_gaps) available_height - total_gaps else 0;

        // First pass: calculate fixed sizes
        var total_flex: f32 = 0;
        for (self.children.items, 0..) |child, i| {
            if (child.flex_grow == 0 and child.flex_basis != null) {
                heights[i] = child.flex_basis.?;
                remaining_height -|= heights[i];
            } else {
                total_flex += child.flex_grow;
            }
        }

        // Second pass: distribute remaining space
        if (total_flex > 0 and remaining_height > 0) {
            for (self.children.items, 0..) |child, i| {
                if (child.flex_grow > 0) {
                    const flex_height = @as(u16, @intFromFloat(
                        @as(f32, @floatFromInt(remaining_height)) * (child.flex_grow / total_flex)
                    ));

                    // Apply min/max constraints
                    var final_height = flex_height;
                    if (child.min_size) |min| final_height = @max(final_height, min);
                    if (child.max_size) |max| final_height = @min(final_height, max);

                    heights[i] = final_height;
                }
            }
        }

        return heights;
    }

    fn calculateTotalHeight(heights: []const u16, gap: u16) u16 {
        var total: u16 = 0;
        for (heights) |h| {
            total +|= h;
        }
        if (heights.len > 1) {
            total +|= gap * @as(u16, @intCast(heights.len - 1));
        }
        return total;
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *FlexColumn = @fieldParentPtr("widget", widget);

        // Forward to children
        for (self.children.items) |child| {
            if (child.widget.handleEvent(event)) {
                return true;
            }
        }
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *FlexColumn = @fieldParentPtr("widget", widget);

        // Resize all children
        for (self.children.items) |child| {
            child.widget.resize(area);
        }
    }

    fn deinit(widget: *Widget) void {
        const self: *FlexColumn = @fieldParentPtr("widget", widget);
        self.children.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

test "FlexRow creation" {
    const allocator = std.testing.allocator;

    const row = try FlexRow.init(allocator);
    defer row.widget.vtable.deinit(&row.widget);

    try std.testing.expect(row.children.items.len == 0);
}

test "FlexColumn creation" {
    const allocator = std.testing.allocator;

    const col = try FlexColumn.init(allocator);
    defer col.widget.vtable.deinit(&col.widget);

    try std.testing.expect(col.children.items.len == 0);
}
