//! VXFW Demo - Showcasing Phantom's new widget framework
//! Demonstrates FlexRow, FlexColumn, Center, Padding, TextView, and ScrollView

const std = @import("std");
const phantom = @import("phantom");
const vxfw = phantom.vxfw;

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create arena for demo widgets
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();


    // Demo 1: Basic TextView with word wrapping
    try demoTextView(arena.allocator());

    // Demo 2: FlexRow layout
    try demoFlexRow(arena.allocator());

    // Demo 3: FlexColumn layout
    try demoFlexColumn(arena.allocator());

    // Demo 4: Center and Padding widgets
    try demoCenterPadding(arena.allocator());

    // Demo 5: ScrollView
    try demoScrollView(arena.allocator());

}

fn demoTextView(allocator: std.mem.Allocator) !void {
    const long_text =
        \\Welcome to Phantom's advanced widget framework (vxfw)!
        \\
        \\This TextView widget demonstrates multi-line text rendering with
        \\word wrapping capabilities. It can handle Unicode text, different
        \\wrapping modes, and provides a solid foundation for text-based
        \\widgets in terminal applications.
        \\
        \\Key features:
        \\- Word boundary wrapping
        \\- Character boundary wrapping
        \\- No wrapping mode
        \\- Unicode support
        \\- Configurable styling
    ;

    const text_view = vxfw.TextView.init(
        long_text,
        phantom.Style.default().withFg(.bright_green),
        .word
    );

    const ctx = vxfw.DrawContext.init(
        allocator,
        phantom.Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.init(60, 20),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try text_view.draw(ctx);
    _ = surface;
    _ = surface;
}

fn demoFlexRow(allocator: std.mem.Allocator) !void {
    // Create child text widgets
    const left_text = vxfw.TextView.simple("Left Panel");
    const center_text = vxfw.TextView.simple("Center Content (Flexible)");
    const right_text = vxfw.TextView.simple("Right Panel");

    const children = [_]vxfw.FlexItem{
        .{ .widget = left_text.widget(), .flex = 0 }, // Fixed width
        .{ .widget = center_text.widget(), .flex = 1 }, // Flexible
        .{ .widget = right_text.widget(), .flex = 0 }, // Fixed width
    };

    const flex_row = vxfw.FlexRow.init(&children);

    const ctx = vxfw.DrawContext.init(
        allocator,
        phantom.Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.init(80, 3),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try flex_row.draw(ctx);
    _ = surface;
}

fn demoFlexColumn(allocator: std.mem.Allocator) !void {
    // Create child text widgets
    const header_text = vxfw.TextView.simple("Header");
    const content_text = vxfw.TextView.simple("Main Content Area (Flexible)");
    const footer_text = vxfw.TextView.simple("Footer");

    const children = [_]vxfw.FlexItem{
        .{ .widget = header_text.widget(), .flex = 0 }, // Fixed height
        .{ .widget = content_text.widget(), .flex = 1 }, // Flexible
        .{ .widget = footer_text.widget(), .flex = 0 }, // Fixed height
    };

    const flex_column = vxfw.FlexColumn.init(&children);

    const ctx = vxfw.DrawContext.init(
        allocator,
        phantom.Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.init(40, 20),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try flex_column.draw(ctx);
    _ = surface;
}

fn demoCenterPadding(allocator: std.mem.Allocator) !void {
    // Create a simple text widget
    const text_widget = vxfw.TextView.simple("Centered & Padded Text");

    // Add padding around it
    const padded_widget = vxfw.Padding.init(
        text_widget.widget(),
        vxfw.Padding.PaddingInsets.all(2)
    );

    // Center it in the available space
    const centered_widget = vxfw.Center.init(padded_widget.widget());

    const ctx = vxfw.DrawContext.init(
        allocator,
        phantom.Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.init(50, 10),
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try centered_widget.draw(ctx);
    _ = surface;
}

fn demoScrollView(allocator: std.mem.Allocator) !void {
    // Create a large text widget that needs scrolling
    const large_text =
        \\This is a very large text content that demonstrates the ScrollView widget.
        \\
        \\Line 1: Lorem ipsum dolor sit amet, consectetur adipiscing elit.
        \\Line 2: Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
        \\Line 3: Ut enim ad minim veniam, quis nostrud exercitation ullamco.
        \\Line 4: Duis aute irure dolor in reprehenderit in voluptate velit esse.
        \\Line 5: Excepteur sint occaecat cupidatat non proident, sunt in culpa.
        \\Line 6: Qui officia deserunt mollit anim id est laborum.
        \\Line 7: Sed ut perspiciatis unde omnis iste natus error sit voluptatem.
        \\Line 8: Accusantium doloremque laudantium, totam rem aperiam.
        \\Line 9: Eaque ipsa quae ab illo inventore veritatis et quasi architecto.
        \\Line 10: Beatae vitae dicta sunt explicabo. Nemo enim ipsam voluptatem.
        \\
        \\This content is larger than the viewport and would benefit from scrolling
        \\capabilities. The ScrollView widget provides both vertical and horizontal
        \\scrolling with optional scrollbars for enhanced user experience.
    ;

    const large_text_widget = vxfw.TextView.init(
        large_text,
        phantom.Style.default(),
        .word
    );

    const scroll_view = vxfw.ScrollView.init(large_text_widget.widget());

    const ctx = vxfw.DrawContext.init(
        allocator,
        phantom.Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.init(60, 10), // Smaller viewport
        vxfw.DrawContext.CellSize.default()
    );

    const surface = try scroll_view.draw(ctx);
    _ = surface;

    // Test scroll position management
    var mutable_scroll = scroll_view;
    _ = mutable_scroll.getScrollPosition();
    mutable_scroll.setScrollPosition(phantom.Point{ .x = 5, .y = 3 });
    _ = mutable_scroll.getScrollPosition();
}

test "VXFW widget framework integration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Test that all widgets can be created and used together
    const text_widget = vxfw.TextView.simple("Test");
    const padded = vxfw.Padding.init(text_widget.widget(), vxfw.Padding.PaddingInsets.all(1));
    const centered = vxfw.Center.init(padded.widget());
    const scrollable = vxfw.ScrollView.init(centered.widget());

    const ctx = vxfw.DrawContext.init(
        arena.allocator(),
        phantom.Size.init(0, 0),
        vxfw.DrawContext.SizeConstraints.init(20, 10),
        vxfw.DrawContext.CellSize.default()
    );

    // Test that the full widget tree can be drawn
    _ = try scrollable.draw(ctx);
}