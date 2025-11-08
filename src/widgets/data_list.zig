//! Data-bound ListView widget that reacts to ListDataSource events.
const std = @import("std");
const widget_mod = @import("../widget.zig");
const Widget = widget_mod.Widget;
const SizeConstraints = widget_mod.SizeConstraints;
const Buffer = @import("../terminal.zig").Buffer;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const data = @import("../data/list_source.zig");
const list_view_mod = @import("list_view.zig");

const Rect = geometry.Rect;
const Style = style.Style;
const math = std.math;

pub const VirtualizationConfig = struct {
    window_size: usize = 128,
    preload: usize = 32,
};

pub const InitOptions = struct {
    virtualization: ?VirtualizationConfig = null,
};

/// Generic data-bound list widget. Provides ListDataSource-backed rendering using ListView visuals.
pub fn DataListView(comptime Item: type) type {
    const SourceType = data.ListDataSource(Item);
    const EventType = data.Event(Item);
    const ObserverType = data.Observer(Item);
    const ListView = list_view_mod.ListView;
    const ListViewItem = list_view_mod.ListViewItem;
    const ListViewConfig = list_view_mod.ListViewConfig;

    return struct {
        const Self = @This();
        const AdapterError = std.mem.Allocator.Error;

        /// Adapter mapping items into visual rows.
        pub const Adapter = struct {
            buildItem: *const fn (allocator: std.mem.Allocator, item: Item, index: usize) AdapterError!ListViewItem,
        };

        /// Factory helpers for common adapters.
        pub const adapters = struct {
            /// Adapter that formats items with `std.fmt.allocPrint`.
            pub fn formatter(
                comptime formatterFn: fn (allocator: std.mem.Allocator, item: Item, index: usize) AdapterError![]const u8,
            ) Adapter {
                const FormatFn = formatterFn;
                return Adapter{
                    .buildItem = struct {
                        fn build(allocator: std.mem.Allocator, item: Item, index: usize) AdapterError!ListViewItem {
                            const text_slice = try FormatFn(allocator, item, index);
                            return ListViewItem{
                                .text = text_slice,
                            };
                        }
                    }.build,
                };
            }

            /// Adapter for string slices. Duplicates each string for the list view.
            pub fn text() Adapter {
                comptime {
                    const info = @typeInfo(Item);
                    switch (info) {
                        .pointer => |ptr| {
                            if (ptr.size != .slice) {
                                @compileError("text adapter requires slice items");
                            }
                            if (ptr.child != u8) {
                                @compileError("text adapter only supports []const u8 items");
                            }
                        },
                        else => @compileError("text adapter requires slice pointer type"),
                    }
                }
                return Adapter{
                    .buildItem = struct {
                        fn build(allocator: std.mem.Allocator, item: Item, index: usize) AdapterError!ListViewItem {
                            _ = index;
                            return ListViewItem{
                                .text = try allocator.dupe(u8, item),
                            };
                        }
                    }.build,
                };
            }
        };

        widget: Widget,
        allocator: std.mem.Allocator,
        source: SourceType,
        adapter: Adapter,
        list_view: *ListView,
        observer: ObserverType,
        registered: bool = false,
        state: data.State,
        last_error: ?anyerror = null,
        empty_style: Style = Style.default().withFg(style.Color.bright_black),
        virtualization: VirtualizationState = .{},

        const VirtualizationState = struct {
            enabled: bool = false,
            window_size: usize = 0,
            preload: usize = 0,
            window_start: usize = 0,
            window_end: usize = 0,
            dirty: bool = false,
        };

        const vtable = Widget.WidgetVTable{
            .render = render,
            .handleEvent = handleEvent,
            .resize = resize,
            .deinit = deinit,
            .getConstraints = getConstraints,
        };

        pub const Error = error{AllocationFailed} || std.mem.Allocator.Error || data.InMemoryListSource(Item).Error;

        pub fn init(
            allocator: std.mem.Allocator,
            source: SourceType,
            adapter: Adapter,
            config: ListViewConfig,
            options: InitOptions,
        ) !*Self {
            const self = try allocator.create(Self);
            const list_view = try ListView.init(allocator, config);
            const ctx: *anyopaque = @ptrCast(self);
            const observer = data.makeObserver(Item, handleSourceEvent, ctx);

            self.* = .{
                .widget = .{ .vtable = &vtable },
                .allocator = allocator,
                .source = source,
                .adapter = adapter,
                .list_view = list_view,
                .observer = observer,
                .state = source.state(),
            };

            if (options.virtualization) |virt| {
                self.virtualization.enabled = true;
                self.virtualization.window_size = if (virt.window_size == 0) 64 else virt.window_size;
                self.virtualization.preload = virt.preload;
                self.virtualization.window_start = 0;
                self.virtualization.window_end = 0;
                self.virtualization.dirty = true;
                self.list_view.setVirtualTotal(self.source.len());
            }

            self.source.subscribe(&self.observer);
            self.registered = true;

            // If the data source already has content, request the initial range.
            try self.fullRefresh();
            return self;
        }

        pub fn setEmptyStyle(self: *Self, style_override: Style) void {
            self.empty_style = style_override;
        }

        fn fullRefresh(self: *Self) AdapterError!void {
            if (self.virtualization.enabled) {
                self.virtualization.dirty = true;
                try self.ensureVirtualWindow(self.list_view.viewport_height);
                return;
            }

            self.clearItems();
            const count = self.source.len();
            var index: usize = 0;
            while (index < count) : (index += 1) {
                if (self.source.get(index)) |item| {
                    try self.appendItem(item, index);
                }
            }
        }

        fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
            const self: *Self = @fieldParentPtr("widget", widget);

            if (self.virtualization.enabled) {
                self.ensureVirtualWindow(area.height) catch |err| {
                    self.last_error = err;
                    self.state = .failed;
                };
            }

            const is_empty = self.list_view.items.items.len == 0;

            if (self.state == .loading and is_empty) {
                buffer.writeText(area.x, area.y, "Loading…", self.empty_style);
                return;
            }

            if (self.state == .failed and is_empty) {
                var msg_store: [96]u8 = undefined;
                const message = if (self.last_error) |err|
                    std.fmt.bufPrint(&msg_store, "Data failed: {s}", .{@errorName(err)}) catch "Data failed"
                else
                    "Data failed";
                buffer.writeText(area.x, area.y, message, self.empty_style);
                return;
            }

            if (is_empty) {
                buffer.writeText(area.x, area.y, "No data", self.empty_style);
                return;
            }

            self.list_view.widget.render(buffer, area);
        }

        fn handleEvent(widget: *Widget, event: Event) bool {
            const self: *Self = @fieldParentPtr("widget", widget);
            return self.list_view.widget.handleEvent(event);
        }

        fn resize(widget: *Widget, area: Rect) void {
            const self: *Self = @fieldParentPtr("widget", widget);
            self.list_view.widget.resize(area);
            if (self.virtualization.enabled) {
                self.virtualization.dirty = true;
            }
        }

        fn getConstraints(widget: *Widget) SizeConstraints {
            const self: *Self = @fieldParentPtr("widget", widget);
            return self.list_view.widget.getConstraints();
        }

        fn deinit(widget: *Widget) void {
            const self: *Self = @fieldParentPtr("widget", widget);
            if (self.registered) {
                self.source.unsubscribe(&self.observer);
                self.registered = false;
            }
            self.clearItems();
            self.list_view.widget.deinit();
            self.allocator.destroy(self);
        }

        fn clearItemsInternal(self: *Self, reset_state: bool) void {
            if (self.list_view.items.items.len != 0) {
                for (self.list_view.items.items) |*item| {
                    self.releaseListViewItem(item);
                }
                self.list_view.items.clearRetainingCapacity();
            }

            if (reset_state) {
                self.list_view.selected_index = null;
                self.list_view.hovered_index = null;
                self.list_view.scroll_offset = 0;
            }
        }

        fn clearItems(self: *Self) void {
            self.clearItemsInternal(true);
            if (self.virtualization.enabled) {
                self.virtualization.window_start = 0;
                self.virtualization.window_end = 0;
                self.virtualization.dirty = true;
            }
        }

        fn appendItem(self: *Self, item: Item, index: usize) AdapterError!void {
            const new_item = try self.adapter.buildItem(self.allocator, item, index);
            try self.list_view.items.append(new_item);
            if (self.list_view.selected_index == null and self.list_view.items.items.len > 0) {
                self.list_view.selected_index = 0;
            }
        }

        fn replaceSlice(self: *Self, start: usize, items: []const Item) AdapterError!void {
            var i: usize = 0;
            while (i < items.len) : (i += 1) {
                const idx = start + i;
                if (idx >= self.list_view.items.items.len) break;
                self.releaseListViewItem(&self.list_view.items.items[idx]);
                self.list_view.items.items[idx] = try self.adapter.buildItem(self.allocator, items[i], idx);
            }
        }

        fn updateItem(self: *Self, index: usize, item: Item) AdapterError!void {
            if (index >= self.list_view.items.items.len) return;
            self.releaseListViewItem(&self.list_view.items.items[index]);
            self.list_view.items.items[index] = try self.adapter.buildItem(self.allocator, item, index);
        }

        fn releaseListViewItem(self: *Self, item: *ListViewItem) void {
            self.allocator.free(item.text);
            if (item.secondary_text) |sec| {
                self.allocator.free(sec);
            }
            item.* = undefined;
        }

        fn ensureVirtualWindow(self: *Self, viewport_height: u16) AdapterError!void {
            if (!self.virtualization.enabled) return;

            const total = self.source.len();
            self.list_view.setVirtualTotal(total);

            if (total == 0) {
                self.clearItemsInternal(false);
                self.virtualization.window_start = 0;
                self.virtualization.window_end = 0;
                self.virtualization.dirty = false;
                return;
            }

            const visible_start = self.list_view.scroll_offset;
            const item_height = if (self.list_view.item_height == 0) 1 else self.list_view.item_height;
            const viewport_rows = if (viewport_height == 0)
                @max(self.virtualization.window_size, 1)
            else
                @max(@as(usize, viewport_height / item_height), 1);

            const preload = self.virtualization.preload;
            const start = if (visible_start > preload) visible_start - preload else 0;
            var desired_end = visible_start + viewport_rows + preload;
            if (desired_end > total) desired_end = total;
            if (desired_end < start) desired_end = start;

            const double_preload = math.mul(usize, preload, 2) catch std.math.maxInt(usize);
            var max_window = math.add(usize, self.virtualization.window_size, double_preload) catch std.math.maxInt(usize);
            if (max_window == 0) max_window = 1;
            if (max_window > total) max_window = total;

            const span = desired_end - start;
            if (span > max_window) {
                desired_end = math.add(usize, start, max_window) catch total;
                if (desired_end > total) desired_end = total;
            }

            const needs_reload = self.virtualization.dirty or
                start < self.virtualization.window_start or
                desired_end > self.virtualization.window_end or
                (desired_end - start) > self.list_view.items.items.len;

            if (!needs_reload) return;

            try self.reloadVirtualWindow(start, desired_end);
        }

        fn reloadVirtualWindow(self: *Self, start: usize, end: usize) AdapterError!void {
            self.clearItemsInternal(false);

            var index = start;
            while (index < end) : (index += 1) {
                if (self.source.get(index)) |item| {
                    try self.appendItem(item, index);
                }
            }

            self.virtualization.window_start = start;
            self.virtualization.window_end = end;
            self.virtualization.dirty = false;
            self.list_view.setVirtualWindowStart(start);
        }

        fn onSourceEvent(self: *Self, event: EventType) void {
            switch (event) {
                .reset => {
                    self.clearItems();
                    if (self.virtualization.enabled) {
                        self.list_view.setVirtualTotal(self.source.len());
                    }
                },
                .appended => |info| {
                    if (self.virtualization.enabled) {
                        self.virtualization.dirty = true;
                        self.list_view.setVirtualTotal(self.source.len());
                    } else {
                        const start_index = self.list_view.items.items.len;
                        var i: usize = 0;
                        while (i < info.items.len) : (i += 1) {
                            self.appendItem(info.items[i], start_index + i) catch |err| {
                                self.last_error = err;
                                break;
                            };
                        }
                    }
                },
                .replaced => |info| {
                    if (self.virtualization.enabled) {
                        self.virtualization.dirty = true;
                    } else {
                        self.replaceSlice(info.range.start, info.items) catch |err| {
                            self.last_error = err;
                        };
                    }
                },
                .updated => |info| {
                    if (self.virtualization.enabled) {
                        self.virtualization.dirty = true;
                    } else {
                        self.updateItem(info.index, info.item) catch |err| {
                            self.last_error = err;
                        };
                    }
                },
                .failed => |err| {
                    self.last_error = err;
                    self.state = .failed;
                    self.clearItems();
                    if (self.virtualization.enabled) {
                        self.list_view.setVirtualTotal(self.source.len());
                    }
                },
                .state => |state| {
                    self.state = state;
                    if (state == .ready and self.list_view.items.items.len == 0) {
                        self.fullRefresh() catch |err| {
                            self.last_error = err;
                        };
                    }
                    if (self.virtualization.enabled) {
                        self.virtualization.dirty = true;
                    }
                },
            }
        }

        fn handleSourceEvent(event: EventType, ctx: ?*anyopaque) void {
            const self = @as(*Self, @ptrCast(@alignCast(ctx.?)));
            self.onSourceEvent(event);
        }
    };
}

