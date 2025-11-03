//! Theme - Color theme definition and parsing
//! Supports JSON-based themes with color references

const std = @import("std");
const Color = @import("../style.zig").Color;

/// Theme definition
pub const Theme = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    description: []const u8,

    // Color definitions (palette)
    defs: std.StringHashMap(Color),

    // Theme colors (semantic)
    colors: ThemeColors,

    // Syntax highlighting colors
    syntax: SyntaxColors,

    pub fn init(allocator: std.mem.Allocator) Theme {
        return Theme{
            .allocator = allocator,
            .name = "",
            .description = "",
            .defs = std.StringHashMap(Color).init(allocator),
            .colors = ThemeColors{},
            .syntax = SyntaxColors{},
        };
    }

    pub fn deinit(self: *Theme) void {
        self.allocator.free(self.name);
        self.allocator.free(self.description);
        self.defs.deinit();
    }

    /// Load theme from JSON file
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Theme {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
        defer allocator.free(content);

        return try parseJson(allocator, content);
    }

    /// Parse theme from JSON string
    pub fn parseJson(allocator: std.mem.Allocator, json: []const u8) !Theme {
        var theme = Theme.init(allocator);
        errdefer theme.deinit();

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        // Parse name
        if (root.get("name")) |name_val| {
            theme.name = try allocator.dupe(u8, name_val.string);
        }

        // Parse description
        if (root.get("description")) |desc_val| {
            theme.description = try allocator.dupe(u8, desc_val.string);
        }

        // Parse defs (color palette)
        if (root.get("defs")) |defs_val| {
            var defs_iter = defs_val.object.iterator();
            while (defs_iter.next()) |entry| {
                const color = try parseColor(entry.value_ptr.*.string);
                try theme.defs.put(entry.key_ptr.*, color);
            }
        }

        // Parse theme colors (semantic colors)
        if (root.get("theme")) |theme_val| {
            theme.colors = try parseThemeColors(&theme.defs, theme_val.object);
        }

        // Parse syntax colors
        if (root.get("syntax")) |syntax_val| {
            theme.syntax = try parseSyntaxColors(&theme.defs, syntax_val.object);
        }

        return theme;
    }

    /// Get a color by name, resolving references
    pub fn getColor(self: *const Theme, name: []const u8) ?Color {
        // Try theme colors first
        if (std.mem.eql(u8, name, "primary")) return self.colors.primary;
        if (std.mem.eql(u8, name, "secondary")) return self.colors.secondary;
        if (std.mem.eql(u8, name, "accent")) return self.colors.accent;
        if (std.mem.eql(u8, name, "error")) return self.colors.error_color;
        if (std.mem.eql(u8, name, "warning")) return self.colors.warning;
        if (std.mem.eql(u8, name, "success")) return self.colors.success;
        if (std.mem.eql(u8, name, "info")) return self.colors.info;
        if (std.mem.eql(u8, name, "text")) return self.colors.text;
        if (std.mem.eql(u8, name, "background")) return self.colors.background;

        // Try defs (palette)
        return self.defs.get(name);
    }
};

/// Semantic theme colors
pub const ThemeColors = struct {
    primary: Color = Color.blue,
    secondary: Color = Color.cyan,
    accent: Color = Color.magenta,
    error_color: Color = Color.red,
    warning: Color = Color.yellow,
    success: Color = Color.green,
    info: Color = Color.cyan,
    text: Color = Color.white,
    text_muted: Color = Color.bright_black,
    background: Color = Color.black,
    background_panel: Color = Color.black,
    background_element: Color = Color.bright_black,
    border: Color = Color.bright_black,
    border_active: Color = Color.cyan,
    border_subtle: Color = Color.black,
};

/// Syntax highlighting colors
pub const SyntaxColors = struct {
    keyword: Color = Color.magenta,
    function: Color = Color.blue,
    string: Color = Color.green,
    number: Color = Color.yellow,
    comment: Color = Color.bright_black,
    type: Color = Color.cyan,
    operator: Color = Color.white,
    variable: Color = Color.white,
    constant: Color = Color.yellow,
};

/// Parse hex color string (#RRGGBB)
fn parseColor(hex: []const u8) !Color {
    if (hex.len == 0) return error.InvalidColor;

    // Handle hex colors (#RRGGBB)
    if (hex[0] == '#') {
        if (hex.len != 7) return error.InvalidColor;

        const r = try std.fmt.parseInt(u8, hex[1..3], 16);
        const g = try std.fmt.parseInt(u8, hex[3..5], 16);
        const b = try std.fmt.parseInt(u8, hex[5..7], 16);

        return Color.rgb(r, g, b);
    }

    // Handle named colors
    return Color.fromName(hex) orelse error.InvalidColor;
}

