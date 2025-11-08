//! Phantom v0.7.1 Test Demo
//! This demonstrates the major fixes in v0.7.1:
//! - No more zsync crashes on exit
//! - Proper vertical layout without widget overlap
//! - runtime.initRuntime() is now optional

const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("============================================================\n", .{});
    std.debug.print("👻 PHANTOM v{s} - STABILITY TEST\n", .{phantom.version});
    std.debug.print("============================================================\n", .{});
    std.debug.print("✅ No more zsync crashes on exit\n", .{});
    std.debug.print("✅ Fixed widget overlapping with auto vertical layout\n", .{});
    std.debug.print("✅ runtime.initRuntime() is now optional\n", .{});
    std.debug.print("============================================================\n", .{});
    std.debug.print("🎮 Press Ctrl+C or ESC to exit\n", .{});
    std.debug.print("============================================================\n\n", .{});

    // NOTE: We're NOT calling phantom.runtime.initRuntime() - it's optional now!

    var app = try phantom.App.init(allocator, phantom.AppConfig{
        .title = "Phantom v0.7.1 Test",
        .tick_rate_ms = 30,
    });
    defer app.deinit();

    // Create multiple widgets to test vertical layout
    const title = try phantom.widgets.Text.initWithStyle(
        allocator,
        "👻 PHANTOM v0.7.1 - The Fixed Version",
        phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold()
    );
    try app.addWidget(&title.widget);

    const subtitle = try phantom.widgets.Text.initWithStyle(
        allocator,
        "Ratatui-style TUI framework for Zig",
        phantom.Style.default().withFg(phantom.Color.bright_green)
    );
    try app.addWidget(&subtitle.widget);

    // Create a list to show features
    const feature_list = try phantom.widgets.List.init(allocator);
    feature_list.setSelectedStyle(phantom.Style.default()
        .withFg(phantom.Color.black)
        .withBg(phantom.Color.bright_cyan)
        .withBold());

    try feature_list.addItemText("✅ Fixed: No more IOT instruction crashes");
    try feature_list.addItemText("✅ Fixed: Widgets render in proper vertical layout");
    try feature_list.addItemText("✅ Fixed: runtime.initRuntime() is optional");
    try feature_list.addItemText("✅ Improved: More Ratatui-like API");
    try feature_list.addItemText("🎯 Ready for production use!");

    try app.addWidget(&feature_list.widget);

    const instructions = try phantom.widgets.Text.initWithStyle(
        allocator,
        "🎮 Use ↑↓ arrows or j/k to navigate • ESC/Ctrl+C to exit",
        phantom.Style.default().withFg(phantom.Color.bright_yellow)
    );
    try app.addWidget(&instructions.widget);

    // Run the app - should exit cleanly without crashes!
    try app.run();

    std.debug.print("\n", .{});
    std.debug.print("============================================================\n", .{});
    std.debug.print("✅ Clean exit - no crashes!\n", .{});
    std.debug.print("============================================================\n", .{});
}
