//! Advanced Phantom TUI demo showcasing more features
const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();


    var app = try phantom.App.init(allocator, phantom.AppConfig{
        .title = "👻 Phantom TUI - Advanced Demo",
        .tick_rate_ms = 30, // Smooth 33 FPS
    });
    defer app.deinit();

    // Create styled welcome banner
    const banner = try phantom.widgets.Text.initWithStyle(allocator, "🌟 Welcome to Phantom TUI Framework! 🌟", phantom.Style.default().withFg(phantom.Color.bright_magenta).withBold());
    try app.addWidget(&banner.widget);

    // Create subtitle
    const subtitle = try phantom.widgets.Text.initWithStyle(allocator, "The Next-Gen TUI Framework for Zig - Built with zsync async ⚡", phantom.Style.default().withFg(phantom.Color.bright_cyan));
    try app.addWidget(&subtitle.widget);

    // Create feature showcase list
    const feature_list = try phantom.widgets.List.init(allocator);
    feature_list.setSelectedStyle(phantom.Style.default().withFg(phantom.Color.white).withBg(phantom.Color.bright_blue).withBold());

    try feature_list.addItemText("🚀 Pure Zig - Zero C dependencies, idiomatic code");
    try feature_list.addItemText("⚡ Async-Native - Built with zsync async runtime");
    try feature_list.addItemText("🧱 Rich Widgets - Text, Lists, Tables, Progress bars");
    try feature_list.addItemText("🌈 Styled Output - Colors, gradients, bold, underline");
    try feature_list.addItemText("🖼️  Flex Layouts - Compositional layout engine");
    try feature_list.addItemText("🖱️  Input Handling - Keyboard, mouse, focus management");
    try feature_list.addItemText("🔄 Live Updates - Non-blocking async render loop");
    try feature_list.addItemText("🧩 Extensible - Custom widgets and event hooks");
    try feature_list.addItemText("🧪 Testable - Comprehensive snapshot testing");
    try feature_list.addItemText("👻 Ghostly - Rattatui parity with next-gen upgrades!");

    try app.addWidget(&feature_list.widget);

    // Instructions
    const instructions = try phantom.widgets.Text.initWithStyle(allocator, "🎮 Use ↑↓ or j/k to navigate • Press Ctrl+C or ESC to exit", phantom.Style.default().withFg(phantom.Color.bright_yellow));
    try app.addWidget(&instructions.widget);

    // Print startup info
    std.debug.print("\n============================================================\n");
    std.debug.print("👻 PHANTOM TUI FRAMEWORK - ADVANCED DEMO\n");
    std.debug.print("============================================================\n");
    std.debug.print("🎯 Framework Status: MVP Complete!\n");
    std.debug.print("✅ Core Systems: Terminal, Events, Widgets, Styling\n");
    std.debug.print("✅ Widget Library: Text, Block, List (with more coming!)\n");
    std.debug.print("✅ Async Ready: Event loop foundation with zsync\n");
    std.debug.print("🎮 Controls: ↑↓ arrows or j/k keys to navigate\n");
    std.debug.print("🚪 Exit: Ctrl+C or ESC key\n");
    std.debug.print("============================================================\n\n");

    // Run the application
    try app.run();

    std.debug.print("\n============================================================\n");
    std.debug.print("👻 Thanks for trying Phantom TUI!\n");
    std.debug.print("🚀 Next: More widgets, layout engine, mouse support...\n");
    std.debug.print("============================================================\n");
}
