//! Simple Package Manager Demo - showcasing TaskMonitor for v0.2.1
const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize runtime
    try phantom.runtime.initRuntime(allocator);
    defer phantom.runtime.deinitRuntime();

    // Create application
    var app = try phantom.App.init(allocator, phantom.AppConfig{
        .title = "👻 Phantom v0.2.1 - TaskMonitor Demo",
        .tick_rate_ms = 30,
    });
    defer app.deinit();

    // Header
    const title = try phantom.widgets.Text.initWithStyle(allocator, "👻 PHANTOM TUI v0.2.1 - PACKAGE MANAGER DEMO", phantom.Style.default().withFg(phantom.Color.bright_magenta).withBold());
    try app.addWidget(&title.widget);

    const subtitle = try phantom.widgets.Text.initWithStyle(allocator, "🚀 TaskMonitor Widget for ZION & Reaper Integration", phantom.Style.default().withFg(phantom.Color.bright_cyan));
    try app.addWidget(&subtitle.widget);

    // Task monitor
    const monitor = try phantom.widgets.TaskMonitor.init(allocator);
    try app.addWidget(&monitor.widget);

    // Add demo tasks with different progress states
    try monitor.addTask("firefox", "🔥 Firefox Browser");
    monitor.updateProgress("firefox", 75.0);
    try monitor.updateTask("firefox", .running, "🔄 Compiling...");

    try monitor.addTask("discord", "💬 Discord Chat");
    monitor.updateProgress("discord", 45.0);
    try monitor.updateTask("discord", .running, "📥 Downloading sources...");

    try monitor.addTask("vscode", "💻 VS Code Editor");
    monitor.updateProgress("vscode", 100.0);
    try monitor.updateTask("vscode", .completed, "✅ Installation complete!");

    try monitor.addTask("git", "🌿 Git VCS");
    monitor.updateProgress("git", 20.0);
    try monitor.updateTask("git", .running, "⏳ Resolving dependencies...");

    try monitor.addTask("zig", "⚡ Zig Compiler");
    monitor.updateProgress("zig", 90.0);
    try monitor.updateTask("zig", .running, "🔧 Configuring installation...");

    try monitor.addTask("phantom", "👻 Phantom TUI");
    monitor.updateProgress("phantom", 100.0);
    try monitor.updateTask("phantom", .completed, "✅ Ready for production!");

    // Instructions
    const instructions = try phantom.widgets.Text.initWithStyle(allocator, "\n🎯 This showcases multi-task progress tracking for package managers\n🎮 Press Ctrl+C or ESC to exit", phantom.Style.default().withFg(phantom.Color.bright_yellow));
    try app.addWidget(&instructions.widget);

    // Print startup
    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("👻 PHANTOM TUI v0.2.1 - TASKMONITOR DEMO\n", .{});
    std.debug.print("=" ** 60 ++ "\n", .{});
    std.debug.print("🚀 Ratatui-level TUI experience achieved!\n", .{});
    std.debug.print("📦 Perfect for ZION package manager\n", .{});
    std.debug.print("⚰️  Perfect for Reaper AUR manager\n", .{});
    std.debug.print("🎨 Enhanced emoji support\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});

    // Run the application
    try app.run();

    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("👻 Thanks for trying Phantom v0.2.1!\n", .{});
    std.debug.print("🚀 TaskMonitor ready for production!\n", .{});
    std.debug.print("=" ** 60 ++ "\n", .{});
}
