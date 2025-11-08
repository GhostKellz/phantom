//! Toast overlay widget for transient notifications.
const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const SizeConstraints = @import("../widget.zig").SizeConstraints;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const Event = @import("../event.zig").Event;
const Key = @import("../event.zig").Key;

const Rect = geometry.Rect;
const Style = style.Style;
const math = std.math;

fn nowMillis() usize {
    return @as(usize, @intCast(std.time.milliTimestamp() catch 0));
}

pub const ToastOverlay = struct {
    pub const ToastKind = enum { info, success, warning, failure };

    pub const ToastPalette = struct {
        info: Style = Style.default().withBg(style.Color.bright_blue).withFg(style.Color.white),
        success: Style = Style.default().withBg(style.Color.green).withFg(style.Color.black),
        warning: Style = Style.default().withBg(style.Color.yellow).withFg(style.Color.black),
        failure: Style = Style.default().withBg(style.Color.red).withFg(style.Color.white),
        text: Style = Style.default().withFg(style.Color.white),
        info_icon: []const u8 = "ℹ",
        success_icon: []const u8 = "✔",
        warning_icon: []const u8 = "!",
        failure_icon: []const u8 = "✖",
    };

    pub const Config = struct {
        max_visible: u8 = 4,
        max_queue: u8 = 12,
        default_duration_ms: u64 = 4000,
        dismiss_key: ?Key = .escape,
        palette: ToastPalette = .{},
    };

    pub const ToastOptions = struct {
        kind: ToastKind = .info,
        duration_ms: ?u64 = null,
        sticky: bool = false,
    };

    pub const Error = std.mem.Allocator.Error;

    widget: Widget,
    allocator: std.mem.Allocator,
    config: Config,
    toasts: std.ArrayList(Toast),

    const Toast = struct {
        message: []u8,
        kind: ToastKind,
        created_ms: usize,
        expires_at_ms: ?usize,
    };

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
        .getConstraints = getConstraints,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !*ToastOverlay {
        const self = try allocator.create(ToastOverlay);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .config = config,
            .toasts = std.ArrayList(Toast).init(allocator),
        };
        return self;
    }

    pub fn pushToast(self: *ToastOverlay, message: []const u8, options: ToastOptions) Error!void {
        const now = nowMillis();
        self.cleanupExpired(now);

        if (self.config.max_queue > 0 and self.toasts.items.len >= self.config.max_queue) {
            self.discardOldest();
        }

        const owned_message = try self.allocator.dupe(u8, message);
        errdefer self.allocator.free(owned_message);

        const duration_ms = options.duration_ms orelse self.config.default_duration_ms;
        const duration = durationToUsize(duration_ms);
        const expires_at = if (options.sticky or duration == 0)
            null
        else
            math.add(usize, now, duration) catch std.math.maxInt(usize);

        try self.toasts.append(.{
            .message = owned_message,
            .kind = options.kind,
            .created_ms = now,
            .expires_at_ms = expires_at,
        });
    }

    pub fn dismissLatest(self: *ToastOverlay) void {
        if (self.toasts.items.len == 0) return;
        const index = self.toasts.items.len - 1;
        self.releaseToast(index);
        _ = self.toasts.pop();
    }

    pub fn clear(self: *ToastOverlay) void {
        var i: usize = 0;
        while (i < self.toasts.items.len) : (i += 1) {
            self.allocator.free(self.toasts.items[i].message);
        }
        self.toasts.clearRetainingCapacity();
    }

    fn durationToUsize(duration: u64) usize {
        return if (duration > std.math.maxInt(usize))
            std.math.maxInt(usize)
        else
            @intCast(duration);
    }

    fn discardOldest(self: *ToastOverlay) void {
        if (self.toasts.items.len == 0) return;
        self.releaseToast(0);
        _ = self.toasts.orderedRemove(0);
    }

    fn releaseToast(self: *ToastOverlay, index: usize) void {
        self.allocator.free(self.toasts.items[index].message);
    }

    fn cleanupExpired(self: *ToastOverlay, now: usize) void {
        var i: usize = 0;
        while (i < self.toasts.items.len) {
            if (self.toasts.items[i].expires_at_ms) |deadline| {
                if (deadline <= now) {
                    self.releaseToast(i);
                    _ = self.toasts.orderedRemove(i);
                    continue;
                }
            }
            i += 1;
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *ToastOverlay = @fieldParentPtr("widget", widget);
        if (area.width == 0 or area.height == 0) return;

        const now = nowMillis();
        self.cleanupExpired(now);

        if (self.toasts.items.len == 0) return;

        const visible_cap = @min(
            @as(usize, self.toasts.items.len),
            @as(usize, @min(@as(u16, self.config.max_visible), area.height)),
        );
        if (visible_cap == 0) return;

        var rendered: usize = 0;
        var row: u16 = area.y + area.height;
        while (rendered < visible_cap and row > area.y) : (rendered += 1) {
            row -= 1;
            const index = self.toasts.items.len - rendered - 1;
            self.renderToast(buffer, area, row, self.toasts.items[index]);
        }
    }

    fn renderToast(self: *ToastOverlay, buffer: *Buffer, area: Rect, row: u16, toast: Toast) void {
        const toast_style = self.styleForKind(toast.kind);
        const text_style = self.config.palette.text;
        const icon = self.iconForKind(toast.kind);

        buffer.fill(Rect{ .x = area.x, .y = row, .width = area.width, .height = 1 }, Cell.init(' ', toast_style));

        const end_x = area.x + area.width;
        var cursor = area.x + 1;

        if (cursor < end_x and icon.len != 0) {
            const chunk = @min(@as(usize, end_x - cursor), icon.len);
            buffer.writeText(cursor, row, icon[0..chunk], text_style);
            cursor += @intCast(chunk);
            if (cursor < end_x) {
                buffer.writeText(cursor, row, " ", text_style);
                cursor += 1;
            }
        }

        if (cursor < end_x) {
            const chunk = @min(@as(usize, end_x - cursor), toast.message.len);
            buffer.writeText(cursor, row, toast.message[0..chunk], text_style);
        }
    }

    fn styleForKind(self: *const ToastOverlay, kind: ToastKind) Style {
        return switch (kind) {
            .info => self.config.palette.info,
            .success => self.config.palette.success,
            .warning => self.config.palette.warning,
            .failure => self.config.palette.failure,
        };
    }

    fn iconForKind(self: *const ToastOverlay, kind: ToastKind) []const u8 {
        return switch (kind) {
            .info => self.config.palette.info_icon,
            .success => self.config.palette.success_icon,
            .warning => self.config.palette.warning_icon,
            .failure => self.config.palette.failure_icon,
        };
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *ToastOverlay = @fieldParentPtr("widget", widget);
        switch (event) {
            .tick => {
                self.cleanupExpired(nowMillis());
                return false;
            },
            .key => |key| {
                if (self.config.dismiss_key) |dismiss_key| {
                    if (key == dismiss_key) {
                        self.dismissLatest();
                        return true;
                    }
                }
            },
            else => {},
        }
        return false;
    }

    fn getConstraints(widget: *Widget) SizeConstraints {
        const self: *ToastOverlay = @fieldParentPtr("widget", widget);
        _ = self;
        return SizeConstraints.unconstrained();
    }

    fn deinit(widget: *Widget) void {
        const self: *ToastOverlay = @fieldParentPtr("widget", widget);
        self.clear();
        self.toasts.deinit();
        self.allocator.destroy(self);
    }
};

