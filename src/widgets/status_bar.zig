//! Application status bar widget with customizable segments.
const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const SizeConstraints = @import("../widget.zig").SizeConstraints;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const Event = @import("../event.zig").Event;

const Rect = geometry.Rect;
const Style = style.Style;
const math = std.math;

/// Status bar presenting horizontal segments (text, indicators, progress bars).
pub const StatusBar = struct {
    pub const Config = struct {
        /// Horizontal gap (spaces) between segments
        gap: u8 = 2,
        /// Background style for the entire bar (used when clearing the area)
        background_style: Style = Style.default().withBg(style.Color.black).withFg(style.Color.white),
    };

    pub const IndicatorState = enum { idle, info, success, warning, failure };

    pub const IndicatorPalette = struct {
        idle: Style = Style.default().withFg(style.Color.bright_black),
        info: Style = Style.default().withFg(style.Color.cyan),
        success: Style = Style.default().withFg(style.Color.bright_green),
        warning: Style = Style.default().withFg(style.Color.yellow),
        failure: Style = Style.default().withFg(style.Color.bright_red),

        pub fn styleFor(self: IndicatorPalette, state: IndicatorState) Style {
            return switch (state) {
                .idle => self.idle,
                .info => self.info,
                .success => self.success,
                .warning => self.warning,
                .failure => self.failure,
            };
        }
    };

    pub const TextSegmentConfig = struct {
        label: []const u8,
        value: []const u8,
        /// Text shown between label and value
        separator: []const u8 = ": ",
        style: Style = Style.default(),
    };

    pub const IndicatorSegmentConfig = struct {
        label: []const u8,
        icon: []const u8 = "",
        state: IndicatorState = .idle,
        palette: IndicatorPalette = .{},
    };

    pub const ProgressSegmentConfig = struct {
        label: []const u8,
        percent: f32 = 0.0,
        width: u16 = 12,
        text_style: Style = Style.default(),
        track_style: Style = Style.default().withFg(style.Color.bright_black),
        fill_style: Style = Style.default().withFg(style.Color.bright_green),
        fill_char: u8 = '#',
        empty_char: u8 = ' ',
    };

    pub const Error = error{
        IndexOutOfBounds,
        InvalidSegmentKind,
    } || std.mem.Allocator.Error;

    widget: Widget,
    allocator: std.mem.Allocator,
    segments: std.ArrayList(Segment),
    gap: u8,
    background_style: Style,

    const Segment = union(enum) {
        text: TextSegment,
        indicator: IndicatorSegment,
        progress: ProgressSegment,
    };

    const TextSegment = struct {
        label: []u8,
        value: []u8,
        separator: []u8,
        style: Style,
    };

    const IndicatorSegment = struct {
        label: []u8,
        icon: []u8,
        state: IndicatorState,
        palette: IndicatorPalette,
    };

    const ProgressSegment = struct {
        label: []u8,
        percent: f32,
        width: u16,
        text_style: Style,
        track_style: Style,
        fill_style: Style,
        fill_char: u8,
        empty_char: u8,
    };

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
        .getConstraints = getConstraints,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !*StatusBar {
        const self = try allocator.create(StatusBar);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .segments = std.ArrayList(Segment).init(allocator),
            .gap = config.gap,
            .background_style = config.background_style,
        };
        return self;
    }

    pub fn setGap(self: *StatusBar, gap: u8) void {
        self.gap = gap;
    }

    pub fn setBackgroundStyle(self: *StatusBar, style_override: Style) void {
        self.background_style = style_override;
    }

    pub fn addTextSegment(self: *StatusBar, config: TextSegmentConfig) Error!usize {
        const label = try self.allocator.dupe(u8, config.label);
        errdefer self.allocator.free(label);
        const value = try self.allocator.dupe(u8, config.value);
        errdefer self.allocator.free(value);
        const separator = try self.allocator.dupe(u8, config.separator);
        errdefer self.allocator.free(separator);

        const segment = Segment{ .text = .{
            .label = label,
            .value = value,
            .separator = separator,
            .style = config.style,
        } };
        try self.segments.append(segment);
        return self.segments.items.len - 1;
    }

    pub fn setTextValue(self: *StatusBar, index: usize, value: []const u8) Error!void {
        const segment = try self.getSegment(index);
        switch (segment.*) {
            .text => |*text| {
                const copy = try self.allocator.dupe(u8, value);
                self.allocator.free(text.value);
                text.value = copy;
            },
            else => return error.InvalidSegmentKind,
        }
    }

    pub fn setTextLabel(self: *StatusBar, index: usize, label: []const u8) Error!void {
        const segment = try self.getSegment(index);
        switch (segment.*) {
            .text => |*text| {
                const copy = try self.allocator.dupe(u8, label);
                self.allocator.free(text.label);
                text.label = copy;
            },
            else => return error.InvalidSegmentKind,
        }
    }

    pub fn addIndicatorSegment(self: *StatusBar, config: IndicatorSegmentConfig) Error!usize {
        const label = try self.allocator.dupe(u8, config.label);
        errdefer self.allocator.free(label);
        const icon = try self.allocator.dupe(u8, config.icon);
        errdefer self.allocator.free(icon);
        const segment = Segment{ .indicator = .{
            .label = label,
            .icon = icon,
            .state = config.state,
            .palette = config.palette,
        } };
        try self.segments.append(segment);
        return self.segments.items.len - 1;
    }

    pub fn setIndicatorState(self: *StatusBar, index: usize, state: IndicatorState) Error!void {
        const segment = try self.getSegment(index);
        switch (segment.*) {
            .indicator => |*indicator| {
                indicator.state = state;
            },
            else => return error.InvalidSegmentKind,
        }
    }

    pub fn setIndicatorLabel(self: *StatusBar, index: usize, label: []const u8) Error!void {
        const segment = try self.getSegment(index);
        switch (segment.*) {
            .indicator => |*indicator| {
                const copy = try self.allocator.dupe(u8, label);
                self.allocator.free(indicator.label);
                indicator.label = copy;
            },
            else => return error.InvalidSegmentKind,
        }
    }

    pub fn addProgressSegment(self: *StatusBar, config: ProgressSegmentConfig) Error!usize {
        const label = try self.allocator.dupe(u8, config.label);
        errdefer self.allocator.free(label);
        const segment = Segment{ .progress = .{
            .label = label,
            .percent = clamp01(config.percent),
            .width = config.width,
            .text_style = config.text_style,
            .track_style = config.track_style,
            .fill_style = config.fill_style,
            .fill_char = config.fill_char,
            .empty_char = config.empty_char,
        } };
        try self.segments.append(segment);
        return self.segments.items.len - 1;
    }

    pub fn setProgress(self: *StatusBar, index: usize, percent: f32) Error!void {
        const segment = try self.getSegment(index);
        switch (segment.*) {
            .progress => |*progress| {
                progress.percent = clamp01(percent);
            },
            else => return error.InvalidSegmentKind,
        }
    }

    pub fn setProgressLabel(self: *StatusBar, index: usize, label: []const u8) Error!void {
        const segment = try self.getSegment(index);
        switch (segment.*) {
            .progress => |*progress| {
                const copy = try self.allocator.dupe(u8, label);
                self.allocator.free(progress.label);
                progress.label = copy;
            },
            else => return error.InvalidSegmentKind,
        }
    }

    pub fn clear(self: *StatusBar) void {
        for (self.segments.items) |*segment| {
            self.releaseSegment(segment);
        }
        self.segments.clearRetainingCapacity();
    }

    fn clamp01(value: f32) f32 {
        if (value < 0.0) return 0.0;
        if (value > 1.0) return 1.0;
        return value;
    }

    fn getSegment(self: *StatusBar, index: usize) Error!*Segment {
        if (index >= self.segments.items.len) return error.IndexOutOfBounds;
        return &self.segments.items[index];
    }

    fn releaseSegment(self: *StatusBar, segment: *Segment) void {
        switch (segment.*) {
            .text => |*text| {
                self.allocator.free(text.label);
                self.allocator.free(text.value);
                self.allocator.free(text.separator);
            },
            .indicator => |*indicator| {
                self.allocator.free(indicator.label);
                self.allocator.free(indicator.icon);
            },
            .progress => |*progress| {
                self.allocator.free(progress.label);
            },
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *StatusBar = @fieldParentPtr("widget", widget);
        if (area.width == 0 or area.height == 0) return;

        buffer.fill(area, Cell.init(' ', self.background_style));

        const end_x: u16 = area.x + area.width;
        var cursor: u16 = area.x;
        var index: usize = 0;
        while (index < self.segments.items.len and cursor < end_x) : (index += 1) {
            if (index != 0 and cursor < end_x) {
                const gap = @min(@as(u16, self.gap), end_x - cursor);
                cursor += gap;
            }
            if (cursor >= end_x) break;
            cursor += self.renderSegment(buffer, cursor, area, self.segments.items[index]);
        }
    }

    fn renderSegment(self: *StatusBar, buffer: *Buffer, cursor: u16, area: Rect, segment: Segment) u16 {
        return switch (segment) {
            .text => |text| self.renderTextSegment(buffer, cursor, area, text),
            .indicator => |indicator| self.renderIndicatorSegment(buffer, cursor, area, indicator),
            .progress => |progress| self.renderProgressSegment(buffer, cursor, area, progress),
        };
    }

    fn renderTextSegment(self: *StatusBar, buffer: *Buffer, cursor: u16, area: Rect, segment: TextSegment) u16 {
        var pos = cursor;
        const end_x = area.x + area.width;

        if (segment.label.len != 0) {
            pos += self.writeLimited(buffer, pos, area.y, end_x, segment.label, segment.style);
            if (segment.value.len != 0 and pos < end_x and segment.separator.len != 0) {
                pos += self.writeLimited(buffer, pos, area.y, end_x, segment.separator, segment.style);
            }
        }

        if (segment.value.len != 0 and pos < end_x) {
            pos += self.writeLimited(buffer, pos, area.y, end_x, segment.value, segment.style);
        }

        return pos - cursor;
    }

    fn renderIndicatorSegment(self: *StatusBar, buffer: *Buffer, cursor: u16, area: Rect, segment: IndicatorSegment) u16 {
        var pos = cursor;
        const end_x = area.x + area.width;
        const indicator_style = segment.palette.styleFor(segment.state);

        if (segment.icon.len != 0) {
            pos += self.writeLimited(buffer, pos, area.y, end_x, segment.icon, indicator_style);
            if (pos < end_x) {
                pos += self.writeLimited(buffer, pos, area.y, end_x, " ", indicator_style);
            }
        }

        if (pos < end_x) {
            pos += self.writeLimited(buffer, pos, area.y, end_x, segment.label, indicator_style);
        }

        return pos - cursor;
    }

    fn renderProgressSegment(self: *StatusBar, buffer: *Buffer, cursor: u16, area: Rect, segment: ProgressSegment) u16 {
        var pos = cursor;
        const end_x = area.x + area.width;

        if (segment.label.len != 0) {
            pos += self.writeLimited(buffer, pos, area.y, end_x, segment.label, segment.text_style);
            if (pos < end_x) {
                pos += self.writeLimited(buffer, pos, area.y, end_x, " ", segment.text_style);
            }
        }

        if (pos < end_x) {
            pos += self.renderProgressBar(buffer, pos, area.y, end_x, segment);
        }

        if (pos < end_x) {
            var pct_buf: [8]u8 = undefined;
            const pct_float = segment.percent * @as(f32, 100.0);
            const pct_clamped = math.clamp(f32, pct_float, 0.0, 100.0);
            const pct_value = @as(u8, @intFromFloat(math.round(f32, pct_clamped)));
            const pct_text = std.fmt.bufPrint(&pct_buf, " {d}%", .{pct_value}) catch " 0%";
            pos += self.writeLimited(buffer, pos, area.y, end_x, pct_text, segment.text_style);
        }

        return pos - cursor;
    }

    fn renderProgressBar(self: *StatusBar, buffer: *Buffer, start_x: u16, y: u16, end_x: u16, segment: ProgressSegment) u16 {
        _ = self;
        var pos = start_x;
        if (pos >= end_x) return 0;

        buffer.setCell(pos, y, Cell.init('[', segment.track_style));
        pos += 1;
        if (pos >= end_x) return pos - start_x;

        const remaining_for_bar: u16 = end_x - pos;
        var bar_width: u16 = 0;
        if (remaining_for_bar > 0) {
            if (remaining_for_bar > 1) {
                bar_width = @min(segment.width, remaining_for_bar - 1);
            }
        }

        var filled_count: u16 = if (bar_width == 0) 0 else blk: {
            const normalized = math.clamp(f32, segment.percent, 0.0, 1.0);
            const fill_amount = normalized * @as(f32, bar_width);
            const rounded = math.round(f32, fill_amount);
            break :blk @as(u16, @intFromFloat(rounded));
        };
        if (filled_count > bar_width) filled_count = bar_width;

        var i: u16 = 0;
        while (i < bar_width and pos < end_x) : (i += 1) {
            const fill_style = if (i < filled_count) segment.fill_style else segment.track_style;
            const ch: u8 = if (i < filled_count) segment.fill_char else segment.empty_char;
            buffer.setCell(pos, y, Cell.init(ch, fill_style));
            pos += 1;
        }

        if (pos < end_x) {
            buffer.setCell(pos, y, Cell.init(']', segment.track_style));
            pos += 1;
        }

        return pos - start_x;
    }

    fn writeLimited(self: *const StatusBar, buffer: *Buffer, x: u16, y: u16, end_x: u16, text: []const u8, text_style: Style) u16 {
        _ = self;
        if (text.len == 0 or x >= end_x) return 0;
        const available = end_x - x;
        if (available == 0) return 0;
        const chunk = @min(@as(usize, available), text.len);
        buffer.writeText(x, y, text[0..chunk], text_style);
        return @intCast(chunk);
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        _ = widget;
        _ = event;
        return false;
    }

    fn getConstraints(widget: *Widget) SizeConstraints {
        const self: *StatusBar = @fieldParentPtr("widget", widget);
        _ = self;
        return SizeConstraints.minimum(0, 1);
    }

    fn deinit(widget: *Widget) void {
        const self: *StatusBar = @fieldParentPtr("widget", widget);
        self.clear();
        self.segments.deinit();
        self.allocator.destroy(self);
    }
};

