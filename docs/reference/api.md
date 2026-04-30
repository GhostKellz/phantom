# Phantom API Reference

This is a compact reference for the current supported Phantom surface on Zig `0.17.0-dev`.

## Core Types

### `phantom.App`

```zig
pub fn init(allocator: std.mem.Allocator, config: phantom.AppConfig) !phantom.App
pub fn deinit(self: *App) void
pub fn addWidget(self: *App, widget: *phantom.Widget) !void
pub fn removeWidget(self: *App, widget: *phantom.Widget) void
pub fn run(self: *App) !void
pub fn runWithoutDefaults(self: *App) !void
pub fn stop(self: *App) void
pub fn invalidate(self: *App) void
pub fn postEvent(self: *App, event: phantom.Event) !void
pub fn postEventWithPriority(self: *App, event: phantom.Event, priority: phantom.event_queue.EventPriority) !void
```

### `phantom.AppConfig`

```zig
pub const AppConfig = struct {
    title: []const u8 = "Phantom App",
    tick_rate_ms: u64 = 16,
    mouse_enabled: bool = false,
    resize_enabled: bool = true,
    add_default_handler: bool = true,
    enable_transitions: bool = true,
    transition_duration_ms: u64 = 180,
    transition_delay_ms: u64 = 0,
    transition_curve: phantom.animation.TransitionCurve = .ease,
    event_loop_config: phantom.EventLoop.Config = .{},
};
```

## Core Widget Interface

```zig
pub const Widget = struct {
    vtable: *const WidgetVTable,

    pub const WidgetVTable = struct {
        render: *const fn (self: *Widget, buffer: *phantom.Buffer, area: phantom.Rect) void,
        deinit: *const fn (self: *Widget) void,
        handleEvent: ?*const fn (self: *Widget, event: phantom.Event) bool = null,
        resize: ?*const fn (self: *Widget, new_area: phantom.Rect) void = null,
        getConstraints: ?*const fn (self: *Widget) phantom.SizeConstraints = null,
        canFocus: ?*const fn (self: *Widget) bool = null,
        focus: ?*const fn (self: *Widget) void = null,
        blur: ?*const fn (self: *Widget) void = null,
    };
};
```

## Recommended Widgets

### `phantom.widgets.Text`

```zig
pub fn init(allocator: std.mem.Allocator, content: []const u8) !*Text
pub fn initWithStyle(allocator: std.mem.Allocator, content: []const u8, text_style: phantom.Style) !*Text
pub fn setContent(self: *Text, content: []const u8) !void
pub fn setStyle(self: *Text, text_style: phantom.Style) void
pub fn setAlignment(self: *Text, alignment: Text.Alignment) void
```

### `phantom.widgets.List`

```zig
pub fn init(allocator: std.mem.Allocator) !*List
pub fn addItem(self: *List, item: ListItem) !void
pub fn addItems(self: *List, items: []const ListItem) !void
pub fn addItemText(self: *List, text: []const u8) !void
pub fn clear(self: *List) void
pub fn selectNext(self: *List) void
pub fn selectPrevious(self: *List) void
pub fn getSelectedItem(self: *const List) ?ListItem
```

### `phantom.widgets.ProgressBar`

```zig
pub fn init(allocator: std.mem.Allocator) !*ProgressBar
pub fn setValue(self: *ProgressBar, value: f64) void
pub fn setMaxValue(self: *ProgressBar, max_value: f64) void
pub fn setPercentage(self: *ProgressBar, percentage: f64) void
pub fn getPercentage(self: *const ProgressBar) f64
pub fn setProgressStyle(self: *ProgressBar, progress_style: phantom.emoji.ProgressStyle) void
```

### `phantom.widgets.ThemeTokenDashboard`

```zig
pub fn init(
    allocator: std.mem.Allocator,
    source: phantom.data.ListDataSource(phantom.widgets.ThemeToken),
    title: []const u8,
    config: ThemeTokenDashboard.Config,
) !*ThemeTokenDashboard
```

### `phantom.widgets.CodeEditor`

```zig
pub fn init(allocator: std.mem.Allocator, config: phantom.widgets.CodeEditorConfig) !*CodeEditor
pub fn setText(self: *CodeEditor, text: []const u8) !void
pub fn getText(self: *CodeEditor) ![]const u8
pub fn setReadOnly(self: *CodeEditor, enabled: bool) void
pub fn isReadOnly(self: *const CodeEditor) bool
pub fn setPlaceholder(self: *CodeEditor, placeholder: []const u8) !void
pub fn setShowLineNumbers(self: *CodeEditor, enabled: bool) !void
pub fn lineCount(self: *const CodeEditor) usize
pub fn cursorPosition(self: *const CodeEditor) struct { line: usize, column: usize }
pub fn moveCursorTo(self: *CodeEditor, line: usize, column: usize) void
pub fn gotoLine(self: *CodeEditor, line_1_based: usize) void
pub fn findText(self: *CodeEditor, needle: []const u8) ?struct { line: usize, column: usize }
pub fn findAndMoveCursor(self: *CodeEditor, needle: []const u8) bool
pub fn findNext(self: *CodeEditor, needle: []const u8) ?struct { line: usize, column: usize }
pub fn findPrevious(self: *CodeEditor, needle: []const u8) ?struct { line: usize, column: usize }
pub fn hasSelection(self: *const CodeEditor) bool
pub fn clearSelection(self: *CodeEditor) void
pub fn statusSummary(self: *const CodeEditor, allocator: std.mem.Allocator) ![]u8
```

