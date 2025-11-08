//! Theme Gallery Demo - Explore manifest-driven themes with live reload
//! Demonstrates runtime manifest loading, theme switching, and token previews

const std = @import("std");
const phantom = @import("phantom");

const ThemeManager = phantom.theme.ThemeManager;
const ManifestLoader = phantom.theme.ManifestLoader;
const Theme = phantom.theme.Theme;
const Color = phantom.Color;
const Style = phantom.Style;

const ThemeGalleryUI = struct {
    allocator: std.mem.Allocator,
    manager: *ThemeManager,
    loader: *ManifestLoader,
    app: *phantom.App,

    title: *phantom.widgets.Text,
    subtitle: *phantom.widgets.Text,
    instructions: *phantom.widgets.Text,
    theme_list: *phantom.widgets.List,
    preview_header: *phantom.widgets.Text,
    preview_surface: *phantom.widgets.Text,
    preview_notice: *phantom.widgets.Text,
    status: *phantom.widgets.Text,

    tick_counter: u32 = 0,

    pub fn create(
        allocator: std.mem.Allocator,
        manager: *ThemeManager,
        loader: *ManifestLoader,
        app: *phantom.App,
    ) !*ThemeGalleryUI {
        const self = try allocator.create(ThemeGalleryUI);
        errdefer allocator.destroy(self);

        const theme = manager.getActiveTheme();

        self.* = ThemeGalleryUI{
            .allocator = allocator,
            .manager = manager,
            .loader = loader,
            .app = app,
            .title = undefined,
            .subtitle = undefined,
            .instructions = undefined,
            .theme_list = undefined,
            .preview_header = undefined,
            .preview_surface = undefined,
            .preview_notice = undefined,
            .status = undefined,
        };

        self.title = try phantom.widgets.Text.initWithStyle(
            allocator,
            "🎨 Phantom Theme Gallery",
            Style.default().withFg(getAccentColor(theme)).withBold(),
        );

        self.subtitle = try phantom.widgets.Text.initWithStyle(
            allocator,
            "Manifest loader + token-driven widgets",
            Style.default().withFg(theme.colors.text_muted),
        );

        self.instructions = try phantom.widgets.Text.initWithStyle(
            allocator,
            "↑/↓ navigate • Enter activate • R reload manifests • Q quit",
            Style.default().withFg(theme.colors.text_muted).withItalic(),
        );

        self.theme_list = try phantom.widgets.List.init(allocator);

        self.preview_header = try phantom.widgets.Text.init(allocator, "Accent preview");
        self.preview_surface = try phantom.widgets.Text.init(allocator, "Surface preview");
        self.preview_notice = try phantom.widgets.Text.init(allocator, "Notice preview");
        self.status = try phantom.widgets.Text.init(allocator, "Loading themes...");

        try self.refreshThemeList();
        try self.updateThemeDrivenStyles();
        try self.updateActiveThemeInfo();

        try app.addWidget(&self.title.widget);
        try app.addWidget(&self.subtitle.widget);
        try app.addWidget(&self.instructions.widget);
        try app.addWidget(&self.theme_list.widget);
        try app.addWidget(&self.preview_header.widget);
        try app.addWidget(&self.preview_surface.widget);
        try app.addWidget(&self.preview_notice.widget);
        try app.addWidget(&self.status.widget);

        return self;
    }

    pub fn deinit(self: *ThemeGalleryUI) void {
        self.title.widget.deinit();
        self.subtitle.widget.deinit();
        self.instructions.widget.deinit();
        self.theme_list.widget.deinit();
        self.preview_header.widget.deinit();
        self.preview_surface.widget.deinit();
        self.preview_notice.widget.deinit();
        self.status.widget.deinit();
        self.allocator.destroy(self);
    }

    fn refreshThemeList(self: *ThemeGalleryUI) !void {
        self.theme_list.clear();

        const names = try self.manager.listThemes(self.allocator);
        defer self.allocator.free(names);

        std.sort.sort([]const u8, names, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        const active_key = self.manager.active_theme_name;
        var active_index: ?usize = null;

        for (names, 0..) |name, idx| {
            try self.theme_list.addItemText(name);
            if (active_index == null and std.mem.eql(u8, name, active_key)) {
                active_index = idx;
            }
        }

        if (active_index) |idx| {
            self.theme_list.selected_index = idx;
        } else if (self.theme_list.items.items.len > 0) {
            self.theme_list.selected_index = 0;
        }
    }

    fn updateThemeDrivenStyles(self: *ThemeGalleryUI) !void {
        const theme = self.manager.getActiveTheme();

        const accent = getAccentColor(theme);
        const surface = theme.getPaletteColor("surface") orelse theme.colors.background_panel;
        const text = theme.colors.text;
        const text_muted = theme.colors.text_muted;

        self.title.setStyle(Style.default().withFg(accent).withBold());
        self.subtitle.setStyle(Style.default().withFg(text_muted));
        self.instructions.setStyle(Style.default().withFg(text_muted).withItalic());

        self.theme_list.setItemStyle(Style.default().withFg(text));
        self.theme_list.setSelectedStyle(Style.default().withFg(theme.colors.background).withBg(accent).withBold());

        self.preview_header.setStyle(Style.default().withFg(theme.colors.background).withBg(accent).withBold());
        self.preview_surface.setStyle(Style.default().withFg(text).withBg(surface));
        const notice_color = theme.getPaletteColor("success") orelse theme.colors.success;
        self.preview_notice.setStyle(Style.default().withFg(theme.colors.background).withBg(notice_color).withBold());

        const header_line = try self.formatPreviewLine("Accent", accent);
        defer self.allocator.free(header_line);
        try self.preview_header.setContent(header_line);

        const surface_line = try self.formatPreviewLine("Surface", surface);
        defer self.allocator.free(surface_line);
        try self.preview_surface.setContent(surface_line);

        const notice_line = try self.formatPreviewLine("Notice", notice_color);
        defer self.allocator.free(notice_line);
        try self.preview_notice.setContent(notice_line);

        // Reapply selected index for the active theme in case ordering changed
        const active_key = self.manager.active_theme_name;
        if (self.theme_list.items.items.len > 0) {
            for (self.theme_list.items.items, 0..) |item, idx| {
                if (std.mem.eql(u8, item.text, active_key)) {
                    self.theme_list.selected_index = idx;
                    break;
                }
            }
        }
    }

    fn updateActiveThemeInfo(self: *ThemeGalleryUI) !void {
        const theme = self.manager.getActiveTheme();
        const status_msg = try std.fmt.allocPrint(
            self.allocator,
            "Active theme: {s} ({s} variant, {s})",
            .{ theme.name, @tagName(theme.variant), @tagName(theme.origin) },
        );
        defer self.allocator.free(status_msg);
        try self.status.setContent(status_msg);
    }

    fn formatPreviewLine(self: *ThemeGalleryUI, label: []const u8, color: Color) ![]const u8 {
        const color_name = try describeColor(self.allocator, color);
        defer self.allocator.free(color_name);
        return std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ label, color_name });
    }

    fn activateSelectedTheme(self: *ThemeGalleryUI) !void {
        if (self.theme_list.getSelectedItem()) |item| {
            try self.manager.setTheme(item.text);
            try self.updateThemeDrivenStyles();
            try self.updateActiveThemeInfo();
            self.setStatusMessage("✅ Theme activated");
            self.app.invalidate();
        } else {
            self.setStatusMessage("⚠ No theme selected");
        }
    }

    fn refreshFromDisk(self: *ThemeGalleryUI) void {
        self.loader.refresh();
        self.setStatusMessage("🔄 Reloaded manifest files");
        self.refreshThemeList() catch |err| {
            std.log.err("failed to refresh theme list: {}", .{err});
        };
        self.updateThemeDrivenStyles() catch |err| {
            std.log.err("failed to update theme styles: {}", .{err});
        };
        self.updateActiveThemeInfo() catch |err| {
            std.log.err("failed to update active theme info: {}", .{err});
        };
        self.app.invalidate();
    }

    fn setStatusMessage(self: *ThemeGalleryUI, message: []const u8) void {
        const dup = std.fmt.allocPrint(self.allocator, "{s}", .{message}) catch return;
        defer self.allocator.free(dup);
        self.status.setContent(dup) catch return;
    }

    fn tick(self: *ThemeGalleryUI) void {
        self.tick_counter += 1;
        if (self.tick_counter % 30 == 0) { // roughly every half second at 60 FPS
            self.refreshFromDisk();
        }
    }

    fn handleKey(self: *ThemeGalleryUI, key: phantom.Key) !bool {
        switch (key) {
            .enter => {
                try self.activateSelectedTheme();
                return true;
            },
            .char => |codepoint| {
                switch (codepoint) {
                    'r', 'R' => {
                        self.refreshFromDisk();
                        return true;
                    },
                    'q', 'Q' => {
                        self.app.stop();
                        return true;
                    },
                    else => {},
                }
            },
            .ctrl_r => {
                self.refreshFromDisk();
                return true;
            },
            else => {},
        }
        return false;
    }

    pub fn handleEvent(self: *ThemeGalleryUI, event: phantom.Event) !bool {
        switch (event) {
            .key => |key| return self.handleKey(key),
            .tick => {
                self.tick();
                return false;
            },
            else => return false,
        }
    }
};

