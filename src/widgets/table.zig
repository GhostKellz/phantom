//! Table widget for displaying tabular data
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
const Style = style.Style;

/// Table column configuration
pub const Column = struct {
    title: []const u8,
    width: ?u16 = null, // null means auto-size
    min_width: u16 = 1,
    max_width: ?u16 = null,
    alignment: Alignment = .left,
    
    pub const Alignment = enum {
        left,
        center,
        right,
    };
};

/// Table row data
pub const Row = struct {
    cells: []const []const u8,
    style: Style = Style.default(),
    
    pub fn init(cells: []const []const u8) Row {
        return Row{ .cells = cells };
    }
    
    pub fn withStyle(cells: []const []const u8, row_style: Style) Row {
        return Row{ .cells = cells, .style = row_style };
    }
};

/// Table widget for displaying tabular data
pub const Table = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    
    // Data
    columns: std.ArrayList(Column),
    rows: std.ArrayList(Row),
    
    // Selection
    selected_row: ?usize = null,
    selected_col: ?usize = null,
    
    // Scrolling
    scroll_offset_row: usize = 0,
    scroll_offset_col: usize = 0,
    
    // Styling
    header_style: Style,
    row_style: Style,
    selected_style: Style,
    border_style: Style,
    
    // Configuration
    show_header: bool = true,
    show_borders: bool = true,
    selectable: bool = true,
    column_spacing: u16 = 1,
    
    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),
    calculated_widths: std.ArrayList(u16),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*Table {
        const table = try allocator.create(Table);
        table.* = Table{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .columns = std.ArrayList(Column).init(allocator),
            .rows = std.ArrayList(Row).init(allocator),
            .header_style = Style.default().withBold(),
            .row_style = Style.default(),
            .selected_style = Style.default().withBg(style.Color.blue),
            .border_style = Style.default(),
            .calculated_widths = std.ArrayList(u16).init(allocator),
        };
        return table;
    }

    pub fn addColumn(self: *Table, column: Column) !void {
        try self.columns.append(column);
        try self.calculated_widths.append(0);
    }

    pub fn addRow(self: *Table, row: Row) !void {
        try self.rows.append(row);
        if (self.selectable and self.selected_row == null and self.rows.items.len > 0) {
            self.selected_row = 0;
        }
    }

    pub fn setColumns(self: *Table, columns: []const Column) !void {
        self.columns.clearAndFree();
        self.calculated_widths.clearAndFree();
        
        for (columns) |column| {
            try self.addColumn(column);
        }
    }

    pub fn setRows(self: *Table, rows: []const Row) !void {
        self.rows.clearAndFree();
        
        for (rows) |row| {
            try self.addRow(row);
        }
    }

    pub fn clear(self: *Table) void {
        self.rows.clearAndFree();
        self.selected_row = null;
        self.scroll_offset_row = 0;
        self.scroll_offset_col = 0;
    }

    pub fn clearColumns(self: *Table) void {
        self.columns.clearAndFree();
        self.calculated_widths.clearAndFree();
        self.clear();
    }

    pub fn setHeaderStyle(self: *Table, header_style: Style) void {
        self.header_style = header_style;
    }

    pub fn setRowStyle(self: *Table, row_style: Style) void {
        self.row_style = row_style;
    }

    pub fn setSelectedStyle(self: *Table, selected_style: Style) void {
        self.selected_style = selected_style;
    }

    pub fn setBorderStyle(self: *Table, border_style: Style) void {
        self.border_style = border_style;
    }

    pub fn setShowHeader(self: *Table, show: bool) void {
        self.show_header = show;
    }

    pub fn setShowBorders(self: *Table, show: bool) void {
        self.show_borders = show;
    }

    pub fn setSelectable(self: *Table, selectable: bool) void {
        self.selectable = selectable;
        if (!selectable) {
            self.selected_row = null;
        }
    }

    pub fn setColumnSpacing(self: *Table, spacing: u16) void {
        self.column_spacing = spacing;
    }

    pub fn selectNext(self: *Table) void {
        if (!self.selectable or self.rows.items.len == 0) return;
        
        if (self.selected_row) |row| {
            if (row + 1 < self.rows.items.len) {
                self.selected_row = row + 1;
            }
        } else {
            self.selected_row = 0;
        }
    }

    pub fn selectPrevious(self: *Table) void {
        if (!self.selectable or self.rows.items.len == 0) return;
        
        if (self.selected_row) |row| {
            if (row > 0) {
                self.selected_row = row - 1;
            }
        } else {
            self.selected_row = 0;
        }
    }

    pub fn getSelectedRow(self: *const Table) ?Row {
        if (self.selected_row) |row| {
            if (row < self.rows.items.len) {
                return self.rows.items[row];
            }
        }
        return null;
    }

    fn calculateColumnWidths(self: *Table) void {
        if (self.columns.items.len == 0) return;
        
        const available_width = if (self.area.width > 2) self.area.width - 2 else 0;
        var total_spacing = if (self.columns.items.len > 1) 
            (self.columns.items.len - 1) * self.column_spacing else 0;
        
        if (self.show_borders) {
            total_spacing += @as(u16, @intCast(self.columns.items.len + 1));
        }
        
        const content_width = if (available_width > total_spacing) available_width - total_spacing else 0;
        
        // Reset calculated widths
        for (self.calculated_widths.items) |*width| {
            width.* = 0;
        }
        
        // Calculate minimum widths from content
        for (self.columns.items, 0..) |column, col_idx| {
            var min_width = column.min_width;
            
            // Check header width
            if (self.show_header) {
                min_width = @max(min_width, @as(u16, @intCast(column.title.len)));
            }
            
            // Check data widths
            for (self.rows.items) |row| {
                if (col_idx < row.cells.len) {
                    min_width = @max(min_width, @as(u16, @intCast(row.cells[col_idx].len)));
                }
            }
            
            // Apply column constraints
            if (column.max_width) |max_width| {
                min_width = @min(min_width, max_width);
            }
            
            if (column.width) |fixed_width| {
                min_width = fixed_width;
            }
            
            self.calculated_widths.items[col_idx] = min_width;
        }
        
        // Distribute remaining space
        var total_min_width: u16 = 0;
        for (self.calculated_widths.items) |width| {
            total_min_width += width;
        }
        
        if (total_min_width < content_width) {
            const remaining = content_width - total_min_width;
            const per_column = remaining / @as(u16, @intCast(self.columns.items.len));
            
            for (self.calculated_widths.items, 0..) |*width, col_idx| {
                const column = self.columns.items[col_idx];
                const additional = if (col_idx < self.columns.items.len - 1) per_column else remaining - per_column * col_idx;
                
                if (column.max_width) |max_width| {
                    width.* = @min(width.* + additional, max_width);
                } else {
                    width.* += additional;
                }
            }
        }
    }

    fn drawBorder(self: *Table, buffer: *Buffer, x: u16, y: u16, width: u16, height: u16) void {
        if (!self.show_borders or width < 2 or height < 2) return;
        
        // Top and bottom borders
        var border_x = x;
        while (border_x < x + width) : (border_x += 1) {
            buffer.setCell(border_x, y, Cell.init('─', self.border_style));
            buffer.setCell(border_x, y + height - 1, Cell.init('─', self.border_style));
        }
        
        // Left and right borders
        var border_y = y;
        while (border_y < y + height) : (border_y += 1) {
            buffer.setCell(x, border_y, Cell.init('│', self.border_style));
            buffer.setCell(x + width - 1, border_y, Cell.init('│', self.border_style));
        }
        
        // Corners
        buffer.setCell(x, y, Cell.init('┌', self.border_style));
        buffer.setCell(x + width - 1, y, Cell.init('┐', self.border_style));
        buffer.setCell(x, y + height - 1, Cell.init('└', self.border_style));
        buffer.setCell(x + width - 1, y + height - 1, Cell.init('┘', self.border_style));
    }

    fn drawCell(self: *Table, buffer: *Buffer, x: u16, y: u16, width: u16, text: []const u8, alignment: Column.Alignment, cell_style: Style) void {
        _ = self;
        if (width == 0) return;
        
        // Clear cell background
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(cell_style));
        
        // Calculate text position
        const text_len = @min(text.len, width);
        const text_x = switch (alignment) {
            .left => x,
            .center => x + (width - @as(u16, @intCast(text_len))) / 2,
            .right => x + width - @as(u16, @intCast(text_len)),
        };
        
        // Draw text
        if (text_len > 0) {
            buffer.writeText(text_x, y, text[0..text_len], cell_style);
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Table = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;
        
        // Calculate column widths
        self.calculateColumnWidths();
        
        // Draw outer border
        if (self.show_borders) {
            self.drawBorder(buffer, area.x, area.y, area.width, area.height);
        }
        
        // Calculate content area
        var content_area = area;
        if (self.show_borders) {
            content_area = Rect.init(area.x + 1, area.y + 1, area.width - 2, area.height - 2);
        }
        
        if (content_area.height == 0 or content_area.width == 0) return;
        
        var current_y = content_area.y;
        
        // Draw header
        if (self.show_header and self.columns.items.len > 0) {
            var current_x = content_area.x;
            
            for (self.columns.items, 0..) |column, col_idx| {
                const col_width = self.calculated_widths.items[col_idx];
                
                self.drawCell(buffer, current_x, current_y, col_width, column.title, column.alignment, self.header_style);
                
                current_x += col_width;
                if (col_idx < self.columns.items.len - 1) {
                    current_x += self.column_spacing;
                    if (self.show_borders) {
                        buffer.setCell(current_x - 1, current_y, Cell.init('│', self.border_style));
                        current_x += 1;
                    }
                }
            }
            
            current_y += 1;
            
            // Draw header separator
            if (self.show_borders and current_y < content_area.y + content_area.height) {
                var sep_x = content_area.x;
                while (sep_x < content_area.x + content_area.width) : (sep_x += 1) {
                    buffer.setCell(sep_x, current_y, Cell.init('─', self.border_style));
                }
                current_y += 1;
            }
        }
        
        // Draw rows
        const visible_rows = if (current_y < content_area.y + content_area.height) 
            content_area.y + content_area.height - current_y else 0;
        
        var row_idx = self.scroll_offset_row;
        var displayed_rows: u16 = 0;
        
        while (row_idx < self.rows.items.len and displayed_rows < visible_rows) {
            const row = self.rows.items[row_idx];
            const is_selected = self.selectable and self.selected_row == row_idx;
            
            var current_x = content_area.x;
            
            for (self.columns.items, 0..) |column, col_idx| {
                const col_width = self.calculated_widths.items[col_idx];
                const cell_text = if (col_idx < row.cells.len) row.cells[col_idx] else "";
                
                const cell_style = if (is_selected) self.selected_style else row.style;
                
                self.drawCell(buffer, current_x, current_y, col_width, cell_text, column.alignment, cell_style);
                
                current_x += col_width;
                if (col_idx < self.columns.items.len - 1) {
                    current_x += self.column_spacing;
                    if (self.show_borders) {
                        buffer.setCell(current_x - 1, current_y, Cell.init('│', self.border_style));
                        current_x += 1;
                    }
                }
            }
            
            row_idx += 1;
            displayed_rows += 1;
            current_y += 1;
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Table = @fieldParentPtr("widget", widget);
        
        if (!self.selectable) return false;

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
        const self: *Table = @fieldParentPtr("widget", widget);
        self.area = area;
        self.calculateColumnWidths();
    }

    fn deinit(widget: *Widget) void {
        const self: *Table = @fieldParentPtr("widget", widget);
        self.columns.deinit();
        self.rows.deinit();
        self.calculated_widths.deinit();
        self.allocator.destroy(self);
    }
};

test "Table widget creation" {
    const allocator = std.testing.allocator;

    const table = try Table.init(allocator);
    defer table.widget.deinit();

    try std.testing.expect(table.columns.items.len == 0);
    try std.testing.expect(table.rows.items.len == 0);
    try std.testing.expect(table.selected_row == null);
}

test "Table widget column and row management" {
    const allocator = std.testing.allocator;

    const table = try Table.init(allocator);
    defer table.widget.deinit();

    try table.addColumn(Column{ .title = "Name", .width = 20 });
    try table.addColumn(Column{ .title = "Age", .width = 10 });
    
    try table.addRow(Row.init(&[_][]const u8{ "John", "25" }));
    try table.addRow(Row.init(&[_][]const u8{ "Jane", "30" }));

    try std.testing.expect(table.columns.items.len == 2);
    try std.testing.expect(table.rows.items.len == 2);
    try std.testing.expect(table.selected_row.? == 0);
    
    table.selectNext();
    try std.testing.expect(table.selected_row.? == 1);
    
    table.selectPrevious();
    try std.testing.expect(table.selected_row.? == 0);
}
