//! NetworkTopology widget for visualizing VPN connections and mesh networks
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const emoji = @import("../emoji.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Connection status for network links
pub const ConnectionStatus = enum {
    connected,
    connecting,
    disconnected,
    err,
    
    pub fn getEmoji(self: ConnectionStatus) []const u8 {
        return switch (self) {
            .connected => "🟢",
            .connecting => "🟡",
            .disconnected => "⚪",
            .err => "🔴",
        };
    }
    
    pub fn getStyle(self: ConnectionStatus) Style {
        return switch (self) {
            .connected => Style.withFg(style.Color.bright_green),
            .connecting => Style.withFg(style.Color.bright_yellow),
            .disconnected => Style.withFg(style.Color.white),
            .err => Style.withFg(style.Color.bright_red),
        };
    }
};

/// Network node representing a peer/device
pub const NetworkNode = struct {
    id: []const u8,
    name: []const u8,
    ip_address: []const u8,
    status: ConnectionStatus = .disconnected,
    latency_ms: f64 = 0.0,
    last_seen: u64 = 0, // timestamp
    is_relay: bool = false,
    is_exit_node: bool = false,
    position: Position = Position{},
    
    pub const Position = struct {
        x: u16 = 0,
        y: u16 = 0,
    };
    
    pub fn getDisplayName(self: *const NetworkNode) []const u8 {
        return if (self.name.len > 0) self.name else self.id;
    }
    
    pub fn getIcon(self: *const NetworkNode) []const u8 {
        if (self.is_exit_node) return "🌐";
        if (self.is_relay) return "🔄";
        return "💻";
    }
};

/// Connection between two nodes
pub const Connection = struct {
    from_id: []const u8,
    to_id: []const u8,
    status: ConnectionStatus = .disconnected,
    latency_ms: f64 = 0.0,
    throughput_mbps: f64 = 0.0,
    is_direct: bool = true, // false for relayed connections
    last_activity: u64 = 0,
    
    pub fn getLineStyle(self: *const Connection) []const u8 {
        return switch (self.status) {
            .connected => if (self.is_direct) "━" else "┄",
            .connecting => "┅",
            .disconnected => "·",
            .err => "✗",
        };
    }
};

/// Layout style for network topology
pub const TopologyLayout = enum {
    auto,      // Automatic spring-based layout
    circular,  // Nodes arranged in a circle
    grid,      // Grid-based layout
    star,      // Star topology with central hub
    mesh,      // Full mesh layout
};

/// NetworkTopology widget for mesh network visualization
pub const NetworkTopology = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    
    // Network data
    nodes: std.ArrayList(NetworkNode),
    connections: std.ArrayList(Connection),
    node_map: std.HashMap([]const u8, usize, std.hash_map.StringContext, std.hash_map.default_max_load_percentage), // id -> index
    
    // Layout
    layout: TopologyLayout = .auto,
    center_x: u16 = 0,
    center_y: u16 = 0,
    scale: f64 = 1.0,
    
    // Display options
    show_latency: bool = true,
    show_throughput: bool = true,
    show_node_details: bool = true,
    animate_connections: bool = true,
    compact_mode: bool = false,
    
    // Styling
    header_style: Style,
    node_style: Style,
    connection_style: Style,
    info_style: Style,
    
    // Interactive state
    selected_node: ?usize = null,
    hover_node: ?usize = null,
    
    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*NetworkTopology {
        const topology = try allocator.create(NetworkTopology);
        topology.* = NetworkTopology{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .nodes = std.ArrayList(NetworkNode){},
            .connections = std.ArrayList(Connection){},
            .node_map = std.HashMap([]const u8, usize, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .header_style = Style.withFg(style.Color.bright_cyan).withBold(),
            .node_style = Style.withFg(style.Color.bright_white),
            .connection_style = Style.withFg(style.Color.bright_blue),
            .info_style = Style.withFg(style.Color.white),
        };
        
        return topology;
    }

    /// Add a network node to the topology
    pub fn addNode(self: *NetworkTopology, node: NetworkNode) !void {
        // Store owned copy of the node data
        const owned_node = NetworkNode{
            .id = try self.allocator.dupe(u8, node.id),
            .name = try self.allocator.dupe(u8, node.name),
            .ip_address = try self.allocator.dupe(u8, node.ip_address),
            .status = node.status,
            .latency_ms = node.latency_ms,
            .last_seen = node.last_seen,
            .is_relay = node.is_relay,
            .is_exit_node = node.is_exit_node,
            .position = node.position,
        };
        
        const index = self.nodes.items.len;
        try self.nodes.append(owned_node);
        try self.node_map.put(owned_node.id, index);
        
        // Auto-position if not specified
        if (owned_node.position.x == 0 and owned_node.position.y == 0) {
            self.calculateNodePosition(index);
        }
    }

    /// Update an existing node's status
    pub fn updateNode(self: *NetworkTopology, node_id: []const u8, status: ConnectionStatus, latency_ms: f64) void {
        if (self.node_map.get(node_id)) |index| {
            if (index < self.nodes.items.len) {
                self.nodes.items[index].status = status;
                self.nodes.items[index].latency_ms = latency_ms;
                self.nodes.items[index].last_seen = std.time.timestamp();
            }
        }
    }

    /// Add/update connection between nodes
    pub fn updateConnection(self: *NetworkTopology, from_id: []const u8, to_id: []const u8, status: ConnectionStatus, latency_ms: f64) !void {
        // Find existing connection
        for (self.connections.items) |*conn| {
            if (std.mem.eql(u8, conn.from_id, from_id) and std.mem.eql(u8, conn.to_id, to_id)) {
                conn.status = status;
                conn.latency_ms = latency_ms;
                conn.last_activity = std.time.timestamp();
                return;
            }
        }
        
        // Create new connection
        const connection = Connection{
            .from_id = try self.allocator.dupe(u8, from_id),
            .to_id = try self.allocator.dupe(u8, to_id),
            .status = status,
            .latency_ms = latency_ms,
            .last_activity = std.time.timestamp(),
        };
        try self.connections.append(connection);
    }

    /// Set the layout algorithm
    pub fn setLayout(self: *NetworkTopology, layout: TopologyLayout) void {
        self.layout = layout;
        self.recalculateLayout();
    }

    /// Enable/disable compact display mode
    pub fn setCompactMode(self: *NetworkTopology, compact: bool) void {
        self.compact_mode = compact;
    }

    /// Select a node for detailed view
    pub fn selectNode(self: *NetworkTopology, node_id: []const u8) void {
        self.selected_node = self.node_map.get(node_id);
    }

    fn calculateNodePosition(self: *NetworkTopology, node_index: usize) void {
        if (node_index >= self.nodes.items.len) return;
        
        const area_width = @as(f64, @floatFromInt(self.area.width));
        const area_height = @as(f64, @floatFromInt(self.area.height));
        
        switch (self.layout) {
            .circular => {
                const angle = (@as(f64, @floatFromInt(node_index)) / @as(f64, @floatFromInt(self.nodes.items.len))) * 2.0 * std.math.pi;
                const radius = @min(area_width, area_height) * 0.3;
                self.nodes.items[node_index].position.x = @as(u16, @intFromFloat(self.center_x + radius * @cos(angle)));
                self.nodes.items[node_index].position.y = @as(u16, @intFromFloat(self.center_y + radius * @sin(angle)));
            },
            .grid => {
                const cols = @as(u16, @intFromFloat(@sqrt(area_width)));
                const row = @as(u16, @intCast(node_index / cols));
                const col = @as(u16, @intCast(node_index % cols));
                self.nodes.items[node_index].position.x = self.area.x + col * (self.area.width / cols);
                self.nodes.items[node_index].position.y = self.area.y + row * (self.area.height / @max(1, @as(u16, @intCast(self.nodes.items.len / cols))));
            },
            .star => {
                if (node_index == 0) {
                    // Central hub
                    self.nodes.items[0].position.x = self.center_x;
                    self.nodes.items[0].position.y = self.center_y;
                } else {
                    // Satellite nodes
                    const angle = (@as(f64, @floatFromInt(node_index - 1)) / @as(f64, @floatFromInt(self.nodes.items.len - 1))) * 2.0 * std.math.pi;
                    const radius = @min(area_width, area_height) * 0.3;
                    self.nodes.items[node_index].position.x = @as(u16, @intFromFloat(self.center_x + radius * @cos(angle)));
                    self.nodes.items[node_index].position.y = @as(u16, @intFromFloat(self.center_y + radius * @sin(angle)));
                }
            },
            else => {
                // Auto/mesh: Simple grid for now
                const cols: u16 = 4;
                const row = @as(u16, @intCast(node_index / cols));
                const col = @as(u16, @intCast(node_index % cols));
                self.nodes.items[node_index].position.x = self.area.x + col * (self.area.width / cols);
                self.nodes.items[node_index].position.y = self.area.y + row * 3;
            },
        }
    }

    fn recalculateLayout(self: *NetworkTopology) void {
        for (0..self.nodes.items.len) |i| {
            self.calculateNodePosition(i);
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *NetworkTopology = @fieldParentPtr("widget", widget);
        self.area = area;
        self.center_x = area.x + area.width / 2;
        self.center_y = area.y + area.height / 2;

        if (area.height == 0 or area.width == 0) return;

        var y: u16 = area.y;
        
        // Header
        if (y < area.y + area.height) {
            buffer.fill(Rect.init(area.x, y, area.width, 1), Cell.withStyle(self.header_style));
            const header = if (self.compact_mode) "🌐 Network" else "🌐 NETWORK TOPOLOGY";
            buffer.writeText(area.x, y, header, self.header_style);
            
            // Show stats in header
            const stats_text = std.fmt.allocPrint(self.allocator, "  ({d} nodes, {d} connections)", .{ self.nodes.items.len, self.connections.items.len }) catch return;
            defer self.allocator.free(stats_text);
            if (area.x + header.len + stats_text.len < area.x + area.width) {
                buffer.writeText(area.x + @as(u16, @intCast(header.len)), y, stats_text, self.info_style);
            }
            y += 1;
        }

        // Render connections first (so they appear behind nodes)
        self.renderConnections(buffer, area);
        
        // Render nodes
        self.renderNodes(buffer, area);
        
        // Render node details panel if a node is selected
        if (self.selected_node) |selected_index| {
            self.renderNodeDetails(buffer, area, selected_index);
        }
    }

    fn renderConnections(self: *NetworkTopology, buffer: *Buffer, area: Rect) void {
        for (self.connections.items) |*conn| {
            const from_index = self.node_map.get(conn.from_id) orelse continue;
            const to_index = self.node_map.get(conn.to_id) orelse continue;
            
            if (from_index >= self.nodes.items.len or to_index >= self.nodes.items.len) continue;
            
            const from_node = &self.nodes.items[from_index];
            const to_node = &self.nodes.items[to_index];
            
            // Draw line between nodes
            self.drawConnection(buffer, area, from_node.position, to_node.position, conn);
        }
    }

    fn drawConnection(self: *NetworkTopology, buffer: *Buffer, area: Rect, from: NetworkNode.Position, to: NetworkNode.Position, conn: *const Connection) void {
        _ = area; // TODO: Check bounds
        
        const line_char = conn.getLineStyle();
        const line_style = conn.status.getStyle();
        
        // Simple line drawing (could be enhanced with Bresenham algorithm)
        const dx = @as(i32, @intCast(to.x)) - @as(i32, @intCast(from.x));
        const dy = @as(i32, @intCast(to.y)) - @as(i32, @intCast(from.y));
        const steps = @max(@abs(dx), @abs(dy));
        
        if (steps == 0) return;
        
        const x_inc = @as(f64, @floatFromInt(dx)) / @as(f64, @floatFromInt(steps));
        const y_inc = @as(f64, @floatFromInt(dy)) / @as(f64, @floatFromInt(steps));
        
        for (0..@as(usize, @intCast(steps))) |i| {
            const x = @as(u16, @intFromFloat(@as(f64, @floatFromInt(from.x)) + x_inc * @as(f64, @floatFromInt(i))));
            const y = @as(u16, @intFromFloat(@as(f64, @floatFromInt(from.y)) + y_inc * @as(f64, @floatFromInt(i))));
            
            // Skip if position is occupied by a node
            var skip = false;
            for (self.nodes.items) |*node| {
                if (node.position.x == x and node.position.y == y) {
                    skip = true;
                    break;
                }
            }
            
            if (!skip and i > 0 and i < steps - 1) { // Don't draw over the nodes themselves
                buffer.setCell(x, y, Cell.init(@as(u21, @intCast(line_char[0])), line_style));
            }
        }
        
        // Show latency near the middle of the connection if enabled
        if (self.show_latency and conn.latency_ms > 0) {
            const mid_x = @as(u16, @intFromFloat((@as(f64, @floatFromInt(from.x)) + @as(f64, @floatFromInt(to.x))) / 2.0));
            const mid_y = @as(u16, @intFromFloat((@as(f64, @floatFromInt(from.y)) + @as(f64, @floatFromInt(to.y))) / 2.0));
            
            const latency_text = std.fmt.allocPrint(self.allocator, "{d:.0}ms", .{conn.latency_ms}) catch return;
            defer self.allocator.free(latency_text);
            
            buffer.writeText(mid_x, mid_y, latency_text, Style.withFg(style.Color.bright_yellow));
        }
    }

    fn renderNodes(self: *NetworkTopology, buffer: *Buffer, area: Rect) void {
        for (self.nodes.items, 0..) |*node, i| {
            // Check if node is within the display area
            if (node.position.x < area.x or node.position.x >= area.x + area.width or
                node.position.y < area.y or node.position.y >= area.y + area.height) {
                continue;
            }
            
            // Determine node style
            const node_style = if (self.selected_node == i) Style.withFg(style.Color.bright_cyan).withBold()
            else if (self.hover_node == i) Style.withFg(style.Color.bright_white).withBold()
            else node.status.getStyle();
            
            // Draw node icon
            const icon = node.getIcon();
            buffer.writeText(node.position.x, node.position.y, icon, node_style);
            
            // Draw node name/status if not in compact mode
            if (!self.compact_mode and node.position.y + 1 < area.y + area.height) {
                const status_emoji = node.status.getEmoji();
                const node_text = if (node.name.len > 0) node.name else node.id;
                const display_text = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ status_emoji, node_text }) catch return;
                defer self.allocator.free(display_text);
                
                const max_len = @min(display_text.len, 12); // Limit to prevent overlap
                buffer.writeText(node.position.x, node.position.y + 1, display_text[0..max_len], self.info_style);
            }
        }
    }

    fn renderNodeDetails(self: *NetworkTopology, buffer: *Buffer, area: Rect, node_index: usize) void {
        if (node_index >= self.nodes.items.len) return;
        
        const node = &self.nodes.items[node_index];
        const panel_width: u16 = 30;
        const panel_x = if (area.width > panel_width) area.x + area.width - panel_width else area.x;
        var panel_y = area.y + 2;
        
        // Node details panel
        const details = [_][]const u8{
            "┌─ NODE DETAILS ─────────────┐",
        };
        
        for (details) |line| {
            if (panel_y < area.y + area.height) {
                buffer.writeText(panel_x, panel_y, line, self.header_style);
                panel_y += 1;
            }
        }
        
        // Node information
        const info_lines = [_][]const u8{
            std.fmt.allocPrint(self.allocator, "│ Name: {s}", .{node.getDisplayName()}) catch return,
            std.fmt.allocPrint(self.allocator, "│ IP: {s}", .{node.ip_address}) catch return,
            std.fmt.allocPrint(self.allocator, "│ Status: {s}", .{@tagName(node.status)}) catch return,
            std.fmt.allocPrint(self.allocator, "│ Latency: {d:.1}ms", .{node.latency_ms}) catch return,
        };
        defer for (info_lines) |line| self.allocator.free(line);
        
        for (info_lines) |line| {
            if (panel_y < area.y + area.height) {
                buffer.writeText(panel_x, panel_y, line, self.info_style);
                panel_y += 1;
            }
        }
        
        buffer.writeText(panel_x, panel_y, "└────────────────────────────┘", self.header_style);
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *NetworkTopology = @fieldParentPtr("widget", widget);
        
        switch (event) {
            .mouse => |mouse_event| {
                // Find node under cursor
                for (self.nodes.items, 0..) |*node, i| {
                    if (mouse_event.x == node.position.x and mouse_event.y == node.position.y) {
                        switch (mouse_event.button) {
                            .left => {
                                if (mouse_event.pressed) {
                                    self.selected_node = i;
                                    return true;
                                }
                            },
                            else => {},
                        }
                        self.hover_node = i;
                        return true;
                    }
                }
                self.hover_node = null;
            },
            .key => |key_event| {
                switch (key_event.key) {
                    .escape => {
                        self.selected_node = null;
                        return true;
                    },
                    .tab => {
                        // Cycle through layout modes
                        self.layout = switch (self.layout) {
                            .auto => .circular,
                            .circular => .grid,
                            .grid => .star,
                            .star => .mesh,
                            .mesh => .auto,
                        };
                        self.recalculateLayout();
                        return true;
                    },
                    else => {},
                }
            },
            else => {},
        }
        
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *NetworkTopology = @fieldParentPtr("widget", widget);
        self.area = area;
        self.center_x = area.x + area.width / 2;
        self.center_y = area.y + area.height / 2;
        self.recalculateLayout();
    }

    fn deinit(widget: *Widget) void {
        const self: *NetworkTopology = @fieldParentPtr("widget", widget);
        
        // Free node data
        for (self.nodes.items) |*node| {
            self.allocator.free(node.id);
            self.allocator.free(node.name);
            self.allocator.free(node.ip_address);
        }
        self.nodes.deinit();
        
        // Free connection data
        for (self.connections.items) |*conn| {
            self.allocator.free(conn.from_id);
            self.allocator.free(conn.to_id);
        }
        self.connections.deinit();
        
        self.node_map.deinit();
        self.allocator.destroy(self);
    }
};

test "NetworkTopology widget creation" {
    const allocator = std.testing.allocator;

    const topology = try NetworkTopology.init(allocator);
    defer topology.widget.deinit();

    // Add test nodes
    try topology.addNode(NetworkNode{
        .id = "node1",
        .name = "Laptop",
        .ip_address = "100.64.0.1",
        .status = .connected,
        .latency_ms = 15.5,
    });
    
    try topology.addNode(NetworkNode{
        .id = "relay1",
        .name = "Relay Server",
        .ip_address = "100.64.0.100",
        .status = .connected,
        .is_relay = true,
        .latency_ms = 45.2,
    });
    
    // Add connection
    try topology.updateConnection("node1", "relay1", .connected, 30.0);
    
    try std.testing.expect(topology.nodes.items.len == 2);
    try std.testing.expect(topology.connections.items.len == 1);
}
