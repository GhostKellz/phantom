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
pub const TaskStatus = if (config.enable_data_widgets) @import("task_monitor.zig").TaskStatus else void;
pub const DataListView = if (config.enable_data_widgets) @import("data_list.zig").DataListView else void;
pub const dataListView = if (config.enable_data_widgets) @import("data_list.zig").dataListView else void;
pub const DataStateIndicator = if (config.enable_data_widgets) @import("data_status.zig").DataStateIndicator else void;
pub const DataBadge = if (config.enable_data_widgets) @import("data_status.zig").DataBadge else void;
pub const DataEventOverlay = if (config.enable_data_widgets) @import("data_status.zig").DataEventOverlay else void;
pub const ThemeTokenDashboard = if (config.enable_data_widgets) @import("theme_dashboard.zig").ThemeTokenDashboard else void;
pub const ThemeToken = if (config.enable_data_widgets) @import("theme_dashboard.zig").ThemeToken else void;
pub const ThemeTokenKind = if (config.enable_data_widgets) @import("theme_dashboard.zig").Kind else void;
pub const buildThemeTokenEntries = if (config.enable_data_widgets) @import("theme_dashboard.zig").buildThemeTokenEntries else void;

// Advanced widgets - conditionally exported
pub const StreamingText = if (config.enable_advanced) @import("streaming_text.zig").StreamingText else void;
pub const CodeBlock = if (config.enable_advanced) @import("code_block.zig").CodeBlock else void;
pub const Container = if (config.enable_advanced) @import("container.zig").Container else void;
pub const ThemePicker = if (config.enable_advanced) @import("theme_picker.zig").ThemePicker else void;
pub const StatusBar = if (config.enable_advanced) @import("status_bar.zig").StatusBar else void;
pub const ToastOverlay = if (config.enable_advanced) @import("toast_overlay.zig").ToastOverlay else void;
pub const Popover = if (config.enable_advanced) @import("popover.zig").Popover else void;
pub const Terminal = if (config.enable_terminal_widget) @import("terminal.zig").Terminal else void;

// Package management widgets - conditionally exported
pub const UniversalPackageBrowser = if (config.enable_package_mgmt) @import("universal_package_browser.zig").UniversalPackageBrowser else void;
pub const AURDependencies = if (config.enable_package_mgmt) @import("aur_dependencies.zig").AURDependencies else void;

// Blockchain/crypto widgets - conditionally exported
pub const BlockchainPackageBrowser = if (config.enable_crypto) @import("blockchain_package_browser.zig").BlockchainPackageBrowser else void;

// Development tools widgets - conditionally exported
pub const CommandBuilder = if (config.enable_system) @import("command_builder.zig").CommandBuilder else void;
pub const NetworkTopology = if (config.enable_system) @import("network_topology.zig").NetworkTopology else void;
pub const SystemMonitor = if (config.enable_system) @import("system_monitor.zig").SystemMonitor else void;

// Advanced text editor
pub const editor = @import("editor/mod.zig");

// Essential widgets
pub const ScrollView = if (config.enable_advanced) @import("scroll_view.zig").ScrollView else void;
pub const ListView = if (config.enable_advanced) @import("list_view.zig").ListView else void;
pub const ListViewConfig = if (config.enable_advanced) @import("list_view.zig").ListViewConfig else void;
pub const RichText = if (config.enable_advanced) @import("rich_text.zig").RichText else void;
pub const Border = if (config.enable_basic_widgets) @import("border.zig").Border else void;
pub const Spinner = if (config.enable_basic_widgets) @import("spinner.zig").Spinner else void;

// Flexible layout system
pub const flex = if (config.enable_advanced) @import("flex.zig") else void;
pub const FlexRow = if (config.enable_advanced) @import("flex.zig").FlexRow else void;
pub const FlexColumn = if (config.enable_advanced) @import("flex.zig").FlexColumn else void;
pub const FlexChild = if (config.enable_advanced) @import("flex.zig").FlexChild else void;
pub const Alignment = if (config.enable_advanced) @import("flex.zig").Alignment else void;
pub const Justify = if (config.enable_advanced) @import("flex.zig").Justify else void;