const testing = std.testing;

fn makeBuffer(width: u16, height: u16) !Buffer {
    return try Buffer.init(testing.allocator, geometry.Size.init(width, height));
}

fn expectTextAt(buffer: *const Buffer, x: u16, y: u16, text: []const u8) !void {
    var idx: usize = 0;
    while (idx < text.len) : (idx += 1) {
        const column = x + @as(u16, @intCast(idx));
        const cell = buffer.getCell(column, y) orelse return error.TestUnexpectedResult;
        try testing.expectEqual(@as(u21, text[idx]), cell.char);
    }
}

test "StatusBar manages segments and renders" {
    var status_bar = try StatusBar.init(testing.allocator, .{});
    defer status_bar.widget.deinit();

    const text_idx = try status_bar.addTextSegment(.{ .label = "Mode", .value = "Live" });
    const indicator_idx = try status_bar.addIndicatorSegment(.{ .label = "Connected", .icon = "*", .state = .success });
    const progress_idx = try status_bar.addProgressSegment(.{ .label = "Sync", .percent = 0.25, .width = 8 });

    try status_bar.setTextValue(text_idx, "Monitor");
    try status_bar.setIndicatorState(indicator_idx, .warning);
    try status_bar.setIndicatorLabel(indicator_idx, "Lagging");
    try status_bar.setProgress(progress_idx, 0.75);

    var buffer = try makeBuffer(80, 1);
    defer buffer.deinit();
    const area = Rect.init(0, 0, 80, 1);
    status_bar.widget.render(&buffer, area);

    try expectTextAt(&buffer, 0, 0, "Monitor");
}
