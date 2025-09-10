# 👻 Phantom TUI Framework - Complete Documentation

**Version**: 0.3.3  
**Zig Compatibility**: 0.16+  
**License**: MIT  

---

## 📖 Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [Core Concepts](#core-concepts)
5. [Widget Reference](#widget-reference)
6. [Style System](#style-system)
7. [Event Handling](#event-handling)
8. [Layout System](#layout-system)
9. [Examples](#examples)
10. [Best Practices](#best-practices)
11. [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

Phantom is a production-ready TUI (Terminal User Interface) framework for Zig, inspired by Ratatui and built from the ground up for modern Zig development. It provides a comprehensive widget system, advanced styling capabilities, and efficient rendering for creating professional terminal applications.

### ✨ Key Features

- **🚀 Production Ready**: Stable API compatible with Zig 0.16+
- **🧩 Rich Widget Library**: 20+ widgets including advanced components
- **🎨 Advanced Styling**: Colors, attributes, backgrounds with fluent API
- **⚡ High Performance**: Efficient diff-based rendering
- **🖱️ Full Input Support**: Keyboard navigation, mouse events, focus management  
- **📱 Responsive Layouts**: Flexible constraint-based layout system
- **🔧 Memory Safe**: Proper allocator usage and cleanup patterns
- **🧪 Testable**: Comprehensive testing support

---

## 🛠️ Installation

### Prerequisites

- **Zig 0.16+** (tested with 0.16.0-dev.164+bc7955306)
- Terminal with ANSI support

### Add to Your Project

#### Method 1: Using `zig fetch`
```bash
zig fetch --save https://github.com/ghostkellz/phantom/archive/v0.3.3.tar.gz
```

#### Method 2: Manual `build.zig.zon`
```zig
.{
    .name = "your-project",
    .version = "0.1.0",
    .dependencies = .{
        .phantom = .{
            .url = "https://github.com/ghostkellz/phantom/archive/v0.3.3.tar.gz",
            .hash = "phantom-0.3.3-[HASH_WILL_BE_PROVIDED]",
        },
    },
}
```

#### Update `build.zig`
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const phantom_dep = b.dependency("phantom", .{
        .target = target,
        .optimize = optimize,
    });
    const phantom_mod = phantom_dep.module("phantom");

    const exe = b.addExecutable(.{
        .name = "your-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("phantom", phantom_mod);
    b.installArtifact(exe);
}
```

---

## 🚀 Quick Start

### Basic Application

```zig
const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize application
    var app = try phantom.App.init(allocator, phantom.AppConfig{
        .title = "👻 My Phantom App",
        .tick_rate_ms = 50,
    });
    defer app.deinit();

    // Create styled text
    const hello_text = try phantom.widgets.Text.initWithStyle(
        allocator,
        "Hello, Phantom! 👻",
        phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold()
    );

    try app.addWidget(&hello_text.widget);

    // Run application
    try app.run();
}
```

### Advanced Example with Multiple Widgets

```zig
const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try phantom.App.init(allocator, .{
        .title = "Advanced Phantom Demo",
        .tick_rate_ms = 16, // 60 FPS
        .mouse_enabled = true,
    });
    defer app.deinit();

    // Header text
    const header = try phantom.widgets.Text.initWithStyle(
        allocator,
        "🚀 Advanced Phantom TUI Demo",
        phantom.Style.default().withFg(phantom.Color.bright_magenta).withBold()
    );
    try app.addWidget(&header.widget);

    // Interactive list
    const feature_list = try phantom.widgets.List.init(allocator);
    try feature_list.addItemText("🧱 Rich Widget Library");
    try feature_list.addItemText("🎨 Advanced Styling System");
    try feature_list.addItemText("⚡ High Performance Rendering");
    try feature_list.addItemText("🖱️ Full Mouse Support");
    try feature_list.addItemText("📱 Responsive Layouts");
    
    feature_list.setSelectedStyle(
        phantom.Style.default().withFg(phantom.Color.white).withBg(phantom.Color.bright_blue).withBold()
    );
    try app.addWidget(&feature_list.widget);

    // Progress bar
    const progress = try phantom.widgets.ProgressBar.init(allocator);
    try progress.setLabel("Loading Features");
    progress.setValue(75.0);
    progress.setFillStyle(phantom.Style.default().withFg(phantom.Color.bright_green));
    try app.addWidget(&progress.widget);

    // Input field
    const input = try phantom.widgets.Input.init(allocator);
    try input.setPlaceholder("Type something...");
    input.setOnSubmit(onInputSubmit);
    try app.addWidget(&input.widget);

    try app.run();
}

fn onInputSubmit(input: *phantom.widgets.Input, text: []const u8) void {
    std.debug.print("User entered: {s}\n", .{text});
}
```

---

## 🧩 Core Concepts

### Application Lifecycle

1. **Initialize**: Create app with configuration
2. **Setup**: Add widgets and configure layout
3. **Run**: Enter the main event loop
4. **Cleanup**: Automatic cleanup on scope exit

### Widget System

- **Base Widget**: All widgets inherit from the base `Widget` interface
- **VTable System**: Efficient virtual method dispatch
- **Composition**: Widgets can contain other widgets
- **Lifecycle**: Automatic memory management with proper cleanup

### Rendering Pipeline

1. **Input Processing**: Handle keyboard/mouse events
2. **Widget Updates**: Update widget state
3. **Layout Calculation**: Calculate widget positions
4. **Diff Rendering**: Only redraw changed areas
5. **Buffer Flush**: Output to terminal

---

## 🎨 Widget Reference

### Core Display Widgets

#### Text Widget
```zig
// Basic text
const text = try phantom.widgets.Text.init(allocator, "Hello World");

// Styled text  
const styled_text = try phantom.widgets.Text.initWithStyle(
    allocator,
    "Styled Text",
    phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold()
);

// Multi-line text with alignment
const multiline = try phantom.widgets.Text.init(allocator, "Line 1\nLine 2\nLine 3");
multiline.setAlignment(.center);
```

#### Block Widget
```zig
// Container with border
const block = try phantom.widgets.Block.init(allocator);
try block.setTitle("My Block");
block.setBorderStyle(phantom.Style.default().withFg(phantom.Color.bright_blue));

// Different border types
block.setBorderType(.rounded); // .single, .double, .rounded, .thick
```

### Interactive Widgets

#### List Widget
```zig
const list = try phantom.widgets.List.init(allocator);

// Add items
try list.addItemText("Option 1");
try list.addItemText("Option 2");
try list.addItemText("Option 3");

// Styling
list.setSelectedStyle(phantom.Style.default().withBg(phantom.Color.bright_blue));
list.setNormalStyle(phantom.Style.default().withFg(phantom.Color.white));

// Event handling
list.setOnSelect(onListSelect);

fn onListSelect(list_widget: *phantom.widgets.List, index: usize) void {
    std.debug.print("Selected item: {d}\n", .{index});
}
```

#### Button Widget
```zig
const button = try phantom.widgets.Button.init(allocator, "Click Me");

// Styling states
button.setNormalStyle(phantom.Style.default().withFg(phantom.Color.white));
button.setHoverStyle(phantom.Style.default().withBg(phantom.Color.bright_blue));
button.setPressedStyle(phantom.Style.default().withBg(phantom.Color.blue));

// Event handling
button.setOnClick(onButtonClick);

fn onButtonClick(btn: *phantom.widgets.Button) void {
    std.debug.print("Button clicked!\n", .{});
}
```

#### Input Widget
```zig
const input = try phantom.widgets.Input.init(allocator);

// Configuration
try input.setPlaceholder("Enter your name...");
input.setMaxLength(50);
input.setPassword(false); // Set true for password field

// Styling
input.setNormalStyle(phantom.Style.default().withFg(phantom.Color.white));
input.setFocusedStyle(phantom.Style.default().withBg(phantom.Color.bright_blue));

// Events
input.setOnChange(onInputChange);
input.setOnSubmit(onInputSubmit);

fn onInputChange(input_widget: *phantom.widgets.Input, text: []const u8) void {
    std.debug.print("Input changed: {s}\n", .{text});
}
```

### Advanced Widgets

#### StreamingText Widget
```zig
// Perfect for AI chat interfaces
const streaming = try phantom.widgets.StreamingText.init(allocator);

// Configuration
streaming.setTypingSpeed(50); // Characters per second
streaming.setAutoScroll(true);
streaming.setShowCursor(true);

// Add text chunks (simulates streaming)
streaming.startStreaming();
try streaming.addChunk("Hello, ");
try streaming.addChunk("this is streaming text!");
// streaming.stopStreaming(); // Call when done

// Styling
streaming.setTextStyle(phantom.Style.default().withFg(phantom.Color.white));
streaming.setStreamingStyle(phantom.Style.default().withFg(phantom.Color.cyan));
streaming.setCursorStyle(phantom.Style.default().withBg(phantom.Color.white));
```

#### Table Widget
```zig
const table = try phantom.widgets.Table.init(allocator);

// Define columns
try table.addColumn(.{ .title = "Name", .width = 20 });
try table.addColumn(.{ .title = "Age", .width = 10 });
try table.addColumn(.{ .title = "City", .width = 15 });

// Add rows
try table.addRow(&[_][]const u8{ "Alice", "25", "New York" });
try table.addRow(&[_][]const u8{ "Bob", "30", "Los Angeles" });
try table.addRow(&[_][]const u8{ "Charlie", "35", "Chicago" });

// Styling
table.setHeaderStyle(phantom.Style.default().withBold().withFg(phantom.Color.bright_cyan));
table.setSelectedStyle(phantom.Style.default().withBg(phantom.Color.bright_blue));
table.setAlternateRowStyle(phantom.Style.default().withBg(phantom.Color.bright_black));
```

#### ProgressBar Widget
```zig
const progress = try phantom.widgets.ProgressBar.init(allocator);

// Configuration
progress.setValue(65.0); // 0.0 to 100.0
try progress.setLabel("Loading");
progress.setShowValue(true);
progress.setShowPercentage(true);

// Styling
progress.setFillStyle(phantom.Style.default().withFg(phantom.Color.green));
progress.setBarStyle(phantom.Style.default().withFg(phantom.Color.bright_black));
progress.setTextStyle(phantom.Style.default().withFg(phantom.Color.white));
```

#### CodeBlock Widget
```zig
const code_sample = 
    \\const std = @import("std");
    \\
    \\pub fn main() void {
    \\    std.debug.print("Hello, World!\n", .{});
    \\}
;

const code_block = try phantom.widgets.CodeBlock.init(allocator, code_sample, .zig);

// Configuration
code_block.setShowLineNumbers(true);
code_block.setTabSize(4);
code_block.setWrapLines(false);

// Styling (syntax highlighting built-in)
code_block.setBackgroundStyle(phantom.Style.default().withBg(phantom.Color.black));
```

### Specialized Widgets

#### Dialog Widget
```zig
const dialog = try phantom.widgets.Dialog.init(allocator, .info);

// Configuration
try dialog.setTitle("Information");
try dialog.setMessage("This is an information dialog.");

// Add buttons
try dialog.addButton(.{ .text = "OK", .action = .close });
try dialog.addButton(.{ .text = "Cancel", .action = .cancel });

// Show dialog
dialog.show();
```

#### ContextMenu Widget
```zig
const menu = try phantom.widgets.ContextMenu.init(allocator);

// Add menu items
try menu.addItem(.{ .text = "Copy", .shortcut = "Ctrl+C" });
try menu.addItem(.{ .text = "Paste", .shortcut = "Ctrl+V" });
try menu.addSeparator();
try menu.addItem(.{ .text = "Delete", .shortcut = "Del" });

// Show at position
menu.showAt(.{ .x = 10, .y = 5 });
```

#### TaskMonitor Widget
```zig
const monitor = try phantom.widgets.TaskMonitor.init(allocator);

// Add tasks
try monitor.addTask("task1", "Downloading files");
try monitor.addTask("task2", "Processing data");
try monitor.addTask("task3", "Generating report");

// Update task progress
try monitor.updateTask("task1", .{ .progress = 50.0, .status = .running });
try monitor.updateTask("task2", .{ .progress = 100.0, .status = .completed });
try monitor.updateTask("task3", .{ .progress = 0.0, .status = .failed });
```

---

## 🎨 Style System

### Color System

Phantom supports a comprehensive color system:

```zig
// Basic colors
phantom.Color.black
phantom.Color.red
phantom.Color.green
phantom.Color.yellow
phantom.Color.blue
phantom.Color.magenta
phantom.Color.cyan
phantom.Color.white

// Bright variants
phantom.Color.bright_black  // (gray)
phantom.Color.bright_red
phantom.Color.bright_green
phantom.Color.bright_yellow
phantom.Color.bright_blue
phantom.Color.bright_magenta
phantom.Color.bright_cyan
phantom.Color.bright_white

// Custom colors
phantom.Color.rgb(255, 128, 0)    // True color RGB
phantom.Color.indexed(142)        // 256-color palette
```

### Style Creation

#### Builder Pattern (Recommended)
```zig
// Start with default and chain modifications
const style = phantom.Style.default()
    .withFg(phantom.Color.bright_cyan)
    .withBg(phantom.Color.black)
    .withBold()
    .withUnderline();
```

#### Direct Construction
```zig
const style = phantom.Style{
    .fg = phantom.Color.bright_cyan,
    .bg = phantom.Color.black,
    .attributes = .{
        .bold = true,
        .italic = false,
        .underline = true,
        .strikethrough = false,
        .dim = false,
        .reverse = false,
        .blink = false,
    },
};
```

### Text Attributes

```zig
style.withBold()          // Bold text
style.withItalic()        // Italic text (if supported)
style.withUnderline()     // Underlined text
style.withStrikethrough() // Strikethrough text
style.withDim()          // Dimmed text
style.withReverse()      // Inverted colors
style.withBlink()        // Blinking text (rarely supported)
```

### Style Examples

```zig
// Error message style
const error_style = phantom.Style.default()
    .withFg(phantom.Color.bright_red)
    .withBold();

// Success message style  
const success_style = phantom.Style.default()
    .withFg(phantom.Color.bright_green)
    .withBold();

// Warning style
const warning_style = phantom.Style.default()
    .withFg(phantom.Color.bright_yellow);

// Code style
const code_style = phantom.Style.default()
    .withFg(phantom.Color.cyan)
    .withBg(phantom.Color.black);

// Highlight style
const highlight_style = phantom.Style.default()
    .withFg(phantom.Color.black)
    .withBg(phantom.Color.bright_yellow);
```

---

## ⌨️ Event Handling

### Key Events

```zig
fn handleKeyEvent(event: phantom.Event) bool {
    switch (event) {
        .key => |key| {
            switch (key) {
                // Control keys
                .ctrl_c => return true,  // Exit
                .ctrl_q => return true,  // Quit
                .escape => return true,  // Cancel
                
                // Navigation
                .up => handleUp(),
                .down => handleDown(),
                .left => handleLeft(),
                .right => handleRight(),
                .page_up => handlePageUp(),
                .page_down => handlePageDown(),
                .home => handleHome(),
                .end => handleEnd(),
                
                // Function keys
                .f1 => showHelp(),
                .f2 => showSettings(),
                .f10 => showMenu(),
                
                // Character input
                .char => |c| handleChar(c),
                .enter => handleEnter(),
                .backspace => handleBackspace(),
                .delete => handleDelete(),
                .tab => handleTab(),
                
                else => {},
            }
        },
        else => {},
    }
    return false;
}
```

### Mouse Events

```zig
fn handleMouseEvent(mouse: phantom.MouseEvent) void {
    switch (mouse.button) {
        .left => {
            if (mouse.kind == .press) {
                handleLeftClick(mouse.x, mouse.y);
            }
        },
        .right => {
            if (mouse.kind == .press) {
                showContextMenu(mouse.x, mouse.y);
            }
        },
        .wheel_up => handleScrollUp(),
        .wheel_down => handleScrollDown(),
        else => {},
    }
}
```

### Widget Event Callbacks

```zig
// Button click callback
fn onButtonClick(button: *phantom.widgets.Button) void {
    std.debug.print("Button '{}' clicked!\n", .{button.getText()});
}

// List selection callback
fn onListSelect(list: *phantom.widgets.List, index: usize) void {
    const item = list.getItem(index);
    std.debug.print("Selected: {s}\n", .{item.text});
}

// Input change callback
fn onInputChange(input: *phantom.widgets.Input, text: []const u8) void {
    // Validate input as user types
    if (text.len > 0 and std.ascii.isAlpha(text[0])) {
        input.setStyle(normal_style);
    } else {
        input.setStyle(error_style);
    }
}

// Input submit callback
fn onInputSubmit(input: *phantom.widgets.Input, text: []const u8) void {
    processUserInput(text);
    input.clear();
}
```

---

## 📐 Layout System

### Constraint-Based Layouts

```zig
// Create layout manager
const layout = phantom.layout.Layout.init(allocator);
defer layout.deinit();

// Horizontal split
const h_areas = layout.split(.horizontal, &[_]phantom.layout.Constraint{
    .{ .percentage = 25 }, // Sidebar (25%)
    .{ .percentage = 75 }, // Main content (75%)
});

// Vertical split of main area
const v_areas = layout.split(.vertical, &[_]phantom.layout.Constraint{
    .{ .min = 3 },         // Header (minimum 3 lines)
    .{ .percentage = 80 }, // Content (80% of remaining)
    .{ .min = 1 },         // Status bar (1 line)
});
```

### Layout Constraints

```zig
// Fixed size constraints
.{ .min = 10 }       // Minimum 10 units
.{ .max = 50 }       // Maximum 50 units  
.{ .length = 20 }    // Exactly 20 units

// Flexible constraints
.{ .percentage = 30 }     // 30% of available space
.{ .ratio = [2]u32{1, 3} } // 1:3 ratio

// Priority constraints
.{ .priority = .high, .min = 5 }   // High priority, min 5
.{ .priority = .low, .percentage = 20 } // Low priority, 20%
```

### Responsive Design

```zig
fn updateLayout(app: *phantom.App, terminal_size: phantom.geometry.Size) !void {
    const layout = phantom.layout.Layout.init(app.allocator);
    defer layout.deinit();
    
    // Adjust layout based on terminal size
    const constraints = if (terminal_size.width < 80)
        // Mobile-like layout
        &[_]phantom.layout.Constraint{
            .{ .percentage = 100 }, // Stack vertically
        }
    else
        // Desktop layout  
        &[_]phantom.layout.Constraint{
            .{ .percentage = 30 },  // Sidebar
            .{ .percentage = 70 },  // Main content
        };
    
    const areas = layout.split(.horizontal, constraints);
    
    // Apply layout to widgets
    for (app.widgets.items, 0..) |widget, i| {
        if (i < areas.len) {
            widget.resize(areas[i]);
        }
    }
}
```

---

## 💼 Examples

### Chat Application

```zig
const ChatApp = struct {
    app: *phantom.App,
    chat_history: *phantom.widgets.StreamingText,
    input_field: *phantom.widgets.Input,
    send_button: *phantom.widgets.Button,
    
    pub fn init(allocator: std.mem.Allocator) !*ChatApp {
        const self = try allocator.create(ChatApp);
        
        self.app = try phantom.App.init(allocator, .{
            .title = "💬 Chat Application",
            .tick_rate_ms = 30,
        });
        
        // Chat history (streaming text for AI responses)
        self.chat_history = try phantom.widgets.StreamingText.init(allocator);
        self.chat_history.setAutoScroll(true);
        self.chat_history.setTypingSpeed(80);
        try self.app.addWidget(&self.chat_history.widget);
        
        // Input field
        self.input_field = try phantom.widgets.Input.init(allocator);
        try self.input_field.setPlaceholder("Type your message...");
        self.input_field.setOnSubmit(onMessageSubmit);
        try self.app.addWidget(&self.input_field.widget);
        
        // Send button
        self.send_button = try phantom.widgets.Button.init(allocator, "Send");
        self.send_button.setOnClick(onSendClick);
        try self.app.addWidget(&self.send_button.widget);
        
        return self;
    }
    
    pub fn run(self: *ChatApp) !void {
        try self.app.run();
    }
    
    fn onMessageSubmit(input: *phantom.widgets.Input, message: []const u8) void {
        // Handle user message
        processMessage(message);
        input.clear();
    }
    
    fn onSendClick(button: *phantom.widgets.Button) void {
        _ = button;
        // Trigger send message
    }
};
```

### File Manager

```zig
const FileManager = struct {
    app: *phantom.App,
    file_list: *phantom.widgets.List,
    path_input: *phantom.widgets.Input,
    status_bar: *phantom.widgets.Text,
    
    current_path: []const u8,
    
    pub fn init(allocator: std.mem.Allocator, initial_path: []const u8) !*FileManager {
        const self = try allocator.create(FileManager);
        
        self.app = try phantom.App.init(allocator, .{
            .title = "📁 File Manager",
            .tick_rate_ms = 50,
        });
        
        self.current_path = try allocator.dupe(u8, initial_path);
        
        // Path input
        self.path_input = try phantom.widgets.Input.init(allocator);
        try self.path_input.setText(initial_path);
        self.path_input.setOnSubmit(onPathChange);
        try self.app.addWidget(&self.path_input.widget);
        
        // File list
        self.file_list = try phantom.widgets.List.init(allocator);
        self.file_list.setOnSelect(onFileSelect);
        try self.app.addWidget(&self.file_list.widget);
        
        // Status bar
        self.status_bar = try phantom.widgets.Text.init(allocator, "Ready");
        try self.app.addWidget(&self.status_bar.widget);
        
        // Load initial directory
        try self.loadDirectory(initial_path);
        
        return self;
    }
    
    fn loadDirectory(self: *FileManager, path: []const u8) !void {
        self.file_list.clear();
        
        var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const icon = switch (entry.kind) {
                .directory => "📁",
                .file => "📄",
                else => "❓",
            };
            
            const display_name = try std.fmt.allocPrint(
                self.app.allocator, 
                "{s} {s}", 
                .{ icon, entry.name }
            );
            
            try self.file_list.addItemText(display_name);
        }
        
        const status = try std.fmt.allocPrint(
            self.app.allocator,
            "📁 {s} ({d} items)",
            .{ path, self.file_list.getItemCount() }
        );
        try self.status_bar.setText(status);
    }
    
    fn onPathChange(input: *phantom.widgets.Input, path: []const u8) void {
        // Change directory
        _ = input;
        _ = path;
    }
    
    fn onFileSelect(list: *phantom.widgets.List, index: usize) void {
        // Handle file selection
        _ = list;
        _ = index;
    }
};
```

---

## 🏆 Best Practices

### Memory Management

```zig
// ✅ Good: Always defer cleanup
var app = try phantom.App.init(allocator, .{});
defer app.deinit(); // Cleans up all widgets automatically

// ✅ Good: Use arena allocator for temporary data
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const temp_allocator = arena.allocator();

// ❌ Bad: Manual cleanup (error-prone)
const widget = try phantom.widgets.Text.init(allocator, "text");
// ... forgot to call widget.deinit()
```

### Performance Optimization

```zig
// ✅ Adjust tick rate based on use case
const config = phantom.AppConfig{
    .tick_rate_ms = 16,  // 60 FPS for smooth animations
    .tick_rate_ms = 100, // 10 FPS for data displays
    .tick_rate_ms = 250, // 4 FPS for static content
};

// ✅ Use efficient text updates
const streaming = try phantom.widgets.StreamingText.init(allocator);
streaming.setTypingSpeed(100); // Adjust based on content

// ✅ Batch widget updates
try app.batchUpdate(.{
    .widgets = &[_]*phantom.Widget{ &text.widget, &list.widget },
    .layout_changed = true,
});
```

### Error Handling

```zig
// ✅ Proper error handling with context
fn createWidget(allocator: std.mem.Allocator) !*phantom.widgets.Text {
    const text = phantom.widgets.Text.init(allocator, "Hello") catch |err| {
        std.log.err("Failed to create text widget: {}", .{err});
        return err;
    };
    return text;
}

// ✅ Validate user input
fn validateInput(text: []const u8) bool {
    return text.len > 0 and text.len <= 100;
}
```

### Code Organization

```zig
// ✅ Separate concerns
const UI = struct {
    app: *phantom.App,
    widgets: UIWidgets,
    
    const UIWidgets = struct {
        header: *phantom.widgets.Text,
        content: *phantom.widgets.List,
        footer: *phantom.widgets.Text,
    };
    
    pub fn init(allocator: std.mem.Allocator) !*UI {
        // Initialize UI components
    }
    
    pub fn update(self: *UI, data: AppData) !void {
        // Update widgets with new data
    }
};

// ✅ Use configuration structs
const ChatConfig = struct {
    typing_speed: u64 = 50,
    auto_scroll: bool = true,
    show_timestamps: bool = true,
    max_history: usize = 1000,
};
```

---

## 🔧 Troubleshooting

### Common Issues

#### Widget Not Displaying
```zig
// ❌ Problem: Widget not added to app
const text = try phantom.widgets.Text.init(allocator, "Hello");
// Missing: try app.addWidget(&text.widget);

// ✅ Solution: Always add widgets to app
try app.addWidget(&text.widget);
```

#### Events Not Working
```zig
// ❌ Problem: Event handler not set
const button = try phantom.widgets.Button.init(allocator, "Click");

// ✅ Solution: Set event handlers
button.setOnClick(onButtonClick);
```

#### Performance Issues
```zig
// ❌ Problem: Too high tick rate
.tick_rate_ms = 1, // 1000 FPS - too high!

// ✅ Solution: Use appropriate tick rate
.tick_rate_ms = 16, // 60 FPS - smooth for animations
.tick_rate_ms = 50, // 20 FPS - good for general UI
```

#### Memory Leaks
```zig
// ❌ Problem: Manual widget cleanup
const widget = try phantom.widgets.Text.init(allocator, "text");
defer widget.widget.deinit(); // Manual cleanup

// ✅ Solution: Use app cleanup
try app.addWidget(&widget.widget); // App handles cleanup
defer app.deinit(); // Cleans up all widgets
```

### Debug Mode

```zig
const app = try phantom.App.init(allocator, .{
    .debug_mode = true,        // Enable debug logging
    .show_fps = true,         // Show FPS counter
    .show_memory_usage = true, // Show memory usage
});
```

### Logging

```zig
// Enable phantom logging
const std = @import("std");

pub const log_level: std.log.Level = .debug;

// In your code
std.log.debug("Widget created: {s}", .{widget.name});
std.log.info("App started successfully", .{});
std.log.err("Failed to load config: {}", .{err});
```

---

## 📚 Additional Resources

- **API Reference**: See [API.md](API.md) for detailed API documentation
- **Integration Guide**: See [PHANTOM_INTEGRATION.md](PHANTOM_INTEGRATION.md) for project integration
- **Examples**: Check the `examples/` directory for complete applications
- **GitHub Issues**: Report bugs and request features
- **Community**: Join discussions in GitHub Discussions

---

**Ready to build amazing TUI applications with Phantom? Start with the Quick Start guide and explore the examples!** 👻✨