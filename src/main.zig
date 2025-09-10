const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Phantom runtime
    try phantom.runtime.initRuntime(allocator);
    defer phantom.runtime.deinitRuntime();

    // Create app
    var app = try phantom.App.init(allocator, phantom.AppConfig{
        .title = "👻 Phantom TUI Demo",
        .tick_rate_ms = 50,
    });
    defer app.deinit();

    // Create a simple text widget
    const hello_text = try phantom.widgets.Text.initWithStyle(allocator, "Welcome to Phantom TUI! 👻", phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold());
    try app.addWidget(&hello_text.widget);

    // Create a list widget
    const list = try phantom.widgets.List.init(allocator);
    try list.addItemText("🚀 Feature 1: Pure Zig");
    try list.addItemText("⚡ Feature 2: Async with zsync");
    try list.addItemText("🧱 Feature 3: Rich widgets");
    try list.addItemText("🌈 Feature 4: Styled output");
    try list.addItemText("🖱️  Feature 5: Input handling");
    try app.addWidget(&list.widget);

    // Print startup message
    std.debug.print("Starting Phantom TUI Demo...\n", .{});
    std.debug.print("Use arrow keys or j/k to navigate the list\n", .{});
    std.debug.print("Press Ctrl+C or Escape to exit\n", .{});

    // Run the app
    try app.run();

    std.debug.print("Phantom TUI Demo ended. Goodbye! 👻\n", .{});
}

test "simple test" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList(i32){};
    defer list.deinit(allocator);
    try list.append(allocator, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
