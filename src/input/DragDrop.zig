//! DragDrop - Drag and drop support for widgets
//! Handles drag and drop operations with type-safe data transfer

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");

const Allocator = std.mem.Allocator;
const Point = geometry.Point;
const Rect = geometry.Rect;

/// Drag and drop manager
pub const DragDropManager = struct {
    allocator: Allocator,
    current_drag: ?DragOperation = null,
    drop_zones: std.array_list.AlignedManaged(DropZone, null),

    pub fn init(allocator: Allocator) DragDropManager {
        return DragDropManager{
            .allocator = allocator,
            .drop_zones = std.array_list.AlignedManaged(DropZone, null).init(allocator),
        };
    }

    pub fn deinit(self: *DragDropManager) void {
        if (self.current_drag) |*drag| {
            drag.deinit(self.allocator);
        }
        self.drop_zones.deinit();
    }

    /// Start a drag operation
    pub fn startDrag(self: *DragDropManager, source: DragSource, data: DragData, position: Point) !void {
        // End any existing drag
        if (self.current_drag) |*drag| {
            drag.deinit(self.allocator);
        }

        self.current_drag = DragOperation{
            .source = source,
            .data = data,
            .start_position = position,
            .current_position = position,
            .state = .dragging,
        };
    }

    /// Update drag position
    pub fn updateDrag(self: *DragDropManager, position: Point) void {
        if (self.current_drag) |*drag| {
            drag.current_position = position;
        }
    }

    /// End drag operation and attempt drop
    pub fn endDrag(self: *DragDropManager, position: Point) !?DropResult {
        if (self.current_drag) |*drag| {
            defer {
                drag.deinit(self.allocator);
                self.current_drag = null;
            }

            // Find drop zone at position
            for (self.drop_zones.items) |drop_zone| {
                if (drop_zone.bounds.containsPoint(position)) {
                    // Check if drop zone accepts this data type
                    if (drop_zone.accepts_data_type(drag.data.data_type)) {
                        return DropResult{
                            .target = drop_zone.target,
                            .data = drag.data,
                            .position = position,
                            .source = drag.source,
                        };
                    }
                }
            }
        }

        return null;
    }

    /// Cancel current drag operation
    pub fn cancelDrag(self: *DragDropManager) void {
        if (self.current_drag) |*drag| {
            drag.deinit(self.allocator);
            self.current_drag = null;
        }
    }

    /// Register a drop zone
    pub fn registerDropZone(self: *DragDropManager, drop_zone: DropZone) !void {
        try self.drop_zones.append(drop_zone);
    }

    /// Unregister a drop zone
    pub fn unregisterDropZone(self: *DragDropManager, target: vxfw.Widget) void {
        var i: usize = 0;
        while (i < self.drop_zones.items.len) {
            if (std.meta.eql(self.drop_zones.items[i].target, target)) {
                _ = self.drop_zones.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Get current drag operation
    pub fn getCurrentDrag(self: *const DragDropManager) ?DragOperation {
        return self.current_drag;
    }

    /// Check if currently dragging
    pub fn isDragging(self: *const DragDropManager) bool {
        return self.current_drag != null;
    }
};

/// Drag operation state
pub const DragOperation = struct {
    source: DragSource,
    data: DragData,
    start_position: Point,
    current_position: Point,
    state: DragState,

    pub fn deinit(self: *DragOperation, allocator: Allocator) void {
        self.data.deinit(allocator);
    }

    pub fn getDragDistance(self: *const DragOperation) f32 {
        const dx = @as(f32, @floatFromInt(self.current_position.x - self.start_position.x));
        const dy = @as(f32, @floatFromInt(self.current_position.y - self.start_position.y));
        return @sqrt(dx * dx + dy * dy);
    }
};

pub const DragState = enum {
    starting,
    dragging,
    dropping,
    cancelled,
};

/// Source of a drag operation
pub const DragSource = struct {
    widget: vxfw.Widget,
    item_id: ?[]const u8 = null,
    metadata: ?*anyopaque = null,
};

/// Drop target zone
pub const DropZone = struct {
    target: vxfw.Widget,
    bounds: Rect,
    accepted_types: []const DataType,

    pub fn accepts_data_type(self: *const DropZone, data_type: DataType) bool {
        for (self.accepted_types) |accepted| {
            if (std.meta.eql(accepted, data_type)) {
                return true;
            }
        }
        return false;
    }
};

/// Result of a successful drop operation
pub const DropResult = struct {
    target: vxfw.Widget,
    data: DragData,
    position: Point,
    source: DragSource,
};

/// Data being dragged
pub const DragData = struct {
    data_type: DataType,
    data: []const u8,

    pub fn init(allocator: Allocator, data_type: DataType, data: []const u8) !DragData {
        return DragData{
            .data_type = data_type,
            .data = try allocator.dupe(u8, data),
        };
    }

    pub fn deinit(self: *const DragData, allocator: Allocator) void {
        allocator.free(self.data);
    }

    /// Create text drag data
    pub fn text(allocator: Allocator, text_data: []const u8) !DragData {
        return init(allocator, .text, text_data);
    }

    /// Create file drag data
    pub fn file(allocator: Allocator, file_path: []const u8) !DragData {
        return init(allocator, .file, file_path);
    }

    /// Create custom drag data
    pub fn custom(allocator: Allocator, type_name: []const u8, data: []const u8) !DragData {
        return init(allocator, DataType{ .custom = type_name }, data);
    }
};

/// Data type for drag and drop operations
pub const DataType = union(enum) {
    text,
    file,
    image,
    url,
    custom: []const u8,
};

/// Widget mixin for drag and drop support
pub fn DragDropWidget(comptime WidgetType: type) type {
    return struct {
        widget: WidgetType,
        drag_manager: *DragDropManager,
        is_drag_source: bool = false,
        is_drop_target: bool = false,
        accepted_types: []const DataType = &[_]DataType{},
        drag_threshold: f32 = 5.0,

        const Self = @This();

        pub fn init(widget: WidgetType, drag_manager: *DragDropManager) Self {
            return Self{
                .widget = widget,
                .drag_manager = drag_manager,
            };
        }

        /// Enable this widget as a drag source
        pub fn enableDragSource(self: *Self) void {
            self.is_drag_source = true;
        }

        /// Enable this widget as a drop target
        pub fn enableDropTarget(self: *Self, accepted_types: []const DataType) !void {
            self.is_drop_target = true;
            self.accepted_types = accepted_types;
        }

        /// Register drop zone for this widget
        pub fn registerDropZone(self: *Self, bounds: Rect) !void {
            if (self.is_drop_target) {
                const drop_zone = DropZone{
                    .target = self.widget_interface(),
                    .bounds = bounds,
                    .accepted_types = self.accepted_types,
                };
                try self.drag_manager.registerDropZone(drop_zone);
            }
        }

        /// Unregister drop zone for this widget
        pub fn unregisterDropZone(self: *Self) void {
            self.drag_manager.unregisterDropZone(self.widget_interface());
        }

        /// Start dragging from this widget
        pub fn startDrag(self: *Self, data: DragData, position: Point) !vxfw.Command {
            if (self.is_drag_source) {
                const source = DragSource{
                    .widget = self.widget_interface(),
                };
                try self.drag_manager.startDrag(source, data, position);
                return vxfw.Command{ .set_mouse_shape = .grabbing };
            }
            return vxfw.Command.redraw;
        }

        pub fn widget_interface(self: *const Self) vxfw.Widget {
            return .{
                .userdata = @constCast(self),
                .drawFn = typeErasedDrawFn,
                .eventHandlerFn = typeErasedEventHandler,
            };
        }

        fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
            const self: *const Self = @ptrCast(@alignCast(ptr));

            // Draw the underlying widget
            const surface = try self.widget.draw(ctx);

            // Add drag visual feedback if currently dragging
            if (self.drag_manager.getCurrentDrag()) |drag| {
                if (std.meta.eql(drag.source.widget, self.widget_interface())) {
                    // Add visual feedback for drag source (e.g., dimmed appearance)
                    // This would need surface manipulation capabilities
                }
            }

            return surface;
        }

        fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
            const self: *Self = @ptrCast(@alignCast(ptr));
            var commands = ctx.createCommandList();

            // Handle drag and drop events
            switch (ctx.event) {
                .mouse => |mouse| {
                    if (ctx.isMouseEvent()) |_| {
                        const local_pos = ctx.getLocalMousePosition() orelse return commands;

                        switch (mouse.action) {
                            .press => {
                                if (mouse.button == .left and self.is_drag_source) {
                                    // Potential drag start - we'll wait for movement
                                    // The actual drag would start in the move handler
                                }
                            },
                            .move => {
                                if (self.drag_manager.isDragging()) {
                                    self.drag_manager.updateDrag(local_pos);
                                    try commands.append(.redraw);
                                }
                            },
                            .release => {
                                if (mouse.button == .left and self.drag_manager.isDragging()) {
                                    if (self.drag_manager.endDrag(local_pos)) |drop_result| {
                                        // Create drop event
                                        const drop_event = vxfw.Event{
                                            .user = .{
                                                .data = @ptrCast(&drop_result),
                                                .type_name = "drop",
                                            }
                                        };

                                        // Forward to target widget
                                        const drop_ctx = vxfw.EventContext.init(drop_event, ctx.arena, ctx.bounds);
                                        const drop_commands = try drop_result.target.handleEvent(drop_ctx);
                                        for (drop_commands.items) |cmd| {
                                            try commands.append(cmd);
                                        }
                                    } else {
                                        // Drop failed - could emit cancelled event
                                        self.drag_manager.cancelDrag();
                                    }

                                    try commands.append(vxfw.Command{ .set_mouse_shape = .default });
                                    try commands.append(.redraw);
                                }
                            },
                        }
                    }
                },
                .user => |user_event| {
                    if (std.mem.eql(u8, user_event.type_name, "drop")) {
                        _ = user_event.data;
                        // Handle the drop in the underlying widget
                        return self.widget.handleEvent(ctx);
                    }
                },
                else => {},
            }

            // Forward other events to underlying widget
            const widget_commands = try self.widget.handleEvent(ctx);
            for (widget_commands.items) |cmd| {
                try commands.append(cmd);
            }

            return commands;
        }
    };
}

/// Enhanced ListView with drag and drop support
pub const DragDropListView = DragDropWidget(vxfw.ListView);

/// Enhanced TextField with drag and drop support
pub const DragDropTextField = DragDropWidget(vxfw.TextField);

test "DragDropManager basic functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var manager = DragDropManager.init(arena.allocator());
    defer manager.deinit();

    // Test initial state
    try std.testing.expect(!manager.isDragging());

    // Test drag operation
    const drag_data = try DragData.text(arena.allocator(), "test data");
    const source = DragSource{ .widget = undefined };

    try manager.startDrag(source, drag_data, Point{ .x = 10, .y = 10 });
    try std.testing.expect(manager.isDragging());

    // Test drag update
    manager.updateDrag(Point{ .x = 15, .y = 15 });
    const current_drag = manager.getCurrentDrag().?;
    try std.testing.expectEqual(@as(i16, 15), current_drag.current_position.x);

    // Test drag distance
    try std.testing.expect(current_drag.getDragDistance() > 0);
}

test "DropZone accepts data type" {
    const accepted_types = [_]DataType{ .text, .file };
    const drop_zone = DropZone{
        .target = undefined,
        .bounds = Rect.init(0, 0, 10, 10),
        .accepted_types = &accepted_types,
    };

    try std.testing.expect(drop_zone.accepts_data_type(.text));
    try std.testing.expect(drop_zone.accepts_data_type(.file));
    try std.testing.expect(!drop_zone.accepts_data_type(.image));
}