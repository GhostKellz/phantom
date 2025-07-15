# Phantom TUI Wishlist

Based on the development of ZEKE and the need for a robust TUI library (like Ratatui for Rust), here are the features that would make Phantom a comprehensive terminal user interface framework:

## Core TUI Framework

### 1. **Terminal Management**
- **Requested**: Low-level terminal control with cross-platform support
```zig
const terminal = try phantom.Terminal.init(allocator);
defer terminal.deinit();

try terminal.enterAlternateScreen();
try terminal.enableRawMode();
defer {
    terminal.exitAlternateScreen() catch {};
    terminal.disableRawMode() catch {};
}
```

### 2. **Event System**
- **Requested**: Unified event handling for keyboard, mouse, and resize events
```zig
const event = try terminal.readEvent();
switch (event) {
    .key => |key| {
        switch (key.code) {
            .char => |c| handleChar(c),
            .enter => handleEnter(),
            .backspace => handleBackspace(),
            .up, .down, .left, .right => handleArrowKeys(key.code),
            .f => |f_key| handleFunctionKey(f_key), // F1-F12
            .tab => handleTab(),
            .esc => handleEscape(),
            else => {},
        }
    },
    .mouse => |mouse| handleMouse(mouse),
    .resize => |size| handleResize(size.width, size.height),
}
```

### 3. **Style System**
- **Requested**: Rich text styling with colors, attributes, and themes
```zig
try terminal.setStyle(.{
    .fg = .red,
    .bg = .black,
    .bold = true,
    .italic = true,
    .underline = true,
    .strikethrough = true,
});

// 256-color support
try terminal.setStyle(.{ .fg = .color256(196) }); // Bright red

// RGB color support
try terminal.setStyle(.{ .fg = .rgb(255, 100, 50) });

// Style reset
try terminal.resetStyle();
```

### 4. **Layout System**
- **Requested**: Flexible layout engine for responsive UIs
```zig
const layout = phantom.Layout.init(allocator);
defer layout.deinit();

const main_area = layout.split(.horizontal, &[_]phantom.Constraint{
    .{ .percentage = 20 }, // Sidebar
    .{ .percentage = 80 }, // Main content
});

const content_area = layout.split(.vertical, &[_]phantom.Constraint{
    .{ .min = 3 }, // Header
    .{ .percentage = 80 }, // Chat area
    .{ .min = 3 }, // Input area
    .{ .min = 1 }, // Status bar
});
```

## Widget System

### 5. **Core Widgets**
- **Requested**: Essential UI components
```zig
// Text display
const text = phantom.Text.init("Hello, World!")
    .style(.{ .fg = .green, .bold = true })
    .alignment(.center);

// Input field
const input = phantom.Input.init(allocator)
    .placeholder("Type your message...")
    .max_length(1000)
    .password(false);

// Button
const button = phantom.Button.init("Send")
    .style(.{ .fg = .white, .bg = .blue })
    .on_click(sendMessage);
```

### 6. **List and Table Widgets**
- **Requested**: Data display components
```zig
// List widget
const list = phantom.List.init(allocator)
    .items(&chat_messages)
    .selected_style(.{ .fg = .black, .bg = .cyan })
    .highlight_symbol("► ");

// Table widget
const table = phantom.Table.init(allocator)
    .headers(&[_][]const u8{"Model", "Provider", "Status"})
    .rows(&model_data)
    .column_spacing(2)
    .style(.{ .fg = .white });
```

### 7. **Advanced Widgets**
- **Requested**: Complex UI components
```zig
// Progress bar
const progress = phantom.ProgressBar.init()
    .percentage(75)
    .style(.{ .fg = .green })
    .label("Processing...");

// Scrollable text area
const text_area = phantom.TextArea.init(allocator)
    .content(large_text)
    .scrollable(true)
    .wrap(true);

// Tabs
const tabs = phantom.Tabs.init(allocator)
    .add_tab("Chat", chat_widget)
    .add_tab("Models", model_widget)
    .add_tab("Settings", settings_widget)
    .selected(0);
```

## Dialog and Modal System

### 8. **Modal Dialogs**
- **Requested**: Overlay dialogs and popups
```zig
const dialog = phantom.Dialog.init(allocator)
    .title("Select Model")
    .content(model_selector)
    .buttons(&[_]phantom.Button{
        phantom.Button.init("OK").on_click(confirmSelection),
        phantom.Button.init("Cancel").on_click(cancelSelection),
    })
    .modal(true);
```

### 9. **Context Menus**
- **Requested**: Right-click and context-sensitive menus
```zig
const context_menu = phantom.ContextMenu.init(allocator)
    .add_item("Copy", copyAction)
    .add_item("Paste", pasteAction)
    .add_separator()
    .add_item("Delete", deleteAction);
```

### 10. **Notification System**
- **Requested**: Toast notifications and alerts
```zig
const notification = phantom.Notification.init("Message sent!")
    .type(.success)
    .duration(3000) // 3 seconds
    .position(.top_right);

try phantom.showNotification(notification);
```

## Advanced Features

### 11. **Scrolling and Pagination**
- **Requested**: Smooth scrolling for large content
```zig
const scroll_view = phantom.ScrollView.init(allocator)
    .content(large_widget)
    .vertical_scroll(true)
    .horizontal_scroll(false)
    .scroll_speed(3);
```

### 12. **Animation System**
- **Requested**: Smooth transitions and animations
```zig
const animation = phantom.Animation.init()
    .duration(500) // 500ms
    .easing(.ease_in_out)
    .from(.{ .x = 0, .alpha = 0 })
    .to(.{ .x = 10, .alpha = 1 });

try widget.animate(animation);
```

