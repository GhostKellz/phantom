//! Widget system module exports
const std = @import("std");
const config = @import("phantom_config");

// Core widget types - always available
pub const Widget = @import("../widget.zig").Widget;

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

// v0.5.0: Advanced text editor for Grim - always available
pub const editor = @import("editor/mod.zig");

// v0.6.0: Essential widgets for modern TUI applications - always available
pub const ScrollView = if (config.enable_advanced) @import("scroll_view.zig").ScrollView else void;
pub const ListView = if (config.enable_advanced) @import("list_view.zig").ListView else void;
pub const RichText = if (config.enable_advanced) @import("rich_text.zig").RichText else void;
pub const Border = if (config.enable_basic_widgets) @import("border.zig").Border else void;
pub const Spinner = if (config.enable_basic_widgets) @import("spinner.zig").Spinner else void;

// v0.6.0: Flexible layout system - always available
pub const flex = if (config.enable_advanced) @import("flex.zig") else void;
pub const FlexRow = if (config.enable_advanced) @import("flex.zig").FlexRow else void;
pub const FlexColumn = if (config.enable_advanced) @import("flex.zig").FlexColumn else void;
pub const FlexChild = if (config.enable_advanced) @import("flex.zig").FlexChild else void;
pub const Alignment = if (config.enable_advanced) @import("flex.zig").Alignment else void;
pub const Justify = if (config.enable_advanced) @import("flex.zig").Justify else void;

// v0.6.1: Container widgets for composition - always available
pub const Stack = if (config.enable_advanced) @import("stack.zig").Stack else void;
pub const Tabs = if (config.enable_advanced) @import("tabs.zig").Tabs else void;

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

    // v0.6.0 widget tests
    _ = @import("scroll_view.zig");
    _ = @import("list_view.zig");
    _ = @import("rich_text.zig");
    _ = @import("border.zig");
    _ = @import("spinner.zig");
    _ = @import("flex.zig");

    // v0.6.1 widget tests
    _ = @import("container.zig");
    _ = @import("stack.zig");
    _ = @import("tabs.zig");
}
