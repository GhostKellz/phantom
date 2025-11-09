//! Reaper AUR Dependencies - Interactive TUI Demo
//! Shows a proper package manager interface with dependency tree
const std = @import("std");
const phantom = @import("phantom");

var global_app: *phantom.App = undefined;
var dep_list: *phantom.widgets.List = undefined;

const DependencyType = enum {
    depends,
    makedepends,
    optdepends,

    pub fn getIcon(self: DependencyType) []const u8 {
        return switch (self) {
            .depends => "🔗",
            .makedepends => "🔨",
            .optdepends => "⭐",
        };
    }

    pub fn getColor(self: DependencyType) phantom.Color {
        return switch (self) {
            .depends => phantom.Color.bright_green,
            .makedepends => phantom.Color.bright_yellow,
            .optdepends => phantom.Color.bright_blue,
        };
    }
};

const Dependency = struct {
    name: []const u8,
    repo: []const u8,
    dep_type: DependencyType,
    installed: bool,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try phantom.App.init(allocator, .{
        .title = "REAPER AUR Dependencies",
        .tick_rate_ms = 16,
        .mouse_enabled = false,
    });
    defer app.deinit();
    global_app = &app;

    // Header
    const header = try phantom.widgets.Text.initWithStyle(
        allocator,
        "🎵 REAPER - Digital Audio Workstation",
        phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold(),
    );
    try app.addWidget(&header.widget);

    const subtitle = try phantom.widgets.Text.initWithStyle(
        allocator,
        "AUR Package Dependencies Viewer",
        phantom.Style.default().withFg(phantom.Color.bright_green),
    );
    try app.addWidget(&subtitle.widget);

    const divider = try phantom.widgets.Text.initWithStyle(
        allocator,
        "═══════════════════════════════════════════════════════════════",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&divider.widget);

    // Dependency list
    dep_list = try phantom.widgets.List.init(allocator);
    dep_list.setItemStyle(phantom.Style.default());
    dep_list.setSelectedStyle(
        phantom.Style.default()
            .withBg(phantom.Color.blue)
            .withFg(phantom.Color.white)
            .withBold(),
    );

    // Add REAPER dependencies
    const deps = [_]Dependency{
        .{ .name = "glibc", .repo = "core", .dep_type = .depends, .installed = true },
        .{ .name = "alsa-lib", .repo = "extra", .dep_type = .depends, .installed = true },
        .{ .name = "jack2", .repo = "extra", .dep_type = .depends, .installed = false },
        .{ .name = "libx11", .repo = "extra", .dep_type = .depends, .installed = true },
        .{ .name = "gtk3", .repo = "extra", .dep_type = .depends, .installed = true },
        .{ .name = "wine", .repo = "extra", .dep_type = .optdepends, .installed = false },
        .{ .name = "vst-bridge", .repo = "aur", .dep_type = .optdepends, .installed = false },
        .{ .name = "pulseaudio", .repo = "extra", .dep_type = .optdepends, .installed = true },
        .{ .name = "pipewire", .repo = "extra", .dep_type = .optdepends, .installed = false },
        .{ .name = "unzip", .repo = "extra", .dep_type = .makedepends, .installed = true },
        .{ .name = "p7zip", .repo = "extra", .dep_type = .makedepends, .installed = true },
        .{ .name = "ardour", .repo = "community", .dep_type = .optdepends, .installed = false },
        .{ .name = "linvst", .repo = "aur", .dep_type = .optdepends, .installed = false },
        .{ .name = "yabridge", .repo = "aur", .dep_type = .optdepends, .installed = false },
        .{ .name = "reaper-bin", .repo = "aur", .dep_type = .depends, .installed = false },
    };

    for (deps) |dep| {
        const status_icon = if (dep.installed) "✅" else "📦";
        const line = try std.fmt.allocPrint(
            allocator,
            "{s} {s} {s: <20} [{s: <10}] {s}",
            .{ dep.dep_type.getIcon(), status_icon, dep.name, dep.repo, if (dep.installed) "installed" else "available" },
        );
        defer allocator.free(line);
        try dep_list.addItemText(line);
    }

    try app.addWidget(&dep_list.widget);

    const divider2 = try phantom.widgets.Text.initWithStyle(
        allocator,
        "═══════════════════════════════════════════════════════════════",
        phantom.Style.default().withFg(phantom.Color.bright_black),
    );
    try app.addWidget(&divider2.widget);

    // Stats
    const stats = try phantom.widgets.Text.initWithStyle(
        allocator,
        "📊 Total: 15 deps | ✅ Installed: 7 | 📦 Available: 8",
        phantom.Style.default().withFg(phantom.Color.bright_yellow),
    );
    try app.addWidget(&stats.widget);

    const instructions = try phantom.widgets.Text.initWithStyle(
        allocator,
        "↑/↓ Navigate • q/Ctrl+C Exit",
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
        else => {},
    }
    return false;
}
