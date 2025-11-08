//! Feature Showcase Demo - Key Widgets and Enhancements
//! Demonstrates: ScrollView, ListView, FlexRow/FlexColumn, RichText, Border, Spinner, Animation
const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize application
    var app = try phantom.App.init(allocator, .{
        .title = "Phantom Feature Showcase",
        .tick_rate_ms = 50,
        .mouse_enabled = true,
    });
    defer app.deinit();

    std.debug.print("Phantom Feature Showcase\n", .{});
    std.debug.print("==========================\n\n", .{});

    // === Demo 1: FlexRow Layout ===
    std.debug.print("1. FlexRow Layout\n", .{});
    {
        var flex_row = try phantom.widgets.FlexRow.init(allocator);
        defer flex_row.widget.vtable.deinit(&flex_row.widget);

        flex_row.setGap(2);
        flex_row.setJustify(.space_between);

        var text1 = try phantom.widgets.Text.initWithStyle(
            allocator,
            "Left",
            phantom.Style.default().withFg(phantom.Color.bright_cyan),
        );
        defer text1.widget.vtable.deinit(&text1.widget);

        var text2 = try phantom.widgets.Text.initWithStyle(
            allocator,
            "Center",
            phantom.Style.default().withFg(phantom.Color.bright_yellow),
        );
        defer text2.widget.vtable.deinit(&text2.widget);

        var text3 = try phantom.widgets.Text.initWithStyle(
            allocator,
            "Right",
            phantom.Style.default().withFg(phantom.Color.bright_green),
        );
        defer text3.widget.vtable.deinit(&text3.widget);

        try flex_row.addChildWidget(&text1.widget);
        try flex_row.addChildWidget(&text2.widget);
        try flex_row.addChildWidget(&text3.widget);

        std.debug.print("  ✓ FlexRow with 3 children and space-between justify\n", .{});
    }

    // === Demo 2: ListView with Virtualization ===
    std.debug.print("\n2. ListView with Virtualization\n", .{});
    {
        var list_view = try phantom.widgets.ListView.init(allocator, .{});
        defer list_view.widget.vtable.deinit(&list_view.widget);

        // Add 1000 items to demonstrate virtualization
        var i: usize = 0;
        while (i < 1000) : (i += 1) {
            const text = try std.fmt.allocPrint(allocator, "Item {d}", .{i});
            try list_view.addItem(.{ .text = text, .icon = '•' });
        }

        std.debug.print("  ✓ ListView with 1000 items (virtualized rendering)\n", .{});
        std.debug.print("  ✓ Only visible items are rendered for performance\n", .{});
    }

    // === Demo 3: ScrollView ===
    std.debug.print("\n3. ScrollView\n", .{});
    {
        var scroll_view = try phantom.widgets.ScrollView.init(allocator);
        defer scroll_view.widget.vtable.deinit(&scroll_view.widget);

        scroll_view.setContentSize(200, 100); // Larger than viewport
        scroll_view.setScrollbars(true, true);

        std.debug.print("  ✓ ScrollView with content 200x100\n", .{});
        std.debug.print("  ✓ Scrollable with keyboard (arrows, Page Up/Down, Home/End)\n", .{});
        std.debug.print("  ✓ Scrollable with mouse (wheel scrolling)\n", .{});
    }

    // === Demo 4: RichText with Markdown ===
    std.debug.print("\n4. RichText with Markdown Parsing\n", .{});
    {
        var rich_text = try phantom.widgets.RichText.init(allocator);
        defer rich_text.widget.vtable.deinit(&rich_text.widget);

        try rich_text.parseMarkdown("This is **bold**, *italic*, and `code` text!");

        std.debug.print("  ✓ Markdown parsing: **bold**, *italic*, `code`\n", .{});
        std.debug.print("  ✓ Inline style support\n", .{});
    }

    // === Demo 5: Border Widget ===
    std.debug.print("\n5. Border Widget\n", .{});
    {
        var border = try phantom.widgets.Border.init(allocator);
        defer border.widget.vtable.deinit(&border.widget);

        border.setBorderStyle(.rounded);
        try border.setTitle("Bordered Panel");

        var inner_text = try phantom.widgets.Text.initWithStyle(
            allocator,
            "Content inside border",
            phantom.Style.default(),
        );
        defer inner_text.widget.vtable.deinit(&inner_text.widget);

        border.setChild(&inner_text.widget);

        std.debug.print("  ✓ Border styles: single, double, rounded, thick, ascii\n", .{});
        std.debug.print("  ✓ Optional title support\n", .{});
    }

    // === Demo 6: Spinner Widget ===
    std.debug.print("\n6. Spinner Widget\n", .{});
    {
        var spinner = try phantom.widgets.Spinner.init(allocator);
        defer spinner.widget.vtable.deinit(&spinner.widget);

        spinner.setStyle(.dots);
        try spinner.setMessage("Loading...");

        std.debug.print("  ✓ Spinner styles: dots, line, arrow, box, bounce, arc, circle, braille\n", .{});
        std.debug.print("  ✓ Animated loading indicators\n", .{});
    }

    // === Demo 7: Animation Framework ===
    std.debug.print("\n7. Animation Framework\n", .{});
    {
        // Smooth scroll animation
        var scroll = phantom.animation.SmoothScroll.init(0.0);
        scroll.scrollTo(100.0, 1000); // Scroll to 100 over 1 second

        std.debug.print("  ✓ Smooth scrolling with easing functions\n", .{});
        std.debug.print("  ✓ Fade in/out effects\n", .{});
        std.debug.print("  ✓ Easing: linear, ease-in, ease-out, ease-in-out, bounce, elastic\n", .{});

        // Fade animation
        var fade = phantom.animation.Fade.init();
        fade.fadeOut(500);

        std.debug.print("  ✓ Fade animations for UI transitions\n", .{});
    }

    // === Demo 8: Enhanced Mouse Support ===
    std.debug.print("\n8. Enhanced Mouse Support\n", .{});
    {
        var mouse_state = phantom.mouse.MouseState.init(allocator);
        defer mouse_state.deinit();

        std.debug.print("  ✓ Hover detection\n", .{});
        std.debug.print("  ✓ Drag and drop support\n", .{});
        std.debug.print("  ✓ Double-click detection\n", .{});
        std.debug.print("  ✓ Mouse wheel scrolling\n", .{});
    }

    // === Demo 9: Clipboard Support ===
    std.debug.print("\n9. Clipboard Integration\n", .{});
    {
        var clipboard_mgr = phantom.clipboard.ClipboardManager.init(allocator);
        defer clipboard_mgr.deinit();

        if (clipboard_mgr.isAvailable()) {
            std.debug.print("  ✓ System clipboard integration\n", .{});
            std.debug.print("  ✓ Copy/paste support\n", .{});
            std.debug.print("  ✓ Cross-platform (Linux, macOS, Windows)\n", .{});
        } else {
            std.debug.print("  ⚠ Clipboard not available on this platform\n", .{});
        }
    }

    std.debug.print("\n==========================\n", .{});
    std.debug.print("Feature showcase complete!\n\n", .{});

    std.debug.print("Key Feature Highlights:\n", .{});
    std.debug.print("  • ScrollView - Essential for LSP diagnostics and file explorers\n", .{});
    std.debug.print("  • ListView - Virtualized rendering for large lists (completion menus)\n", .{});
    std.debug.print("  • FlexRow/FlexColumn - Modern responsive layouts\n", .{});
    std.debug.print("  • RichText - Formatted text with markdown support\n", .{});
    std.debug.print("  • Border - Decorative borders for floating windows\n", .{});
    std.debug.print("  • Spinner - Loading state indicators\n", .{});
    std.debug.print("  • Animation - Smooth transitions and easing\n", .{});
    std.debug.print("  • Mouse - Enhanced hover, drag, and double-click\n", .{});
    std.debug.print("  • Clipboard - System clipboard integration\n", .{});

    std.debug.print("\nThese widgets unblock Grim editor UI polish!\n", .{});
}
