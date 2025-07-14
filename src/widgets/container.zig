//! Container widget (placeholder)
const std = @import("std");
const Widget = @import("../app.zig").Widget;

pub const Container = struct {
    widget: Widget,

    pub fn init() Container {
        return Container{
            .widget = Widget{ .vtable = undefined },
        };
    }
};