/// Compile-time macro for convenient construction.
pub fn dataListView(
    comptime Item: type,
    allocator: std.mem.Allocator,
    source: data.ListDataSource(Item),
    adapter: DataListView(Item).Adapter,
    config: list_view_mod.ListViewConfig,
) !*DataListView(Item) {
    return try DataListView(Item).init(allocator, source, adapter, config, .{});
}

const testing = std.testing;

test "DataListView populates from in-memory source" {
    const Item = []const u8;
    const SourceType = data.InMemoryListSource(Item);
    var source = SourceType.init(testing.allocator);
    defer source.deinit();

    try source.setItems(&[_][]const u8{ "alpha", "beta", "gamma" });

    const handle = source.asListDataSource();
    const adapter = DataListView(Item).adapters.text();
    const config = list_view_mod.ListViewConfig{};
    var widget = try DataListView(Item).init(testing.allocator, handle, adapter, config, .{});
    defer widget.widget.deinit();

    try testing.expectEqual(@as(usize, 3), widget.list_view.items.items.len);
    try testing.expectEqualStrings("alpha", widget.list_view.items.items[0].text);
}

test "DataListView virtualizes large sources" {
    const Item = []const u8;
    const SourceType = data.InMemoryListSource(Item);
    var source = SourceType.init(testing.allocator);
    defer source.deinit();

    var items: [128][]const u8 = undefined;
    for (items, 0..) |*slot, idx| {
        var buf: [24]u8 = undefined;
        const len = std.fmt.bufPrint(&buf, "item {d}", .{idx}) catch 0;
        slot.* = try testing.allocator.dupe(u8, buf[0..len]);
    }
    defer {
        for (items) |text| {
            testing.allocator.free(text);
        }
    }
    try source.setItems(items[0..]);

    const handle = source.asListDataSource();
    const adapter = DataListView(Item).adapters.text();
    const config = list_view_mod.ListViewConfig{ .viewport_height = 5 };
    const options = InitOptions{ .virtualization = .{ .window_size = 32, .preload = 8 } };
    var widget = try DataListView(Item).init(testing.allocator, handle, adapter, config, options);
    defer widget.widget.deinit();

    var buffer = try Buffer.init(testing.allocator, geometry.Size.init(40, 6));
    defer buffer.deinit();

    widget.widget.render(&buffer, Rect.init(0, 0, 40, 6));
    try testing.expect(widget.list_view.items.items.len <= 32 + 8 + 6);
    try testing.expectEqual(@as(usize, 0), widget.virtualization.window_start);

    widget.list_view.scroll_offset = 64;
    widget.virtualization.dirty = true;
    widget.widget.render(&buffer, Rect.init(0, 0, 40, 6));
    try testing.expect(widget.virtualization.window_start <= 64);
    try testing.expect(widget.virtualization.window_end > 64);

    const local_index = widget.list_view.scroll_offset - widget.virtualization.window_start;
    try testing.expect(local_index < widget.list_view.items.items.len);

    var expect_buf: [24]u8 = undefined;
    const expect_len = std.fmt.bufPrint(&expect_buf, "item {d}", .{widget.list_view.scroll_offset}) catch 0;
    try testing.expectEqualStrings(expect_buf[0..expect_len], widget.list_view.items.items[local_index].text);

    try testing.expectEqual(widget.list_view.virtual_window_start, widget.virtualization.window_start);
}
