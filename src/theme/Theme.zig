//! Theme - Color theme definition and parsing
//! Supports JSON-based themes with color references

const std = @import("std");
const style = @import("../style.zig");
const ascii = std.ascii;

const Color = style.Color;
const Attributes = style.Attributes;
const Style = style.Style;

pub const Variant = enum { dark, light };

pub const Origin = enum { builtin, user, dynamic };

pub const TypographyPreset = struct {
    family: []const u8 = "default",
    weight: u16 = 400,
    tracking: i8 = 0,
    uppercase: bool = false,
    attributes: Attributes = Attributes.none(),
    owns_family: bool = false,

    pub fn setFamily(self: *TypographyPreset, allocator: std.mem.Allocator, value: []const u8) !void {
        if (self.owns_family) allocator.free(self.family);
        self.family = try allocator.dupe(u8, value);
        self.owns_family = true;
    }

    pub fn deinit(self: *TypographyPreset, allocator: std.mem.Allocator) void {
        if (self.owns_family) allocator.free(self.family);
    }
};

pub const Typography = struct {
    allocator: std.mem.Allocator,
    presets: std.StringHashMap(TypographyPreset),

    pub fn init(allocator: std.mem.Allocator) Typography {
        return Typography{
            .allocator = allocator,
            .presets = std.StringHashMap(TypographyPreset).init(allocator),
        };
    }

    pub fn deinit(self: *Typography) void {
        var it = self.presets.valueIterator();
        while (it.next()) |preset| {
            preset.deinit(self.allocator);
        }

        var key_it = self.presets.keyIterator();
        while (key_it.next()) |key| {
            self.allocator.free(key.*);
        }

        self.presets.deinit();
    }

    pub fn set(self: *Typography, name: []const u8, preset: TypographyPreset) !void {
        var entry = try self.presets.getOrPut(name);
        if (entry.found_existing) {
            entry.value_ptr.deinit(self.allocator);
        } else {
            entry.key_ptr.* = try self.allocator.dupe(u8, name);
        }
        entry.value_ptr.* = preset;
    }

    pub fn get(self: *const Typography, name: []const u8) ?*const TypographyPreset {
        return self.presets.getPtr(name);
    }
};

pub const ComponentStyle = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    attributes: Attributes = Attributes.none(),
    typography: ?[]const u8 = null,
    owns_typography: bool = false,

    pub fn setTypography(self: *ComponentStyle, allocator: std.mem.Allocator, value: []const u8) !void {
        if (self.owns_typography) {
            if (self.typography) |existing| {
                allocator.free(existing);
            }
        }
        self.typography = try allocator.dupe(u8, value);
        self.owns_typography = true;
    }

    pub fn deinit(self: *ComponentStyle, allocator: std.mem.Allocator) void {
        if (self.owns_typography) {
            if (self.typography) |name| {
                allocator.free(name);
            }
        }
    }

    pub fn toStyle(self: *const ComponentStyle) Style {
        var result = Style.default();
        if (self.fg) |fg| result = result.withFg(fg);
        if (self.bg) |bg| result = result.withBg(bg);
        result = result.withAttributes(self.attributes);
        return result;
    }
};

