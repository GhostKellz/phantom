//! Table widget (placeholder)
const std = @import("std");
const Widget = @import("../app.zig").Widget;

pub const Table = struct {
    widget: Widget,

    pub fn init() Table {
        return Table{
            .widget = Widget{ .vtable = undefined },
        };
    }
};
