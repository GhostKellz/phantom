//! Widget system module exports
const std = @import("std");
const config = @import("phantom_config");

// Core widget types - always available
pub const Widget = @import("../app.zig").Widget;

// Basic widgets - conditionally exported
pub const Text = if (config.enable_basic_widgets) @import("text.zig").Text else void;
pub const Block = if (config.enable_basic_widgets) @import("block.zig").Block else void;
pub const List = if (config.enable_basic_widgets) @import("list.zig").List else void;
pub const Button = if (config.enable_basic_widgets) @import("button.zig").Button else void;
pub const Input = if (config.enable_basic_widgets) @import("input.zig").Input else void;
pub const TextArea = if (config.enable_basic_widgets) @import("textarea.zig").TextArea else void;

// Data display widgets - conditionally exported
pub const ProgressBar = if (config.enable_data_widgets) @import("progress.zig").ProgressBar else void;
pub const Table = if (config.enable_data_widgets) @import("table.zig").Table else void;
pub const TaskMonitor = if (config.enable_data_widgets) @import("task_monitor.zig").TaskMonitor else void;

// Advanced widgets - conditionally exported
pub const StreamingText = if (config.enable_advanced) @import("streaming_text.zig").StreamingText else void;
pub const CodeBlock = if (config.enable_advanced) @import("code_block.zig").CodeBlock else void;
pub const Container = if (config.enable_advanced) @import("container.zig").Container else void;
pub const ThemePicker = if (config.enable_advanced) @import("theme_picker.zig").ThemePicker else void;

// Package management widgets - conditionally exported
pub const UniversalPackageBrowser = if (config.enable_package_mgmt) @import("universal_package_browser.zig").UniversalPackageBrowser else void;
pub const AURDependencies = if (config.enable_package_mgmt) @import("aur_dependencies.zig").AURDependencies else void;

// Blockchain/crypto widgets - conditionally exported
pub const BlockchainPackageBrowser = if (config.enable_crypto) @import("blockchain_package_browser.zig").BlockchainPackageBrowser else void;

// Development tools widgets - conditionally exported
pub const CommandBuilder = if (config.enable_system) @import("command_builder.zig").CommandBuilder else void;
pub const NetworkTopology = if (config.enable_system) @import("network_topology.zig").NetworkTopology else void;
pub const SystemMonitor = if (config.enable_system) @import("system_monitor.zig").SystemMonitor else void;

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
