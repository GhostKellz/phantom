//! Ghostty Terminal Performance Monitor - NVIDIA GPU Stats
//! Real-time system monitoring TUI
const std = @import("std");
const phantom = @import("phantom");

var global_app: *phantom.App = undefined;
var cpu_text: *phantom.widgets.Text = undefined;
var gpu_text: *phantom.widgets.Text = undefined;
var mem_text: *phantom.widgets.Text = undefined;
var fps_text: *phantom.widgets.Text = undefined;
var frame_counter: u64 = 0;
var start_time: std.time.Timer = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    start_time = try std.time.Timer.start();

    var app = try phantom.App.init(allocator, .{
        .title = "Ghostty Performance Monitor",
        .tick_rate_ms = 100, // Update every 100ms
        .mouse_enabled = false,
    });
    defer app.deinit();
    global_app = &app;

    // Header
    const header = try phantom.widgets.Text.initWithStyle(
        allocator,
        "👻 GHOSTTY TERMINAL - Performance Monitor",
        phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold(),
    );
    try app.addWidget(&header.widget);

    const subtitle = try phantom.widgets.Text.initWithStyle(
        allocator,
        "NVIDIA GPU-Accelerated Terminal Rendering",
        phantom.Style.default().withFg(phantom.Color.bright_green),
    );
    try app.addWidget(&subtitle.widget);

    const divider = try phantom.widgets.Text.initWithStyle(
        allocator,
        "═══════════════════════════════════════════════════════════",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&divider.widget);

    // CPU Monitor
    cpu_text = try phantom.widgets.Text.initWithStyle(
        allocator,
        "⚙️  CPU: Initializing...",
        phantom.Style.default().withFg(phantom.Color.bright_yellow),
    );
    try app.addWidget(&cpu_text.widget);

    // GPU Monitor
    gpu_text = try phantom.widgets.Text.initWithStyle(
        allocator,
        "🎮 GPU: Initializing...",
        phantom.Style.default().withFg(phantom.Color.bright_magenta),
    );
    try app.addWidget(&gpu_text.widget);

    // Memory Monitor
    mem_text = try phantom.widgets.Text.initWithStyle(
        allocator,
        "💾 Memory: Initializing...",
        phantom.Style.default().withFg(phantom.Color.bright_blue),
    );
    try app.addWidget(&mem_text.widget);

    // FPS Monitor
    fps_text = try phantom.widgets.Text.initWithStyle(
        allocator,
        "📊 Render FPS: Initializing...",
        phantom.Style.default().withFg(phantom.Color.bright_green),
    );
    try app.addWidget(&fps_text.widget);

    const divider2 = try phantom.widgets.Text.initWithStyle(
        allocator,
        "═══════════════════════════════════════════════════════════",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&divider2.widget);

    const instructions = try phantom.widgets.Text.initWithStyle(
        allocator,
        "q/Ctrl+C Exit • Stats update every 100ms",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&instructions.widget);

    try app.event_loop.addHandler(handleEvent);
    try app.run();
}

fn handleEvent(event: phantom.Event) !bool {
    switch (event) {
        .key => |key| {
            if (key == .ctrl_c or key.isChar('q')) {
                global_app.stop();
                return true;
            }
        },
        .tick => {
            try updateStats();
        },
        else => {},
    }
    return false;
}

fn updateStats() !void {
    frame_counter += 1;
    const elapsed_ns = start_time.read();
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;

    // Simulate realistic system stats
    const cpu_usage = 15.0 + 20.0 * @sin(elapsed_s * 0.5);
    const cpu_temp = 45.0 + 10.0 * @sin(elapsed_s * 0.3);

    // NVIDIA GPU stats
    const gpu_usage = 25.0 + 15.0 * @sin(elapsed_s * 0.8);
    const vram_used = 1024 + @as(u64, @intFromFloat(512.0 * @cos(elapsed_s * 0.6)));
    const gpu_temp = 50.0 + 15.0 * @sin(elapsed_s * 0.4);
    const gpu_power = 75.0 + 25.0 * @cos(elapsed_s * 0.5);

    // Memory stats
    const mem_used = 2048 + @as(u64, @intFromFloat(512.0 * @sin(elapsed_s * 0.2)));
    const mem_total: u64 = 16384;

    // Terminal FPS
    const render_fps = 144.0 + 16.0 * @sin(elapsed_s * 1.2);
    const frame_time = 1000.0 / render_fps;

    // Update text widgets
    const cpu_str = try std.fmt.allocPrint(
        cpu_text.allocator,
        "⚙️  CPU: {d:.1}% usage | Temp: {d:.1}°C",
        .{ cpu_usage, cpu_temp },
    );
    try cpu_text.setContent(cpu_str);

    const gpu_str = try std.fmt.allocPrint(
        gpu_text.allocator,
        "🎮 GPU (NVIDIA): {d:.1}% | VRAM: {d}MB/8192MB | {d:.1}°C | {d:.0}W",
        .{ gpu_usage, vram_used, gpu_temp, gpu_power },
    );
    try gpu_text.setContent(gpu_str);

    const mem_str = try std.fmt.allocPrint(
        mem_text.allocator,
        "💾 Memory: {d}MB / {d}MB ({d:.1}%)",
        .{ mem_used, mem_total, @as(f64, @floatFromInt(mem_used * 100)) / @as(f64, @floatFromInt(mem_total)) },
    );
    try mem_text.setContent(mem_str);

    const fps_str = try std.fmt.allocPrint(
        fps_text.allocator,
        "📊 Render: {d:.1} FPS | Frame Time: {d:.2}ms | Frames: {d}",
        .{ render_fps, frame_time, frame_counter },
    );
    try fps_text.setContent(fps_str);
}
