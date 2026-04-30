const std = @import("std");
const phantom = @import("phantom");

const WorkspaceFile = struct {
    path: []const u8,
    search_hint: ?[]const u8 = null,
    syntax_name: ?[]const u8 = null,
};

const workspace_files = [_]WorkspaceFile{
    .{
        .path = "src/app.zig",
        .search_hint = "App.init",
        .syntax_name = "zig",
    },
    .{
        .path = "src/widgets/terminal.zig",
        .search_hint = "attachSession",
        .syntax_name = "zig",
    },
    .{
        .path = "docs/guides/terminal-sessions.md",
        .search_hint = "PTY",
        .syntax_name = "markdown",
    },
};

const EditorBufferState = struct {
    file_index: usize,
    editor_state: phantom.widgets.CodeEditor.CursorPosition = .{ .line = 0, .column = 0 },
    search_match: ?phantom.widgets.CodeEditor.SearchMatch = null,
    current_text: []u8 = &.{},
    dirty: bool = false,
};

var global_app: *phantom.App = undefined;
var global_status: *phantom.widgets.Text = undefined;
var global_sidebar: *phantom.widgets.List = undefined;
var global_tabs: *phantom.widgets.Tabs = undefined;
var global_editor: *phantom.widgets.CodeEditor = undefined;
var global_terminal: *phantom.widgets.Terminal = undefined;
var global_root: *phantom.widgets.Container = undefined;
var global_workspace: *phantom.widgets.Container = undefined;
var global_buffers: []EditorBufferState = &.{};
var global_active_buffer_index: usize = 0;
var global_allocator: std.mem.Allocator = undefined;

