//! Blockchain Package Browser - Specialized for crypto/blockchain projects
const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Blockchain-specific package categories
pub const BlockchainCategory = enum {
    consensus,      // Consensus algorithms
    cryptography,   // Crypto primitives
    networking,     // P2P networking
    storage,        // Blockchain storage
    rpc,           // RPC clients/servers
    wallet,        // Wallet implementations
    defi,          // DeFi protocols
    nft,           // NFT standards
    bridge,        // Cross-chain bridges
    oracle,        // Oracle integrations
    
    pub fn getIcon(self: BlockchainCategory) []const u8 {
        return switch (self) {
            .consensus => "⚖️",
            .cryptography => "🔐",
            .networking => "🌐",
            .storage => "💾",
            .rpc => "🔌",
            .wallet => "💰",
            .defi => "🏦",
            .nft => "🎨",
            .bridge => "🌉",
            .oracle => "🔮",
        };
    }
    
    pub fn getDisplayName(self: BlockchainCategory) []const u8 {
        return switch (self) {
            .consensus => "Consensus",
            .cryptography => "Cryptography",
            .networking => "Networking",
            .storage => "Storage",
            .rpc => "RPC",
            .wallet => "Wallet",
            .defi => "DeFi",
            .nft => "NFT",
            .bridge => "Bridge",
            .oracle => "Oracle",
        };
    }
    
    pub fn getColor(self: BlockchainCategory) style.Color {
        return switch (self) {
            .consensus => style.Color.bright_yellow,
            .cryptography => style.Color.bright_red,
            .networking => style.Color.bright_blue,
            .storage => style.Color.bright_green,
            .rpc => style.Color.bright_cyan,
            .wallet => style.Color.bright_magenta,
            .defi => style.Color.yellow,
            .nft => style.Color.magenta,
            .bridge => style.Color.cyan,
            .oracle => style.Color.white,
        };
    }
};

/// Blockchain network types
pub const BlockchainNetwork = enum {
    bitcoin,
    ethereum,
    solana,
    cardano,
    polkadot,
    cosmos,
    avalanche,
    polygon,
    arbitrum,
    optimism,
    generic,
    
    pub fn getIcon(self: BlockchainNetwork) []const u8 {
        return switch (self) {
            .bitcoin => "₿",
            .ethereum => "Ξ",
            .solana => "◎",
            .cardano => "⊙",
            .polkadot => "●",
            .cosmos => "⚛️",
            .avalanche => "🏔️",
            .polygon => "🟣",
            .arbitrum => "🔵",
            .optimism => "🔴",
            .generic => "⚡",
        };
    }
    
    pub fn getDisplayName(self: BlockchainNetwork) []const u8 {
        return switch (self) {
            .bitcoin => "Bitcoin",
            .ethereum => "Ethereum",
            .solana => "Solana",
            .cardano => "Cardano",
            .polkadot => "Polkadot",
            .cosmos => "Cosmos",
            .avalanche => "Avalanche",
            .polygon => "Polygon",
            .arbitrum => "Arbitrum",
            .optimism => "Optimism",
            .generic => "Generic",
        };
    }
};

/// Blockchain package information
pub const BlockchainPackage = struct {
    name: []const u8,
    version: ?[]const u8 = null,
    description: ?[]const u8 = null,
    category: BlockchainCategory,
    networks: std.ArrayList(BlockchainNetwork),
    language: []const u8 = "zig", // rust, go, javascript, etc.
    repository_url: ?[]const u8 = null,
    documentation_url: ?[]const u8 = null,
    license: []const u8 = "MIT",
    stars: u32 = 0,
    last_updated: []const u8 = "",
    is_audited: bool = false,
    security_score: u8 = 0, // 0-100
    dependencies: std.ArrayList([]const u8),
    
    pub fn getDisplayInfo(self: *const BlockchainPackage, allocator: std.mem.Allocator) ![]const u8 {
        const version_str = self.version orelse "latest";
        const desc_str = self.description orelse "No description";
        const security_icon = if (self.is_audited) "🛡️" else "⚠️";
        
        return std.fmt.allocPrint(allocator, "{s} {s} {s} v{s} - {s} {s}", .{
            self.category.getIcon(), security_icon, self.name, version_str, desc_str, self.language
        });
    }
    
    pub fn getSecurityRating(self: *const BlockchainPackage) []const u8 {
        if (self.security_score >= 90) return "🟢 Excellent";
        if (self.security_score >= 70) return "🟡 Good";
        if (self.security_score >= 50) return "🟠 Fair";
        return "🔴 Poor";
    }
};