fn getAccentColor(theme: *const Theme) Color {
    return theme.getPaletteColor("accent") orelse theme.colors.accent;
}

fn describeColor(allocator: std.mem.Allocator, color: Color) ![]const u8 {
    return switch (color) {
        .rgb => |rgb| std.fmt.allocPrint(allocator, "#{X:0>2}{X:0>2}{X:0>2}", .{ rgb.r, rgb.g, rgb.b }),
        else => std.fmt.allocPrint(allocator, "{s}", .{@tagName(color)}),
    };
}

var global_ui: ?*ThemeGalleryUI = null;

fn galleryEventHandler(event: phantom.Event) !bool {
    const ui = global_ui orelse return false;
    return ui.handleEvent(event);
}

fn registerSampleManifests(allocator: std.mem.Allocator, loader: *ManifestLoader) !void {
    const samples = [_]struct {
        name: []const u8,
        path: []const u8,
        auto_activate: bool,
    }{
        .{ .name = "phantom-daybreak", .path = "examples/themes/phantom-daybreak.json", .auto_activate = false },
        .{ .name = "phantom-nightfall", .path = "examples/themes/phantom-nightfall.json", .auto_activate = true },
    };

    for (samples) |sample| {
        const absolute = try std.fs.cwd().realpathAlloc(allocator, sample.path);
        defer allocator.free(absolute);
        try loader.registerFile(sample.name, absolute, .{
            .origin = .dynamic,
            .auto_activate = sample.auto_activate,
        });
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = try ThemeManager.init(allocator);
    defer manager.deinit();

    var loader = ManifestLoader.init(allocator, manager);
    defer loader.deinit();

    try registerSampleManifests(allocator, &loader);

    var app = try phantom.App.init(allocator, .{
        .title = "Phantom Theme Gallery",
        .tick_rate_ms = 60,
        .mouse_enabled = true,
    });
    defer app.deinit();

    const ui = try ThemeGalleryUI.create(allocator, manager, &loader, &app);
    global_ui = ui;
    defer {
        global_ui = null;
        ui.deinit();
    }

    try app.event_loop.addHandler(galleryEventHandler);

    std.debug.print("\nPhantom Theme Gallery\n", .{});
    std.debug.print("======================\n", .{});
    std.debug.print("Available themes are loaded from JSON manifests.\n", .{});
    std.debug.print("Edit the files under examples/themes and press R to hot-reload.\n\n", .{});

    try app.run();
}
