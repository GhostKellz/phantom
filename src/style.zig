//! Style system for Phantom TUI - colors, attributes, and styling
const std = @import("std");

/// RGB color representation
pub const Color = union(enum) {
    /// Default terminal colors
    default,
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,

    /// Bright variants
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,

    /// 256-color palette index
    indexed: u8,

    /// True color RGB
    rgb: struct { r: u8, g: u8, b: u8 },

    pub fn fromRgb(r: u8, g: u8, b: u8) Color {
        return Color{ .rgb = .{ .r = r, .g = g, .b = b } };
    }

    pub fn ansiCode(self: Color, background: bool) []const u8 {
        return switch (self) {
            .default => if (background) "\x1b[49m" else "\x1b[39m",
            .black => if (background) "\x1b[40m" else "\x1b[30m",
            .red => if (background) "\x1b[41m" else "\x1b[31m",
            .green => if (background) "\x1b[42m" else "\x1b[32m",
            .yellow => if (background) "\x1b[43m" else "\x1b[33m",
            .blue => if (background) "\x1b[44m" else "\x1b[34m",
            .magenta => if (background) "\x1b[45m" else "\x1b[35m",
            .cyan => if (background) "\x1b[46m" else "\x1b[36m",
            .white => if (background) "\x1b[47m" else "\x1b[37m",
            .bright_black => if (background) "\x1b[100m" else "\x1b[90m",
            .bright_red => if (background) "\x1b[101m" else "\x1b[91m",
            .bright_green => if (background) "\x1b[102m" else "\x1b[92m",
            .bright_yellow => if (background) "\x1b[103m" else "\x1b[93m",
            .bright_blue => if (background) "\x1b[104m" else "\x1b[94m",
            .bright_magenta => if (background) "\x1b[105m" else "\x1b[95m",
            .bright_cyan => if (background) "\x1b[106m" else "\x1b[96m",
            .bright_white => if (background) "\x1b[107m" else "\x1b[97m",
            .indexed => |idx| blk: {
                _ = idx; // TODO: implement 256-color support
                break :blk if (background) "\x1b[49m" else "\x1b[39m";
            },
            .rgb => |_| blk: {
                // TODO: implement true color support
                break :blk if (background) "\x1b[49m" else "\x1b[39m";
            },
        };
    }
};

/// Text attributes
pub const Attributes = packed struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    strikethrough: bool = false,
    dim: bool = false,
    reverse: bool = false,
    blink: bool = false,

    pub fn none() Attributes {
        return Attributes{};
    }

    pub fn withBold() Attributes {
        return Attributes{ .bold = true };
    }

    pub fn withItalic() Attributes {
        return Attributes{ .italic = true };
    }

    pub fn withUnderline() Attributes {
        return Attributes{ .underline = true };
    }

    pub fn ansiCodes(self: Attributes, allocator: std.mem.Allocator) ![]const u8 {
        var codes = std.ArrayList(u8).init(allocator);
        defer codes.deinit();

        if (self.bold) try codes.appendSlice("\x1b[1m");
        if (self.italic) try codes.appendSlice("\x1b[3m");
        if (self.underline) try codes.appendSlice("\x1b[4m");
        if (self.strikethrough) try codes.appendSlice("\x1b[9m");
        if (self.dim) try codes.appendSlice("\x1b[2m");
        if (self.reverse) try codes.appendSlice("\x1b[7m");
        if (self.blink) try codes.appendSlice("\x1b[5m");

        return codes.toOwnedSlice();
    }
};

/// Complete style definition
pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    attributes: Attributes = Attributes.none(),

    pub fn default() Style {
        return Style{};
    }

    pub fn withFg(color: Color) Style {
        return Style{ .fg = color };
    }

    pub fn withBg(self: Style, color: Color) Style {
        var new_style = self;
        new_style.bg = color;
        return new_style;
    }

    pub fn withAttributes(attrs: Attributes) Style {
        return Style{ .attributes = attrs };
    }

    pub fn withBold(self: Style) Style {
        var new_style = self;
        new_style.attributes.bold = true;
        return new_style;
    }

    pub fn withItalic(self: Style) Style {
        var new_style = self;
        new_style.attributes.italic = true;
        return new_style;
    }

    pub fn withUnderline(self: Style) Style {
        var new_style = self;
        new_style.attributes.underline = true;
        return new_style;
    }

    /// Generate ANSI escape codes for this style
    pub fn ansiCodes(self: Style, allocator: std.mem.Allocator) ![]const u8 {
        var codes = std.ArrayList(u8).init(allocator);
        defer codes.deinit();

        // Reset first
        try codes.appendSlice("\x1b[0m");

        // Foreground color
        if (self.fg) |fg| {
            try codes.appendSlice(fg.ansiCode(false));
        }

        // Background color
        if (self.bg) |bg| {
            try codes.appendSlice(bg.ansiCode(true));
        }

        // Attributes
        const attr_codes = try self.attributes.ansiCodes(allocator);
        defer allocator.free(attr_codes);
        try codes.appendSlice(attr_codes);

        return codes.toOwnedSlice();
    }
};

test "Color ANSI codes" {
    try std.testing.expectEqualStrings("\x1b[31m", Color.red.ansiCode(false));
    try std.testing.expectEqualStrings("\x1b[41m", Color.red.ansiCode(true));
    try std.testing.expectEqualStrings("\x1b[94m", Color.bright_blue.ansiCode(false));
}

test "Style creation and modification" {
    const style = Style.withFg(Color.red).withBold();
    try std.testing.expect(style.fg.? == Color.red);
    try std.testing.expect(style.attributes.bold);
}