/// Parse theme colors section, resolving references
fn parseThemeColors(defs: *const std.StringHashMap(Color), obj: std.json.ObjectMap) !ThemeColors {
    var colors = ThemeColors{};

    if (obj.get("primary")) |val| colors.primary = try resolveColorRef(defs, val.string);
    if (obj.get("secondary")) |val| colors.secondary = try resolveColorRef(defs, val.string);
    if (obj.get("accent")) |val| colors.accent = try resolveColorRef(defs, val.string);
    if (obj.get("error")) |val| colors.error_color = try resolveColorRef(defs, val.string);
    if (obj.get("warning")) |val| colors.warning = try resolveColorRef(defs, val.string);
    if (obj.get("success")) |val| colors.success = try resolveColorRef(defs, val.string);
    if (obj.get("info")) |val| colors.info = try resolveColorRef(defs, val.string);
    if (obj.get("text")) |val| colors.text = try resolveColorRef(defs, val.string);
    if (obj.get("textMuted")) |val| colors.text_muted = try resolveColorRef(defs, val.string);
    if (obj.get("background")) |val| colors.background = try resolveColorRef(defs, val.string);
    if (obj.get("backgroundPanel")) |val| colors.background_panel = try resolveColorRef(defs, val.string);
    if (obj.get("backgroundElement")) |val| colors.background_element = try resolveColorRef(defs, val.string);
    if (obj.get("border")) |val| colors.border = try resolveColorRef(defs, val.string);
    if (obj.get("borderActive")) |val| colors.border_active = try resolveColorRef(defs, val.string);
    if (obj.get("borderSubtle")) |val| colors.border_subtle = try resolveColorRef(defs, val.string);

    return colors;
}

/// Parse syntax colors section, resolving references
fn parseSyntaxColors(defs: *const std.StringHashMap(Color), obj: std.json.ObjectMap) !SyntaxColors {
    var colors = SyntaxColors{};

    if (obj.get("keyword")) |val| colors.keyword = try resolveColorRef(defs, val.string);
    if (obj.get("function")) |val| colors.function = try resolveColorRef(defs, val.string);
    if (obj.get("string")) |val| colors.string = try resolveColorRef(defs, val.string);
    if (obj.get("number")) |val| colors.number = try resolveColorRef(defs, val.string);
    if (obj.get("comment")) |val| colors.comment = try resolveColorRef(defs, val.string);
    if (obj.get("type")) |val| colors.type = try resolveColorRef(defs, val.string);
    if (obj.get("operator")) |val| colors.operator = try resolveColorRef(defs, val.string);
    if (obj.get("variable")) |val| colors.variable = try resolveColorRef(defs, val.string);
    if (obj.get("constant")) |val| colors.constant = try resolveColorRef(defs, val.string);

    return colors;
}

/// Resolve color reference (either direct hex or reference to defs)
fn resolveColorRef(defs: *const std.StringHashMap(Color), ref: []const u8) !Color {
    // If it starts with #, parse as hex color
    if (ref.len > 0 and ref[0] == '#') {
        return try parseColor(ref);
    }

    // Otherwise, look up in defs
    return defs.get(ref) orelse error.UndefinedColorReference;
}

// Tests
test "Theme parseColor" {
    const testing = std.testing;

    const red = try parseColor("#ff0000");
    try testing.expectEqual(@as(u8, 255), red.r);
    try testing.expectEqual(@as(u8, 0), red.g);
    try testing.expectEqual(@as(u8, 0), red.b);

    const blue = try parseColor("#0000ff");
    try testing.expectEqual(@as(u8, 0), blue.r);
    try testing.expectEqual(@as(u8, 0), blue.g);
    try testing.expectEqual(@as(u8, 255), blue.b);
}

test "Theme JSON parsing" {
    const testing = std.testing;

    const json =
        \\{
        \\  "name": "Test Theme",
        \\  "description": "A test theme",
        \\  "defs": {
        \\    "teal": "#4fd6be",
        \\    "mint": "#66ffc2"
        \\  },
        \\  "theme": {
        \\    "primary": "teal",
        \\    "accent": "mint"
        \\  },
        \\  "syntax": {
        \\    "keyword": "mint",
        \\    "string": "teal"
        \\  }
        \\}
    ;

    var theme = try Theme.parseJson(testing.allocator, json);
    defer theme.deinit();

    try testing.expectEqualStrings("Test Theme", theme.name);
    try testing.expectEqualStrings("A test theme", theme.description);

    // Check color resolution
    const teal = theme.defs.get("teal").?;
    try testing.expectEqual(@as(u8, 0x4f), teal.r);
    try testing.expectEqual(@as(u8, 0xd6), teal.g);
    try testing.expectEqual(@as(u8, 0xbe), teal.b);

    // Check theme colors use references
    try testing.expectEqual(teal.r, theme.colors.primary.r);
    try testing.expectEqual(teal.g, theme.colors.primary.g);
    try testing.expectEqual(teal.b, theme.colors.primary.b);
}
