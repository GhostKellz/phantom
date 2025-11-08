//! Data source bound status widgets (indicators, badges, overlays).
const std = @import("std");
const ArrayList = std.array_list.Managed;
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const data = @import("../data/list_source.zig");
const time_utils = @import("../time/utils.zig");

const Rect = geometry.Rect;
const Style = style.Style;

fn nowMillis() usize {
    const ts = time_utils.unixTimestampMillis();
    const clamped = if (ts < 0) 0 else ts;
    return @intCast(clamped);
}

/// Animated indicator reflecting a `ListDataSource` lifecycle state.
pub fn DataStateIndicator(comptime Item: type) type {
    const SourceType = data.ListDataSource(Item);
    const ObserverType = data.Observer(Item);
    const EventType = data.Event(Item);

    return struct {
        const Self = @This();

        pub const Config = struct {
            label: []const u8 = "items",
            loading_style: Style = Style.default().withFg(style.Color.bright_cyan),
            ready_style: Style = Style.default().withFg(style.Color.bright_green),
            idle_style: Style = Style.default().withFg(style.Color.bright_black),
            exhausted_style: Style = Style.default().withFg(style.Color.bright_magenta),
            failed_style: Style = Style.default().withFg(style.Color.bright_red),
        };

        widget: Widget,
        allocator: std.mem.Allocator,
        source: SourceType,
        observer: ObserverType,
        registered: bool = false,
        state: data.State,
        last_error: ?anyerror = null,
        label: []const u8,
        count: usize = 0,
        event_counter: usize = 0,
        last_update_ms: usize = 0,
        spinner_index: usize = 0,
        config: Config,

        const spinner_frames = [_]u8{ '-', '\\', '|', '/' };

        const vtable = Widget.WidgetVTable{
            .render = render,
            .handleEvent = handleEvent,
            .deinit = deinit,
        };

        pub fn init(allocator: std.mem.Allocator, source: SourceType, config: Config) !*Self {
            const self = try allocator.create(Self);
            const ctx: *anyopaque = @ptrCast(self);
            const observer = data.makeObserver(Item, handleSourceEvent, ctx);
            const label_copy = try allocator.dupe(u8, config.label);

            self.* = .{
                .widget = .{ .vtable = &vtable },
                .allocator = allocator,
                .source = source,
                .observer = observer,
                .state = source.state(),
                .label = label_copy,
                .config = config,
            };

            self.source.subscribe(&self.observer);
            self.registered = true;
            self.refreshFromSource();
            return self;
        }

        fn styleFor(self: *Self, state: data.State) Style {
            return switch (state) {
                .idle => self.config.idle_style,
                .loading => self.config.loading_style,
                .ready => self.config.ready_style,
                .exhausted => self.config.exhausted_style,
                .failed => self.config.failed_style,
            };
        }

        fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
            const self: *Self = @fieldParentPtr("widget", widget);
            if (area.width == 0 or area.height == 0) return;

            var msg_buffer: [160]u8 = undefined;
            const display = switch (self.state) {
                .idle => std.fmt.bufPrint(&msg_buffer, "Idle – 0 {s}", .{self.label}) catch "Idle",
                .loading => std.fmt.bufPrint(
                    &msg_buffer,
                    "{c} Loading {d} {s}",
                    .{ spinner_frames[self.spinner_index % spinner_frames.len], self.count, self.label },
                ) catch "Loading…",
                .ready => std.fmt.bufPrint(&msg_buffer, "Ready – {d} {s}", .{ self.count, self.label }) catch "Ready",
                .exhausted => std.fmt.bufPrint(&msg_buffer, "Complete – {d} {s}", .{ self.count, self.label }) catch "Complete",
                .failed => blk: {
                    if (self.last_error) |err| {
                        break :blk std.fmt.bufPrint(&msg_buffer, "Failed ({s})", .{@errorName(err)}) catch "Failed";
                    }
                    break :blk "Failed";
                },
            };

            buffer.writeText(area.x, area.y, display, self.styleFor(self.state));

            if (area.height > 1) {
                const since_ms = nowMillis() - self.last_update_ms;
                const secondary = std.fmt.bufPrint(&msg_buffer, "Events: {d} · {d} ms ago", .{ self.event_counter, since_ms }) catch "";
                buffer.writeText(area.x, area.y + 1, secondary, self.config.idle_style);
            }
        }

        fn handleEvent(widget: *Widget, event: Event) bool {
            const self: *Self = @fieldParentPtr("widget", widget);
            switch (event) {
                .tick => {
                    self.spinner_index = (self.spinner_index + 1) % spinner_frames.len;
                    return false;
                },
                else => return false,
            }
        }

        fn deinit(widget: *Widget) void {
            const self: *Self = @fieldParentPtr("widget", widget);
            if (self.registered) {
                self.source.unsubscribe(&self.observer);
            }
            self.allocator.free(self.label);
            self.allocator.destroy(self);
        }

        fn refreshFromSource(self: *Self) void {
            self.count = self.source.len();
            self.last_update_ms = nowMillis();
        }

        fn recordEvent(self: *Self) void {
            self.event_counter += 1;
            self.last_update_ms = nowMillis();
            self.refreshFromSource();
        }

        fn onSourceEvent(self: *Self, event: EventType) void {
            switch (event) {
                .reset => {
                    self.count = 0;
                    self.last_error = null;
                    self.state = .idle;
                    self.recordEvent();
                },
                .appended => {
                    self.recordEvent();
                },
                .replaced => {
                    self.recordEvent();
                },
                .updated => {
                    self.recordEvent();
                },
                .failed => |err| {
                    self.last_error = err;
                    self.state = .failed;
                    self.recordEvent();
                },
                .state => |state| {
                    self.state = state;
                    self.recordEvent();
                },
            }
        }

        fn handleSourceEvent(event: EventType, ctx: ?*anyopaque) void {
            const self = @as(*Self, @ptrCast(@alignCast(ctx.?)));
            self.onSourceEvent(event);
        }
    };
}