/// Theme definition
pub const Theme = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    description: []const u8,
    name_owned: bool = false,
    description_owned: bool = false,

    // Color definitions (palette)
    defs: std.StringHashMap(Color),
    palette_tokens: std.StringHashMap(Color),

    // Theme colors (semantic)
    colors: ThemeColors,

    // Syntax highlighting colors
    syntax: SyntaxColors,

    component_styles: std.StringHashMap(ComponentStyle),

    variant: Variant = .dark,
    typography: Typography,
    origin: Origin = .builtin,

    pub fn init(allocator: std.mem.Allocator) Theme {
        return Theme{
            .allocator = allocator,
            .name = "",
            .description = "",
            .name_owned = false,
            .description_owned = false,
            .defs = std.StringHashMap(Color).init(allocator),
            .palette_tokens = std.StringHashMap(Color).init(allocator),
            .colors = ThemeColors{},
            .syntax = SyntaxColors{},
            .component_styles = std.StringHashMap(ComponentStyle).init(allocator),
            .variant = .dark,
            .typography = Typography.init(allocator),
            .origin = .builtin,
        };
    }

    pub fn deinit(self: *Theme) void {
        if (self.name_owned) self.allocator.free(self.name);
        if (self.description_owned) self.allocator.free(self.description);

        freeStringKeys(Color, self.allocator, &self.defs);
        self.defs.deinit();

        freeStringKeys(Color, self.allocator, &self.palette_tokens);
        self.palette_tokens.deinit();

        freeComponentStyles(self.allocator, &self.component_styles);
        self.component_styles.deinit();

        self.typography.deinit();
    }

    pub fn setName(self: *Theme, value: []const u8) !void {
        if (self.name_owned) {
            self.allocator.free(self.name);
            self.name_owned = false;
        }
        self.name = try self.allocator.dupe(u8, value);
        self.name_owned = true;
    }

    pub fn setDescription(self: *Theme, value: []const u8) !void {
        if (self.description_owned) {
            self.allocator.free(self.description);
            self.description_owned = false;
        }
        self.description = try self.allocator.dupe(u8, value);
        self.description_owned = true;
    }

    pub fn setOrigin(self: *Theme, origin: Origin) void {
        self.origin = origin;
    }

    pub fn getPaletteColor(self: *const Theme, token: []const u8) ?Color {
        return self.palette_tokens.get(token);
    }

    pub fn getTypography(self: *const Theme, name: []const u8) ?*const TypographyPreset {
        return self.typography.get(name);
    }

    pub fn getComponentStyle(self: *const Theme, name: []const u8) ?*const ComponentStyle {
        return self.component_styles.getPtr(name);
    }

    pub fn resolveComponentStyle(self: *const Theme, name: []const u8) ?Style {
        if (self.component_styles.getPtr(name)) |component| {
            return component.toStyle();
        }
        return null;
    }

    pub fn getComponentTypography(self: *const Theme, name: []const u8) ?*const TypographyPreset {
        if (self.component_styles.getPtr(name)) |component| {
            if (component.typography) |typo_name| {
                return self.typography.get(typo_name);
            }
        }
        return null;
    }

    pub fn setComponentStyle(self: *Theme, name: []const u8, component: ComponentStyle) !void {
        try putComponentStyle(&self.component_styles, self.allocator, name, component);
    }

    pub fn isDark(self: *const Theme) bool {
        return self.variant == .dark;
    }

    /// Load theme from JSON file
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Theme {
        const content = try std.fs.cwd().readFileAlloc(path, allocator, @enumFromInt(10 * 1024 * 1024)); // 10MB max
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
            try theme.setName(name_val.string);
        }

        // Parse description
        if (root.get("description")) |desc_val| {
            try theme.setDescription(desc_val.string);
        }

        if (root.get("variant")) |variant_val| {
            if (variant_val != .string) return error.InvalidThemeVariant;
            theme.variant = variantFromString(variant_val.string) orelse return error.InvalidThemeVariant;
        }

        // Parse defs (color palette)
        if (root.get("defs")) |defs_val| {
            var defs_iter = defs_val.object.iterator();
            while (defs_iter.next()) |entry| {
                if (entry.value_ptr.* != .string) return error.InvalidColor;
                const color = try parseColor(entry.value_ptr.*.string);
                try putColor(&theme.defs, theme.allocator, entry.key_ptr.*, color);
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

        if (root.get("palette")) |palette_val| {
            try parsePaletteTokens(&theme, palette_val.object);
        }

        if (root.get("typography")) |typography_val| {
            try parseTypography(&theme, typography_val.object);
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
        if (std.mem.eql(u8, name, "text_muted") or std.mem.eql(u8, name, "textMuted")) return self.colors.text_muted;
        if (std.mem.eql(u8, name, "background")) return self.colors.background;
        if (std.mem.eql(u8, name, "background_panel") or std.mem.eql(u8, name, "backgroundPanel")) return self.colors.background_panel;
        if (std.mem.eql(u8, name, "background_element") or std.mem.eql(u8, name, "backgroundElement")) return self.colors.background_element;
        if (std.mem.eql(u8, name, "border")) return self.colors.border;
        if (std.mem.eql(u8, name, "border_active") or std.mem.eql(u8, name, "borderActive")) return self.colors.border_active;
        if (std.mem.eql(u8, name, "border_subtle") or std.mem.eql(u8, name, "borderSubtle")) return self.colors.border_subtle;

        if (self.palette_tokens.get(name)) |token| return token;

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

        return Color.fromRgb(r, g, b);
    }

    // Handle named colors
    return colorFromName(hex) orelse error.InvalidColor;
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

fn colorFromName(raw: []const u8) ?Color {
    var buf: [32]u8 = undefined;
    if (raw.len > buf.len) return null;
    const normalized = normalizeKey(raw, &buf);

    if (std.mem.eql(u8, normalized, "default")) return Color.default;
    if (std.mem.eql(u8, normalized, "black")) return Color.black;
    if (std.mem.eql(u8, normalized, "red")) return Color.red;
    if (std.mem.eql(u8, normalized, "green")) return Color.green;
    if (std.mem.eql(u8, normalized, "yellow")) return Color.yellow;
    if (std.mem.eql(u8, normalized, "blue")) return Color.blue;
    if (std.mem.eql(u8, normalized, "magenta")) return Color.magenta;
    if (std.mem.eql(u8, normalized, "cyan")) return Color.cyan;
    if (std.mem.eql(u8, normalized, "white")) return Color.white;
    if (std.mem.eql(u8, normalized, "brightblack")) return Color.bright_black;
    if (std.mem.eql(u8, normalized, "brightred")) return Color.bright_red;
    if (std.mem.eql(u8, normalized, "brightgreen")) return Color.bright_green;
    if (std.mem.eql(u8, normalized, "brightyellow")) return Color.bright_yellow;
    if (std.mem.eql(u8, normalized, "brightblue")) return Color.bright_blue;
    if (std.mem.eql(u8, normalized, "brightmagenta")) return Color.bright_magenta;
    if (std.mem.eql(u8, normalized, "brightcyan")) return Color.bright_cyan;
    if (std.mem.eql(u8, normalized, "brightwhite")) return Color.bright_white;
    return null;
}

fn normalizeKey(raw: []const u8, buffer: []u8) []const u8 {
    var len: usize = 0;
    for (raw) |ch| {
        if (ch == '_' or ch == '-' or ch == ' ') continue;
        if (len >= buffer.len) break;
        buffer[len] = ascii.toLower(ch);
        len += 1;
    }
    return buffer[0..len];
}

fn freeStringKeys(comptime V: type, allocator: std.mem.Allocator, map: *std.StringHashMap(V)) void {
    var it = map.keyIterator();
    while (it.next()) |key| {
        allocator.free(key.*);
    }
}

fn putColor(map: *std.StringHashMap(Color), allocator: std.mem.Allocator, key: []const u8, value: Color) !void {
    var entry = try map.getOrPut(key);
    if (!entry.found_existing) {
        entry.key_ptr.* = try allocator.dupe(u8, key);
    }
    entry.value_ptr.* = value;
}

fn putComponentStyle(map: *std.StringHashMap(ComponentStyle), allocator: std.mem.Allocator, key: []const u8, value: ComponentStyle) !void {
    var entry = try map.getOrPut(key);
    if (entry.found_existing) {
        entry.value_ptr.deinit(allocator);
    } else {
        entry.key_ptr.* = try allocator.dupe(u8, key);
    }
    entry.value_ptr.* = value;
}

fn freeComponentStyles(allocator: std.mem.Allocator, map: *std.StringHashMap(ComponentStyle)) void {
    var iter = map.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(allocator);
        allocator.free(entry.key_ptr.*);
    }
}

pub fn variantFromString(value: []const u8) ?Variant {
    if (ascii.eqlIgnoreCase(value, "dark")) return .dark;
    if (ascii.eqlIgnoreCase(value, "light")) return .light;
    return null;
}

fn parsePaletteTokens(theme: *Theme, obj: std.json.ObjectMap) !void {
    var iter = obj.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* != .string) return error.InvalidPaletteToken;
        const color = resolveColorRef(&theme.defs, entry.value_ptr.*.string) catch |err|
            switch (err) {
                error.UndefinedColorReference => blk: {
                    if (theme.getColor(entry.value_ptr.*.string)) |semantic_color| {
                        break :blk semantic_color;
                    }
                    const parsed_color = try parseColor(entry.value_ptr.*.string);
                    break :blk parsed_color;
                },
                else => return err,
            };
        try putColor(&theme.palette_tokens, theme.allocator, entry.key_ptr.*, color);
    }
}

