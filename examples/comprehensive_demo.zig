//! Comprehensive Phantom TUI demo showcasing all widgets
const std = @import("std");
const phantom = @import("phantom");

// Demo state
var demo_state = struct {
    current_page: u8 = 0,
    progress_value: f64 = 0.0,
    streaming_active: bool = false,
    input_text: []const u8 = "",
    
    const TOTAL_PAGES = 7;
    
    pub fn nextPage(self: *@This()) void {
        self.current_page = (self.current_page + 1) % TOTAL_PAGES;
    }
    
    pub fn prevPage(self: *@This()) void {
        self.current_page = if (self.current_page == 0) TOTAL_PAGES - 1 else self.current_page - 1;
    }
}{};

// Button click handlers
fn onNextClick(button: *phantom.widgets.Button) void {
    _ = button;
    demo_state.nextPage();
}

fn onPrevClick(button: *phantom.widgets.Button) void {
    _ = button;
    demo_state.prevPage();
}

fn onProgressIncrement(button: *phantom.widgets.Button) void {
    _ = button;
    demo_state.progress_value = @min(demo_state.progress_value + 10.0, 100.0);
}

fn onProgressDecrement(button: *phantom.widgets.Button) void {
    _ = button;
    demo_state.progress_value = @max(demo_state.progress_value - 10.0, 0.0);
}

fn onStreamingToggle(button: *phantom.widgets.Button) void {
    _ = button;
    demo_state.streaming_active = !demo_state.streaming_active;
}

// Input callbacks
fn onInputChange(input: *phantom.widgets.Input, text: []const u8) void {
    _ = input;
    demo_state.input_text = text;
}

fn onInputSubmit(input: *phantom.widgets.Input, text: []const u8) void {
    _ = input;
    std.debug.print("Input submitted: '{}'\n", .{text});
}

// TextArea callbacks
fn onTextAreaChange(textarea: *phantom.widgets.TextArea, text: []const u8) void {
    _ = textarea;
    std.debug.print("TextArea changed: {} characters\n", .{text.len});
}

fn onTextAreaSubmit(textarea: *phantom.widgets.TextArea, text: []const u8) void {
    _ = textarea;
    std.debug.print("TextArea submitted: {} characters\n", .{text.len});
}

// StreamingText callbacks
fn onStreamingChunk(streaming_text: *phantom.widgets.StreamingText, chunk: []const u8) void {
    _ = streaming_text;
    std.debug.print("Streaming chunk: '{}'\n", .{chunk});
}

