//! Package Manager Demo - showcasing TaskMonitor for ZION/Reaper
const std = @import("std");
const phantom = @import("phantom");

// Global state for event handler
var global_task_monitor: ?*phantom.widgets.TaskMonitor = null;
var global_overall_progress: ?*phantom.widgets.ProgressBar = null;
var demo_timer: u32 = 0;

// Event handler function
fn demoEventHandler(event: phantom.Event) anyerror!bool {
    switch (event) {
        .tick => {
            demo_timer += 1;

            const task_monitor = global_task_monitor orelse return false;
            const overall_progress = global_overall_progress orelse return false;

            // Simulate firefox build progress
            if (demo_timer < 50) {
                const firefox_progress = @as(f64, @floatFromInt(demo_timer * 2));
                task_monitor.updateProgress("firefox", firefox_progress);
                try task_monitor.updateTask("firefox", .running, "Downloading sources...");
            } else if (demo_timer < 80) {
                const firefox_progress = @as(f64, @floatFromInt((demo_timer - 50) * 3 + 50));
                task_monitor.updateProgress("firefox", @min(firefox_progress, 100.0));
                try task_monitor.updateTask("firefox", .running, "Compiling C++ sources...");
            }

            // Simulate discord install
            if (demo_timer > 20 and demo_timer < 60) {
                const discord_progress = @as(f64, @floatFromInt(demo_timer - 20)) * 2.5;
                task_monitor.updateProgress("discord", @min(discord_progress, 100.0));
                try task_monitor.updateTask("discord", .running, "Extracting package...");
            }

            // Simulate neovim update
            if (demo_timer > 30 and demo_timer < 70) {
                const neovim_progress = @as(f64, @floatFromInt(demo_timer - 30)) * 2.5;
                task_monitor.updateProgress("neovim", @min(neovim_progress, 100.0));
                try task_monitor.updateTask("neovim", .running, "Resolving dependencies...");
            }

            // Simulate rust compilation (slow)
            if (demo_timer > 40 and demo_timer < 120) {
                const rust_progress = @as(f64, @floatFromInt(demo_timer - 40)) * 1.25;
                task_monitor.updateProgress("rust", @min(rust_progress, 100.0));
                try task_monitor.updateTask("rust", .running, "Building LLVM backend...");
            }

            // Update overall progress
            const overall = task_monitor.getOverallProgress();
            overall_progress.setValue(overall);

            // Complete demo after a while
            if (demo_timer > 150) {
                try task_monitor.updateTask("firefox", .completed, "Build completed successfully!");
                try task_monitor.updateTask("discord", .completed, "Installation complete!");
                try task_monitor.updateTask("neovim", .completed, "Dependencies updated!");
                try task_monitor.updateTask("rust", .completed, "Toolchain ready!");
                overall_progress.setValue(100.0);
            }
        },
        else => {},
    }
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try phantom.runtime.initRuntime(allocator);
    defer phantom.runtime.deinitRuntime();

    var app = try phantom.App.init(allocator, phantom.AppConfig{
        .title = "🪐 ZION Package Manager Demo",
        .tick_rate_ms = 100, // 10 FPS for demo
    });
    defer app.deinit();

    // Header
    const header = try phantom.widgets.Text.initWithStyle(allocator, "🪐 ZION Package Manager - Multi-Task Demo", phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold());
    try app.addWidget(&header.widget);

    // Create TaskMonitor
    var task_monitor = try phantom.widgets.TaskMonitor.init(allocator);
    task_monitor.setMaxVisibleTasks(8);
    task_monitor.setCompactMode(false);

    // Add sample tasks that package managers would have
    try task_monitor.addTask("firefox", "Building firefox from AUR");
    try task_monitor.addTask("discord", "Installing discord from official");
    try task_monitor.addTask("neovim", "Updating neovim dependencies");
    try task_monitor.addTask("rust", "Compiling rust toolchain");

    try app.addWidget(&task_monitor.widget);

    // Instructions
    const instructions = try phantom.widgets.Text.initWithStyle(allocator, "🎮 Watch the live package build progress • Press Ctrl+C to exit", phantom.Style.default().withFg(phantom.Color.bright_yellow));
    try app.addWidget(&instructions.widget);

    // Overall progress
    var overall_progress = try phantom.widgets.ProgressBar.init(allocator);
    overall_progress.setProgressStyle(.blocks);
    overall_progress.setShowEmoji(true);
    overall_progress.setShowETA(true);
    try app.addWidget(&overall_progress.widget);

    std.debug.print("\n============================================================\n", .{});
    std.debug.print("🪐 ZION Package Manager Demo\n", .{});
    std.debug.print("============================================================\n", .{});
    std.debug.print("📦 Multi-package build simulation\n", .{});
    std.debug.print("⚡ Real-time progress tracking\n", .{});
    std.debug.print("🎯 Perfect for AUR package managers like Reaper\n", .{});
    std.debug.print("🚪 Exit: Ctrl+C or ESC key\n", .{});
    std.debug.print("============================================================\n\n", .{});

    // Set global state for event handler
    global_task_monitor = task_monitor;
    global_overall_progress = overall_progress;

    // Add event handler for demo simulation
    try app.event_loop.addHandler(demoEventHandler);

    // Run the application
    try app.run();

    std.debug.print("\n============================================================\n", .{});
    std.debug.print("🪐 Thanks for trying ZION Package Manager Demo!\n", .{});
    std.debug.print("🚀 TaskMonitor widget ready for production use!\n", .{});
    std.debug.print("⚰️  Perfect for Reaper AUR package manager!\n", .{});
    std.debug.print("============================================================\n", .{});
}