fn parseTypography(theme: *Theme, obj: std.json.ObjectMap) !void {
    var iter = obj.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* != .object) return error.InvalidTypographyPreset;

        var preset = TypographyPreset{};
        const preset_obj = entry.value_ptr.*.object;

        if (preset_obj.get("family")) |family_val| {
            if (family_val != .string) return error.InvalidTypographyPreset;
            try preset.setFamily(theme.allocator, family_val.string);
        }

        if (preset_obj.get("weight")) |weight_val| {
            switch (weight_val) {
                .integer => |int_val| {
                    const clamped = std.math.clamp(int_val, 0, @as(i64, std.math.maxInt(u16)));
                    preset.weight = @intCast(clamped);
                },
                .float => |float_val| {
                    const converted: i64 = @intFromFloat(float_val);
                    const clamped = std.math.clamp(converted, 0, @as(i64, std.math.maxInt(u16)));
                    preset.weight = @intCast(clamped);
                },
                else => return error.InvalidTypographyPreset,
            }
        }

        if (preset_obj.get("tracking")) |tracking_val| {
            const amount: i64 = switch (tracking_val) {
                .integer => |int_val| int_val,
                .float => |float_val| @intFromFloat(float_val),
                else => return error.InvalidTypographyPreset,
            };
            const clamped = std.math.clamp(amount, -128, 127);
            preset.tracking = @intCast(clamped);
        }

        if (preset_obj.get("uppercase")) |upper_val| {
            if (upper_val != .bool) return error.InvalidTypographyPreset;
            preset.uppercase = upper_val.bool;
        }

        if (preset_obj.get("style")) |style_val| {
            if (style_val != .array) return error.InvalidTypographyPreset;
            for (style_val.array.items) |item| {
                if (item != .string) return error.InvalidTypographyPreset;
                applyStyleToken(&preset, item.string);
            }
        }

        if (preset_obj.get("attributes")) |attrs_val| {
            if (attrs_val != .object) return error.InvalidTypographyPreset;
            var attrs_iter = attrs_val.object.iterator();
            while (attrs_iter.next()) |attr| {
                if (attr.value_ptr.* != .bool) return error.InvalidTypographyPreset;
                const enabled = attr.value_ptr.*.bool;
                applyAttributeFlag(&preset, attr.key_ptr.*, enabled);
            }
        }

        try theme.typography.set(entry.key_ptr.*, preset);
    }
}

