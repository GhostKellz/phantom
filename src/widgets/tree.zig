//! Tree Widget - Hierarchical data display with expand/collapse
//! Perfect for file explorers, JSON viewers, symbol outlines
//! Supports icons, keyboard navigation, and custom rendering

const std = @import("std");
const phantom = @import("../root.zig");
const Widget = phantom.Widget;
const Buffer = phantom.Buffer;
const Cell = phantom.Cell;
const Event = phantom.Event;
const Key = phantom.Key;
const Rect = phantom.Rect;
const Style = phantom.Style;
const Color = phantom.Color;

/// Tree node with hierarchical structure
pub const TreeNode = struct {
    id: []const u8,
    label: []const u8,
    icon: ?u21 = null,
    metadata: ?*anyopaque = null,
    children: std.ArrayList(*TreeNode),
    expanded: bool = false,
    parent: ?*TreeNode = null,
    depth: usize = 0,

    pub fn init(allocator: std.mem.Allocator, id: []const u8, label: []const u8) !*TreeNode {
        const node = try allocator.create(TreeNode);
        node.* = .{
            .id = try allocator.dupe(u8, id),
            .label = try allocator.dupe(u8, label),
            .children = .{},
        };
        return node;
    }

    pub fn deinit(self: *TreeNode, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
        allocator.free(self.id);
        allocator.free(self.label);
        allocator.destroy(self);
    }

    pub fn addChild(self: *TreeNode, allocator: std.mem.Allocator, child: *TreeNode) !void {
        child.parent = self;
        child.depth = self.depth + 1;
        try self.children.append(allocator, child);
    }

    pub fn toggle(self: *TreeNode) void {
        if (self.children.items.len > 0) {
            self.expanded = !self.expanded;
        }
    }

    pub fn expand(self: *TreeNode) void {
        self.expanded = true;
    }

    pub fn collapse(self: *TreeNode) void {
        self.expanded = false;
    }

    pub fn hasChildren(self: *const TreeNode) bool {
        return self.children.items.len > 0;
    }
};

/// Configuration for Tree widget
pub const TreeConfig = struct {
    /// Show expand/collapse indicators
    show_indicators: bool = true,

    /// Indent per level (spaces)
    indent_size: usize = 2,

    /// Style for normal nodes
    node_style: Style = Style.default(),

    /// Style for selected node
    selected_style: Style = Style.default().withBg(Color.blue),

    /// Style for hovered node (mouse)
    hovered_style: Style = Style.default().withBg(Color.bright_black),

    /// Style for expand/collapse indicators
    indicator_style: Style = Style.default().withFg(Color.bright_cyan),

    /// Style for icons
    icon_style: Style = Style.default().withFg(Color.yellow),

    /// Characters for expand/collapse indicators
    expanded_char: u21 = '▼',
    collapsed_char: u21 = '▶',
    leaf_char: u21 = ' ',

    pub fn default() TreeConfig {
        return .{};
    }
};

/// Custom error types for Tree
pub const Error = error{
    NodeNotFound,
    InvalidPath,
    CircularReference,
} || std.mem.Allocator.Error;

