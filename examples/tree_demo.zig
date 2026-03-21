//! Tree Widget Demo - File explorer example
//! Shows hierarchical data with expand/collapse

const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create tree widget
    const tree = try phantom.widgets.Tree.init(allocator, phantom.widgets.TreeConfig{
        .show_indicators = true,
        .indent_size = 2,
        .expanded_char = '▼',
        .collapsed_char = '▶',
    });

    // Build file tree structure
    const root = try phantom.widgets.TreeNode.init(allocator, "root", "/home/user");
    root.icon = '📁';
    root.expanded = true; // Start expanded

    // Add directories
    const src = try phantom.widgets.TreeNode.init(allocator, "src", "src");
    src.icon = '📁';
    try root.addChild(allocator, src);

    const tests = try phantom.widgets.TreeNode.init(allocator, "tests", "tests");
    tests.icon = '📁';
    try root.addChild(allocator, tests);

    // Add files to src/
    const main_zig = try phantom.widgets.TreeNode.init(allocator, "main", "main.zig");
    main_zig.icon = '📄';
    try src.addChild(allocator, main_zig);

    const lib_zig = try phantom.widgets.TreeNode.init(allocator, "lib", "lib.zig");
    lib_zig.icon = '📄';
    try src.addChild(allocator, lib_zig);

    // Add widget subdirectory
    const widgets = try phantom.widgets.TreeNode.init(allocator, "widgets", "widgets");
    widgets.icon = '📁';
    try src.addChild(allocator, widgets);

    const tree_zig = try phantom.widgets.TreeNode.init(allocator, "tree", "tree.zig");
    tree_zig.icon = '🌲';
    try widgets.addChild(allocator, tree_zig);

    // Add files to tests/
    const test_main = try phantom.widgets.TreeNode.init(allocator, "test_main", "test_main.zig");
    test_main.icon = '🧪';
    try tests.addChild(allocator, test_main);

    // Add build files
    const build_zig = try phantom.widgets.TreeNode.init(allocator, "build", "build.zig");
    build_zig.icon = '⚙';
    try root.addChild(allocator, build_zig);

    const readme = try phantom.widgets.TreeNode.init(allocator, "readme", "README.md");
    readme.icon = '📖';
    try root.addChild(allocator, readme);

    tree.setRoot(root);

    // Create app
    var app = try phantom.App.init(allocator, .{
        .title = "Tree Widget Demo - File Explorer",
        .mouse_enabled = false,
    });
    defer app.deinit();

    try app.addWidget(&tree.widget);

    _ = try std.io.getStdIn().reader().readByte();

    try app.run();
}