### Stateful widgets

These widgets now expose lightweight state snapshots so applications can own or restore navigation state explicitly:

```zig
phantom.widgets.List.State
phantom.widgets.Table.State
phantom.widgets.Tabs.State
```

Useful helpers include:

```zig
pub fn state(self: *const List) List.State
pub fn applyState(self: *List, new_state: List.State) void
pub fn scrollbarState(self: *const List, viewport_length: usize) phantom.widgets.ScrollbarState

pub fn state(self: *const Table) Table.State
pub fn applyState(self: *Table, new_state: Table.State) void
pub fn scrollbarState(self: *const Table, viewport_length: usize) phantom.widgets.ScrollbarState

pub fn state(self: *const Tabs) Tabs.State
pub fn applyState(self: *Tabs, new_state: Tabs.State) void
```

`Tabs.State` now includes both the active tab index and the visible tab-window start used for overflowed tab bars.

### `phantom.widgets.Terminal`

The terminal widget now exposes a stronger workspace-oriented surface:

```zig
pub fn status(self: *const Terminal) Terminal.Status
pub fn scrollbarState(self: *const Terminal, viewport_length: usize) phantom.widgets.ScrollbarState
pub fn paste(self: *Terminal, text: []const u8) bool
pub fn selectAll(self: *Terminal) !void
pub fn bracketedPasteEnabled(self: *const Terminal) bool
pub fn mouseReportingEnabled(self: *const Terminal) bool
pub fn mouseMotionEnabled(self: *const Terminal) bool
pub fn mouseAnyEventEnabled(self: *const Terminal) bool
```

Mouse forwarding currently targets xterm SGR sequences and includes modifier and motion bits when the terminal enables those modes.

## Layout

### `phantom.layout.engine`

Recommended for new code.

Key entry points:

```zig
pub const LayoutBuilder
pub const LayoutNodeHandle
pub const ChildWeight
pub const WeightSpec
pub fn splitRow(allocator: std.mem.Allocator, area: phantom.Rect, specs: []const WeightSpec) ![]phantom.Rect
pub fn splitColumn(allocator: std.mem.Allocator, area: phantom.Rect, specs: []const WeightSpec) ![]phantom.Rect
```

### `phantom.layout.migration`

Temporary bridge helpers for older split-based code:

```zig
pub fn splitRowLegacy(allocator: std.mem.Allocator, area: phantom.Rect, weights: []const f64) ![]phantom.Rect
pub fn splitColumnLegacy(allocator: std.mem.Allocator, area: phantom.Rect, weights: []const f64) ![]phantom.Rect
pub fn splitGridLegacy(allocator: std.mem.Allocator, area: phantom.Rect, row_weights: []const f64, column_weights: []const f64) !GridTracks
```

## Async Runtime

```zig
pub fn startGlobal(allocator: std.mem.Allocator, config: phantom.async_runtime.Config) !*phantom.async_runtime.AsyncRuntime
pub fn ensureGlobal(allocator: std.mem.Allocator, config: phantom.async_runtime.Config) !*phantom.async_runtime.AsyncRuntime
pub fn shutdownGlobal() void
pub fn globalRuntime() ?*phantom.async_runtime.AsyncRuntime
pub fn withTestHarness(allocator: std.mem.Allocator, config: phantom.async_runtime.Config, body: anytype) !void
```

## Advanced And Experimental Surfaces

- `phantom.grove`: supported advanced surface for syntax highlighting
- `phantom.vxfw`: advanced low-level widget framework
- `phantom.terminal_session`: supported advanced PTY/session manager, available when built with `-Dterminal-widget=true`

## Notes

- The recommended consumer path is `App` + `widgets` + `layout.engine`.
- For workspace-style applications, the current strongest path is `Container` + `List` + `CodeEditor` + `Terminal` with App-managed focus routing.
- See `docs/guides/workspace-apps.md` and `examples/workspace_demo.zig` for the canonical pane-oriented setup.
- Some older docs and examples in the repository still cover deeper or more experimental subsystems; treat this file and the root `README.md` as the current supported entrypoint.
