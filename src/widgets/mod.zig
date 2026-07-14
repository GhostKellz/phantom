//! Widget system module exports
const std = @import("std");
const config = @import("phantom_config");

// Core widget types - always available
pub const Widget = @import("../widget.zig").Widget;

// Shared interaction-state styling conventions (focus ring, hover, disabled,
// validation-error). Always available so any widget can adopt them.
pub const widget_state = @import("widget_state.zig");
pub const StateFlags = @import("widget_state.zig").StateFlags;
pub const VisualState = @import("widget_state.zig").VisualState;
pub const StateStyles = @import("widget_state.zig").StateStyles;
pub const drawFocusRing = @import("widget_state.zig").drawFocusRing;

// Basic widgets - conditionally exported
pub const Text = if (config.enable_basic_widgets) @import("text.zig").Text else void;
pub const Block = if (config.enable_basic_widgets) @import("block.zig").Block else void;
pub const List = if (config.enable_basic_widgets) @import("list.zig").List else void;
pub const Button = if (config.enable_basic_widgets) @import("button.zig").Button else void;
pub const Input = if (config.enable_basic_widgets) @import("input.zig").Input else void;
pub const TextArea = if (config.enable_basic_widgets) @import("textarea.zig").TextArea else void;
pub const CodeEditor = if (config.enable_advanced) @import("editor/CodeEditor.zig").CodeEditor else void;
pub const CodeEditorConfig = if (config.enable_advanced) @import("editor/CodeEditor.zig").Config else void;

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

// Rich block text composition over text.Span/Line/Text
pub const Paragraph = if (config.enable_basic_widgets) @import("paragraph.zig").Paragraph else void;
pub const WrapMode = if (config.enable_basic_widgets) @import("paragraph.zig").WrapMode else void;
pub const Padding = if (config.enable_basic_widgets) @import("paragraph.zig").Padding else void;

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
pub const ChartType = if (config.enable_data_widgets) @import("chart.zig").ChartType else void;
pub const Gauge = if (config.enable_data_widgets) @import("gauge.zig").Gauge else void;
pub const Sparkline = if (config.enable_data_widgets) @import("sparkline.zig").Sparkline else void;
pub const SparklineStyle = if (config.enable_data_widgets) @import("sparkline.zig").SparklineStyle else void;
pub const PieChart = if (config.enable_data_widgets) @import("pie_chart.zig").PieChart else void;
pub const PieSlice = if (config.enable_data_widgets) @import("pie_chart.zig").Slice else void;
pub const Histogram = if (config.enable_data_widgets) @import("histogram.zig").Histogram else void;
pub const Scrollbar = if (config.enable_basic_widgets) @import("scrollbar.zig").Scrollbar else void;
pub const ScrollbarState = if (config.enable_basic_widgets) @import("scrollbar.zig").ScrollbarState else void;
pub const ScrollbarOrientation = if (config.enable_basic_widgets) @import("scrollbar.zig").ScrollbarOrientation else void;
pub const Calendar = if (config.enable_advanced) @import("calendar.zig").Calendar else void;
pub const Canvas = if (config.enable_advanced) @import("canvas.zig").Canvas else void;

// Input picker widgets
pub const DateTimePicker = if (config.enable_advanced) @import("datetime_picker.zig").DateTimePicker else void;
pub const DateTime = if (config.enable_advanced) @import("datetime_picker.zig").DateTime else void;
pub const DateTimePickerMode = if (config.enable_advanced) @import("datetime_picker.zig").Mode else void;
pub const ColorPicker = if (config.enable_advanced) @import("color_picker.zig").ColorPicker else void;
pub const ColorChannel = if (config.enable_advanced) @import("color_picker.zig").Channel else void;

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

// Widgets that expose a serializable navigation/view snapshot must all satisfy
// the `StatefulWidget` contract. This fails to compile if any drifts.
test "stateful widgets satisfy the StatefulWidget contract" {
    const StatefulWidget = @import("../widget.zig").StatefulWidget;
    if (config.enable_basic_widgets) {
        StatefulWidget.assert(@import("list.zig").List);
        StatefulWidget.assert(@import("input.zig").Input);
        StatefulWidget.assert(@import("textarea.zig").TextArea);
    }
    if (config.enable_data_widgets) {
        StatefulWidget.assert(@import("table.zig").Table);
        StatefulWidget.assert(@import("task_monitor.zig").TaskMonitor);
    }
    if (config.enable_advanced) {
        StatefulWidget.assert(@import("tabs.zig").Tabs);
        StatefulWidget.assert(@import("scroll_view.zig").ScrollView);
        StatefulWidget.assert(@import("editor/CodeEditor.zig").CodeEditor);
    }
    if (config.enable_system) {
        StatefulWidget.assert(@import("system_monitor.zig").SystemMonitor);
    }
    if (config.enable_terminal_widget) {
        StatefulWidget.assert(@import("terminal.zig").Terminal);
    }
}

test {
    if (config.enable_basic_widgets) {
        _ = @import("text.zig");
        _ = @import("block.zig");
        _ = @import("list.zig");
        _ = @import("button.zig");
        _ = @import("input.zig");
        _ = @import("textarea.zig");
        _ = @import("border.zig");
        _ = @import("spinner.zig");
        _ = @import("scrollbar.zig");
        _ = @import("paragraph.zig");
    }

    _ = @import("widget_state.zig");

    if (config.enable_data_widgets) {
        _ = @import("progress.zig");
        _ = @import("table.zig");
        _ = @import("task_monitor.zig");
        _ = @import("data_list.zig");
        _ = @import("data_status.zig");
        _ = @import("theme_dashboard.zig");
        _ = @import("bar_chart.zig");
        _ = @import("chart.zig");
        _ = @import("gauge.zig");
        _ = @import("sparkline.zig");
        _ = @import("pie_chart.zig");
        _ = @import("histogram.zig");
        _ = @import("presets.zig");
    }

    if (config.enable_package_mgmt) {
        _ = @import("universal_package_browser.zig");
        _ = @import("aur_dependencies.zig");
    }

    if (config.enable_crypto) {
        _ = @import("blockchain_package_browser.zig");
    }

    if (config.enable_system) {
        _ = @import("command_builder.zig");
        _ = @import("network_topology.zig");
        _ = @import("system_monitor.zig");
    }

    if (config.enable_advanced) {
        _ = @import("streaming_text.zig");
        _ = @import("code_block.zig");
        _ = @import("scroll_view.zig");
        _ = @import("list_view.zig");
        _ = @import("rich_text.zig");
        _ = @import("flex.zig");
        _ = @import("container.zig");
        _ = @import("stack.zig");
        _ = @import("tabs.zig");
        _ = @import("status_bar.zig");
        _ = @import("toast_overlay.zig");
        _ = @import("popover.zig");
        _ = @import("calendar.zig");
        _ = @import("canvas.zig");
        _ = @import("datetime_picker.zig");
        _ = @import("color_picker.zig");
        _ = @import("tree.zig");
        _ = @import("diff.zig");
        _ = @import("markdown.zig");
        _ = @import("syntax_highlight.zig");
    }

    if (config.enable_terminal_widget) {
        _ = @import("terminal.zig");
    }
}
