//! ThemePicker - Interactive theme selection widget with fuzzy search
//! Provides a searchable, filterable interface for theme selection

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const FuzzySearch = @import("../search/FuzzySearch.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Rect = geometry.Rect;
const Point = geometry.Point;
const Style = style.Style;

/// Interactive theme picker widget with fuzzy search
pub const ThemePicker = struct {
    allocator: Allocator,
    fuzzy_search: FuzzySearch.ThemeFuzzySearch,
    search_query: std.array_list.AlignedManaged(u8, null),
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    visible_items: usize = 10,
    search_results: []FuzzySearch.ThemeSearchResult,
    show_descriptions: bool = true,
    category_filter: ?FuzzySearch.ThemeCategory = null,

    const Self = @This();

    pub fn init(allocator: Allocator) !ThemePicker {
        var fuzzy_search = FuzzySearch.ThemeFuzzySearch.init(allocator);

        // Add some default themes for demonstration
        try addDefaultThemes(&fuzzy_search);

        return ThemePicker{
            .allocator = allocator,
            .fuzzy_search = fuzzy_search,
            .search_query = std.array_list.AlignedManaged(u8, null).init(allocator),
            .search_results = &[_]FuzzySearch.ThemeSearchResult{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.fuzzy_search.deinit();
        self.search_query.deinit();
        for (self.search_results) |result| {
            result.deinit(self.allocator);
        }
        self.allocator.free(self.search_results);
    }

    /// Add a theme to the picker
    pub fn addTheme(self: *Self, theme: FuzzySearch.ThemeInfo) !void {
        try self.fuzzy_search.addTheme(theme);
        try self.refreshSearch();
    }

    /// Set category filter
    pub fn setCategory(self: *Self, category: ?FuzzySearch.ThemeCategory) !void {
        self.category_filter = category;
        try self.refreshSearch();
    }

    /// Update search query
    pub fn setQuery(self: *Self, query: []const u8) !void {
        self.search_query.clearRetainingCapacity();
        try self.search_query.appendSlice(query);
        try self.refreshSearch();
        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    /// Add character to search query
    pub fn addToQuery(self: *Self, char: u8) !void {
        try self.search_query.append(char);
        try self.refreshSearch();
        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    /// Remove last character from search query
    pub fn backspace(self: *Self) !void {
        if (self.search_query.items.len > 0) {
            _ = self.search_query.pop();
            try self.refreshSearch();
            self.selected_index = 0;
            self.scroll_offset = 0;
        }
    }

    /// Move selection up
    pub fn selectPrevious(self: *Self) void {
        if (self.search_results.len == 0) return;

        if (self.selected_index > 0) {
            self.selected_index -= 1;
        } else {
            self.selected_index = self.search_results.len - 1;
        }
        self.adjustScrollOffset();
    }

    /// Move selection down
    pub fn selectNext(self: *Self) void {
        if (self.search_results.len == 0) return;

        if (self.selected_index < self.search_results.len - 1) {
            self.selected_index += 1;
        } else {
            self.selected_index = 0;
        }
        self.adjustScrollOffset();
    }

    /// Get currently selected theme
    pub fn getSelectedTheme(self: *Self) ?FuzzySearch.ThemeInfo {
        if (self.search_results.len == 0 or self.selected_index >= self.search_results.len) {
            return null;
        }
        return self.search_results[self.selected_index].theme;
    }

    /// Create widget interface
    pub fn widget(self: *Self) vxfw.Widget {
        return vxfw.Widget{
            .userdata = self,
            .drawFn = typeErasedDrawFn,
            .eventHandlerFn = typeErasedEventHandler,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.handleEvent(ctx);
    }

    fn draw(self: *Self, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        var surface = try vxfw.Surface.init(ctx.arena, undefined, ctx.min);

        // Calculate layout
        const search_box_height = 3;
        const content_height = if (ctx.min.height > search_box_height)
            ctx.min.height - search_box_height
        else
            0;

        // Draw search box
        try self.drawSearchBox(&surface, Rect{
            .x = 0,
            .y = 0,
            .width = ctx.min.width,
            .height = search_box_height,
        });

        // Draw theme list
        if (content_height > 0) {
            try self.drawThemeList(&surface, Rect{
                .x = 0,
                .y = search_box_height,
                .width = ctx.min.width,
                .height = content_height,
            });
        }

        return surface;
    }

    fn drawSearchBox(self: *Self, surface: *vxfw.Surface, rect: Rect) !void {
        // Draw border
        try surface.setBorder(rect, Style.default().withBorder(true));

        // Draw search prompt and query
        const prompt = "Search themes: ";
        const search_text = try std.fmt.allocPrint(
            self.allocator,
            "{s}{s}",
            .{ prompt, self.search_query.items }
        );
        defer self.allocator.free(search_text);

        try surface.writeText(Point{ .x = rect.x + 1, .y = rect.y + 1 }, search_text, Style.default());

        // Draw cursor
        const cursor_x = rect.x + 1 + prompt.len + self.search_query.items.len;
        if (cursor_x < rect.x + rect.width - 1) {
            try surface.setCell(
                cursor_x,
                rect.y + 1,
                '█',
                Style.default().withReverse(true)
            );
        }

        // Show result count
        if (rect.height > 2) {
            const status = try std.fmt.allocPrint(
                self.allocator,
                "Found {d} themes",
                .{self.search_results.len}
            );
            defer self.allocator.free(status);

            try surface.writeText(
                Point{ .x = rect.x + 1, .y = rect.y + 2 },
                status,
                Style.default().withDim(true)
            );
        }
    }

    fn drawThemeList(self: *Self, surface: *vxfw.Surface, rect: Rect) !void {
        if (self.search_results.len == 0) {
            try surface.writeText(
                Point{ .x = rect.x + 1, .y = rect.y + 1 },
                "No themes found",
                Style.default().withDim(true)
            );
            return;
        }

        self.visible_items = rect.height;

        // Calculate visible range
        const end_index = @min(
            self.scroll_offset + self.visible_items,
            self.search_results.len
        );

        // Draw themes
        for (self.search_results[self.scroll_offset..end_index], 0..) |result, display_index| {
            const y = rect.y + display_index;
            const actual_index = self.scroll_offset + display_index;
            const is_selected = actual_index == self.selected_index;

            try self.drawThemeItem(surface, result, Point{ .x = rect.x, .y = y }, rect.width, is_selected);
        }

        // Draw scrollbar if needed
        if (self.search_results.len > self.visible_items) {
            try self.drawScrollbar(surface, rect);
        }
    }

    fn drawThemeItem(self: *Self, surface: *vxfw.Surface, result: FuzzySearch.ThemeSearchResult, pos: Point, width: u16, is_selected: bool) !void {
        const theme = result.theme;

        // Selection background
        if (is_selected) {
            for (0..width) |i| {
                try surface.setCell(
                    pos.x + @as(u16, @intCast(i)),
                    pos.y,
                    ' ',
                    Style.default().withReverse(true)
                );
            }
        }

        // Create highlighted theme name
        const highlighted_name = try FuzzySearch.createHighlightedText(
            self.allocator,
            theme.name,
            result.highlight_positions,
            "",  // We'll handle highlighting with styles
            ""
        );
        defer self.allocator.free(highlighted_name);

        // Theme name with category indicator
        const category_char = switch (theme.category) {
            .dark => "🌙",
            .light => "☀",
            .high_contrast => "🔆",
            .colorful => "🎨",
            .minimal => "⚪",
            .terminal => "💻",
            .editor => "📝",
        };

        const name_text = try std.fmt.allocPrint(
            self.allocator,
            "{s} {s}",
            .{ category_char, highlighted_name }
        );
        defer self.allocator.free(name_text);

        var base_style = if (is_selected)
            Style.default().withReverse(true)
        else
            Style.default();

        // Add bold for exact matches
        if (result.score > 0.8) {
            base_style = base_style.withBold(true);
        }

        try surface.writeText(Point{ .x = pos.x + 1, .y = pos.y }, name_text, base_style);

        // Show description if enabled and there's space
        if (self.show_descriptions and width > 40) {
            const desc_start = @min(name_text.len + 2, width - 20);
            if (desc_start < width - 1) {
                const max_desc_len = width - desc_start - 1;
                const description = if (theme.description.len > max_desc_len)
                    theme.description[0..max_desc_len]
                else
                    theme.description;

                try surface.writeText(
                    Point{ .x = pos.x + desc_start, .y = pos.y },
                    description,
                    base_style.withDim(true)
                );
            }
        }
    }

    fn drawScrollbar(self: *Self, surface: *vxfw.Surface, rect: Rect) !void {
        const scrollbar_x = rect.x + rect.width - 1;
        const scrollbar_height = rect.height;

        // Calculate scrollbar thumb position and size
        const thumb_size = @max(1, (scrollbar_height * self.visible_items) / self.search_results.len);
        const thumb_pos = (scrollbar_height * self.scroll_offset) / self.search_results.len;

        // Draw scrollbar track
        for (0..scrollbar_height) |i| {
            const y = rect.y + i;
            const is_thumb = i >= thumb_pos and i < thumb_pos + thumb_size;

            try surface.setCell(
                scrollbar_x,
                @intCast(y),
                if (is_thumb) '█' else '░',
                Style.default().withDim(!is_thumb)
            );
        }
    }

    fn handleEvent(self: *Self, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
        var commands = vxfw.CommandList.init(ctx.arena);

        switch (ctx.event) {
            .key_press => |key| {
                switch (key.key) {
                    .up => self.selectPrevious(),
                    .down => self.selectNext(),
                    .enter => {
                        if (self.getSelectedTheme()) |theme| {
                            // Emit theme selection event
                            try commands.append(.{ .user = .{
                                .name = "theme_selected",
                                .data = @ptrCast(&theme),
                            }});
                        }
                    },
                    .backspace => {
                        try self.backspace();
                        try commands.append(.redraw);
                    },
                    .character => {
                        // Get the actual character from somewhere - this is simplified
                        if (key.key == .character) {
                            try self.addToQuery('a'); // Placeholder - would need actual character
                            try commands.append(.redraw);
                        }
                    },
                    .escape => {
                        try commands.append(.{ .user = .{
                            .name = "theme_picker_cancel",
                            .data = null,
                        }});
                    },
                    else => {},
                }
            },
            .init => {
                try self.refreshSearch();
                try commands.append(.redraw);
            },
            else => {},
        }

        return commands;
    }

    fn refreshSearch(self: *Self) !void {
        // Free old results
        for (self.search_results) |result| {
            result.deinit(self.allocator);
        }
        self.allocator.free(self.search_results);

        // Perform new search
        self.search_results = try self.fuzzy_search.searchThemes(self.search_query.items);

        // Apply category filter if set
        if (self.category_filter) |filter| {
            var filtered = std.ArrayList(FuzzySearch.ThemeSearchResult).init(self.allocator);
            for (self.search_results) |result| {
                if (result.theme.category == filter) {
                    try filtered.append(result);
                } else {
                    result.deinit(self.allocator);
                }
            }
            self.allocator.free(self.search_results);
            self.search_results = try filtered.toOwnedSlice();
        }
    }

    fn adjustScrollOffset(self: *Self) void {
        if (self.selected_index < self.scroll_offset) {
            self.scroll_offset = self.selected_index;
        } else if (self.selected_index >= self.scroll_offset + self.visible_items) {
            self.scroll_offset = self.selected_index - self.visible_items + 1;
        }
    }
};

/// Add some default themes for demonstration
fn addDefaultThemes(fuzzy_search: *FuzzySearch.ThemeFuzzySearch) !void {
    const themes = [_]FuzzySearch.ThemeInfo{
        .{
            .name = "Dracula",
            .description = "Dark theme with vibrant colors",
            .category = .dark,
            .tags = null,
        },
        .{
            .name = "Solarized Dark",
            .description = "Precision colors for machines and people",
            .category = .dark,
            .tags = null,
        },
        .{
            .name = "Solarized Light",
            .description = "Light variant of the solarized theme",
            .category = .light,
            .tags = null,
        },
        .{
            .name = "Monokai",
            .description = "Sublime Text's default color scheme",
            .category = .dark,
            .tags = null,
        },
        .{
            .name = "One Dark",
            .description = "Atom's iconic One Dark theme",
            .category = .dark,
            .tags = null,
        },
        .{
            .name = "Gruvbox",
            .description = "Retro groove color scheme",
            .category = .dark,
            .tags = null,
        },
        .{
            .name = "Nord",
            .description = "Arctic, north-bluish color palette",
            .category = .dark,
            .tags = null,
        },
        .{
            .name = "Tokyo Night",
            .description = "Clean, dark theme inspired by Tokyo's neon lights",
            .category = .dark,
            .tags = null,
        },
        .{
            .name = "Catppuccin",
            .description = "Soothing pastel theme for developers",
            .category = .dark,
            .tags = null,
        },
        .{
            .name = "Ayu Light",
            .description = "Simple theme with bright colors",
            .category = .light,
            .tags = null,
        },
        .{
            .name = "High Contrast",
            .description = "Maximum contrast for accessibility",
            .category = .high_contrast,
            .tags = null,
        },
        .{
            .name = "Terminal Basic",
            .description = "Classic terminal colors",
            .category = .terminal,
            .tags = null,
        },
    };

    for (themes) |theme| {
        try fuzzy_search.addTheme(theme);
    }
}

// Tests
test "theme picker creation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var picker = try ThemePicker.init(arena.allocator());
    defer picker.deinit();

    // Should have default themes loaded
    try std.testing.expect(picker.search_results.len > 0);
}

test "theme search functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var picker = try ThemePicker.init(arena.allocator());
    defer picker.deinit();

    // Search for "dark" themes
    try picker.setQuery("dark");
    try std.testing.expect(picker.search_results.len > 0);

    // All results should be dark themes or mention "dark"
    for (picker.search_results) |result| {
        const has_dark = std.mem.indexOf(u8, result.theme.name, "dark") != null or
                        std.mem.indexOf(u8, result.theme.description, "dark") != null or
                        result.theme.category == .dark;
        try std.testing.expect(has_dark);
    }
}

test "theme selection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var picker = try ThemePicker.init(arena.allocator());
    defer picker.deinit();

    // Test navigation
    const initial_theme = picker.getSelectedTheme();
    picker.selectNext();
    const next_theme = picker.getSelectedTheme();

    if (picker.search_results.len > 1) {
        try std.testing.expect(!std.mem.eql(u8, initial_theme.?.name, next_theme.?.name));
    }
}