### 13. **Theme System**
- **Requested**: Customizable themes and color schemes
```zig
const theme = phantom.Theme.init()
    .primary_color(.blue)
    .secondary_color(.cyan)
    .background_color(.black)
    .text_color(.white)
    .accent_color(.green);

try phantom.setTheme(theme);

// Pre-built themes
try phantom.setTheme(.dark);
try phantom.setTheme(.light);
try phantom.setTheme(.monokai);
```

## Rendering and Performance

### 14. **Efficient Rendering**
- **Requested**: Optimized rendering with dirty rectangle tracking
```zig
const renderer = phantom.Renderer.init(allocator);
defer renderer.deinit();

// Only redraw changed areas
renderer.markDirty(widget_area);
try renderer.render();
```

### 15. **Double Buffering**
- **Requested**: Smooth updates without flicker
```zig
const buffer = phantom.Buffer.init(allocator, width, height);
defer buffer.deinit();

// Render to buffer
try buffer.render(widget);

// Swap buffers
try terminal.swapBuffers(buffer);
```

### 16. **Unicode Support**
- **Requested**: Full Unicode and emoji support
```zig
const text = phantom.Text.init("🚀 Hello 世界! 🎉")
    .style(.{ .fg = .green });

// Proper width calculation for Unicode
const width = phantom.textWidth("🚀 Hello 世界! 🎉");
```

## Input Handling

### 17. **Advanced Input Processing**
- **Requested**: Key combinations and input sequences
```zig
const input_handler = phantom.InputHandler.init(allocator);

// Key combinations
try input_handler.bind(.{ .ctrl = true, .key = 'c' }, quitAction);
try input_handler.bind(.{ .alt = true, .key = 'enter' }, sendAction);

// Input sequences
try input_handler.bindSequence(&[_]phantom.KeyCode{.esc, .esc}, escapeAction);
```

### 18. **Mouse Support**
- **Requested**: Full mouse interaction
```zig
const mouse_handler = phantom.MouseHandler.init();

switch (mouse_event) {
    .click => |click| {
        const widget = findWidgetAt(click.x, click.y);
        try widget.handleClick(click);
    },
    .drag => |drag| handleDrag(drag),
    .scroll => |scroll| handleScroll(scroll),
}
```

### 19. **Clipboard Integration**
- **Requested**: System clipboard access
```zig
// Copy to clipboard
try phantom.clipboard.copy("Hello, World!");

// Paste from clipboard
const text = try phantom.clipboard.paste(allocator);
defer allocator.free(text);
```

## Application Framework

### 20. **Event Loop**
- **Requested**: Main application loop with event handling
```zig
const app = phantom.App.init(allocator);
defer app.deinit();

try app.run(main_widget);
```

### 21. **State Management**
- **Requested**: Application state handling
```zig
const state = phantom.State.init(AppState);
state.update(.{ .current_model = "gpt-4" });

// React to state changes
try state.subscribe(onStateChange);
```

### 22. **Component System**
- **Requested**: Reusable UI components
```zig
const ChatPanel = phantom.Component.init(ChatPanelState, struct {
    pub fn render(self: *@This(), state: ChatPanelState) !phantom.Widget {
        return phantom.Column.init(allocator)
            .add(phantom.Text.init("Chat History"))
            .add(phantom.List.init(allocator).items(state.messages))
            .add(phantom.Input.init(allocator).value(state.current_input));
    }
});
```

## Integration Features

### 23. **Image Support**
- **Requested**: Image rendering in terminals that support it
```zig
const image = phantom.Image.init("/path/to/image.png")
    .width(20)
    .height(10)
    .fit(.contain);
```

### 24. **Hyperlinks**
- **Requested**: Clickable links in supported terminals
```zig
const link = phantom.Link.init("https://example.com")
    .text("Click here")
    .style(.{ .fg = .blue, .underline = true });
```

### 25. **Terminal Feature Detection**
- **Requested**: Capability detection for different terminals
```zig
const caps = phantom.capabilities.detect();
if (caps.true_color) {
    // Use RGB colors
} else if (caps.color_256) {
    // Use 256-color palette
} else {
    // Fallback to 16 colors
}
```

## Developer Experience

### 26. **Debug Mode**
- **Requested**: Development tools and debugging
```zig
const debug = phantom.Debug.init(allocator);
try debug.enable();

// Show widget bounds
debug.show_bounds = true;

// Log events
debug.log_events = true;
```

### 27. **Hot Reload**
- **Requested**: Live UI updates during development
```zig
const dev_server = phantom.DevServer.init(allocator);
try dev_server.watch("src/ui/");
```

### 28. **Widget Inspector**
- **Requested**: Runtime UI inspection
```zig
const inspector = phantom.Inspector.init(allocator);
try inspector.inspect(main_widget);
```

## ZEKE-Specific Features

### 29. **Code Syntax Highlighting**
- **Requested**: Syntax highlighting for code blocks
```zig
const code_block = phantom.CodeBlock.init(allocator)
    .language("rust")
    .content(code_string)
    .line_numbers(true)
    .theme(.monokai);
```

### 30. **Markdown Rendering**
- **Requested**: Rich text markdown support
```zig
const markdown = phantom.Markdown.init(allocator)
    .content("# Hello\n\nThis is **bold** text.")
    .style(.{ .fg = .white });
```

### 31. **Streaming Text**
- **Requested**: Real-time text updates for AI responses
```zig
const streaming_text = phantom.StreamingText.init(allocator)
    .on_chunk(handleTextChunk)
    .typing_speed(50); // Characters per second
```

This comprehensive TUI framework would make Phantom a powerful foundation for building rich terminal applications like ZEKE, providing all the necessary components for creating an excellent developer experience in the terminal.