fn applyStyleToken(preset: *TypographyPreset, token: []const u8) void {
    if (ascii.eqlIgnoreCase(token, "bold")) {
        preset.attributes.bold = true;
        if (preset.weight < 600) preset.weight = 600;
    } else if (ascii.eqlIgnoreCase(token, "italic")) {
        preset.attributes.italic = true;
    } else if (ascii.eqlIgnoreCase(token, "underline")) {
        preset.attributes.underline = true;
    } else if (ascii.eqlIgnoreCase(token, "strikethrough")) {
        preset.attributes.strikethrough = true;
    } else if (ascii.eqlIgnoreCase(token, "dim")) {
        preset.attributes.dim = true;
    } else if (ascii.eqlIgnoreCase(token, "reverse")) {
        preset.attributes.reverse = true;
    } else if (ascii.eqlIgnoreCase(token, "blink")) {
        preset.attributes.blink = true;
    } else if (ascii.eqlIgnoreCase(token, "uppercase") or ascii.eqlIgnoreCase(token, "caps")) {
        preset.uppercase = true;
    }
}

fn applyAttributeFlag(preset: *TypographyPreset, key: []const u8, enabled: bool) void {
    if (ascii.eqlIgnoreCase(key, "bold")) {
        preset.attributes.bold = enabled;
    } else if (ascii.eqlIgnoreCase(key, "italic")) {
        preset.attributes.italic = enabled;
    } else if (ascii.eqlIgnoreCase(key, "underline")) {
        preset.attributes.underline = enabled;
    } else if (ascii.eqlIgnoreCase(key, "strikethrough")) {
        preset.attributes.strikethrough = enabled;
    } else if (ascii.eqlIgnoreCase(key, "dim")) {
        preset.attributes.dim = enabled;
    } else if (ascii.eqlIgnoreCase(key, "reverse")) {
        preset.attributes.reverse = enabled;
    } else if (ascii.eqlIgnoreCase(key, "blink")) {
        preset.attributes.blink = enabled;
    } else if (ascii.eqlIgnoreCase(key, "uppercase")) {
        preset.uppercase = enabled;
    }
}