/// Compact badge summarising item counts and recent activity.
pub fn DataBadge(comptime Item: type) type {
    const SourceType = data.ListDataSource(Item);
    const ObserverType = data.Observer(Item);
    const EventType = data.Event(Item);

    return struct {
        const Self = @This();

        pub const Config = struct {
            label: []const u8 = "Items",
            badge_style: Style = Style.default().withBg(style.Color.blue).withFg(style.Color.white),
            warn_style: Style = Style.default().withBg(style.Color.yellow).withFg(style.Color.black),
            error_style: Style = Style.default().withBg(style.Color.red).withFg(style.Color.white),
        };

        widget: Widget,
        allocator: std.mem.Allocator,
        source: SourceType,
        observer: ObserverType,
        registered: bool = false,
        label: []const u8,
        config: Config,
        state: data.State,
        count: usize = 0,
        events: usize = 0,
        last_error: ?anyerror = null,

        const vtable = Widget.WidgetVTable{
            .render = render,
            .deinit = deinit,
        };

        pub fn init(allocator: std.mem.Allocator, source: SourceType, config: Config) !*Self {
            const label_copy = try allocator.dupe(u8, config.label);
            const self = try allocator.create(Self);
            const ctx: *anyopaque = @ptrCast(self);
            const observer = data.makeObserver(Item, handleSourceEvent, ctx);

            self.* = .{
                .widget = .{ .vtable = &vtable },
                .allocator = allocator,
                .source = source,
                .observer = observer,
                .label = label_copy,
                .config = config,
                .state = source.state(),
            };

            self.source.subscribe(&self.observer);
            self.registered = true;
            self.refresh();
            return self;
        }

        fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
            const self: *Self = @fieldParentPtr("widget", widget);
            if (area.width == 0 or area.height == 0) return;

            var msg_buffer: [128]u8 = undefined;
            const message = std.fmt.bufPrint(&msg_buffer, "{s}: {d} (events {d})", .{ self.label, self.count, self.events }) catch "";

            const style_choice = switch (self.state) {
                .failed => self.config.error_style,
                .loading => self.config.warn_style,
                else => self.config.badge_style,
            };

            buffer.writeText(area.x, area.y, message, style_choice);
        }

        fn deinit(widget: *Widget) void {
            const self: *Self = @fieldParentPtr("widget", widget);
            if (self.registered) {
                self.source.unsubscribe(&self.observer);
            }
            self.allocator.free(self.label);
            self.allocator.destroy(self);
        }

        fn refresh(self: *Self) void {
            self.count = self.source.len();
        }

        fn onSourceEvent(self: *Self, event: EventType) void {
            self.events += 1;
            switch (event) {
                .reset => {
                    self.count = 0;
                    self.state = .idle;
                    self.last_error = null;
                },
                .appended => self.refresh(),
                .replaced => self.refresh(),
                .updated => self.refresh(),
                .failed => |err| {
                    self.last_error = err;
                    self.state = .failed;
                },
                .state => |state| {
                    self.state = state;
                },
            }
            if (self.state != .failed) self.last_error = null;
        }

        fn handleSourceEvent(event: EventType, ctx: ?*anyopaque) void {
            const self = @as(*Self, @ptrCast(@alignCast(ctx.?)));
            self.onSourceEvent(event);
        }
    };
}

