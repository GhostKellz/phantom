# 👻 Phantom TUI Framework - API Reference

**Version**: 0.3.3  
**Zig Compatibility**: 0.16+  

---

## 📖 Table of Contents

1. [Core API](#core-api)
2. [Widget API](#widget-api)
3. [Style API](#style-api)
4. [Event API](#event-api)
5. [Layout API](#layout-api)
6. [Utility API](#utility-api)

---

## 🏗️ Core API

### Application (`phantom.App`)

#### `App.init(allocator: std.mem.Allocator, config: AppConfig) !*App`

Creates a new application instance.

**Parameters:**
- `allocator`: Memory allocator for the application
- `config`: Application configuration

**Returns:** Pointer to initialized App

**Example:**
```zig
var app = try phantom.App.init(allocator, .{
    .title = "My App",
    .tick_rate_ms = 50,
    .mouse_enabled = true,
});
defer app.deinit();
```

#### `AppConfig`

Application configuration structure.

```zig
pub const AppConfig = struct {
    title: []const u8 = "Phantom App",
    tick_rate_ms: u64 = 50,
    mouse_enabled: bool = false,
    debug_mode: bool = false,
    show_fps: bool = false,
    show_memory_usage: bool = false,
};
```

#### `app.addWidget(widget: *Widget) !void`

Adds a widget to the application.

**Parameters:**
- `widget`: Pointer to widget to add

**Example:**
```zig
const text = try phantom.widgets.Text.init(allocator, "Hello");
try app.addWidget(&text.widget);
```

#### `app.run() !void`

Starts the main application loop.

**Example:**
```zig
try app.run(); // Blocks until app exits
```

#### `app.deinit()`

Cleans up application resources. Automatically called by defer.

---

## 🧩 Widget API

### Base Widget (`phantom.Widget`)

All widgets inherit from the base Widget interface.

```zig
pub const Widget = struct {
    vtable: *const WidgetVTable,
    
    pub const WidgetVTable = struct {
        render: *const fn(*Widget, *Buffer, Rect) void,
        handleEvent: *const fn(*Widget, Event) bool,
        resize: *const fn(*Widget, Rect) void,
        deinit: *const fn(*Widget) void,
    };
    
    pub fn render(self: *Widget, buffer: *Buffer, area: Rect) void;
    pub fn handleEvent(self: *Widget, event: Event) bool;
    pub fn resize(self: *Widget, area: Rect) void;
    pub fn deinit(self: *Widget) void;
};
```

### Text Widget (`phantom.widgets.Text`)

Displays styled text content.

#### `Text.init(allocator: std.mem.Allocator, text: []const u8) !*Text`

Creates a basic text widget.

**Parameters:**
- `allocator`: Memory allocator
- `text`: Text content to display

**Example:**
```zig
const text = try phantom.widgets.Text.init(allocator, "Hello, World!");
```

#### `Text.initWithStyle(allocator: std.mem.Allocator, text: []const u8, style: Style) !*Text`

Creates a styled text widget.

**Parameters:**
- `allocator`: Memory allocator
- `text`: Text content
- `style`: Text style

**Example:**
```zig
const styled_text = try phantom.widgets.Text.initWithStyle(
    allocator,
    "Styled Text",
    phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold()
);
```

#### Text Methods

```zig
// Content management
pub fn setText(self: *Text, text: []const u8) !void;
pub fn getText(self: *const Text) []const u8;

// Alignment
pub const Alignment = enum { left, center, right };
pub fn setAlignment(self: *Text, alignment: Alignment) void;
pub fn getAlignment(self: *const Text) Alignment;

// Styling
pub fn setStyle(self: *Text, style: Style) void;
pub fn getStyle(self: *const Text) Style;
```

### List Widget (`phantom.widgets.List`)

Scrollable list with selectable items.

#### `List.init(allocator: std.mem.Allocator) !*List`

Creates a new list widget.

**Example:**
```zig
const list = try phantom.widgets.List.init(allocator);
```

#### List Methods

```zig
// Item management
pub fn addItemText(self: *List, text: []const u8) !void;
pub fn addItem(self: *List, item: ListItem) !void;
pub fn removeItem(self: *List, index: usize) void;
pub fn clear(self: *List) void;
pub fn getItem(self: *const List, index: usize) *const ListItem;
pub fn getItemCount(self: *const List) usize;

// Selection
pub fn setSelectedIndex(self: *List, index: usize) void;
pub fn getSelectedIndex(self: *const List) ?usize;
pub fn selectNext(self: *List) void;
pub fn selectPrevious(self: *List) void;

// Scrolling
pub fn scrollUp(self: *List) void;
pub fn scrollDown(self: *List) void;
pub fn scrollToTop(self: *List) void;
pub fn scrollToBottom(self: *List) void;

// Styling
pub fn setNormalStyle(self: *List, style: Style) void;
pub fn setSelectedStyle(self: *List, style: Style) void;
pub fn setFocusedStyle(self: *List, style: Style) void;

// Events
pub const OnSelectFn = *const fn(*List, usize) void;
pub fn setOnSelect(self: *List, callback: OnSelectFn) void;
```

#### `ListItem`

```zig
pub const ListItem = struct {
    text: []const u8,
    data: ?*anyopaque = null,
    style: ?Style = null,
    selectable: bool = true,
};
```

### Button Widget (`phantom.widgets.Button`)

Clickable button with hover and press states.

#### `Button.init(allocator: std.mem.Allocator, text: []const u8) !*Button`

Creates a button widget.

**Parameters:**
- `allocator`: Memory allocator
- `text`: Button label

**Example:**
```zig
const button = try phantom.widgets.Button.init(allocator, "Click Me");
```

#### Button Methods

```zig
// Content
pub fn setText(self: *Button, text: []const u8) !void;
pub fn getText(self: *const Button) []const u8;

// State
pub fn isHovered(self: *const Button) bool;
pub fn isPressed(self: *const Button) bool;
pub fn isEnabled(self: *const Button) bool;
pub fn setEnabled(self: *Button, enabled: bool) void;

// Styling
pub fn setNormalStyle(self: *Button, style: Style) void;
pub fn setHoverStyle(self: *Button, style: Style) void;
pub fn setPressedStyle(self: *Button, style: Style) void;
pub fn setDisabledStyle(self: *Button, style: Style) void;

// Events
pub const OnClickFn = *const fn(*Button) void;
pub fn setOnClick(self: *Button, callback: OnClickFn) void;

// Manual interaction
pub fn click(self: *Button) void;
pub fn press(self: *Button) void;
pub fn release(self: *Button) void;
```

### Input Widget (`phantom.widgets.Input`)

Single-line text input field.

#### `Input.init(allocator: std.mem.Allocator) !*Input`

Creates an input widget.

**Example:**
```zig
const input = try phantom.widgets.Input.init(allocator);
```

#### Input Methods

```zig
// Content
pub fn setText(self: *Input, text: []const u8) !void;
pub fn getText(self: *const Input) []const u8;
pub fn clear(self: *Input) void;

// Configuration
pub fn setPlaceholder(self: *Input, placeholder: []const u8) !void;
pub fn setMaxLength(self: *Input, max_length: ?usize) void;
pub fn setPassword(self: *Input, is_password: bool) void;
pub fn setPasswordChar(self: *Input, char: u21) void;

// Focus and cursor
pub fn focus(self: *Input) void;
pub fn blur(self: *Input) void;
pub fn isFocused(self: *const Input) bool;
pub fn setCursorPosition(self: *Input, pos: usize) void;
pub fn getCursorPosition(self: *const Input) usize;

// Selection
pub fn selectAll(self: *Input) void;
pub fn selectRange(self: *Input, start: usize, end: usize) void;
pub fn clearSelection(self: *Input) void;
pub fn hasSelection(self: *const Input) bool;

// Styling
pub fn setNormalStyle(self: *Input, style: Style) void;
pub fn setFocusedStyle(self: *Input, style: Style) void;
pub fn setPlaceholderStyle(self: *Input, style: Style) void;
pub fn setSelectionStyle(self: *Input, style: Style) void;

// Events
pub const OnChangeFn = *const fn(*Input, []const u8) void;
pub const OnSubmitFn = *const fn(*Input, []const u8) void;
pub fn setOnChange(self: *Input, callback: OnChangeFn) void;
pub fn setOnSubmit(self: *Input, callback: OnSubmitFn) void;
```

### TextArea Widget (`phantom.widgets.TextArea`)

Multi-line text editor with scrolling.

#### `TextArea.init(allocator: std.mem.Allocator) !*TextArea`

Creates a textarea widget.

**Example:**
```zig
const textarea = try phantom.widgets.TextArea.init(allocator);
```

#### TextArea Methods

```zig
// Content management
pub fn setText(self: *TextArea, text: []const u8) !void;
pub fn getText(self: *TextArea, allocator: std.mem.Allocator) ![]const u8;
pub fn insertText(self: *TextArea, text: []const u8) !void;
pub fn clear(self: *TextArea) void;

// Line operations
pub fn getLineCount(self: *const TextArea) usize;
pub fn getLine(self: *const TextArea, line_index: usize) []const u8;
pub fn insertLine(self: *TextArea, line_index: usize, text: []const u8) !void;
pub fn deleteLine(self: *TextArea, line_index: usize) void;

// Cursor and selection
pub fn setCursorPosition(self: *TextArea, line: usize, column: usize) void;
pub fn getCursorPosition(self: *const TextArea) struct { line: usize, column: usize };
pub fn selectAll(self: *TextArea) void;
pub fn clearSelection(self: *TextArea) void;

// Scrolling
pub fn scrollUp(self: *TextArea) void;
pub fn scrollDown(self: *TextArea) void;
pub fn scrollToLine(self: *TextArea, line: usize) void;

// Configuration
pub fn setReadOnly(self: *TextArea, read_only: bool) void;
pub fn setShowLineNumbers(self: *TextArea, show: bool) void;
pub fn setTabSize(self: *TextArea, size: usize) void;
pub fn setWrapLines(self: *TextArea, wrap: bool) !void;

// Styling
pub fn setTextStyle(self: *TextArea, style: Style) void;
pub fn setLineNumberStyle(self: *TextArea, style: Style) void;
pub fn setSelectionStyle(self: *TextArea, style: Style) void;
```

### StreamingText Widget (`phantom.widgets.StreamingText`)

Real-time streaming text display (perfect for AI responses).

#### `StreamingText.init(allocator: std.mem.Allocator) !*StreamingText`

Creates a streaming text widget.

**Example:**
```zig
const streaming = try phantom.widgets.StreamingText.init(allocator);
```

#### StreamingText Methods

```zig
// Content management
pub fn setText(self: *StreamingText, text: []const u8) !void;
pub fn getText(self: *const StreamingText) []const u8;
pub fn clear(self: *StreamingText) !void;

// Streaming control
pub fn startStreaming(self: *StreamingText) void;
pub fn stopStreaming(self: *StreamingText) void;
pub fn isStreaming(self: *const StreamingText) bool;
pub fn addChunk(self: *StreamingText, chunk: []const u8) !void;

// Configuration
pub fn setTypingSpeed(self: *StreamingText, speed: u64) void; // chars per second
pub fn setAutoScroll(self: *StreamingText, auto_scroll: bool) void;
pub fn setWordWrap(self: *StreamingText, word_wrap: bool) !void;
pub fn setShowCursor(self: *StreamingText, show: bool) void;
pub fn setCursorChar(self: *StreamingText, cursor_char: u21) void;

// Scrolling
pub fn scrollUp(self: *StreamingText) void;
pub fn scrollDown(self: *StreamingText) void;
pub fn scrollToTop(self: *StreamingText) void;
pub fn scrollToBottom(self: *StreamingText) void;

// Styling
pub fn setTextStyle(self: *StreamingText, text_style: Style) void;
pub fn setStreamingStyle(self: *StreamingText, streaming_style: Style) void;
pub fn setCursorStyle(self: *StreamingText, cursor_style: Style) void;

// Events
pub const OnChunkFn = *const fn(*StreamingText, []const u8) void;
pub const OnCompleteFn = *const fn(*StreamingText) void;
pub fn setOnChunk(self: *StreamingText, callback: OnChunkFn) void;
pub fn setOnComplete(self: *StreamingText, callback: OnCompleteFn) void;
```

### ProgressBar Widget (`phantom.widgets.ProgressBar`)

Visual progress indicator.

#### `ProgressBar.init(allocator: std.mem.Allocator) !*ProgressBar`

Creates a progress bar widget.

**Example:**
```zig
const progress = try phantom.widgets.ProgressBar.init(allocator);
```

#### ProgressBar Methods

```zig
// Value management
pub fn setValue(self: *ProgressBar, value: f64) void; // 0.0 to max_value
pub fn getValue(self: *const ProgressBar) f64;
pub fn setMaxValue(self: *ProgressBar, max: f64) void;
pub fn getMaxValue(self: *const ProgressBar) f64;
pub fn getPercentage(self: *const ProgressBar) f64; // 0.0 to 100.0

// Display options
pub fn setLabel(self: *ProgressBar, label: []const u8) !void;
pub fn getLabel(self: *const ProgressBar) []const u8;
pub fn setShowValue(self: *ProgressBar, show: bool) void;
pub fn setShowPercentage(self: *ProgressBar, show: bool) void;

// Progress bar style
pub const BarStyle = enum { blocks, smooth, ascii };
pub fn setBarStyle(self: *ProgressBar, bar_style: BarStyle) void;

// Animation
pub fn setAnimated(self: *ProgressBar, animated: bool) void;
pub fn setAnimationSpeed(self: *ProgressBar, speed: u64) void; // ms per frame

// Styling
pub fn setFillStyle(self: *ProgressBar, style: Style) void;
pub fn setBarStyle(self: *ProgressBar, style: Style) void;
pub fn setTextStyle(self: *ProgressBar, style: Style) void;

// Utility
pub fn increment(self: *ProgressBar, amount: f64) void;
pub fn isComplete(self: *const ProgressBar) bool;
```

### Table Widget (`phantom.widgets.Table`)

Column-based data display with sorting and selection.

#### `Table.init(allocator: std.mem.Allocator) !*Table`

Creates a table widget.

**Example:**
```zig
const table = try phantom.widgets.Table.init(allocator);
```

#### Table Methods

```zig
// Column management
pub const Column = struct {
    title: []const u8,
    width: u16,
    alignment: Alignment = .left,
    sortable: bool = true,
};
pub fn addColumn(self: *Table, column: Column) !void;
pub fn removeColumn(self: *Table, index: usize) void;
pub fn getColumnCount(self: *const Table) usize;

// Row management  
pub const Row = struct {
    cells: [][]const u8,
    data: ?*anyopaque = null,
    style: ?Style = null,
};
pub fn addRow(self: *Table, cells: []const []const u8) !void;
pub fn addRowWithData(self: *Table, row: Row) !void;
pub fn removeRow(self: *Table, index: usize) void;
pub fn clearRows(self: *Table) void;
pub fn getRowCount(self: *const Table) usize;

// Selection and navigation
pub fn setSelectedRow(self: *Table, index: usize) void;
pub fn getSelectedRow(self: *const Table) ?usize;
pub fn selectNext(self: *Table) void;
pub fn selectPrevious(self: *Table) void;

// Scrolling
pub fn scrollUp(self: *Table) void;
pub fn scrollDown(self: *Table) void;
pub fn scrollToRow(self: *Table, row: usize) void;

// Sorting
pub fn sortByColumn(self: *Table, column: usize, ascending: bool) void;
pub fn getSortColumn(self: *const Table) ?usize;
pub fn getSortOrder(self: *const Table) bool; // true = ascending

// Styling
pub fn setHeaderStyle(self: *Table, style: Style) void;
pub fn setRowStyle(self: *Table, style: Style) void;
pub fn setSelectedStyle(self: *Table, style: Style) void;
pub fn setAlternateRowStyle(self: *Table, style: Style) void;
pub fn setBorderStyle(self: *Table, style: Style) void;

// Events
pub const OnRowSelectFn = *const fn(*Table, usize) void;
pub const OnColumnSortFn = *const fn(*Table, usize, bool) void;
pub fn setOnRowSelect(self: *Table, callback: OnRowSelectFn) void;
pub fn setOnColumnSort(self: *Table, callback: OnColumnSortFn) void;
```

### CodeBlock Widget (`phantom.widgets.CodeBlock`)

Syntax-highlighted code display.

#### `CodeBlock.init(allocator: std.mem.Allocator, code: []const u8, language: Language) !*CodeBlock`

Creates a code block widget.

**Parameters:**
- `allocator`: Memory allocator
- `code`: Source code content
- `language`: Programming language for syntax highlighting

**Example:**
```zig
const code_sample = 
    \\const std = @import("std");
    \\pub fn main() void {
    \\    std.debug.print("Hello!\n", .{});
    \\}
;

const code_block = try phantom.widgets.CodeBlock.init(allocator, code_sample, .zig);
```

#### Language Support

```zig
pub const Language = enum {
    zig,
    c,
    cpp,
    rust,
    go,
    python,
    javascript,
    typescript,
    html,
    css,
    json,
    xml,
    markdown,
    bash,
    plain_text,
};
```

#### CodeBlock Methods

```zig
// Content management
pub fn setCode(self: *CodeBlock, code: []const u8) !void;
pub fn getCode(self: *const CodeBlock) []const u8;
pub fn setLanguage(self: *CodeBlock, language: Language) void;

// Display options
pub fn setShowLineNumbers(self: *CodeBlock, show: bool) void;
pub fn setTabSize(self: *CodeBlock, size: usize) void;
pub fn setWrapLines(self: *CodeBlock, wrap: bool) !void;
pub fn setHighlightCurrentLine(self: *CodeBlock, highlight: bool) void;

// Navigation
pub fn scrollUp(self: *CodeBlock) void;
pub fn scrollDown(self: *CodeBlock) void;
pub fn scrollToLine(self: *CodeBlock, line: usize) void;
pub fn goToLine(self: *CodeBlock, line: usize) void;

// Styling (beyond built-in syntax highlighting)
pub fn setBackgroundStyle(self: *CodeBlock, style: Style) void;
pub fn setLineNumberStyle(self: *CodeBlock, style: Style) void;
pub fn setCurrentLineStyle(self: *CodeBlock, style: Style) void;
```

### Dialog Widget (`phantom.widgets.Dialog`)

Modal dialog boxes.

#### `Dialog.init(allocator: std.mem.Allocator, dialog_type: DialogType) !*Dialog`

Creates a dialog widget.

**Parameters:**
- `allocator`: Memory allocator
- `dialog_type`: Type of dialog (info, warning, error, question)

**Example:**
```zig
const dialog = try phantom.widgets.Dialog.init(allocator, .info);
```

#### Dialog Types and Methods

```zig
pub const DialogType = enum { info, warning, error, question, custom };

pub const DialogButton = struct {
    text: []const u8,
    action: ButtonAction,
    is_default: bool = false,
    is_cancel: bool = false,
};

pub const ButtonAction = enum { close, cancel, ok, yes, no, custom };

// Content
pub fn setTitle(self: *Dialog, title: []const u8) !void;
pub fn setMessage(self: *Dialog, message: []const u8) !void;

// Buttons
pub fn addButton(self: *Dialog, button: DialogButton) !void;
pub fn clearButtons(self: *Dialog) void;

// Display
pub fn show(self: *Dialog) void;
pub fn hide(self: *Dialog) void;
pub fn isVisible(self: *const Dialog) bool;

// Modal behavior
pub fn setModal(self: *Dialog, modal: bool) void;
pub fn isModal(self: *const Dialog) bool;

// Events
pub const OnButtonClickFn = *const fn(*Dialog, ButtonAction) void;
pub fn setOnButtonClick(self: *Dialog, callback: OnButtonClickFn) void;
```

### TaskMonitor Widget (`phantom.widgets.TaskMonitor`)

Multi-task progress monitoring (perfect for package managers).

#### `TaskMonitor.init(allocator: std.mem.Allocator) !*TaskMonitor`

Creates a task monitor widget.

**Example:**
```zig
const monitor = try phantom.widgets.TaskMonitor.init(allocator);
```

#### Task Management

```zig
pub const TaskStatus = enum { pending, running, completed, failed, cancelled };

pub const Task = struct {
    id: []const u8,
    name: []const u8,
    progress: f64 = 0.0,
    status: TaskStatus = .pending,
    message: []const u8 = "",
    start_time: ?i64 = null,
    end_time: ?i64 = null,
};

// Task operations
pub fn addTask(self: *TaskMonitor, id: []const u8, name: []const u8) !void;
pub fn removeTask(self: *TaskMonitor, id: []const u8) void;
pub fn updateTask(self: *TaskMonitor, id: []const u8, updates: TaskUpdate) !void;
pub fn getTask(self: *TaskMonitor, id: []const u8) ?*Task;
pub fn clearCompletedTasks(self: *TaskMonitor) void;
pub fn clearAllTasks(self: *TaskMonitor) void;

pub const TaskUpdate = struct {
    progress: ?f64 = null,
    status: ?TaskStatus = null,
    message: ?[]const u8 = null,
};

// Statistics
pub fn getTaskCount(self: *const TaskMonitor) usize;
pub fn getCompletedCount(self: *const TaskMonitor) usize;
pub fn getFailedCount(self: *const TaskMonitor) usize;
pub fn getOverallProgress(self: *const TaskMonitor) f64;

// Display options
pub fn setShowTimestamps(self: *TaskMonitor, show: bool) void;
pub fn setShowProgress(self: *TaskMonitor, show: bool) void;
pub fn setCompactMode(self: *TaskMonitor, compact: bool) void;

// Styling
pub fn setHeaderStyle(self: *TaskMonitor, style: Style) void;
pub fn setTaskStyle(self: *TaskMonitor, style: Style) void;
pub fn setProgressStyle(self: *TaskMonitor, style: Style) void;
pub fn setCompletedStyle(self: *TaskMonitor, style: Style) void;
pub fn setFailedStyle(self: *TaskMonitor, style: Style) void;
```

---

## 🎨 Style API

### Style Structure

```zig
pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    attributes: Attributes = Attributes.none(),
    
    pub fn default() Style;
    pub fn withFg(self: Style, color: Color) Style;
    pub fn withBg(self: Style, color: Color) Style;
    pub fn withAttributes(self: Style, attrs: Attributes) Style;
    pub fn withBold(self: Style) Style;
    pub fn withItalic(self: Style) Style;
    pub fn withUnderline(self: Style) Style;
    pub fn ansiCodes(self: Style, allocator: std.mem.Allocator) ![]const u8;
};
```

### Color System

```zig
pub const Color = union(enum) {
    // Basic colors
    default,
    black, red, green, yellow, blue, magenta, cyan, white,
    
    // Bright variants
    bright_black, bright_red, bright_green, bright_yellow,
    bright_blue, bright_magenta, bright_cyan, bright_white,
    
    // Extended colors
    indexed: u8,           // 256-color palette
    rgb: struct { r: u8, g: u8, b: u8 }, // True color
    
    pub fn fromRgb(r: u8, g: u8, b: u8) Color;
    pub fn ansiCode(self: Color, background: bool) []const u8;
};
```

### Text Attributes

```zig
pub const Attributes = packed struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    strikethrough: bool = false,
    dim: bool = false,
    reverse: bool = false,
    blink: bool = false,
    
    pub fn none() Attributes;
    pub fn withBold() Attributes;
    pub fn withItalic() Attributes;
    pub fn withUnderline() Attributes;
    pub fn ansiCodes(self: Attributes, allocator: std.mem.Allocator) ![]const u8;
};
```

---

## ⌨️ Event API

### Event Types

```zig
pub const Event = union(enum) {
    key: Key,
    mouse: MouseEvent,
    resize: ResizeEvent,
    focus: FocusEvent,
    paste: PasteEvent,
    custom: CustomEvent,
};
```

### Key Events

```zig
pub const Key = union(enum) {
    // Control keys
    ctrl_a, ctrl_b, ctrl_c, ctrl_d, ctrl_e, ctrl_f, ctrl_g,
    ctrl_h, ctrl_i, ctrl_j, ctrl_k, ctrl_l, ctrl_m, ctrl_n,
    ctrl_o, ctrl_p, ctrl_q, ctrl_r, ctrl_s, ctrl_t, ctrl_u,
    ctrl_v, ctrl_w, ctrl_x, ctrl_y, ctrl_z,
    
    // Special keys
    escape, enter, tab, backspace, delete,
    insert, home, end, page_up, page_down,
    
    // Arrow keys
    up, down, left, right,
    
    // Function keys
    f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,
    
    // Character input
    char: u21,
    
    // Modifier combinations
    alt: u21,
    shift: u21,
    ctrl: u21,
};
```

### Mouse Events

```zig
pub const MouseEvent = struct {
    x: u16,
    y: u16,
    button: MouseButton,
    kind: MouseEventKind,
    modifiers: KeyModifiers,
};

pub const MouseButton = enum {
    left, right, middle,
    wheel_up, wheel_down,
    wheel_left, wheel_right,
};

pub const MouseEventKind = enum {
    press, release, drag, move, scroll,
};

pub const KeyModifiers = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
};
```

### Event Handling

```zig
// Widget event handler
pub fn handleEvent(widget: *Widget, event: Event) bool {
    switch (event) {
        .key => |key| {
            return handleKeyEvent(widget, key);
        },
        .mouse => |mouse| {
            return handleMouseEvent(widget, mouse);
        },
        else => return false,
    }
}

// Global event handler
pub const EventHandler = *const fn(Event) bool;
pub fn setGlobalEventHandler(app: *App, handler: EventHandler) void;
```

---

## 📐 Layout API

### Layout Constraints

```zig
pub const Constraint = union(enum) {
    length: u16,          // Fixed length
    percentage: u8,       // Percentage of available space  
    ratio: [2]u32,       // Ratio (e.g., 1:3)
    min: u16,            // Minimum length
    max: u16,            // Maximum length
    
    pub const Priority = enum { low, normal, high };
    
    // Constraint with priority
    priority: struct {
        constraint: Constraint,
        priority: Priority,
    },
};
```

### Layout Direction

```zig
pub const Direction = enum { horizontal, vertical };

pub const Layout = struct {
    pub fn init(allocator: std.mem.Allocator) Layout;
    pub fn deinit(self: *Layout) void;
    
    pub fn split(
        self: *Layout, 
        direction: Direction, 
        constraints: []const Constraint
    ) []Rect;
    
    pub fn splitArea(
        self: *Layout,
        area: Rect,
        direction: Direction,
        constraints: []const Constraint
    ) []Rect;
};
```

### Geometry Types

```zig
pub const Position = struct {
    x: u16,
    y: u16,
    
    pub fn init(x: u16, y: u16) Position;
    pub fn add(self: Position, other: Position) Position;
    pub fn sub(self: Position, other: Position) Position;
};

pub const Size = struct {
    width: u16,
    height: u16,
    
    pub fn init(width: u16, height: u16) Size;
    pub fn area(self: Size) u32;
};

pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    
    pub fn init(x: u16, y: u16, width: u16, height: u16) Rect;
    pub fn position(self: Rect) Position;
    pub fn size(self: Rect) Size;
    pub fn area(self: Rect) u32;
    pub fn contains(self: Rect, point: Position) bool;
    pub fn intersects(self: Rect, other: Rect) bool;
    pub fn intersection(self: Rect, other: Rect) ?Rect;
    pub fn union(self: Rect, other: Rect) Rect;
};
```

---

## 🔧 Utility API

### Terminal Interface

```zig
pub const Terminal = struct {
    pub fn init(allocator: std.mem.Allocator) !*Terminal;
    pub fn deinit(self: *Terminal) void;
    
    pub fn enableRawMode(self: *Terminal) !void;
    pub fn disableRawMode(self: *Terminal) !void;
    
    pub fn size(self: *Terminal) !Size;
    pub fn clear(self: *Terminal) !void;
    pub fn flush(self: *Terminal) !void;
    
    pub fn setCursor(self: *Terminal, pos: Position) !void;
    pub fn hideCursor(self: *Terminal) !void;
    pub fn showCursor(self: *Terminal) !void;
    
    pub fn enableMouseCapture(self: *Terminal) !void;
    pub fn disableMouseCapture(self: *Terminal) !void;
    
    pub fn setTitle(self: *Terminal, title: []const u8) !void;
};
```

### Buffer System

```zig
pub const Cell = struct {
    char: u21,
    style: Style,
    
    pub fn init(char: u21, style: Style) Cell;
    pub fn withChar(char: u21) Cell;
    pub fn withStyle(style: Style) Cell;
};

pub const Buffer = struct {
    pub fn init(allocator: std.mem.Allocator, area: Rect) !*Buffer;
    pub fn deinit(self: *Buffer) void;
    
    pub fn setCell(self: *Buffer, x: u16, y: u16, cell: Cell) void;
    pub fn getCell(self: *const Buffer, x: u16, y: u16) Cell;
    
    pub fn fill(self: *Buffer, area: Rect, cell: Cell) void;
    pub fn clear(self: *Buffer) void;
    
    pub fn writeText(self: *Buffer, x: u16, y: u16, text: []const u8, style: Style) void;
    pub fn writeLine(self: *Buffer, x: u16, y: u16, text: []const u8, style: Style) void;
    
    pub fn diff(self: *const Buffer, other: *const Buffer) BufferDiff;
    pub fn merge(self: *Buffer, other: *const Buffer) void;
};
```

### Input System

```zig
pub const InputReader = struct {
    pub fn init(allocator: std.mem.Allocator) !*InputReader;
    pub fn deinit(self: *InputReader) void;
    
    pub fn readEvent(self: *InputReader) !?Event;
    pub fn hasEvent(self: *const InputReader) bool;
    
    pub fn enableMouseEvents(self: *InputReader) void;
    pub fn disableMouseEvents(self: *InputReader) void;
    
    pub fn setTimeout(self: *InputReader, timeout_ms: u64) void;
};
```

### Clipboard Support

```zig
pub const ClipboardManager = struct {
    pub fn init(allocator: std.mem.Allocator) !*ClipboardManager;
    pub fn deinit(self: *ClipboardManager) void;
    
    pub fn getText(self: *ClipboardManager, allocator: std.mem.Allocator) ![]const u8;
    pub fn setText(self: *ClipboardManager, text: []const u8) !void;
    
    pub fn hasText(self: *const ClipboardManager) bool;
    pub fn clear(self: *ClipboardManager) !void;
};
```

---

## 🧪 Testing API

### Widget Testing

```zig
pub const WidgetTester = struct {
    pub fn init(allocator: std.mem.Allocator) !*WidgetTester;
    pub fn deinit(self: *WidgetTester) void;
    
    pub fn renderWidget(self: *WidgetTester, widget: *Widget, area: Rect) !*Buffer;
    pub fn sendEvent(self: *WidgetTester, widget: *Widget, event: Event) bool;
    
    pub fn expectText(self: *WidgetTester, buffer: *Buffer, x: u16, y: u16, expected: []const u8) !void;
    pub fn expectStyle(self: *WidgetTester, buffer: *Buffer, x: u16, y: u16, expected: Style) !void;
    pub fn expectCell(self: *WidgetTester, buffer: *Buffer, x: u16, y: u16, expected: Cell) !void;
};
```

### Application Testing

```zig
pub const AppTester = struct {
    pub fn init(allocator: std.mem.Allocator, config: AppConfig) !*AppTester;
    pub fn deinit(self: *AppTester) void;
    
    pub fn addWidget(self: *AppTester, widget: *Widget) !void;
    pub fn removeWidget(self: *AppTester, widget: *Widget) void;
    
    pub fn sendEvent(self: *AppTester, event: Event) !void;
    pub fn tick(self: *AppTester) !void;
    pub fn render(self: *AppTester) !*Buffer;
    
    pub fn expectWidgetCount(self: *AppTester, expected: usize) !void;
    pub fn expectScreenContent(self: *AppTester, expected: []const u8) !void;
};
```

---

## 📖 Migration Guide

### From v0.3.2 to v0.3.3

#### Style API Changes

```zig
// Old (v0.3.2)
const style = phantom.Style.withFg(phantom.Color.red);

// New (v0.3.3) - Instance method
const style = phantom.Style.default().withFg(phantom.Color.red);
```

#### ArrayList API Changes

```zig
// Old (v0.3.2)
var list = std.ArrayList(T){};

// New (v0.3.3) - Explicit initialization
var list = std.ArrayList(T).init(allocator);
```

---

**This completes the comprehensive API reference for Phantom TUI Framework v0.3.3. All APIs are production-ready and extensively tested.** 👻✨