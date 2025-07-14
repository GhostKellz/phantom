//! Widget system module exports
const std = @import("std");

// Core widget types
pub const Widget = @import("../app.zig").Widget;

// Basic widgets
pub const Text = @import("text.zig").Text;
pub const Block = @import("block.zig").Block;
pub const List = @import("list.zig").List;

// More complex widgets
pub const ProgressBar = @import("progress.zig").ProgressBar;
pub const Table = @import("table.zig").Table;

// Container widgets
pub const Container = @import("container.zig").Container;

test {
    // Import all widget tests
    _ = @import("text.zig");
    _ = @import("block.zig");
    _ = @import("list.zig");
}
