# Workspace Apps

Phantom has a supported workspace-style path for pane-oriented applications such as shells, editors, and mixed tool dashboards.

## Recommended Stack

- `phantom.App` for top-level lifecycle and focus routing
- `phantom.widgets.Container` for pane composition
- `phantom.widgets.List` for sidebars and file pickers
- `phantom.widgets.Tabs` for multi-buffer or multi-pane switching
- `phantom.widgets.CodeEditor` for supported multiline editing
- `phantom.widgets.Terminal` for PTY-backed terminal panes
- `phantom.widgets.Text` for status lines and lightweight feedback

This is the path used by `examples/workspace_demo.zig`.

## Focus Model

Workspace apps should lean on App-managed focus instead of broadcasting every key event to every widget.

- `App` tracks one focused top-level widget.
- `Container` tracks one focused child inside its subtree.
- `Tab` advances focus through the next focusable widget.
- Mouse interaction can still move focus when the clicked widget handles the event.

For a typical workspace, make the root container the only top-level widget in the app and let it manage focus inside the pane tree.

The canonical demo uses a two-level focus model:

- the root horizontal container switches between sidebar and workspace panes
- the inner workspace container switches between editor and terminal panes

This keeps routed input predictable without needing a custom global dispatcher.

## Recommended Pane Layout

The canonical layout is:

- left sidebar for navigation
- upper tab strip for editor/terminal or multi-buffer switching
- main editor pane
- lower terminal pane
- bottom status line

This keeps the focus path predictable and mirrors the kind of shell/editor work Phantom is now targeting.

## Minimal Example

```zig
const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try phantom.async_runtime.AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    var sidebar = try phantom.widgets.List.init(allocator);
    try sidebar.addItemText("src/main.zig");
    try sidebar.addItemText("README.md");

    var editor = try phantom.widgets.CodeEditor.init(allocator, .{
        .placeholder = "Open a file",
        .show_line_numbers = true,
    });

    var terminal = try phantom.widgets.Terminal.init(allocator, .{
        .runtime = runtime,
        .session_config = .{
            .command = &.{ "/bin/sh", "-c", "printf phantom-workspace" },
            .columns = 80,
            .rows = 12,
        },
        .auto_spawn = true,
    });

    var status = try phantom.widgets.Text.init(allocator, "Tab cycles focus");

    var root = try phantom.widgets.Container.init(allocator, .horizontal);
    try root.addChildWithFlex(&sidebar.widget, 1);

    var workspace = try phantom.widgets.Container.init(allocator, .vertical);
    try workspace.addChildWithFlex(&editor.widget, 3);
    try workspace.addChildWithFlex(&terminal.widget, 2);
    try workspace.addChildWithFlex(&status.widget, 1);
    try root.addChildWithFlex(&workspace.widget, 3);

    var app = try phantom.App.init(allocator, .{
        .title = "Workspace",
        .add_default_handler = false,
    });
    defer app.deinit();

    try app.addWidget(&root.widget);
    app.setFocusedWidget(&root.widget);
    try app.run();
}
```

## Build And Run

The terminal pane requires the terminal widget feature:

```bash
zig build -Dterminal-widget=true demo-workspace
```

## Recommended Command Flow

The current recommended workspace interaction pattern is:

- `Tab` cycles between focusable panes
- `Enter` from the sidebar opens the selected file into the editor pane
- `Tab` / `Shift-Tab` inside the workspace switches between editor and terminal tabs
- `/`, `n`, and `N` drive lightweight editor search navigation
- `g` and `G` jump to the top or bottom of the current editor buffer
- `p` pastes into the terminal using the terminal widget paste path
- `Esc` returns focus from the workspace pane back to the sidebar

This is intentionally small, but it gives Phantom a credible baseline for shell/editor-style applications.

The canonical demo now opens and saves the listed repository files directly, so buffer dirtiness and save behavior reflect real filesystem state rather than static seed content.

## Notes

- Use `CodeEditor` as the current supported editor surface.
- `CodeEditor` currently exposes line count, cursor position, goto-line, selection range, and directional text search helpers for status bars and command-driven jumps.
- `List`, `Table`, and `Tabs` now each expose lightweight state structs so applications can own selection and viewport state more explicitly.
- `Terminal` now exposes a compact status snapshot plus paste, selection, and scrollbar helpers that are intended for workspace apps.
- `Tabs` now window their visible labels around the active tab and render overflow indicators when the tab bar is narrower than the tab set.
- `CodeEditor` now renders first-pass diagnostic markers per visible line on the supported `TextArea`-backed path.
- Terminal mouse forwarding now carries xterm SGR modifier and motion bits when the active terminal mode enables them, but richer hover semantics still depend on future event-model expansion.
- Use `TextEditor` only if you are intentionally working on more advanced or unfinished editor internals.
- Keep one root container in the app when you want predictable routed focus across the whole workspace.