// Container widgets for composition
pub const Stack = if (config.enable_advanced) @import("stack.zig").Stack else void;
pub const Tabs = if (config.enable_advanced) @import("tabs.zig").Tabs else void;

// Data visualization widgets
pub const BarChart = if (config.enable_data_widgets) @import("bar_chart.zig").BarChart else void;
pub const Chart = if (config.enable_data_widgets) @import("chart.zig").Chart else void;
pub const Gauge = if (config.enable_data_widgets) @import("gauge.zig").Gauge else void;
pub const Sparkline = if (config.enable_data_widgets) @import("sparkline.zig").Sparkline else void;
pub const Scrollbar = if (config.enable_basic_widgets) @import("scrollbar.zig").Scrollbar else void;
pub const ScrollbarState = if (config.enable_basic_widgets) @import("scrollbar.zig").ScrollbarState else void;
pub const ScrollbarOrientation = if (config.enable_basic_widgets) @import("scrollbar.zig").ScrollbarOrientation else void;
pub const Calendar = if (config.enable_advanced) @import("calendar.zig").Calendar else void;
pub const Canvas = if (config.enable_advanced) @import("canvas.zig").Canvas else void;

// Widget presets for common use cases
pub const presets = if (config.enable_data_widgets or config.enable_advanced) @import("presets.zig") else void;
pub const Presets = if (config.enable_data_widgets or config.enable_advanced) @import("presets.zig").Presets else void;
pub const DashboardLayouts = if (config.enable_data_widgets or config.enable_advanced) @import("presets.zig").DashboardLayouts else void;

// Syntax highlighting with Grove
pub const SyntaxHighlight = if (config.enable_advanced) @import("syntax_highlight.zig").SyntaxHighlight else void;

// Hierarchical data widgets
pub const Tree = if (config.enable_advanced) @import("tree.zig").Tree else void;
pub const TreeNode = if (config.enable_advanced) @import("tree.zig").TreeNode else void;

// Git/comparison widgets
pub const Diff = if (config.enable_advanced) @import("diff.zig").Diff else void;
pub const DiffHunk = if (config.enable_advanced) @import("diff.zig").DiffHunk else void;
pub const DiffLine = if (config.enable_advanced) @import("diff.zig").DiffLine else void;

// Document viewers
pub const Markdown = if (config.enable_advanced) @import("markdown.zig").Markdown else void;

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
    _ = @import("data_list.zig");
    _ = @import("data_status.zig");
    _ = @import("theme_dashboard.zig");
    _ = @import("streaming_text.zig");
    _ = @import("code_block.zig");

    // Import new widget tests
    _ = @import("universal_package_browser.zig");
    _ = @import("aur_dependencies.zig");
    _ = @import("blockchain_package_browser.zig");
    _ = @import("command_builder.zig");
    _ = @import("network_topology.zig");
    _ = @import("system_monitor.zig");

    _ = @import("scroll_view.zig");
    _ = @import("list_view.zig");
    _ = @import("rich_text.zig");
    _ = @import("border.zig");
    _ = @import("spinner.zig");
    _ = @import("flex.zig");

    _ = @import("container.zig");
    _ = @import("stack.zig");
    _ = @import("tabs.zig");
    _ = @import("status_bar.zig");
    _ = @import("toast_overlay.zig");
    _ = @import("popover.zig");
    if (config.enable_terminal_widget) _ = @import("terminal.zig");

    _ = @import("bar_chart.zig");
    _ = @import("chart.zig");
    _ = @import("gauge.zig");
    _ = @import("sparkline.zig");
    _ = @import("calendar.zig");
    _ = @import("canvas.zig");
    _ = @import("presets.zig");
    _ = @import("tree.zig");
    _ = @import("diff.zig");
    _ = @import("markdown.zig");
}
