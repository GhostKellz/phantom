//! Fuzzy Search Demo - Demonstrates the theme picker with fuzzy search
//! Shows advanced search capabilities and interactive theme selection

const std = @import("std");
const phantom = @import("phantom");
const vxfw = phantom.vxfw;
const ThemePicker = phantom.widgets.ThemePicker;
const FuzzySearch = phantom.search;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize phantom TUI
    var app = try phantom.App.init(allocator, phantom.AppConfig{});
    defer app.deinit();

    // Create demo application
    var demo = try FuzzySearchDemo.init(allocator);
    defer demo.deinit();

    // Set root widget
    app.setRootWidget(demo.widget());

    // Run application
    try app.run();
}

const FuzzySearchDemo = struct {
    allocator: std.mem.Allocator,
    theme_picker: ThemePicker,
    selected_theme: ?FuzzySearch.ThemeInfo = null,
    show_help: bool = true,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        var theme_picker = try ThemePicker.init(allocator);

        // Add some additional custom themes
        try theme_picker.addTheme(.{
            .name = "Ghostty Terminal",
            .description = "Custom theme for ghostty terminal emulator",
            .category = .terminal,
            .tags = null,
        });

        try theme_picker.addTheme(.{
            .name = "Phantom UI",
            .description = "Theme designed for Phantom TUI framework",
            .category = .colorful,
            .tags = null,
        });

        try theme_picker.addTheme(.{
            .name = "Cyberpunk 2077",
            .description = "Futuristic neon theme inspired by cyberpunk aesthetics",
            .category = .colorful,
            .tags = null,
        });

        return Self{
            .allocator = allocator,
            .theme_picker = theme_picker,
        };
    }

    pub fn deinit(self: *Self) void {
        self.theme_picker.deinit();
    }

    pub fn widget(self: *Self) vxfw.Widget {
        return vxfw.Widget{
            .userdata = self,
            .drawFn = typeErasedDrawFn,
            .eventHandlerFn = typeErasedEventHandler,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) std.mem.Allocator.Error!vxfw.CommandList {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.handleEvent(ctx);
    }

    fn draw(self: *Self, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        var surface = try vxfw.Surface.init(ctx.arena, undefined, ctx.min);

        // Calculate layout
        const header_height = 3;
        const footer_height = if (self.show_help) @as(u16, 6) else @as(u16, 2);
        const picker_height = if (ctx.min.height > header_height + footer_height)
            ctx.min.height - header_height - footer_height
        else
            @as(u16, 5);

        // Draw header
        try self.drawHeader(&surface, phantom.geometry.Rect{
            .x = 0,
            .y = 0,
            .width = ctx.min.width,
            .height = header_height,
        });

        // Draw theme picker
        const picker_ctx = vxfw.DrawContext{
            .arena = ctx.arena,
            .min = phantom.geometry.Size{
                .width = ctx.min.width,
                .height = picker_height,
            },
        };
        const picker_surface = try self.theme_picker.widget().draw(picker_ctx);

        // Blit picker surface
        try surface.blit(picker_surface, phantom.geometry.Point{
            .x = 0,
            .y = header_height,
        });

        // Draw footer
        try self.drawFooter(&surface, phantom.geometry.Rect{
            .x = 0,
            .y = header_height + picker_height,
            .width = ctx.min.width,
            .height = footer_height,
        });

        return surface;
    }

    fn drawHeader(self: *Self, surface: *vxfw.Surface, rect: phantom.geometry.Rect) !void {
        // Title
        const title = "🎨 Phantom Theme Picker - Fuzzy Search Demo";
        try surface.writeText(
            phantom.geometry.Point{ .x = rect.x + 1, .y = rect.y },
            title,
            phantom.style.Style.default().withBold(true)
        );

        // Subtitle
        const subtitle = "Type to search themes by name, description, or tags";
        try surface.writeText(
            phantom.geometry.Point{ .x = rect.x + 1, .y = rect.y + 1 },
            subtitle,
            phantom.style.Style.default().withDim(true)
        );

        // Selected theme info
        if (self.selected_theme) |theme| {
            const selected_text = try std.fmt.allocPrint(
                self.allocator,
                "Selected: {s} ({s})",
                .{ theme.name, @tagName(theme.category) }
            );
            defer self.allocator.free(selected_text);

            try surface.writeText(
                phantom.geometry.Point{ .x = rect.x + 1, .y = rect.y + 2 },
                selected_text,
                phantom.style.Style.default().withColor(.green)
            );
        } else {
            try surface.writeText(
                phantom.geometry.Point{ .x = rect.x + 1, .y = rect.y + 2 },
                "No theme selected",
                phantom.style.Style.default().withDim(true)
            );
        }
    }

    fn drawFooter(self: *Self, surface: *vxfw.Surface, rect: phantom.geometry.Rect) !void {
        if (self.show_help) {
            const help_lines = [_][]const u8{
                "┌─ Controls ─────────────────────────────────────────┐",
                "│ ↑/↓: Navigate • Enter: Select • Esc: Exit         │",
                "│ Type: Search • Backspace: Delete • H: Toggle Help │",
                "│ 1-6: Filter by category                           │",
                "└───────────────────────────────────────────────────┘",
            };

            for (help_lines, 0..) |line, i| {
                try surface.writeText(
                    phantom.geometry.Point{ .x = rect.x, .y = rect.y + @as(i16, @intCast(i)) },
                    line,
                    phantom.style.Style.default().withDim(true)
                );
            }
        } else {
            try surface.writeText(
                phantom.geometry.Point{ .x = rect.x + 1, .y = rect.y },
                "Press H for help",
                phantom.style.Style.default().withDim(true)
            );
        }
    }

    fn handleEvent(self: *Self, ctx: vxfw.EventContext) std.mem.Allocator.Error!vxfw.CommandList {
        var commands = vxfw.CommandList.init(ctx.arena);

        switch (ctx.event) {
            .key_press => |key| {
                switch (key.key) {
                    .escape => {
                        // Exit application
                        try commands.append(.{ .user = .{
                            .name = "exit",
                            .data = null,
                        }});
                    },
                    .character => {
                        // Handle category filters
                        if (key.key == .character) {
                            // This is simplified - would need actual character handling
                            switch (key.key) {
                                .f1 => {
                                    try self.theme_picker.setCategory(.dark);
                                    try commands.append(.redraw);
                                },
                                .f2 => {
                                    try self.theme_picker.setCategory(.light);
                                    try commands.append(.redraw);
                                },
                                .f3 => {
                                    try self.theme_picker.setCategory(.high_contrast);
                                    try commands.append(.redraw);
                                },
                                .f4 => {
                                    try self.theme_picker.setCategory(.colorful);
                                    try commands.append(.redraw);
                                },
                                .f5 => {
                                    try self.theme_picker.setCategory(.terminal);
                                    try commands.append(.redraw);
                                },
                                .f6 => {
                                    try self.theme_picker.setCategory(null); // Clear filter
                                    try commands.append(.redraw);
                                },
                                else => {
                                    // Forward to theme picker
                                    const picker_commands = try self.theme_picker.widget().handleEvent(ctx);
                                    for (picker_commands.items) |cmd| {
                                        try commands.append(cmd);
                                    }
                                },
                            }
                        }
                    },
                    else => {
                        // Forward other keys to theme picker
                        const picker_commands = try self.theme_picker.widget().handleEvent(ctx);
                        for (picker_commands.items) |cmd| {
                            try commands.append(cmd);
                        }
                    },
                }
            },
            .user => |user_event| {
                if (std.mem.eql(u8, user_event.name, "theme_selected")) {
                    self.selected_theme = @as(*const FuzzySearch.ThemeInfo, @ptrCast(@alignCast(user_event.data.?))).*;
                    try commands.append(.redraw);
                } else if (std.mem.eql(u8, user_event.name, "theme_picker_cancel")) {
                    try commands.append(.{ .user = .{
                        .name = "exit",
                        .data = null,
                    }});
                }
            },
            else => {
                // Forward to theme picker
                const picker_commands = try self.theme_picker.widget().handleEvent(ctx);
                for (picker_commands.items) |cmd| {
                    try commands.append(cmd);
                }
            },
        }

        return commands;
    }
};