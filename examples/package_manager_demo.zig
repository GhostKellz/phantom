//! Package Manager Demo - showcasing TaskMonitor for ZION/Reaper
const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    phantom.runtime.initRuntime(allocator);
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
    const task_monitor = try phantom.widgets.TaskMonitor.init(allocator);
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
    const overall_progress = try phantom.widgets.ProgressBar.init(allocator);
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

    // Simulate package building progress
    const DemoState = struct {
        var timer: u32 = 0;
    };

    // Add event handler for demo simulation
    try app.event_loop.addHandler(struct {
        fn handler(event: phantom.Event) anyerror!bool {
            switch (event) {
                .tick => {
                    DemoState.timer += 1;

                    // Simulate firefox build progress
                    if (DemoState.timer < 50) {
                        const firefox_progress = @as(f64, @floatFromInt(DemoState.timer * 2));
                        task_monitor.updateProgress("firefox", firefox_progress);
                        try task_monitor.updateTask("firefox", .running, "Downloading sources...");
                    } else if (DemoState.timer < 80) {
                        const firefox_progress = @as(f64, @floatFromInt((DemoState.timer - 50) * 3 + 50));
                        task_monitor.updateProgress("firefox", @min(firefox_progress, 100.0));
                        try task_monitor.updateTask("firefox", .running, "Compiling C++ sources...");
                    }

                    // Simulate discord install
                    if (DemoState.timer > 20 and DemoState.timer < 60) {
                        const discord_progress = @as(f64, @floatFromInt((DemoState.timer - 20) * 2.5));
                        task_monitor.updateProgress("discord", @min(discord_progress, 100.0));
                        try task_monitor.updateTask("discord", .running, "Extracting package...");
                    }

                    // Simulate neovim update
                    if (DemoState.timer > 30 and DemoState.timer < 70) {
                        const neovim_progress = @as(f64, @floatFromInt((DemoState.timer - 30) * 2.5));
                        task_monitor.updateProgress("neovim", @min(neovim_progress, 100.0));
                        try task_monitor.updateTask("neovim", .running, "Resolving dependencies...");
                    }

                    // Simulate rust compilation (slow)
                    if (DemoState.timer > 40 and DemoState.timer < 120) {
                        const rust_progress = @as(f64, @floatFromInt((DemoState.timer - 40) * 1.25));
                        task_monitor.updateProgress("rust", @min(rust_progress, 100.0));
                        try task_monitor.updateTask("rust", .running, "Building LLVM backend...");
                    }

                    // Update overall progress
                    const overall = task_monitor.getOverallProgress();
                    overall_progress.setValue(overall);

                    // Complete demo after a while
                    if (DemoState.timer > 150) {
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
    }.handler);

    // Run the application
    try app.run();

    std.debug.print("\n============================================================\n", .{});
    std.debug.print("🪐 Thanks for trying ZION Package Manager Demo!\n", .{});
    std.debug.print("🚀 TaskMonitor widget ready for production use!\n", .{});
    std.debug.print("⚰️  Perfect for Reaper AUR package manager!\n", .{});
    std.debug.print("============================================================\n", .{});
}