/// Tree widget for hierarchical data
pub const Tree = struct {
    widget: Widget,
    allocator: std.mem.Allocator,

    root: ?*TreeNode,
    selected_node: ?*TreeNode,
    hovered_node: ?*TreeNode,

    /// Flattened view of visible nodes (for rendering)
    visible_nodes: std.ArrayList(*TreeNode),

    /// Scroll offset
    scroll_offset: usize,
    viewport_height: u16,

    /// Config
    config: TreeConfig,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator, config: TreeConfig) Error!*Tree {
        const tree = try allocator.create(Tree);
        tree.* = .{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .root = null,
            .selected_node = null,
            .hovered_node = null,
            .visible_nodes = .{},
            .scroll_offset = 0,
            .viewport_height = 10,
            .config = config,
        };
        return tree;
    }

    /// Set the root node
    pub fn setRoot(self: *Tree, root: *TreeNode) void {
        self.root = root;
        self.selected_node = root;
        self.rebuildVisibleNodes();
    }

    /// Rebuild the flattened list of visible nodes
    fn rebuildVisibleNodes(self: *Tree) void {
        self.visible_nodes.clearRetainingCapacity();
        if (self.root) |root| {
            self.collectVisibleNodes(root);
        }
    }

    /// Recursively collect visible nodes (expanded tree traversal)
    fn collectVisibleNodes(self: *Tree, node: *TreeNode) void {
        self.visible_nodes.append(self.allocator, node) catch return;

        if (node.expanded) {
            for (node.children.items) |child| {
                self.collectVisibleNodes(child);
            }
        }
    }

    /// Select next visible node
    pub fn selectNext(self: *Tree) void {
        if (self.visible_nodes.items.len == 0) return;

        if (self.selected_node) |current| {
            // Find current in visible list
            for (self.visible_nodes.items, 0..) |node, i| {
                if (node == current and i + 1 < self.visible_nodes.items.len) {
                    self.selected_node = self.visible_nodes.items[i + 1];
                    self.ensureSelectedVisible();
                    return;
                }
            }
        } else {
            self.selected_node = self.visible_nodes.items[0];
        }
    }

    /// Select previous visible node
    pub fn selectPrevious(self: *Tree) void {
        if (self.visible_nodes.items.len == 0) return;

        if (self.selected_node) |current| {
            for (self.visible_nodes.items, 0..) |node, i| {
                if (node == current and i > 0) {
                    self.selected_node = self.visible_nodes.items[i - 1];
                    self.ensureSelectedVisible();
                    return;
                }
            }
        } else {
            self.selected_node = self.visible_nodes.items[0];
        }
    }

    /// Expand selected node
    pub fn expandSelected(self: *Tree) void {
        if (self.selected_node) |node| {
            if (node.hasChildren() and !node.expanded) {
                node.expand();
                self.rebuildVisibleNodes();
            }
        }
    }

    /// Collapse selected node
    pub fn collapseSelected(self: *Tree) void {
        if (self.selected_node) |node| {
            if (node.expanded) {
                node.collapse();
                self.rebuildVisibleNodes();
            } else if (node.parent) |parent| {
                // If already collapsed, jump to parent
                self.selected_node = parent;
                self.ensureSelectedVisible();
            }
        }
    }

    /// Toggle selected node expansion
    pub fn toggleSelected(self: *Tree) void {
        if (self.selected_node) |node| {
            node.toggle();
            self.rebuildVisibleNodes();
        }
    }

    fn ensureSelectedVisible(self: *Tree) void {
        if (self.selected_node == null) return;

        // Find index of selected node
        var selected_idx: ?usize = null;
        for (self.visible_nodes.items, 0..) |node, i| {
            if (node == self.selected_node.?) {
                selected_idx = i;
                break;
            }
        }

        if (selected_idx) |idx| {
            if (idx < self.scroll_offset) {
                self.scroll_offset = idx;
            } else if (idx >= self.scroll_offset + self.viewport_height) {
                self.scroll_offset = idx -| (self.viewport_height - 1);
            }
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Tree = @fieldParentPtr("widget", widget);

        self.viewport_height = area.height;

        if (self.visible_nodes.items.len == 0) {
            buffer.writeText(area.x, area.y, "No items", Style.default().withFg(Color.bright_black));
            return;
        }

        // Render visible range
        const end_index = @min(self.scroll_offset + area.height, self.visible_nodes.items.len);

        var y: u16 = 0;
        var idx = self.scroll_offset;
        while (idx < end_index) : (idx += 1) {
            const node = self.visible_nodes.items[idx];
            const is_selected = self.selected_node == node;
            const is_hovered = self.hovered_node == node;

            const node_style = if (is_selected)
                self.config.selected_style
            else if (is_hovered)
                self.config.hovered_style
            else
                self.config.node_style;

            // Fill background
            buffer.fill(Rect.init(area.x, area.y + y, area.width, 1), Cell.withStyle(node_style));

            var x = area.x;

            // Indent
            const indent = @as(u16, @intCast(node.depth * self.config.indent_size));
            x += indent;

            // Expand/collapse indicator
            if (self.config.show_indicators) {
                const indicator = if (node.hasChildren())
                    if (node.expanded) self.config.expanded_char else self.config.collapsed_char
                else
                    self.config.leaf_char;

                buffer.setCell(x, area.y + y, Cell.init(indicator, self.config.indicator_style));
                x += 2;
            }

            // Icon
            if (node.icon) |icon| {
                buffer.setCell(x, area.y + y, Cell.init(icon, self.config.icon_style));
                x += 2;
            }

            // Label
            buffer.writeText(x, area.y + y, node.label, node_style);

            y += 1;
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Tree = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key| {
                switch (key) {
                    .up, .char => |c| {
                        if (key == .up or (key == .char and c == 'k')) {
                            self.selectPrevious();
                            return true;
                        }
                    },
                    .down => {
                        self.selectNext();
                        return true;
                    },
                    .right => {
                        self.expandSelected();
                        return true;
                    },
                    .left => {
                        self.collapseSelected();
                        return true;
                    },
                    .enter => {
                        self.toggleSelected();
                        return true;
                    },
                    else => {
                        if (key == .char) {
                            const c = key.char;
                            if (c == 'j') {
                                self.selectNext();
                                return true;
                            } else if (c == 'h') {
                                self.collapseSelected();
                                return true;
                            } else if (c == 'l') {
                                self.expandSelected();
                                return true;
                            }
                        }
                    },
                }
            },
            .mouse => |mouse| {
                if (mouse.button == .wheel_up) {
                    self.selectPrevious();
                    return true;
                }
                if (mouse.button == .wheel_down) {
                    self.selectNext();
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *Tree = @fieldParentPtr("widget", widget);
        self.viewport_height = area.height;
        self.ensureSelectedVisible();
    }

    fn deinit(widget: *Widget) void {
        const self: *Tree = @fieldParentPtr("widget", widget);

        if (self.root) |root| {
            root.deinit(self.allocator);
        }

        self.visible_nodes.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

// Tests
test "Tree basic operations" {
    const testing = std.testing;

    const tree = try Tree.init(testing.allocator, TreeConfig.default());
    defer tree.widget.vtable.deinit(&tree.widget);

    const root = try TreeNode.init(testing.allocator, "root", "Root");
    tree.setRoot(root);

    try testing.expect(tree.root != null);
    try testing.expectEqualStrings("Root", tree.root.?.label);
}

test "Tree node hierarchy" {
    const testing = std.testing;

    const tree = try Tree.init(testing.allocator, TreeConfig.default());
    defer tree.widget.vtable.deinit(&tree.widget);

    const root = try TreeNode.init(testing.allocator, "root", "Root");
    const child1 = try TreeNode.init(testing.allocator, "child1", "Child 1");
    const child2 = try TreeNode.init(testing.allocator, "child2", "Child 2");

    try root.addChild(testing.allocator, child1);
    try root.addChild(testing.allocator, child2);

    tree.setRoot(root);

    try testing.expectEqual(@as(usize, 2), root.children.items.len);
    try testing.expectEqual(@as(usize, 1), child1.depth);
    try testing.expect(child1.parent == root);
}

test "Tree expand/collapse" {
    const testing = std.testing;

    const tree = try Tree.init(testing.allocator, TreeConfig.default());
    defer tree.widget.vtable.deinit(&tree.widget);

    const root = try TreeNode.init(testing.allocator, "root", "Root");
    const child = try TreeNode.init(testing.allocator, "child", "Child");

    try root.addChild(testing.allocator, child);
    tree.setRoot(root);

    try testing.expect(!root.expanded);

    root.expand();
    tree.rebuildVisibleNodes();

    try testing.expect(root.expanded);
    try testing.expectEqual(@as(usize, 2), tree.visible_nodes.items.len); // root + child
}
