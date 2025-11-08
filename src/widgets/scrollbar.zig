//! Scrollbar Widget - Standalone scrollbar for displaying scroll position
//! Based on Ratatui's scrollbar implementation

const std = @import("std");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const Buffer = @import("../terminal.zig").Buffer;

const Rect = geometry.Rect;
const Style = style.Style;
const Color = style.Color;

pub const ScrollbarOrientation = enum {
    vertical_right,
    vertical_left,
    horizontal_bottom,
    horizontal_top,
};

pub const ScrollbarState = struct {
    position: usize = 0,
    content_length: usize = 0,
    viewport_length: usize = 0,

    pub fn new(content_length: usize) ScrollbarState {
        return .{ .content_length = content_length };
    }

    pub fn setPosition(self: *ScrollbarState, position: usize) *ScrollbarState {
        self.position = position;
        return self;
    }

    pub fn setContentLength(self: *ScrollbarState, length: usize) *ScrollbarState {
        self.content_length = length;
        return self;
    }

    pub fn setViewportLength(self: *ScrollbarState, length: usize) *ScrollbarState {
        self.viewport_length = length;
        return self;
    }
};

pub const Scrollbar = struct {
    orientation: ScrollbarOrientation = .vertical_right,
    thumb_style: Style,
    thumb_symbol: []const u8 = "█",
    track_style: Style,
    track_symbol: ?[]const u8 = "│",
    begin_symbol: ?[]const u8 = "↑",
    begin_style: Style,
    end_symbol: ?[]const u8 = "↓",
    end_style: Style,

    pub fn init(orientation: ScrollbarOrientation) Scrollbar {
        const default_style = Style.default();
        return .{
            .orientation = orientation,
            .thumb_style = default_style.withFg(Color.bright_white),
            .track_style = default_style.withFg(Color.bright_black),
            .begin_style = default_style.withFg(Color.bright_black),
            .end_style = default_style.withFg(Color.bright_black),
        };
    }

    pub fn setThumbStyle(self: *Scrollbar, s: Style) *Scrollbar {
        self.thumb_style = s;
        return self;
    }

    pub fn setThumbSymbol(self: *Scrollbar, symbol: []const u8) *Scrollbar {
        self.thumb_symbol = symbol;
        return self;
    }

    pub fn setTrackStyle(self: *Scrollbar, s: Style) *Scrollbar {
        self.track_style = s;
        return self;
    }

    pub fn setTrackSymbol(self: *Scrollbar, symbol: ?[]const u8) *Scrollbar {
        self.track_symbol = symbol;
        return self;
    }

    pub fn setBeginSymbol(self: *Scrollbar, symbol: ?[]const u8) *Scrollbar {
        self.begin_symbol = symbol;
        return self;
    }

    pub fn setEndSymbol(self: *Scrollbar, symbol: ?[]const u8) *Scrollbar {
        self.end_symbol = symbol;
        return self;
    }

    pub fn render(self: *const Scrollbar, buffer: *Buffer, area: Rect, state: *const ScrollbarState) void {
        if (state.content_length == 0) return;

        switch (self.orientation) {
            .vertical_right, .vertical_left => self.renderVertical(buffer, area, state),
            .horizontal_bottom, .horizontal_top => self.renderHorizontal(buffer, area, state),
        }
    }

    fn renderVertical(self: *const Scrollbar, buffer: *Buffer, area: Rect, state: *const ScrollbarState) void {
        if (area.height < 2) return;

        const x = if (self.orientation == .vertical_right) area.x + area.width - 1 else area.x;

        // Draw begin symbol
        if (self.begin_symbol) |symbol| {
            buffer.writeText(x, area.y, symbol, self.begin_style);
        }

        // Draw end symbol
        if (self.end_symbol) |symbol| {
            buffer.writeText(x, area.y + area.height - 1, symbol, self.end_style);
        }

        // Calculate scrollbar area (excluding begin/end)
        const scrollbar_start = area.y + 1;
        const scrollbar_height = if (area.height > 2) area.height - 2 else 0;

        if (scrollbar_height == 0) return;

        // Draw track
        if (self.track_symbol) |symbol| {
            var y: u16 = 0;
            while (y < scrollbar_height) : (y += 1) {
                buffer.writeText(x, scrollbar_start + y, symbol, self.track_style);
            }
        }

        // Calculate thumb position and size
        const content_length = @max(1, state.content_length);
        const viewport_length = @max(1, if (state.viewport_length > 0) state.viewport_length else scrollbar_height);

        // Thumb size proportional to viewport vs content
        const thumb_size_f = (@as(f64, @floatFromInt(scrollbar_height)) * @as(f64, @floatFromInt(viewport_length))) / @as(f64, @floatFromInt(content_length));
        const thumb_size = @max(1, @as(u16, @intFromFloat(thumb_size_f)));

        // Thumb position
        const scrollable_content = if (content_length > viewport_length) content_length - viewport_length else 0;
        const scrollable_area = if (scrollbar_height > thumb_size) scrollbar_height - thumb_size else 0;

        const thumb_pos = if (scrollable_content > 0)
            (@as(u64, state.position) * @as(u64, scrollable_area)) / @as(u64, scrollable_content)
        else
            0;

        // Draw thumb
        var i: u16 = 0;
        while (i < thumb_size and (thumb_pos + i) < scrollbar_height) : (i += 1) {
            buffer.writeText(x, scrollbar_start + @as(u16, @intCast(thumb_pos)) + i, self.thumb_symbol, self.thumb_style);
        }
    }

    fn renderHorizontal(self: *const Scrollbar, buffer: *Buffer, area: Rect, state: *const ScrollbarState) void {
        if (area.width < 2) return;

        const y = if (self.orientation == .horizontal_bottom) area.y + area.height - 1 else area.y;

        // Draw begin symbol
        if (self.begin_symbol) |symbol| {
            buffer.writeText(area.x, y, symbol, self.begin_style);
        }

        // Draw end symbol
        if (self.end_symbol) |symbol| {
            buffer.writeText(area.x + area.width - 1, y, symbol, self.end_style);
        }

        // Calculate scrollbar area
        const scrollbar_start = area.x + 1;
        const scrollbar_width = if (area.width > 2) area.width - 2 else 0;

        if (scrollbar_width == 0) return;

        // Draw track
        if (self.track_symbol) |symbol| {
            var x: u16 = 0;
            while (x < scrollbar_width) : (x += 1) {
                buffer.writeText(scrollbar_start + x, y, symbol, self.track_style);
            }
        }

        // Calculate thumb (similar to vertical)
        const content_length = @max(1, state.content_length);
        const viewport_length = @max(1, if (state.viewport_length > 0) state.viewport_length else scrollbar_width);

        const thumb_size_f = (@as(f64, @floatFromInt(scrollbar_width)) * @as(f64, @floatFromInt(viewport_length))) / @as(f64, @floatFromInt(content_length));
        const thumb_size = @max(1, @as(u16, @intFromFloat(thumb_size_f)));

        const scrollable_content = if (content_length > viewport_length) content_length - viewport_length else 0;
        const scrollable_area = if (scrollbar_width > thumb_size) scrollbar_width - thumb_size else 0;

        const thumb_pos = if (scrollable_content > 0)
            (@as(u64, state.position) * @as(u64, scrollable_area)) / @as(u64, scrollable_content)
        else
            0;

        // Draw thumb
        var i: u16 = 0;
        while (i < thumb_size and (thumb_pos + i) < scrollbar_width) : (i += 1) {
            buffer.writeText(scrollbar_start + @as(u16, @intCast(thumb_pos)) + i, y, self.thumb_symbol, self.thumb_style);
        }
    }
};

test "Scrollbar creation" {
    const scrollbar = Scrollbar.init(.vertical_right);
    try std.testing.expectEqual(ScrollbarOrientation.vertical_right, scrollbar.orientation);
}

test "ScrollbarState" {
    var state = ScrollbarState.new(100);
    _ = state.setPosition(50);
    try std.testing.expectEqual(@as(usize, 50), state.position);
    try std.testing.expectEqual(@as(usize, 100), state.content_length);
}
