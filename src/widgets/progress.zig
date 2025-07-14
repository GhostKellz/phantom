//! Progress bar widget (placeholder)
const std = @import("std");
const Widget = @import("../app.zig").Widget;

pub const ProgressBar = struct {
    widget: Widget,

    pub fn init() ProgressBar {
        return ProgressBar{
            .widget = Widget{ .vtable = undefined },
        };
    }
};