/// Blockchain package browser widget
pub const BlockchainPackageBrowser = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    
    // Package data
    packages: std.ArrayList(BlockchainPackage),
    filtered_packages: std.ArrayList(usize),
    
    // Filters
    category_filter: ?BlockchainCategory = null,
    network_filter: ?BlockchainNetwork = null,
    language_filter: ?[]const u8 = null,
    audited_only: bool = false,
    search_query: std.ArrayList(u8),
    
    // Display state
    selected_package: usize = 0,
    scroll_offset: usize = 0,
    current_view: ViewMode = .package_list,
    
    // Loading state
    is_loading: bool = false,
    load_progress: f64 = 0.0,
    
    // Styling
    header_style: Style,
    package_style: Style,
    selected_style: Style,
    category_style: Style,
    security_style: Style,
    network_style: Style,
    
    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),
    
    pub const ViewMode = enum {
        package_list,
        package_details,
        category_filter,
        network_filter,
    };

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*BlockchainPackageBrowser {
        const browser = try allocator.create(BlockchainPackageBrowser);
        browser.* = BlockchainPackageBrowser{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .packages = std.ArrayList(BlockchainPackage).init(allocator),
            .filtered_packages = std.ArrayList(usize).init(allocator),
            .search_query = std.ArrayList(u8).init(allocator),
            .header_style = Style.withFg(style.Color.bright_cyan).withBold(),
            .package_style = Style.withFg(style.Color.white),
            .selected_style = Style.withFg(style.Color.bright_yellow).withBold(),
            .category_style = Style.withFg(style.Color.bright_green),
            .security_style = Style.withFg(style.Color.bright_red),
            .network_style = Style.withFg(style.Color.bright_blue),
        };
        
        // Load blockchain packages
        try browser.loadBlockchainPackages();
        
        return browser;
    }

    /// Load curated blockchain packages
    fn loadBlockchainPackages(self: *BlockchainPackageBrowser) !void {
        // Consensus packages
        try self.addPackage(BlockchainPackage{
            .name = "zig-bitcoin-consensus",
            .version = "0.1.0",
            .description = "Bitcoin consensus validation library",
            .category = .consensus,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.bitcoin);
                break :blk networks;
            },
            .repository_url = "https://github.com/zigbitcoin/consensus",
            .is_audited = true,
            .security_score = 85,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        try self.addPackage(BlockchainPackage{
            .name = "ethereum-consensus-zig",
            .version = "2.0.1",
            .description = "Ethereum 2.0 consensus implementation",
            .category = .consensus,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.ethereum);
                break :blk networks;
            },
            .is_audited = true,
            .security_score = 92,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        // Cryptography packages
        try self.addPackage(BlockchainPackage{
            .name = "zig-secp256k1",
            .version = "1.0.3",
            .description = "Optimized secp256k1 elliptic curve library",
            .category = .cryptography,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.bitcoin);
                try networks.append(.ethereum);
                break :blk networks;
            },
            .is_audited = true,
            .security_score = 95,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        try self.addPackage(BlockchainPackage{
            .name = "zig-ed25519",
            .version = "0.8.2",
            .description = "Ed25519 signature scheme for Solana/Cardano",
            .category = .cryptography,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.solana);
                try networks.append(.cardano);
                break :blk networks;
            },
            .is_audited = true,
            .security_score = 88,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        try self.addPackage(BlockchainPackage{
            .name = "zig-keccak256",
            .version = "1.1.0",
            .description = "Keccak-256 hash function for Ethereum",
            .category = .cryptography,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.ethereum);
                try networks.append(.polygon);
                break :blk networks;
            },
            .is_audited = false,
            .security_score = 72,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        // Networking packages
        try self.addPackage(BlockchainPackage{
            .name = "libp2p-zig",
            .version = "0.5.1",
            .description = "LibP2P networking stack",
            .category = .networking,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.ethereum);
                try networks.append(.polkadot);
                break :blk networks;
            },
            .is_audited = false,
            .security_score = 68,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        try self.addPackage(BlockchainPackage{
            .name = "zig-gossip",
            .version = "0.3.0",
            .description = "Gossip protocol for blockchain networks",
            .category = .networking,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.solana);
                try networks.append(.avalanche);
                break :blk networks;
            },
            .is_audited = false,
            .security_score = 65,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        // Storage packages
        try self.addPackage(BlockchainPackage{
            .name = "zig-merkle-tree",
            .version = "1.2.0",
            .description = "Efficient Merkle tree implementation",
            .category = .storage,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.generic);
                break :blk networks;
            },
            .is_audited = true,
            .security_score = 82,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        try self.addPackage(BlockchainPackage{
            .name = "rocksdb-zig",
            .version = "0.7.3",
            .description = "RocksDB bindings for blockchain storage",
            .category = .storage,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.generic);
                break :blk networks;
            },
            .is_audited = false,
            .security_score = 75,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        // RPC packages
        try self.addPackage(BlockchainPackage{
            .name = "ethereum-rpc-zig",
            .version = "1.5.0",
            .description = "Ethereum JSON-RPC client",
            .category = .rpc,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.ethereum);
                try networks.append(.polygon);
                try networks.append(.arbitrum);
                break :blk networks;
            },
            .is_audited = false,
            .security_score = 78,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        try self.addPackage(BlockchainPackage{
            .name = "solana-rpc-zig",
            .version = "0.9.2",
            .description = "Solana RPC client implementation",
            .category = .rpc,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.solana);
                break :blk networks;
            },
            .is_audited = false,
            .security_score = 71,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        // Wallet packages
        try self.addPackage(BlockchainPackage{
            .name = "hd-wallet-zig",
            .version = "0.4.1",
            .description = "HD wallet key derivation (BIP32/BIP44)",
            .category = .wallet,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.bitcoin);
                try networks.append(.ethereum);
                break :blk networks;
            },
            .is_audited = true,
            .security_score = 90,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        try self.addPackage(BlockchainPackage{
            .name = "mnemonic-zig",
            .version = "1.0.0",
            .description = "BIP39 mnemonic phrase generation",
            .category = .wallet,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.generic);
                break :blk networks;
            },
            .is_audited = true,
            .security_score = 93,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        // DeFi packages
        try self.addPackage(BlockchainPackage{
            .name = "uniswap-v3-zig",
            .version = "0.6.0",
            .description = "Uniswap V3 protocol implementation",
            .category = .defi,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.ethereum);
                try networks.append(.polygon);
                break :blk networks;
            },
            .is_audited = false,
            .security_score = 76,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        try self.addPackage(BlockchainPackage{
            .name = "aave-zig",
            .version = "0.3.2",
            .description = "Aave lending protocol bindings",
            .category = .defi,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.ethereum);
                try networks.append(.avalanche);
                break :blk networks;
            },
            .is_audited = false,
            .security_score = 69,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        // NFT packages
        try self.addPackage(BlockchainPackage{
            .name = "erc721-zig",
            .version = "1.3.0",
            .description = "ERC-721 NFT standard implementation",
            .category = .nft,
            .networks = blk: {
                var networks = std.ArrayList(BlockchainNetwork).init(self.allocator);
                try networks.append(.ethereum);
                try networks.append(.polygon);
                break :blk networks;
            },
            .is_audited = true,
            .security_score = 87,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
        
        // Update filters
        self.updateFilters();
    }

    fn addPackage(self: *BlockchainPackageBrowser, package: BlockchainPackage) !void {
        try self.packages.append(package);
    }

    /// Update filtered package list
    fn updateFilters(self: *BlockchainPackageBrowser) void {
        self.filtered_packages.clearRetainingCapacity();
        
        for (self.packages.items, 0..) |*pkg, i| {
            // Apply category filter
            if (self.category_filter) |filter| {
                if (pkg.category != filter) continue;
            }
            
            // Apply network filter
            if (self.network_filter) |filter| {
                var found = false;
                for (pkg.networks.items) |network| {
                    if (network == filter) {
                        found = true;
                        break;
                    }
                }
                if (!found) continue;
            }
            
            // Apply audited filter
            if (self.audited_only and !pkg.is_audited) continue;
            
            // Apply search query
            if (self.search_query.items.len > 0) {
                const found_in_name = std.mem.indexOf(u8, pkg.name, self.search_query.items) != null;
                const found_in_desc = if (pkg.description) |desc| 
                    std.mem.indexOf(u8, desc, self.search_query.items) != null 
                else false;
                
                if (!found_in_name and !found_in_desc) continue;
            }
            
            self.filtered_packages.append(i) catch break;
        }
        
        // Reset selection if out of bounds
        if (self.selected_package >= self.filtered_packages.items.len) {
            self.selected_package = 0;
        }
    }

    /// Get currently selected package
    pub fn getSelectedPackage(self: *const BlockchainPackageBrowser) ?*const BlockchainPackage {
        if (self.filtered_packages.items.len == 0 or self.selected_package >= self.filtered_packages.items.len) {
            return null;
        }
        
        const pkg_index = self.filtered_packages.items[self.selected_package];
        return &self.packages.items[pkg_index];
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *BlockchainPackageBrowser = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;

        var y: u16 = area.y;
        
        // Header
        if (y < area.y + area.height) {
            buffer.fill(Rect.init(area.x, y, area.width, 1), Cell.withStyle(self.header_style));
            const header = "⛓️ BLOCKCHAIN PACKAGE BROWSER";
            buffer.writeText(area.x, y, header, self.header_style);
            
            // Show stats
            const stats = std.fmt.allocPrint(self.allocator, "  ({d} packages)", .{ 
                self.filtered_packages.items.len
            }) catch return;
            defer self.allocator.free(stats);
            
            if (area.x + header.len + stats.len < area.x + area.width) {
                buffer.writeText(area.x + @as(u16, @intCast(header.len)), y, stats, self.package_style);
            }
            y += 1;
        }

        // Filter bar
        if (y < area.y + area.height) {
            self.renderFilterBar(buffer, area.x, y, area.width);
            y += 1;
        }

        // Main content
        const content_area = Rect.init(area.x, y, area.width, area.y + area.height - y);
        switch (self.current_view) {
            .package_list => self.renderPackageList(buffer, content_area),
            .package_details => self.renderPackageDetails(buffer, content_area),
            .category_filter => self.renderCategoryFilter(buffer, content_area),
            .network_filter => self.renderNetworkFilter(buffer, content_area),
        }
    }

    fn renderFilterBar(self: *BlockchainPackageBrowser, buffer: *Buffer, x: u16, y: u16, width: u16) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.package_style));
        
        var current_x = x;
        
        // Category filter
        if (self.category_filter) |filter| {
            const filter_text = std.fmt.allocPrint(self.allocator, "{s} {s}", .{ filter.getIcon(), filter.getDisplayName() }) catch return;
            defer self.allocator.free(filter_text);
            
            buffer.writeText(current_x, y, filter_text, Style.withFg(filter.getColor()));
            current_x += @as(u16, @intCast(filter_text.len)) + 2;
        }
        
        // Network filter
        if (self.network_filter) |filter| {
            const filter_text = std.fmt.allocPrint(self.allocator, "{s} {s}", .{ filter.getIcon(), filter.getDisplayName() }) catch return;
            defer self.allocator.free(filter_text);
            
            buffer.writeText(current_x, y, filter_text, self.network_style);
            current_x += @as(u16, @intCast(filter_text.len)) + 2;
        }
        
        // Audited filter
        if (self.audited_only) {
            buffer.writeText(current_x, y, "🛡️ Audited", self.security_style);
            current_x += 10;
        }
        
        // Help text
        const help_text = "F1: Categories | F2: Networks | F3: Audited | /: Search";
        const help_x = x + width - @as(u16, @intCast(help_text.len));
        if (help_x > current_x) {
            buffer.writeText(help_x, y, help_text, Style.withFg(style.Color.bright_black));
        }
    }

    fn renderPackageList(self: *BlockchainPackageBrowser, buffer: *Buffer, area: Rect) void {
        var current_y = area.y;
        
        // Column headers
        if (current_y < area.y + area.height) {
            buffer.fill(Rect.init(area.x, current_y, area.width, 1), Cell.withStyle(self.header_style));
            buffer.writeText(area.x, current_y, "Cat  Security  Name                    Version    Networks        Description", self.header_style);
            current_y += 1;
        }
        
        // Package list
        for (self.filtered_packages.items, 0..) |pkg_index, display_index| {
            if (display_index < self.scroll_offset) continue;
            if (current_y >= area.y + area.height - 1) break; // Leave space for help
            
            const pkg = &self.packages.items[pkg_index];
            const is_selected = display_index == self.selected_package;
            
            self.renderPackageLine(buffer, area.x, current_y, area.width, pkg, is_selected);
            current_y += 1;
        }
        
        // Help text at bottom
        if (area.height > 2) {
            const help_y = area.y + area.height - 1;
            buffer.fill(Rect.init(area.x, help_y, area.width, 1), Cell.withStyle(Style.withFg(style.Color.bright_black)));
            const help_text = "Enter: details | Space: install | /: search | F1-F3: filters | q: quit";
            const help_len = @min(help_text.len, area.width);
            buffer.writeText(area.x, help_y, help_text[0..help_len], Style.withFg(style.Color.bright_black));
        }
    }

    fn renderPackageLine(self: *BlockchainPackageBrowser, buffer: *Buffer, x: u16, y: u16, width: u16, pkg: *const BlockchainPackage, is_selected: bool) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.package_style));
        
        const line_style = if (is_selected) self.selected_style else self.package_style;
        const bg_style = if (is_selected) Style.withBg(style.Color.bright_black) else self.package_style;
        
        var current_x = x;
        
        // Category icon
        buffer.writeText(current_x, y, pkg.category.getIcon(), Style.withFg(pkg.category.getColor()));
        current_x += 5;
        
        // Security rating
        const security_text = if (pkg.is_audited) "🛡️" else "⚠️";
        const security_color = if (pkg.security_score >= 80) style.Color.bright_green 
                              else if (pkg.security_score >= 60) style.Color.bright_yellow 
                              else style.Color.bright_red;
        
        buffer.writeText(current_x, y, security_text, Style.withFg(security_color));
        
        const score_text = std.fmt.allocPrint(self.allocator, "{d}", .{pkg.security_score}) catch return;
        defer self.allocator.free(score_text);
        buffer.writeText(current_x + 2, y, score_text, Style.withFg(security_color));
        current_x += 9;
        
        // Package name
        const name_len = @min(pkg.name.len, 20);
        buffer.writeText(current_x, y, pkg.name[0..name_len], line_style);
        current_x += 24;
        
        // Version
        if (pkg.version) |version| {
            const ver_len = @min(version.len, 8);
            buffer.writeText(current_x, y, version[0..ver_len], Style.withFg(style.Color.bright_black));
        }
        current_x += 11;
        
        // Networks
        var network_text = std.ArrayList(u8).init(self.allocator);
        defer network_text.deinit();
        
        for (pkg.networks.items, 0..) |network, i| {
            if (i > 0) network_text.appendSlice(", ") catch break;
            network_text.appendSlice(network.getIcon()) catch break;
        }
        
        const networks_len = @min(network_text.items.len, 15);
        if (networks_len > 0) {
            buffer.writeText(current_x, y, network_text.items[0..networks_len], self.network_style);
        }
        current_x += 16;
        
        // Description
        if (pkg.description) |desc| {
            const remaining_width = if (current_x < x + width) x + width - current_x else 0;
            const desc_len = @min(desc.len, remaining_width);
            if (desc_len > 0) {
                buffer.writeText(current_x, y, desc[0..desc_len], self.package_style);
            }
        }
        
        // Highlight selected row
        if (is_selected) {
            for (x..x + width) |col| {
                const cell = buffer.getCell(@as(u16, @intCast(col)), y);
                buffer.setCell(@as(u16, @intCast(col)), y, Cell.init(cell.char, bg_style.withFg(cell.style.fg)));
            }
        }
    }

    fn renderPackageDetails(self: *BlockchainPackageBrowser, buffer: *Buffer, area: Rect) void {
        if (self.getSelectedPackage()) |pkg| {
            var y = area.y;
            
            // Package header
            const header = std.fmt.allocPrint(self.allocator, "{s} {s} v{s}", .{ 
                pkg.category.getIcon(), pkg.name, pkg.version orelse "latest" 
            }) catch return;
            defer self.allocator.free(header);
            
            buffer.writeText(area.x, y, header, self.header_style);
            y += 2;
            
            // Security and audit info
            const security_info = std.fmt.allocPrint(self.allocator, "Security: {s} (Score: {d}/100)", .{ 
                pkg.getSecurityRating(), pkg.security_score 
            }) catch return;
            defer self.allocator.free(security_info);
            
            buffer.writeText(area.x, y, security_info, self.security_style);
            y += 1;
            
            if (pkg.is_audited) {
                buffer.writeText(area.x, y, "🛡️ Audited - Security review completed", Style.withFg(style.Color.bright_green));
            } else {
                buffer.writeText(area.x, y, "⚠️ Not audited - Use with caution", Style.withFg(style.Color.bright_yellow));
            }
            y += 2;
            
            // Networks
            buffer.writeText(area.x, y, "Supported Networks:", self.header_style);
            y += 1;
            
            for (pkg.networks.items) |network| {
                const network_info = std.fmt.allocPrint(self.allocator, "  {s} {s}", .{ 
                    network.getIcon(), network.getDisplayName() 
                }) catch continue;
                defer self.allocator.free(network_info);
                
                buffer.writeText(area.x, y, network_info, self.network_style);
                y += 1;
            }
            y += 1;
            
            // Description
            if (pkg.description) |desc| {
                buffer.writeText(area.x, y, "Description:", self.header_style);
                y += 1;
                buffer.writeText(area.x + 2, y, desc, self.package_style);
                y += 2;
            }
            
            // Additional info
            const info_lines = [_][]const u8{
                std.fmt.allocPrint(self.allocator, "Language: {s}", .{pkg.language}) catch return,
                std.fmt.allocPrint(self.allocator, "License: {s}", .{pkg.license}) catch return,
                std.fmt.allocPrint(self.allocator, "Stars: {d}", .{pkg.stars}) catch return,
            };
            
            for (info_lines) |line| {
                if (y < area.y + area.height) {
                    buffer.writeText(area.x, y, line, Style.withFg(style.Color.bright_black));
                    self.allocator.free(line);
                    y += 1;
                }
            }
            
            // URLs
            if (pkg.repository_url) |url| {
                const repo_line = std.fmt.allocPrint(self.allocator, "Repository: {s}", .{url}) catch return;
                defer self.allocator.free(repo_line);
                
                if (y < area.y + area.height) {
                    buffer.writeText(area.x, y, repo_line, Style.withFg(style.Color.bright_cyan));
                    y += 1;
                }
            }
            
        } else {
            buffer.writeText(area.x, area.y, "No package selected", Style.withFg(style.Color.bright_black));
        }
    }

    fn renderCategoryFilter(self: *BlockchainPackageBrowser, buffer: *Buffer, area: Rect) void {
        var y = area.y;
        
        buffer.writeText(area.x, y, "📂 SELECT CATEGORY", self.header_style);
        y += 2;
        
        const categories = [_]BlockchainCategory{ .consensus, .cryptography, .networking, .storage, .rpc, .wallet, .defi, .nft, .bridge, .oracle };
        
        for (categories) |category| {
            if (y >= area.y + area.height) break;
            
            const is_selected = (self.category_filter == category);
            const line_style = if (is_selected) self.selected_style else Style.withFg(category.getColor());
            
            const line = std.fmt.allocPrint(self.allocator, "{s} {s}", .{ 
                category.getIcon(), category.getDisplayName() 
            }) catch continue;
            defer self.allocator.free(line);
            
            buffer.writeText(area.x, y, line, line_style);
            y += 1;
        }
    }

    fn renderNetworkFilter(self: *BlockchainPackageBrowser, buffer: *Buffer, area: Rect) void {
        var y = area.y;
        
        buffer.writeText(area.x, y, "🌐 SELECT NETWORK", self.header_style);
        y += 2;
        
        const networks = [_]BlockchainNetwork{ .bitcoin, .ethereum, .solana, .cardano, .polkadot, .cosmos, .avalanche, .polygon, .arbitrum, .optimism };
        
        for (networks) |network| {
            if (y >= area.y + area.height) break;
            
            const is_selected = (self.network_filter == network);
            const line_style = if (is_selected) self.selected_style else self.network_style;
            
            const line = std.fmt.allocPrint(self.allocator, "{s} {s}", .{ 
                network.getIcon(), network.getDisplayName() 
            }) catch continue;
            defer self.allocator.free(line);
            
            buffer.writeText(area.x, y, line, line_style);
            y += 1;
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *BlockchainPackageBrowser = @fieldParentPtr("widget", widget);
        
        switch (event) {
            .key => |key_event| {
                if (!key_event.pressed) return false;
                
                switch (key_event.key) {
                    .up => {
                        if (self.selected_package > 0) {
                            self.selected_package -= 1;
                        }
                        return true;
                    },
                    .down => {
                        if (self.selected_package + 1 < self.filtered_packages.items.len) {
                            self.selected_package += 1;
                        }
                        return true;
                    },
                    .enter => {
                        switch (self.current_view) {
                            .package_list => self.current_view = .package_details,
                            else => self.current_view = .package_list,
                        }
                        return true;
                    },
                    .escape => {
                        self.current_view = .package_list;
                        return true;
                    },
                    .f1 => {
                        self.current_view = .category_filter;
                        return true;
                    },
                    .f2 => {
                        self.current_view = .network_filter;
                        return true;
                    },
                    .f3 => {
                        self.audited_only = !self.audited_only;
                        self.updateFilters();
                        return true;
                    },
                    .char => |char| {
                        switch (char) {
                            'q' => return true, // Quit signal
                            '/' => {
                                // Start search input
                                return true;
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
        
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *BlockchainPackageBrowser = @fieldParentPtr("widget", widget);
        self.area = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *BlockchainPackageBrowser = @fieldParentPtr("widget", widget);
        
        for (self.packages.items) |*pkg| {
            self.allocator.free(pkg.name);
            if (pkg.version) |v| self.allocator.free(v);
            if (pkg.description) |d| self.allocator.free(d);
            if (pkg.repository_url) |u| self.allocator.free(u);
            if (pkg.documentation_url) |u| self.allocator.free(u);
            pkg.networks.deinit();
            pkg.dependencies.deinit();
        }
        self.packages.deinit();
        self.filtered_packages.deinit();
        self.search_query.deinit();
        
        self.allocator.destroy(self);
    }
};

test "BlockchainPackageBrowser widget creation" {
    const allocator = std.testing.allocator;

    const browser = try BlockchainPackageBrowser.init(allocator);
    defer browser.widget.deinit();

    try std.testing.expect(browser.packages.items.len > 0);
    try std.testing.expect(browser.filtered_packages.items.len > 0);
}