/// Lightweight overlay that logs last N data source events.
pub fn DataEventOverlay(comptime Item: type) type {
    const SourceType = data.ListDataSource(Item);
    const ObserverType = data.Observer(Item);
    const EventType = data.Event(Item);

    return struct {
        const Self = @This();

        pub const Config = struct {
            max_entries: usize = 10,
            header: []const u8 = "Data events",
            style: Style = Style.default().withFg(style.Color.bright_black),
            error_style: Style = Style.default().withFg(style.Color.bright_red),
        };

        widget: Widget,
        allocator: std.mem.Allocator,
        source: SourceType,
        observer: ObserverType,
        registered: bool = false,
        config: Config,
        entries: ArrayList([]u8),

        const vtable = Widget.WidgetVTable{
            .render = render,
            .deinit = deinit,
        };

        pub fn init(allocator: std.mem.Allocator, source: SourceType, config: Config) !*Self {
            const self = try allocator.create(Self);
            const ctx: *anyopaque = @ptrCast(self);
            const observer = data.makeObserver(Item, handleSourceEvent, ctx);

            self.* = .{
                .widget = .{ .vtable = &vtable },
                .allocator = allocator,
                .source = source,
                .observer = observer,
                .config = config,
                .entries = ArrayList([]u8).init(allocator),
            };

            self.source.subscribe(&self.observer);
            self.registered = true;
            self.logEvent("observer registered") catch {};
            return self;
        }

        fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
            const self: *Self = @fieldParentPtr("widget", widget);
            if (area.height == 0 or area.width == 0) return;

            buffer.writeText(area.x, area.y, self.config.header, self.config.style);

            var row: usize = 0;
            while (row < self.entries.items.len and row + 1 < area.height) : (row += 1) {
                const idx = self.entries.items.len - 1 - row;
                const entry = self.entries.items[idx];
                const entry_style = if (std.mem.indexOf(u8, entry, "failed") != null)
                    self.config.error_style
                else
                    self.config.style;
                buffer.writeText(area.x, area.y + @as(u16, @intCast(row + 1)), entry, entry_style);
            }
        }

        fn deinit(widget: *Widget) void {
            const self: *Self = @fieldParentPtr("widget", widget);
            if (self.registered) {
                self.source.unsubscribe(&self.observer);
            }
            self.clearEntries();
            self.entries.deinit();
            self.allocator.destroy(self);
        }

        fn clearEntries(self: *Self) void {
            for (self.entries.items) |entry| {
                self.allocator.free(entry);
            }
            self.entries.clearRetainingCapacity();
        }

        fn logEvent(self: *Self, msg: []const u8) !void {
            try self.entries.append(try self.allocator.dupe(u8, msg));
            if (self.entries.items.len > self.config.max_entries) {
                const removed = self.entries.orderedRemove(0);
                self.allocator.free(removed);
            }
        }

        fn onSourceEvent(self: *Self, event: EventType) void {
            var buf: [128]u8 = undefined;
            const text = switch (event) {
                .reset => std.fmt.bufPrint(&buf, "reset", .{}) catch "reset",
                .appended => |info| std.fmt.bufPrint(&buf, "append +{d}", .{info.count}) catch "append",
                .replaced => |info| std.fmt.bufPrint(&buf, "replace {d}-{d}", .{ info.range.start, info.range.end() }) catch "replace",
                .updated => |info| std.fmt.bufPrint(&buf, "update {d}", .{info.index}) catch "update",
                .failed => |err| std.fmt.bufPrint(&buf, "failed {s}", .{@errorName(err)}) catch "failed",
                .state => |state| std.fmt.bufPrint(&buf, "state {s}", .{@tagName(state)}) catch "state",
            };
            self.logEvent(text) catch {};
        }

        fn handleSourceEvent(event: EventType, ctx: ?*anyopaque) void {
            const self = @as(*Self, @ptrCast(@alignCast(ctx.?)));
            self.onSourceEvent(event);
        }
    };
}

const testing = std.testing;

fn makeSource(comptime Item: type, allocator: std.mem.Allocator) !data.InMemoryListSource(Item) {
    return data.InMemoryListSource(Item).init(allocator);
}

test "DataStateIndicator tracks appended items" {
    const Item = []const u8;
    var source = try makeSource(Item, testing.allocator);
    defer source.deinit();

    const handle = source.asListDataSource();
    var indicator = try DataStateIndicator(Item).init(testing.allocator, handle, .{});
    defer indicator.widget.deinit();

    try source.setItems(&[_][]const u8{ "a", "b" });
    try testing.expectEqual(@as(usize, 2), indicator.count);
    try testing.expect(indicator.state == .ready);
}

test "DataEventOverlay logs failures" {
    const Item = []const u8;
    var source = try makeSource(Item, testing.allocator);
    defer source.deinit();
    const handle = source.asListDataSource();
    var overlay = try DataEventOverlay(Item).init(testing.allocator, handle, .{ .max_entries = 4 });
    defer overlay.widget.deinit();

    source.fail(error.CustomFailure);
    try testing.expect(overlay.entries.items.len >= 2);
}