pub fn main() !void {
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    global_allocator = allocator;

    var runtime = try phantom.async_runtime.AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    global_buffers = try allocator.alloc(EditorBufferState, workspace_files.len);
    defer allocator.free(global_buffers);
    for (workspace_files, 0..) |_, idx| {
        global_buffers[idx] = .{
            .file_index = idx,
            .current_text = try loadWorkspaceFile(io, allocator, workspace_files[idx].path),
        };
    }
    defer for (global_buffers) |buffer_state| allocator.free(buffer_state.current_text);

    var sidebar = try phantom.widgets.List.init(allocator);
    for (workspace_files) |file| try sidebar.addItemText(file.path);
    global_sidebar = sidebar;

    var tabs = try phantom.widgets.Tabs.init(allocator);
    tabs.setTabBarWidth(24);
    global_tabs = tabs;

    var editor = try phantom.widgets.CodeEditor.init(allocator, .{
        .placeholder = "Workspace editor",
        .show_line_numbers = true,
        .word_wrap = false,
    });
    global_editor = editor;

    var terminal = try phantom.widgets.Terminal.init(allocator, .{
        .runtime = runtime,
        .session_config = .{
            .command = if (@import("builtin").os.tag == .windows)
                &.{ "cmd.exe", "/Q", "/K" }
            else
                &.{ "/bin/sh", "-i" },
            .columns = 80,
            .rows = 12,
        },
        .auto_spawn = true,
        .scrollback_limit = 1000,
    });
    global_terminal = terminal;

    var status = try phantom.widgets.Text.initWithStyle(
        allocator,
        "Loading workspace",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    global_status = status;

    var workspace = try phantom.widgets.Container.init(allocator, .vertical);
    workspace.setGap(1);
    global_workspace = workspace;

    try tabs.addFixedTab("Editor", &editor.widget);
    try tabs.addFixedTab("Terminal", &terminal.widget);
    try workspace.addChildWithFlex(&tabs.widget, 5);
    try workspace.addChildWithFlex(&status.widget, 1);

    var root = try phantom.widgets.Container.init(allocator, .horizontal);
    root.setGap(1);
    root.setPadding(1);
    try root.addChildWithFlex(&sidebar.widget, 1);
    try root.addChildWithFlex(&workspace.widget, 3);
    global_root = root;

    var app = try phantom.App.init(allocator, .{
        .title = "Phantom Workspace Demo",
        .tick_rate_ms = 40,
        .mouse_enabled = false,
        .add_default_handler = false,
    });
    defer app.deinit();
    global_app = &app;

    try app.addWidget(&root.widget);
    try app.event_loop.addHandler(handleEvent);
    app.setFocusedWidget(&root.widget);
    root.focusChild(&sidebar.widget);
    try openBuffer(0);
    try updateStatus();
    try app.run();
}

fn handleEvent(event: phantom.Event) !bool {
    switch (event) {
        .tick => {
            const dirty = global_terminal.poll();
            try syncSidebarSelection();
            try updateStatus();
            if (dirty) global_app.invalidate();
            try global_app.render();
            return false;
        },
        .key => |key| {
            if (key.isChar('q') or key == .ctrl_c) {
                global_app.stop();
                return true;
            }

            if (global_app.focused_widget == &global_root.widget) {
                switch (key) {
                    .enter => {
                        if (global_root.focused_child_index == 0) {
                            try syncSidebarSelection();
                            global_root.focusChild(&global_workspace.widget);
                            global_workspace.focusChild(&global_tabs.widget);
                            global_tabs.widget.focus();
                            global_tabs.setActiveTab(0);
                            global_editor.focus();
                            global_terminal.blur();
                            global_app.invalidate();
                            return true;
                        }
                    },
                    .escape => {
                        if (global_root.focused_child_index != 0) {
                            saveActiveEditorState();
                            global_root.focusChild(&global_sidebar.widget);
                            global_editor.blur();
                            global_terminal.blur();
                            global_app.invalidate();
                            return true;
                        }
                    },
                    .char => |c| {
                        switch (c) {
                            '/' => {
                                if (global_tabs.active_index == 0) {
                                    _ = focusSearchHint(.forward);
                                }
                                global_app.invalidate();
                                return true;
                            },
                            'n' => {
                                if (global_tabs.active_index == 0) {
                                    _ = focusSearchHint(.forward);
                                    global_app.invalidate();
                                    return true;
                                }
                            },
                            'N' => {
                                if (global_tabs.active_index == 0) {
                                    _ = focusSearchHint(.backward);
                                    global_app.invalidate();
                                    return true;
                                }
                            },
                            'g' => {
                                if (global_tabs.active_index == 0) {
                                    global_editor.gotoLine(1);
                                    saveActiveEditorState();
                                    global_app.invalidate();
                                    return true;
                                }
                            },
                            'G' => {
                                if (global_tabs.active_index == 0) {
                                    global_editor.gotoLine(global_editor.lineCount());
                                    saveActiveEditorState();
                                    global_app.invalidate();
                                    return true;
                                }
                            },
                            'v' => {
                                if (global_tabs.active_index == 0) {
                                    const cursor = global_editor.cursorPosition();
                                    global_editor.setSelectionRange(.{ .line = cursor.line, .column = 0 }, .{ .line = cursor.line, .column = cursor.column });
                                    saveActiveEditorState();
                                    global_app.invalidate();
                                    return true;
                                }
                            },
                            'p' => {
                                if (global_tabs.active_index == 1) {
                                    _ = global_terminal.paste("printf pasted-from-phantom\n");
                                    global_app.invalidate();
                                    return true;
                                }
                            },
                            'a' => {
                                if (global_tabs.active_index == 1) {
                                    try global_terminal.selectAll();
                                    global_app.invalidate();
                                    return true;
                                }
                            },
                            's' => {
                                if (global_tabs.active_index == 0) {
                                    try saveActiveBuffer();
                                    global_app.invalidate();
                                    return true;
                                }
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            }
        },
        else => {},
    }

    return false;
}

fn syncSidebarSelection() !void {
    const selected = global_sidebar.getSelectedItem() orelse return;
    for (workspace_files, 0..) |file, idx| {
        if (std.mem.eql(u8, selected.text, file.path)) {
            if (global_active_buffer_index != idx and global_root.focused_child_index == 0) {
                try openBuffer(idx);
            }
            return;
        }
    }
}

fn openBuffer(index: usize) !void {
    saveActiveEditorState();
    global_active_buffer_index = index;
    global_sidebar.selectIndex(index);
    try global_editor.setText(global_buffers[index].current_text);
    try global_editor.setSyntaxName(workspace_files[index].syntax_name);
    try global_editor.setDiagnostics(bufferDiagnostics(index));
    const buffer_state = global_buffers[index];
    global_editor.moveCursorTo(buffer_state.editor_state.line, buffer_state.editor_state.column);
    if (buffer_state.search_match) |match| {
        global_editor.moveCursorTo(match.line, match.column);
    }
}

fn saveActiveEditorState() void {
    if (global_buffers.len == 0) return;
    global_buffers[global_active_buffer_index].editor_state = global_editor.cursorPosition();
    global_buffers[global_active_buffer_index].search_match = globalSearchMatch();
    const new_text = global_editor.getText() catch return;
    defer global_allocator.free(new_text);
    global_allocator.free(global_buffers[global_active_buffer_index].current_text);
    global_buffers[global_active_buffer_index].current_text = global_allocator.dupe(u8, new_text) catch return;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    global_buffers[global_active_buffer_index].dirty = !fileContentMatches(io, global_buffers[global_active_buffer_index].current_text, workspace_files[global_active_buffer_index].path);
}

fn saveActiveBuffer() !void {
    saveActiveEditorState();
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = workspace_files[global_active_buffer_index].path,
        .data = global_buffers[global_active_buffer_index].current_text,
    });
    global_buffers[global_active_buffer_index].dirty = false;
}

fn bufferDiagnostics(index: usize) []const phantom.widgets.CodeEditor.Diagnostic {
    return switch (index) {
        0 => &.{.{ .line = 3, .message = "Consider documenting app lifecycle", .severity = .warning }},
        1 => &.{.{ .line = 0, .message = "Session ownership is a critical edge", .severity = .info }},
        else => &.{.{ .line = 0, .message = "Guide should mention PTY lifecycle", .severity = .warning }},
    };
}

fn globalSearchMatch() ?phantom.widgets.CodeEditor.SearchMatch {
    const file = workspace_files[global_active_buffer_index];
    const needle = file.search_hint orelse return null;
    const cursor = global_editor.cursorPosition();
    if (global_editor.findText(needle)) |match| {
        if (match.line == cursor.line and match.column == cursor.column) return match;
    }
    return null;
}

fn focusSearchHint(direction: phantom.widgets.CodeEditor.SearchDirection) bool {
    const file = workspace_files[global_active_buffer_index];
    const needle = file.search_hint orelse return false;

    const matched = switch (direction) {
        .forward => global_editor.findNext(needle) orelse global_editor.findText(needle) orelse return false,
        .backward => global_editor.findPrevious(needle) orelse global_editor.findText(needle) orelse return false,
    };

    global_editor.moveCursorTo(matched.line, matched.column);
    saveActiveEditorState();
    return true;
}

fn updateStatus() !void {
    const focused_pane = focusedPaneName();
    const file = workspace_files[global_active_buffer_index];
    const terminal_status = global_terminal.status();
    const editor_summary = try global_editor.statusSummary(std.heap.page_allocator);
    defer std.heap.page_allocator.free(editor_summary);
    const diagnostic = global_editor.firstDiagnostic();

    var line_buf: [320]u8 = undefined;
    const line = std.fmt.bufPrint(
        &line_buf,
        "focus={s} tab={d} file={s}{s} editor[{s}] diag={s} term[line {d}, col {d}, scroll {d}{s}{s}] | Enter=open | Tab/Shift-Tab=switch pane-tab | /=find n/N=next/prev g/G=top/bottom v=select s=save p=paste a=select-all-term Esc=sidebar q=quit",
        .{
            focused_pane,
            global_tabs.active_index + 1,
            file.path,
            if (global_buffers[global_active_buffer_index].dirty) "*" else "",
            editor_summary,
            if (diagnostic) |diag| diag.message else "none",
            terminal_status.cursor.line + 1,
            terminal_status.cursor.column + 1,
            terminal_status.scroll_offset,
            if (terminal_status.bracketed_paste_enabled) " paste" else "",
            if (terminal_status.has_selection) " selection" else "",
        },
    ) catch "Workspace status";
    try global_status.setContent(line);
}

fn focusedPaneName() []const u8 {
    if (global_root.focused_child_index) |root_idx| {
        if (root_idx == 0) return "sidebar";
        if (root_idx == 1) {
            return switch (global_tabs.active_index) {
                0 => "editor",
                1 => "terminal",
                else => "workspace",
            };
        }
    }
    return "workspace";
}

fn loadWorkspaceFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(100 * 1024 * 1024));
}

fn fileContentMatches(io: std.Io, expected: []const u8, path: []const u8) bool {
    const actual = loadWorkspaceFile(io, global_allocator, path) catch return false;
    defer global_allocator.free(actual);
    return std.mem.eql(u8, actual, expected);
}
