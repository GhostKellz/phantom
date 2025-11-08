//! ThemeTokenDashboard - Token-aware visualization of theme colors.
//! Couples Phantom's data sources with theme token insights for dashboards.

const std = @import("std");
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const data = @import("../data/list_source.zig");
const theme_pkg = @import("../theme/mod.zig");
const time_utils = @import("../time/utils.zig");

const Rect = geometry.Rect;
const Style = style.Style;
const Color = style.Color;
const Theme = theme_pkg.Theme;

fn nowMillis() i64 {
    return time_utils.unixTimestampMillis();
}

/// Classifies the provenance of a theme token.
pub const Kind = enum { semantic, palette, syntax, component, custom };

/// Represents a themed token rendered by the dashboard widget.
pub const ThemeToken = struct {
    name: []const u8,
    group: []const u8 = "",
    kind: Kind = .semantic,
    color: Color,
    text_color: Color,
    description: []const u8 = "",
    contrast_ratio: ?f32 = null,
};

/// Token-aware dashboard that renders rows bound to a `ListDataSource`.
pub const ThemeTokenDashboard = struct {
    const Self = @This();
    const SourceType = data.ListDataSource(ThemeToken);
    const ObserverType = data.Observer(ThemeToken);
    const EventType = data.Event(ThemeToken);

    /// Visual configuration for the dashboard.
    pub const Config = struct {
        panel_style: Style = Style.default(),
        title_style: Style = Style.default().withBold(),
        status_style: Style = Style.default().withFg(style.Color.bright_black),
        highlight_status_style: Style = Style.default().withFg(style.Color.bright_green),
        row_style: Style = Style.default(),
        alt_row_style: ?Style = null,
        label_style: Style = Style.default().withFg(style.Color.white),
        description_style: Style = Style.default().withFg(style.Color.bright_black),
        value_style: Style = Style.default().withFg(style.Color.bright_black),
        show_status_line: bool = true,
        show_group_in_label: bool = true,
        auto_follow: bool = true,
        swatch_width: u16 = 6,
        highlight_window_ms: u64 = 1200,
    };

    widget: Widget,
    allocator: std.mem.Allocator,
    source: SourceType,
    observer: ObserverType,
    registered: bool = false,
    title: []const u8,
    config: Config,
    scroll_offset: usize = 0,
    visible_rows: usize = 0,
    follow_tail: bool,
    pending_tail_snap: bool,
    state: data.State,
    event_counter: usize = 0,
    last_update_ms: i64 = 0,
    highlight_until_ms: i64 = 0,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator, source: SourceType, title: []const u8, config: Config) !*Self {
        const title_copy = try allocator.dupe(u8, title);
        errdefer allocator.free(title_copy);

        const ctx_placeholder: *anyopaque = undefined; // Will be set after allocation
        const observer_placeholder = data.makeObserver(ThemeToken, handleSourceEvent, ctx_placeholder);

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .source = source,
            .observer = observer_placeholder,
            .registered = false,
            .title = title_copy,
            .config = config,
            .scroll_offset = 0,
            .visible_rows = 0,
            .follow_tail = config.auto_follow,
            .pending_tail_snap = config.auto_follow,
            .state = source.state(),
            .event_counter = 0,
            .last_update_ms = nowMillis(),
            .highlight_until_ms = 0,
        };

        // Patch observer context now that `self` is allocated.
        self.observer = data.makeObserver(ThemeToken, handleSourceEvent, @ptrCast(self));
        self.source.subscribe(&self.observer);
        self.registered = true;
        return self;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Self = @fieldParentPtr("widget", widget);
        if (area.width == 0 or area.height == 0) return;

        buffer.fill(area, Cell.withStyle(self.config.panel_style));

        var current_y: u16 = area.y;
        const end_y = area.y + area.height;

        if (current_y >= end_y) return;

        // Title row
        buffer.writeText(area.x, current_y, self.title, self.config.title_style);
        current_y += 1;

        const total_items = self.source.len();
        const now = nowMillis();

        if (self.config.show_status_line and current_y < end_y) {
            var status_buf: [128]u8 = undefined;
            const state_name = @tagName(self.state);
            const status_text = std.fmt.bufPrint(
                &status_buf,
                "{d} tokens  •  {s}",
                .{ total_items, state_name },
            ) catch "";

            const status_style = if (now <= self.highlight_until_ms)
                self.config.highlight_status_style
            else
                self.config.status_style;

            buffer.writeText(area.x, current_y, status_text, status_style);
            current_y += 1;
        }

        if (current_y >= end_y) return;

        const available_rows = @as(usize, @intCast(end_y - current_y));
        self.visible_rows = available_rows;

        if (self.pending_tail_snap and self.follow_tail and available_rows != 0) {
            if (total_items > available_rows) {
                self.scroll_offset = total_items - available_rows;
            } else {
                self.scroll_offset = 0;
            }
            self.pending_tail_snap = false;
        }

        const max_offset = if (available_rows == 0) 0 else if (total_items > available_rows) total_items - available_rows else 0;
        if (self.scroll_offset > max_offset) {
            self.scroll_offset = max_offset;
        }

        var index: usize = self.scroll_offset;
        while (index < total_items and current_y < end_y) : (index += 1) {
            if (self.source.get(index)) |token| {
                self.renderRow(buffer, area, current_y, index, token);
            }
            current_y += 1;
        }

        // Indicate more data above/below when scrolled.
        if (self.scroll_offset != 0 and area.width >= 1) {
            buffer.setCell(area.x + area.width - 1, area.y, Cell.init('▲', self.config.status_style));
        }
        if (self.scroll_offset + available_rows < total_items and area.width >= 1) {
            buffer.setCell(area.x + area.width - 1, end_y - 1, Cell.init('▼', self.config.status_style));
        }
    }

    fn renderRow(self: *Self, buffer: *Buffer, area: Rect, y: u16, index: usize, token: ThemeToken) void {
        const row_style = if (self.config.alt_row_style) |alt|
            if ((index & 1) == 1) alt else self.config.row_style
        else
            self.config.row_style;

        buffer.fill(Rect{ .x = area.x, .y = y, .width = area.width, .height = 1 }, Cell.withStyle(row_style));

        const swatch_width = @min(self.config.swatch_width, area.width);
        if (swatch_width > 0) {
            const swatch_rect = Rect{ .x = area.x, .y = y, .width = swatch_width, .height = 1 };
            const swatch_style = Style.default().withBg(token.color).withFg(token.text_color);
            buffer.fill(swatch_rect, Cell.init(' ', swatch_style));
        }

        const content_start = area.x + swatch_width + @as(u16, if (swatch_width == 0) 0 else 1);
        const area_end = area.x + area.width;

        if (content_start >= area_end) return;

        var label_buf: [160]u8 = undefined;
        const label_text = blk: {
            if (self.config.show_group_in_label and token.group.len != 0) {
                break :blk std.fmt.bufPrint(&label_buf, "{s} \u{2022} {s}", .{ token.group, token.name }) catch token.name;
            }
            break :blk token.name;
        };

        var color_buf: [32]u8 = undefined;
        const color_text = formatColorText(token.color, &color_buf);

        var value_buf: [96]u8 = undefined;
        const value_text = blk: {
            if (token.contrast_ratio) |ratio| {
                break :blk std.fmt.bufPrint(&value_buf, "{s}  {d:.1}:1", .{ color_text, ratio }) catch color_text;
            }
            break :blk color_text;
        };

        const max_value_chars = @as(usize, @intCast(area.width));
        const value_len = @min(value_text.len, max_value_chars);
        const value_start_usize = if (value_len >= max_value_chars)
            @as(usize, area.x)
        else
            @as(usize, area.x) + max_value_chars - value_len;
        const value_x = @as(u16, @intCast(value_start_usize));
        buffer.writeText(value_x, y, value_text[0..value_len], self.config.value_style);

        if (content_start >= value_x) return;
        const label_limit = @as(usize, @intCast(value_x - content_start));
        if (label_limit == 0) return;

        const consumed = writeClippedText(buffer, content_start, y, label_text, label_limit, self.config.label_style);

        if (consumed < label_limit and token.description.len != 0) {
            const remaining = label_limit - consumed;
            if (remaining > 2) {
                var desc_buf: [192]u8 = undefined;
                const desc_text = std.fmt.bufPrint(&desc_buf, " – {s}", .{token.description}) catch token.description;
                _ = writeClippedText(buffer, content_start + @as(u16, @intCast(consumed)), y, desc_text, remaining, self.config.description_style);
            }
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Self = @fieldParentPtr("widget", widget);
        switch (event) {
            .key => |key| {
                const total = self.source.len();
                const visible = self.visible_rows;
                const max_offset = if (visible == 0) 0 else if (total > visible) total - visible else 0;

                switch (key) {
                    .up => {
                        if (self.scroll_offset > 0) {
                            self.scroll_offset -= 1;
                            self.follow_tail = self.scroll_offset == max_offset;
                            return true;
                        }
                    },
                    .down => {
                        if (self.scroll_offset < max_offset) {
                            self.scroll_offset += 1;
                            self.follow_tail = self.scroll_offset == max_offset;
                            return true;
                        }
                    },
                    .page_up => {
                        if (visible != 0 and self.scroll_offset > 0) {
                            const delta = if (self.scroll_offset > visible) visible else self.scroll_offset;
                            self.scroll_offset -= delta;
                            self.follow_tail = self.scroll_offset == max_offset;
                            return true;
                        }
                    },
                    .page_down => {
                        if (visible != 0 and self.scroll_offset < max_offset) {
                            const delta = if (self.scroll_offset + visible < max_offset) visible else max_offset - self.scroll_offset;
                            self.scroll_offset += delta;
                            self.follow_tail = self.scroll_offset == max_offset;
                            return true;
                        }
                    },
                    .home => {
                        if (self.scroll_offset != 0) {
                            self.scroll_offset = 0;
                            self.follow_tail = false;
                            return true;
                        }
                    },
                    .end => {
                        if (self.scroll_offset != max_offset) {
                            self.scroll_offset = max_offset;
                            self.follow_tail = true;
                            self.pending_tail_snap = true;
                            return true;
                        }
                    },
                    .char => |c| {
                        switch (c) {
                            'j' => {
                                if (self.scroll_offset < max_offset) {
                                    self.scroll_offset += 1;
                                    self.follow_tail = self.scroll_offset == max_offset;
                                    return true;
                                }
                            },
                            'k' => {
                                if (self.scroll_offset > 0) {
                                    self.scroll_offset -= 1;
                                    self.follow_tail = self.scroll_offset == max_offset;
                                    return true;
                                }
                            },
                            'G' => {
                                self.scroll_offset = max_offset;
                                self.follow_tail = true;
                                self.pending_tail_snap = true;
                                return true;
                            },
                            'g' => {
                                self.scroll_offset = 0;
                                self.follow_tail = false;
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

    fn deinit(widget: *Widget) void {
        const self: *Self = @fieldParentPtr("widget", widget);
        if (self.registered) {
            self.source.unsubscribe(&self.observer);
        }
        self.allocator.free(self.title);
        self.allocator.destroy(self);
    }

    fn onSourceEvent(self: *Self, event: EventType) void {
        switch (event) {
            .reset => {
                self.scroll_offset = 0;
                self.state = .idle;
                self.follow_tail = self.config.auto_follow;
                self.pending_tail_snap = self.follow_tail;
                self.markUpdated();
            },
            .appended => |_| {
                self.event_counter += 1;
                self.state = .ready;
                if (self.follow_tail) self.pending_tail_snap = true;
                self.markUpdated();
            },
            .replaced => |_| {
                self.event_counter += 1;
                self.markUpdated();
            },
            .updated => |_| {
                self.event_counter += 1;
                self.markUpdated();
            },
            .failed => |_| {
                self.state = .failed;
                self.markUpdated();
            },
            .state => |state| {
                self.state = state;
                if (state == .loading and self.config.auto_follow) {
                    self.follow_tail = true;
                    self.pending_tail_snap = true;
                }
                self.markUpdated();
            },
        }
    }

    fn markUpdated(self: *Self) void {
        self.last_update_ms = nowMillis();
        self.highlight_until_ms = self.last_update_ms + @as(i64, @intCast(self.config.highlight_window_ms));
    }

    fn handleSourceEvent(event: EventType, ctx: ?*anyopaque) void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx.?)));
        self.onSourceEvent(event);
    }
};

fn writeClippedText(buffer: *Buffer, x: u16, y: u16, text: []const u8, limit: usize, text_style: Style) usize {
    if (limit == 0) return 0;

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var written: usize = 0;
    var current_x = x;

    while (written < limit and iter.nextCodepoint()) |codepoint| {
        if (current_x >= buffer.size.width) break;
        buffer.setCell(current_x, y, Cell.init(codepoint, text_style));
        current_x += 1;
        written += 1;
    }

    return written;
}

fn formatColorText(color: Color, buffer: []u8) []const u8 {
    return switch (color) {
        .rgb => |rgb| std.fmt.bufPrint(buffer, "#{X:0>2}{X:0>2}{X:0>2}", .{ rgb.r, rgb.g, rgb.b }) catch "#000000",
        .indexed => |idx| std.fmt.bufPrint(buffer, "IDX {d}", .{idx}) catch "IDX",
        else => blk: {
            const name = @tagName(color);
            const len = @min(name.len, buffer.len);
            std.mem.copy(u8, buffer[0..len], name[0..len]);
            for (buffer[0..len]) |*ch| {
                ch.* = std.ascii.toUpper(ch.*);
            }
            break :blk buffer[0..len];
        },
    };
}

fn chooseTextColor(color: Color) Color {
    return switch (color) {
        .rgb => |rgb| blk: {
            const luminance_value = luminance(convertRgbToLinear(.{ rgb.r, rgb.g, rgb.b }));
            break :blk if (luminance_value > 0.5) Color.black else Color.white;
        },
        .bright_white, .bright_yellow, .bright_cyan, .bright_green => Color.black,
        .white, .yellow => Color.black,
        else => Color.white,
    };
}

fn srgbToLinear(component: u8) f64 {
    const c = @as(f64, @floatFromInt(component)) / 255.0;
    return if (c <= 0.04045)
        c / 12.92
    else
        std.math.pow(f64, (c + 0.055) / 1.055, 2.4);
}

fn convertRgbToLinear(rgb: [3]u8) [3]f64 {
    return .{ srgbToLinear(rgb[0]), srgbToLinear(rgb[1]), srgbToLinear(rgb[2]) };
}

fn luminance(linear: [3]f64) f64 {
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
}

fn colorToRgb(color: Color) ?[3]u8 {
    return switch (color) {
        .rgb => |rgb| .{ rgb.r, rgb.g, rgb.b },
        .black => .{ 0, 0, 0 },
        .red => .{ 205, 0, 0 },
        .green => .{ 0, 205, 0 },
        .yellow => .{ 205, 205, 0 },
        .blue => .{ 0, 0, 205 },
        .magenta => .{ 205, 0, 205 },
        .cyan => .{ 0, 205, 205 },
        .white => .{ 229, 229, 229 },
        .bright_black => .{ 127, 127, 127 },
        .bright_red => .{ 255, 0, 0 },
        .bright_green => .{ 0, 255, 0 },
        .bright_yellow => .{ 255, 255, 0 },
        .bright_blue => .{ 92, 92, 255 },
        .bright_magenta => .{ 255, 0, 255 },
        .bright_cyan => .{ 0, 255, 255 },
        .bright_white => .{ 255, 255, 255 },
        else => null,
    };
}

fn computeContrast(a: Color, b: Color) ?f32 {
    const rgb_a = colorToRgb(a) orelse return null;
    const rgb_b = colorToRgb(b) orelse return null;

    const lum_a = luminance(convertRgbToLinear(rgb_a));
    const lum_b = luminance(convertRgbToLinear(rgb_b));
    const brighter = if (lum_a > lum_b) lum_a else lum_b;
    const darker = if (lum_a > lum_b) lum_b else lum_a;
    const ratio = (brighter + 0.05) / (darker + 0.05);
    return @as(f32, @floatCast(ratio));
}

/// Build a default list of theme tokens derived from the provided theme.
pub fn buildThemeTokenEntries(allocator: std.mem.Allocator, theme: *const Theme) !std.ArrayList(ThemeToken) {
    var list = std.ArrayList(ThemeToken).init(allocator);
    errdefer list.deinit();

    const background = theme.colors.background;

    const addToken = struct {
        fn call(tokens: *std.ArrayList(ThemeToken), token: ThemeToken) !void {
            try tokens.append(token);
        }
    };

    try addToken.call(&list, ThemeToken{
        .name = "Primary",
        .group = "Semantic",
        .kind = .semantic,
        .color = theme.colors.primary,
        .text_color = chooseTextColor(theme.colors.primary),
        .description = "Primary emphasis color",
        .contrast_ratio = computeContrast(theme.colors.primary, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Secondary",
        .group = "Semantic",
        .kind = .semantic,
        .color = theme.colors.secondary,
        .text_color = chooseTextColor(theme.colors.secondary),
        .description = "Secondary accent",
        .contrast_ratio = computeContrast(theme.colors.secondary, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Accent",
        .group = "Semantic",
        .kind = .semantic,
        .color = theme.colors.accent,
        .text_color = chooseTextColor(theme.colors.accent),
        .description = "Accent / highlight",
        .contrast_ratio = computeContrast(theme.colors.accent, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Error",
        .group = "Semantic",
        .kind = .semantic,
        .color = theme.colors.error_color,
        .text_color = chooseTextColor(theme.colors.error_color),
        .description = "Error feedback",
        .contrast_ratio = computeContrast(theme.colors.error_color, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Warning",
        .group = "Semantic",
        .kind = .semantic,
        .color = theme.colors.warning,
        .text_color = chooseTextColor(theme.colors.warning),
        .description = "Warning feedback",
        .contrast_ratio = computeContrast(theme.colors.warning, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Success",
        .group = "Semantic",
        .kind = .semantic,
        .color = theme.colors.success,
        .text_color = chooseTextColor(theme.colors.success),
        .description = "Success confirmation",
        .contrast_ratio = computeContrast(theme.colors.success, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Info",
        .group = "Semantic",
        .kind = .semantic,
        .color = theme.colors.info,
        .text_color = chooseTextColor(theme.colors.info),
        .description = "Informational message",
        .contrast_ratio = computeContrast(theme.colors.info, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Text",
        .group = "Semantic",
        .kind = .semantic,
        .color = theme.colors.text,
        .text_color = chooseTextColor(theme.colors.text),
        .description = "Primary text",
        .contrast_ratio = computeContrast(theme.colors.text, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Muted Text",
        .group = "Semantic",
        .kind = .semantic,
        .color = theme.colors.text_muted,
        .text_color = chooseTextColor(theme.colors.text_muted),
        .description = "Muted text",
        .contrast_ratio = computeContrast(theme.colors.text_muted, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Background",
        .group = "Background",
        .kind = .semantic,
        .color = theme.colors.background,
        .text_color = chooseTextColor(theme.colors.background),
        .description = "Base background",
        .contrast_ratio = computeContrast(theme.colors.background, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Panel",
        .group = "Background",
        .kind = .semantic,
        .color = theme.colors.background_panel,
        .text_color = chooseTextColor(theme.colors.background_panel),
        .description = "Panel background",
        .contrast_ratio = computeContrast(theme.colors.background_panel, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Element",
        .group = "Background",
        .kind = .semantic,
        .color = theme.colors.background_element,
        .text_color = chooseTextColor(theme.colors.background_element),
        .description = "Element background",
        .contrast_ratio = computeContrast(theme.colors.background_element, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Border",
        .group = "Semantic",
        .kind = .semantic,
        .color = theme.colors.border,
        .text_color = chooseTextColor(theme.colors.border),
        .description = "Default border",
        .contrast_ratio = computeContrast(theme.colors.border, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Active Border",
        .group = "Semantic",
        .kind = .semantic,
        .color = theme.colors.border_active,
        .text_color = chooseTextColor(theme.colors.border_active),
        .description = "Focused border",
        .contrast_ratio = computeContrast(theme.colors.border_active, background),
    });

    // Palette tokens
    var palette_it = theme.palette_tokens.iterator();
    while (palette_it.next()) |entry| {
        const name = entry.key_ptr.*;
        const color = entry.value_ptr.*;
        try addToken.call(&list, ThemeToken{
            .name = name,
            .group = "Palette",
            .kind = .palette,
            .color = color,
            .text_color = chooseTextColor(color),
            .description = "Palette token",
            .contrast_ratio = computeContrast(color, background),
        });
    }

    // Syntax tokens
    try addToken.call(&list, ThemeToken{
        .name = "Keyword",
        .group = "Syntax",
        .kind = .syntax,
        .color = theme.syntax.keyword,
        .text_color = chooseTextColor(theme.syntax.keyword),
        .description = "Syntax keyword",
        .contrast_ratio = computeContrast(theme.syntax.keyword, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Function",
        .group = "Syntax",
        .kind = .syntax,
        .color = theme.syntax.function,
        .text_color = chooseTextColor(theme.syntax.function),
        .description = "Function names",
        .contrast_ratio = computeContrast(theme.syntax.function, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "String",
        .group = "Syntax",
        .kind = .syntax,
        .color = theme.syntax.string,
        .text_color = chooseTextColor(theme.syntax.string),
        .description = "String literals",
        .contrast_ratio = computeContrast(theme.syntax.string, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Number",
        .group = "Syntax",
        .kind = .syntax,
        .color = theme.syntax.number,
        .text_color = chooseTextColor(theme.syntax.number),
        .description = "Numeric literal",
        .contrast_ratio = computeContrast(theme.syntax.number, background),
    });
    try addToken.call(&list, ThemeToken{
        .name = "Comment",
        .group = "Syntax",
        .kind = .syntax,
        .color = theme.syntax.comment,
        .text_color = chooseTextColor(theme.syntax.comment),
        .description = "Comments",
        .contrast_ratio = computeContrast(theme.syntax.comment, background),
    });

    return list;
}

test "buildThemeTokenEntries captures palette and semantic tokens" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var theme = Theme.init(allocator);
    defer theme.deinit();

    // Inject a palette token for validation
    {
        var entry = try theme.palette_tokens.getOrPut("brandPurple");
        if (!entry.found_existing) {
            entry.key_ptr.* = try allocator.dupe(u8, "brandPurple");
        }
        entry.value_ptr.* = Color.rgb(128, 64, 255);
    }

    var tokens = try buildThemeTokenEntries(allocator, &theme);
    defer tokens.deinit();

    try testing.expect(tokens.items.len >= 18);

    var found_primary = false;
    var palette_count: usize = 0;

    for (tokens.items) |token| {
        if (std.mem.eql(u8, token.name, "Primary")) {
            found_primary = true;
            try testing.expect(token.contrast_ratio != null);
            try testing.expect(std.mem.eql(u8, token.group, "Semantic"));
        }
        if (std.mem.eql(u8, token.group, "Palette")) {
            palette_count += 1;
        }
    }

    try testing.expect(found_primary);
    try testing.expect(palette_count >= 1);
}
