//! Blockchain Package Browser - Interactive TUI
//! Browse blockchain packages with security ratings
const std = @import("std");
const phantom = @import("phantom");

var global_app: *phantom.App = undefined;
var package_list: *phantom.widgets.List = undefined;

const Package = struct {
    name: []const u8,
    version: []const u8,
    network: []const u8,
    security_score: u8,
    category: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try phantom.App.init(allocator, .{
        .title = "Blockchain Package Browser",
        .tick_rate_ms = 16,
        .mouse_enabled = false,
    });
    defer app.deinit();
    global_app = &app;

    // Header
    const header = try phantom.widgets.Text.initWithStyle(
        allocator,
        "🔐 BLOCKCHAIN PACKAGE BROWSER",
        phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold(),
    );
    try app.addWidget(&header.widget);

    const subtitle = try phantom.widgets.Text.initWithStyle(
        allocator,
        "Decentralized Package Registry with Security Audits",
        phantom.Style.default().withFg(phantom.Color.bright_green),
    );
    try app.addWidget(&subtitle.widget);

    const divider = try phantom.widgets.Text.initWithStyle(
        allocator,
        "═══════════════════════════════════════════════════════════════════════",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&divider.widget);

    // Package list
    package_list = try phantom.widgets.List.init(allocator);
    package_list.setItemStyle(phantom.Style.default());
    package_list.setSelectedStyle(
        phantom.Style.default()
            .withBg(phantom.Color.blue)
            .withFg(phantom.Color.white)
            .withBold(),
    );

    // Add blockchain packages
    const packages = [_]Package{
        .{ .name = "bitcoin-consensus", .version = "v0.1.0", .network = "₿ Bitcoin", .security_score = 95, .category = "Consensus" },
        .{ .name = "ethereum-evm", .version = "v2.0.1", .network = "Ξ Ethereum", .security_score = 92, .category = "VM" },
        .{ .name = "solana-runtime", .version = "v1.18.0", .network = "◎ Solana", .security_score = 88, .category = "Runtime" },
        .{ .name = "cardano-ledger", .version = "v8.7.0", .network = "⊙ Cardano", .security_score = 90, .category = "Ledger" },
        .{ .name = "polkadot-runtime", .version = "v1.0.0", .network = "● Polkadot", .security_score = 87, .category = "Runtime" },
        .{ .name = "cosmos-sdk", .version = "v0.47.0", .network = "⚛️  Cosmos", .security_score = 89, .category = "SDK" },
        .{ .name = "avalanche-consensus", .version = "v1.10.0", .network = "🏔️  Avalanche", .security_score = 85, .category = "Consensus" },
        .{ .name = "polygon-bor", .version = "v0.4.0", .network = "🟣 Polygon", .security_score = 83, .category = "Client" },
        .{ .name = "zkSync-circuits", .version = "v1.4.0", .network = "⚡ zkSync", .security_score = 91, .category = "ZK Proof" },
        .{ .name = "starknet-cairo", .version = "v2.5.0", .network = "🔷 StarkNet", .security_score = 86, .category = "VM" },
        .{ .name = "near-protocol", .version = "v1.35.0", .network = "Ⓝ NEAR", .security_score = 84, .category = "Protocol" },
        .{ .name = "tezos-protocol", .version = "v16.0", .network = "ꜩ Tezos", .security_score = 88, .category = "Protocol" },
    };

    for (packages) |pkg| {
        const security_icon = getSecurityIcon(pkg.security_score);
        const line = try std.fmt.allocPrint(
            allocator,
            "{s} {s: <25} {s: <10} {s: <15} [Score: {d}/100]",
            .{ security_icon, pkg.name, pkg.version, pkg.network, pkg.security_score },
        );
        defer allocator.free(line);
        try package_list.addItemText(line);
    }

    try app.addWidget(&package_list.widget);

    const divider2 = try phantom.widgets.Text.initWithStyle(
        allocator,
        "═══════════════════════════════════════════════════════════════════════",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&divider2.widget);

    // Stats
    const stats = try phantom.widgets.Text.initWithStyle(
        allocator,
        "📊 Total: 12 packages | 🛡️  Avg Security: 88/100 | ⚠️  Alerts: 0",
        phantom.Style.default().withFg(phantom.Color.bright_yellow),
    );
    try app.addWidget(&stats.widget);

    const instructions = try phantom.widgets.Text.initWithStyle(
        allocator,
        "↑/↓ Navigate • Enter View Details • q/Ctrl+C Exit",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&instructions.widget);

    try app.event_loop.addHandler(handleEvent);
    try app.run();
}

fn getSecurityIcon(score: u8) []const u8 {
    return if (score >= 90) "🛡️ " else if (score >= 80) "✅" else if (score >= 70) "⚠️ " else "🚨";
}

fn handleEvent(event: phantom.Event) !bool {
    switch (event) {
        .key => |key| {
            if (key == .ctrl_c or key.isChar('q')) {
                global_app.stop();
                return true;
            }
        },
        else => {},
    }
    return false;
}