// Tests
fn expectRgb(color: Color, r: u8, g: u8, b: u8) !void {
    const testing = std.testing;
    switch (color) {
        .rgb => |rgb| {
            try testing.expectEqual(r, rgb.r);
            try testing.expectEqual(g, rgb.g);
            try testing.expectEqual(b, rgb.b);
        },
        else => try testing.expect(false),
    }
}

test "Theme parseColor" {
    const red = try parseColor("#ff0000");
    try expectRgb(red, 255, 0, 0);

    const blue = try parseColor("#0000ff");
    try expectRgb(blue, 0, 0, 255);
}

test "Theme JSON parsing" {
    const testing = std.testing;

    const json =
        \\{
        \\  "name": "Test Theme",
        \\  "description": "A test theme",
        \\  "variant": "light",
        \\  "defs": {
        \\    "teal": "#4fd6be",
        \\    "mint": "#66ffc2",
        \\    "night": "#1a1b26"
        \\  },
        \\  "theme": {
        \\    "primary": "teal",
        \\    "accent": "mint",
        \\    "background": "night"
        \\  },
        \\  "palette": {
        \\    "surface": "teal",
        \\    "surfaceAlt": "#224455"
        \\  },
        \\  "typography": {
        \\    "heading": {
        \\      "family": "JetBrains Mono",
        \\      "weight": 700,
        \\      "style": ["bold", "uppercase"]
        \\    },
        \\    "body": {
        \\      "tracking": -2
        \\    }
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

    try testing.expect(theme.variant == .light);

    const surface = theme.getPaletteColor("surface").?;
    try testing.expect(std.meta.eql(teal, surface));

    const surface_alt = theme.getColor("surfaceAlt").?; // palette token via getColor
    switch (surface_alt) {
        .rgb => |rgb| {
            try testing.expectEqual(@as(u8, 0x22), rgb.r);
            try testing.expectEqual(@as(u8, 0x44), rgb.g);
            try testing.expectEqual(@as(u8, 0x55), rgb.b);
        },
        else => try testing.expect(false),
    }

    const heading = theme.getTypography("heading").?;
    try testing.expect(heading.attributes.bold);
    try testing.expect(heading.uppercase);
    try testing.expectEqual(@as(u16, 700), heading.weight);

    const body = theme.getTypography("body").?;
    try testing.expectEqual(@as(i8, -2), body.tracking);
}