const testing = std.testing;

fn makeBuffer(width: u16, height: u16) !Buffer {
    return try Buffer.init(testing.allocator, geometry.Size.init(width, height));
}

test "ToastOverlay queues and prunes" {
    var overlay = try ToastOverlay.init(testing.allocator, .{ .default_duration_ms = 10, .max_queue = 3 });
    defer overlay.widget.deinit();

    try overlay.pushToast("one", .{});
    try overlay.pushToast("two", .{});
    try testing.expectEqual(@as(usize, 2), overlay.toasts.items.len);

    overlay.toasts.items[0].expires_at_ms = 0;
    overlay.cleanupExpired(1);
    try testing.expectEqual(@as(usize, 1), overlay.toasts.items.len);

    overlay.dismissLatest();
    try testing.expectEqual(@as(usize, 0), overlay.toasts.items.len);
}

test "ToastOverlay renders latest toasts" {
    var overlay = try ToastOverlay.init(testing.allocator, .{ .default_duration_ms = 5000 });
    defer overlay.widget.deinit();

    try overlay.pushToast("hello", .{ .kind = .success, .sticky = true });
    try overlay.pushToast("world", .{ .kind = .warning, .sticky = true });

    var buffer = try makeBuffer(20, 3);
    defer buffer.deinit();

    const area = Rect.init(0, 0, 20, 3);
    overlay.widget.render(&buffer, area);

    const cell = buffer.getCell(1, 2) orelse return error.TestUnexpectedResult;
    try testing.expect(cell.char != ' ');
}
