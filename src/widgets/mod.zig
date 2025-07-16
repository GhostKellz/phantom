//! Widget system module exports
const std = @import("std");

// Core widget types
pub const Widget = @import("../app.zig").Widget;

// Basic widgets
pub const Text = @import("text.zig").Text;
pub const Block = @import("block.zig").Block;
pub const List = @import("list.zig").List;

// Interactive widgets
pub const Button = @import("button.zig").Button;
pub const Input = @import("input.zig").Input;
pub const TextArea = @import("textarea.zig").TextArea;

// Data display widgets
pub const ProgressBar = @import("progress.zig").ProgressBar;
pub const Table = @import("table.zig").Table;
pub const TaskMonitor = @import("task_monitor.zig").TaskMonitor;

// Advanced widgets
pub const StreamingText = @import("streaming_text.zig").StreamingText;
pub const CodeBlock = @import("code_block.zig").CodeBlock;

// Container widgets
pub const Container = @import("container.zig").Container;

// Package management widgets
pub const UniversalPackageBrowser = @import("universal_package_browser.zig").UniversalPackageBrowser;
pub const AURDependencies = @import("aur_dependencies.zig").AURDependencies;
pub const BlockchainPackageBrowser = @import("blockchain_package_browser.zig").BlockchainPackageBrowser;

// Development tools widgets
pub const CommandBuilder = @import("command_builder.zig").CommandBuilder;
pub const NetworkTopology = @import("network_topology.zig").NetworkTopology;
pub const SystemMonitor = @import("system_monitor.zig").SystemMonitor;

test {
    // Import all widget tests
    _ = @import("text.zig");
    _ = @import("block.zig");
    _ = @import("list.zig");
    _ = @import("button.zig");
    _ = @import("input.zig");
    _ = @import("textarea.zig");
    _ = @import("progress.zig");
    _ = @import("table.zig");
    _ = @import("task_monitor.zig");
    _ = @import("streaming_text.zig");
    _ = @import("code_block.zig");
    
    // Import new widget tests
    _ = @import("universal_package_browser.zig");
    _ = @import("aur_dependencies.zig");
    _ = @import("blockchain_package_browser.zig");
    _ = @import("command_builder.zig");
    _ = @import("network_topology.zig");
    _ = @import("system_monitor.zig");
}