fn onStreamingComplete(streaming_text: *phantom.widgets.StreamingText) void {
    _ = streaming_text;
    std.debug.print("Streaming complete!\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize runtime
    phantom.runtime.initRuntime(allocator);
    defer phantom.runtime.deinitRuntime();

    // Create application
    var app = try phantom.App.init(allocator, phantom.AppConfig{
        .title = "👻 Phantom TUI - Comprehensive Demo",
        .tick_rate_ms = 30,
        .mouse_enabled = true,
    });
    defer app.deinit();

    // Print startup info
    std.debug.print("\n============================================================\n");
    std.debug.print("👻 PHANTOM TUI FRAMEWORK - COMPREHENSIVE DEMO\n");
    std.debug.print("============================================================\n");
    std.debug.print("🎯 All Widgets Showcase:\n");
    std.debug.print("   • Text & Styling\n");
    std.debug.print("   • Lists & Tables\n");
    std.debug.print("   • Buttons & Input Fields\n");
    std.debug.print("   • TextArea & Progress Bars\n");
    std.debug.print("   • StreamingText & CodeBlock\n");
    std.debug.print("   • Advanced Features\n");
    std.debug.print("🎮 Controls: ←→ to navigate pages, interact with widgets\n");
    std.debug.print("🚪 Exit: Ctrl+C or ESC key\n");
    std.debug.print("============================================================\n\n");

    // Create main demo widgets
    try createDemoWidgets(allocator, &app);

    // Run the application
    try app.run();

    std.debug.print("\n============================================================\n");
    std.debug.print("👻 Thanks for trying Phantom TUI Comprehensive Demo!\n");
    std.debug.print("🚀 All widgets implemented and ready for ZEKE integration!\n");
    std.debug.print("============================================================\n");
}

fn createDemoWidgets(allocator: std.mem.Allocator, app: *phantom.App) !void {
    // Page 0: Welcome & Framework Overview
    {
        const title = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "👻 PHANTOM TUI FRAMEWORK - COMPREHENSIVE DEMO", 
            phantom.Style.default().withFg(phantom.Color.bright_magenta).withBold()
        );
        try app.addWidget(&title.widget);

        const subtitle = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "The Next-Gen TUI Framework for Zig - All Widgets Showcase ⚡", 
            phantom.Style.default().withFg(phantom.Color.bright_cyan)
        );
        try app.addWidget(&subtitle.widget);

        const features = try phantom.widgets.List.init(allocator);
        features.setSelectedStyle(phantom.Style.default().withFg(phantom.Color.white).withBg(phantom.Color.bright_blue).withBold());
        
        try features.addItemText("✅ Text & Styling - Rich text with colors, bold, italic");
        try features.addItemText("✅ Lists & Tables - Selectable, scrollable data display");
        try features.addItemText("✅ Buttons - Clickable actions with hover states");
        try features.addItemText("✅ Input Fields - Single-line text input with validation");
        try features.addItemText("✅ TextArea - Multi-line text editing with wrapping");
        try features.addItemText("✅ Progress Bars - Visual progress indicators");
        try features.addItemText("✅ StreamingText - Real-time text updates for AI");
        try features.addItemText("✅ CodeBlock - Syntax highlighted code display");
        try features.addItemText("✅ Advanced Features - Scrolling, events, themes");
        try features.addItemText("🎯 ZEKE Ready - Perfect for AI terminal applications!");
        
        try app.addWidget(&features.widget);
    }

    // Page 1: Button Demo
    {
        const button_title = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "🔘 BUTTON WIDGETS DEMO", 
            phantom.Style.default().withFg(phantom.Color.bright_green).withBold()
        );
        try app.addWidget(&button_title.widget);

        // Create navigation buttons
        const prev_button = try phantom.widgets.Button.init(allocator, "← Previous Page");
        prev_button.setHoverStyle(phantom.Style.default().withFg(phantom.Color.white).withBg(phantom.Color.red));
        prev_button.setOnClick(onPrevClick);
        try app.addWidget(&prev_button.widget);

        const next_button = try phantom.widgets.Button.init(allocator, "Next Page →");
        next_button.setHoverStyle(phantom.Style.default().withFg(phantom.Color.white).withBg(phantom.Color.green));
        next_button.setOnClick(onNextClick);
        try app.addWidget(&next_button.widget);

        // Create progress control buttons
        const progress_inc = try phantom.widgets.Button.init(allocator, "Progress +10%");
        progress_inc.setHoverStyle(phantom.Style.default().withFg(phantom.Color.white).withBg(phantom.Color.blue));
        progress_inc.setOnClick(onProgressIncrement);
        try app.addWidget(&progress_inc.widget);

        const progress_dec = try phantom.widgets.Button.init(allocator, "Progress -10%");
        progress_dec.setHoverStyle(phantom.Style.default().withFg(phantom.Color.white).withBg(phantom.Color.yellow));
        progress_dec.setOnClick(onProgressDecrement);
        try app.addWidget(&progress_dec.widget);

        const button_info = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "Click buttons with mouse or use Enter/Space when focused", 
            phantom.Style.default().withFg(phantom.Color.bright_yellow)
        );
        try app.addWidget(&button_info.widget);
    }

    // Page 2: Input Demo
    {
        const input_title = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "📝 INPUT WIDGETS DEMO", 
            phantom.Style.default().withFg(phantom.Color.bright_blue).withBold()
        );
        try app.addWidget(&input_title.widget);

        // Create input field
        const input_field = try phantom.widgets.Input.init(allocator);
        try input_field.setPlaceholder("Type your message here...");
        input_field.setOnChange(onInputChange);
        input_field.setOnSubmit(onInputSubmit);
        try app.addWidget(&input_field.widget);

        // Create password input
        const password_field = try phantom.widgets.Input.init(allocator);
        try password_field.setPlaceholder("Password (hidden)");
        password_field.setPassword(true);
        try app.addWidget(&password_field.widget);

        // Create limited input
        const limited_input = try phantom.widgets.Input.init(allocator);
        try limited_input.setPlaceholder("Max 20 chars");
        limited_input.setMaxLength(20);
        try app.addWidget(&limited_input.widget);

        const input_info = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "Type text, use arrows to navigate, Enter to submit", 
            phantom.Style.default().withFg(phantom.Color.bright_yellow)
        );
        try app.addWidget(&input_info.widget);
    }

    // Page 3: TextArea Demo
    {
        const textarea_title = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "📄 TEXTAREA WIDGETS DEMO", 
            phantom.Style.default().withFg(phantom.Color.bright_magenta).withBold()
        );
        try app.addWidget(&textarea_title.widget);

        // Create text area
        const textarea = try phantom.widgets.TextArea.init(allocator);
        try textarea.setPlaceholder("Enter your multi-line text here...\nSupports word wrapping and scrolling!");
        textarea.setOnChange(onTextAreaChange);
        textarea.setOnSubmit(onTextAreaSubmit);
        textarea.setShowLineNumbers(true);
        try app.addWidget(&textarea.widget);

        const textarea_info = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "Multi-line editing: Enter for new line, Ctrl+S to submit", 
            phantom.Style.default().withFg(phantom.Color.bright_yellow)
        );
        try app.addWidget(&textarea_info.widget);
    }

    // Page 4: Progress Bar Demo
    {
        const progress_title = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "📊 PROGRESS BAR WIDGETS DEMO", 
            phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold()
        );
        try app.addWidget(&progress_title.widget);

        // Create progress bar with label
        const progress_bar = try phantom.widgets.ProgressBar.init(allocator);
        try progress_bar.setLabel("Processing...");
        progress_bar.setShowPercentage(true);
        progress_bar.setShowValue(true);
        progress_bar.setValue(demo_state.progress_value);
        try app.addWidget(&progress_bar.widget);

        // Create styled progress bar
        const styled_progress = try phantom.widgets.ProgressBar.init(allocator);
        try styled_progress.setLabel("Download");
        styled_progress.setFillStyle(phantom.Style.default().withFg(phantom.Color.bright_green));
        styled_progress.setBarStyle(phantom.Style.default().withFg(phantom.Color.bright_black));
        styled_progress.setValue(75.0);
        try app.addWidget(&styled_progress.widget);

        const progress_info = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "Use button controls to adjust progress values", 
            phantom.Style.default().withFg(phantom.Color.bright_yellow)
        );
        try app.addWidget(&progress_info.widget);
    }

    // Page 5: Table Demo
    {
        const table_title = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "📋 TABLE WIDGETS DEMO", 
            phantom.Style.default().withFg(phantom.Color.bright_red).withBold()
        );
        try app.addWidget(&table_title.widget);

        // Create table
        const table = try phantom.widgets.Table.init(allocator);
        try table.addColumn(phantom.widgets.Table.Column{ .title = "Name", .width = 15 });
        try table.addColumn(phantom.widgets.Table.Column{ .title = "Language", .width = 12 });
        try table.addColumn(phantom.widgets.Table.Column{ .title = "Status", .width = 10 });
        try table.addColumn(phantom.widgets.Table.Column{ .title = "Progress", .width = 8 });
        
        try table.addRow(phantom.widgets.Table.Row.init(&[_][]const u8{ "ZEKE", "Zig", "Active", "85%" }));
        try table.addRow(phantom.widgets.Table.Row.init(&[_][]const u8{ "Phantom", "Zig", "Complete", "100%" }));
        try table.addRow(phantom.widgets.Table.Row.init(&[_][]const u8{ "Demo", "Zig", "Running", "50%" }));
        try table.addRow(phantom.widgets.Table.Row.init(&[_][]const u8{ "Future", "Zig", "Planned", "0%" }));
        
        try app.addWidget(&table.widget);

        const table_info = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "Navigate with arrows or j/k, columns auto-resize", 
            phantom.Style.default().withFg(phantom.Color.bright_yellow)
        );
        try app.addWidget(&table_info.widget);
    }

    // Page 6: StreamingText Demo
    {
        const streaming_title = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "🌊 STREAMING TEXT WIDGETS DEMO", 
            phantom.Style.default().withFg(phantom.Color.bright_green).withBold()
        );
        try app.addWidget(&streaming_title.widget);

        // Create streaming text
        const streaming_text = try phantom.widgets.StreamingText.init(allocator);
        streaming_text.setOnChunk(onStreamingChunk);
        streaming_text.setOnComplete(onStreamingComplete);
        streaming_text.setTypingSpeed(30);
        
        // Add some demo text
        try streaming_text.setText("🤖 AI: Hello! I'm an AI assistant powered by Phantom TUI.\n\nThis is a demonstration of streaming text, perfect for displaying AI responses in real-time.\n\nKey features:\n• Character-by-character streaming\n• Configurable typing speed\n• Auto-scrolling\n• Vim-style navigation\n• Perfect for chat interfaces!");
        
        try app.addWidget(&streaming_text.widget);

        const streaming_button = try phantom.widgets.Button.init(allocator, "Toggle Streaming");
        streaming_button.setOnClick(onStreamingToggle);
        try app.addWidget(&streaming_button.widget);

        const streaming_info = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "Scroll with arrows/j/k, perfect for AI chat interfaces", 
            phantom.Style.default().withFg(phantom.Color.bright_yellow)
        );
        try app.addWidget(&streaming_info.widget);
    }

    // Page 7: CodeBlock Demo
    {
        const code_title = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "💻 CODE BLOCK WIDGETS DEMO", 
            phantom.Style.default().withFg(phantom.Color.bright_blue).withBold()
        );
        try app.addWidget(&code_title.widget);

        // Create code block
        const code_sample = 
            \\const std = @import("std");
            \\const phantom = @import("phantom");
            \\
            \\pub fn main() !void {
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    // Create TUI application
            \\    var app = try phantom.App.init(allocator, .{
            \\        .title = "My App",
            \\        .tick_rate_ms = 16,
            \\    });
            \\    defer app.deinit();
            \\
            \\    // Add widgets
            \\    const text = try phantom.widgets.Text.init(allocator, "Hello, Phantom!");
            \\    try app.addWidget(&text.widget);
            \\
            \\    // Run the app
            \\    try app.run();
            \\}
        ;
        
        const code_block = try phantom.widgets.CodeBlock.init(allocator, code_sample, .zig);
        code_block.setShowLineNumbers(true);
        try app.addWidget(&code_block.widget);

        const code_info = try phantom.widgets.Text.initWithStyle(
            allocator, 
            "Syntax highlighting for Zig, Rust, Python, JS, and more!", 
            phantom.Style.default().withFg(phantom.Color.bright_yellow)
        );
        try app.addWidget(&code_info.widget);
    }

    // Navigation instructions
    const nav_info = try phantom.widgets.Text.initWithStyle(
        allocator, 
        "🎮 Navigation: ←→ arrows to change pages | 🚪 Exit: Ctrl+C or ESC", 
        phantom.Style.default().withFg(phantom.Color.white).withBg(phantom.Color.blue)
    );
    try app.addWidget(&nav_info.widget);
}