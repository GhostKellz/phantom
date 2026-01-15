//! Theme manifest prototype for Phantom style system
//! Provides a schema, parser, and validation helpers for hot-swappable themes.
const std = @import("std");
const ascii = std.ascii;

const style = @import("../style.zig");
const theme = @import("../theme/Theme.zig");

const Color = style.Color;
const Attributes = style.Attributes;
const Theme = theme.Theme;
const ThemeVariant = theme.Variant;
const ThemeOrigin = theme.Origin;
const ThemeTypographyPreset = theme.TypographyPreset;
const ThemeComponentStyle = theme.ComponentStyle;

pub const ManifestError = error{
    InvalidRootObject,
    MissingPaletteSection,
    InvalidPaletteEntry,
    InvalidTokensEntry,
    InvalidColorLiteral,
    UnknownColorReference,
    InvalidTypographyEntry,
    UnknownAttributeToken,
    InvalidComponentEntry,
    MissingRequiredToken,
    UnknownTypographyReference,
    // JSON parsing errors
    OutOfMemory,
    SyntaxError,
    UnexpectedEndOfInput,
    UnexpectedToken,
    InvalidNumber,
    InvalidCharacter,
    InvalidEnumTag,
    DuplicateField,
    UnknownField,
    MissingField,
    LengthMismatch,
    BufferUnderrun,
    Overflow,
    ValueTooLong,
};

pub const Manifest = struct {
    allocator: std.mem.Allocator,
    name: []const u8 = "",
    description: []const u8 = "",
    name_owned: bool = false,
    description_owned: bool = false,
    variant: ThemeVariant = .dark,
    origin: ThemeOrigin = .dynamic,
    palette: std.StringHashMap(Color),
    tokens: std.StringHashMap(Color),
    typography: std.StringHashMap(TypographyToken),
    components: std.StringHashMap(ComponentStyle),

    pub fn init(allocator: std.mem.Allocator) Manifest {
        return Manifest{
            .allocator = allocator,
            .palette = std.StringHashMap(Color).init(allocator),
            .tokens = std.StringHashMap(Color).init(allocator),
            .typography = std.StringHashMap(TypographyToken).init(allocator),
            .components = std.StringHashMap(ComponentStyle).init(allocator),
        };
    }

    pub fn deinit(self: *Manifest) void {
        if (self.name_owned) {
            self.allocator.free(@constCast(self.name));
        }
        if (self.description_owned) {
            self.allocator.free(@constCast(self.description));
        }

        freeStringKeys(Color, self.allocator, &self.palette);
        self.palette.deinit();

        freeStringKeys(Color, self.allocator, &self.tokens);
        self.tokens.deinit();

        var typo_it = self.typography.valueIterator();
        while (typo_it.next()) |token| {
            token.deinit(self.allocator);
        }
        freeStringKeys(TypographyToken, self.allocator, &self.typography);
        self.typography.deinit();

        var comp_it = self.components.valueIterator();
        while (comp_it.next()) |component| {
            component.deinit(self.allocator);
        }
        freeStringKeys(ComponentStyle, self.allocator, &self.components);
        self.components.deinit();
    }

    pub fn setName(self: *Manifest, value: []const u8) !void {
        if (self.name_owned) {
            self.allocator.free(@constCast(self.name));
            self.name_owned = false;
        }
        self.name = try self.allocator.dupe(u8, value);
        self.name_owned = true;
    }

    pub fn setDescription(self: *Manifest, value: []const u8) !void {
        if (self.description_owned) {
            self.allocator.free(@constCast(self.description));
            self.description_owned = false;
        }
        self.description = try self.allocator.dupe(u8, value);
        self.description_owned = true;
    }

    /// Load manifest from file using POSIX APIs (Zig 0.16+ compatible)
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Manifest {
        const contents = try readFileContents(allocator, path, 10 * 1024 * 1024);
        defer allocator.free(contents);

        return try Manifest.parse(allocator, contents);
    }

    /// Read file contents using POSIX APIs (doesn't require Io context)
    fn readFileContents(allocator: std.mem.Allocator, path: []const u8, max_size: usize) ![]u8 {
        const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch |err| {
            return err;
        };
        defer std.posix.close(fd);

        // Read in chunks - standard approach that works across platforms
        var buffer: std.ArrayList(u8) = .empty;
        errdefer buffer.deinit(allocator);

        var chunk: [8192]u8 = undefined;
        while (true) {
            const bytes_read = std.posix.read(fd, &chunk) catch |err| {
                return err;
            };
            if (bytes_read == 0) break;
            if (buffer.items.len + bytes_read > max_size) return error.FileTooBig;
            try buffer.appendSlice(allocator, chunk[0..bytes_read]);
        }

        return try buffer.toOwnedSlice(allocator);
    }

    pub fn parse(allocator: std.mem.Allocator, source: []const u8) ManifestError!Manifest {
        var manifest = Manifest.init(allocator);
        errdefer manifest.deinit();

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, source, .{});
        defer parsed.deinit();

        if (parsed.value != .object) return ManifestError.InvalidRootObject;
        const root = parsed.value.object;

        if (root.get("name")) |name_val| {
            if (name_val != .string) return ManifestError.InvalidRootObject;
            try manifest.setName(name_val.string);
        }

        if (root.get("description")) |desc_val| {
            if (desc_val != .string) return ManifestError.InvalidRootObject;
            try manifest.setDescription(desc_val.string);
        }

        if (root.get("variant")) |variant_val| {
            if (variant_val != .string) return ManifestError.InvalidRootObject;
            manifest.variant = theme.variantFromString(variant_val.string) orelse return ManifestError.InvalidRootObject;
        }

        if (root.get("origin")) |origin_val| {
            if (origin_val != .string) return ManifestError.InvalidRootObject;
            manifest.origin = originFromString(origin_val.string) orelse manifest.origin;
        }

        const palette_val = root.get("palette") orelse return ManifestError.MissingPaletteSection;
        if (palette_val != .object) return ManifestError.InvalidPaletteEntry;
        try parsePaletteSection(&manifest, palette_val.object);

        if (root.get("tokens")) |tokens_val| {
            if (tokens_val != .object) return ManifestError.InvalidTokensEntry;
            try parseTokensSection(&manifest, tokens_val.object);
        }

        if (root.get("typography")) |typo_val| {
            if (typo_val != .object) return ManifestError.InvalidTypographyEntry;
            try parseTypographySection(&manifest, typo_val.object);
        }

        if (root.get("components")) |components_val| {
            if (components_val != .object) return ManifestError.InvalidComponentEntry;
            try parseComponentsSection(&manifest, components_val.object);
        }

        return manifest;
    }

    pub fn validate(self: *const Manifest) ManifestError!void {
        const required = [_][]const u8{ "background", "surface", "text", "accent", "border" };
        for (required) |token| {
            if (self.tokens.get(token) == null and self.palette.get(token) == null) {
                return ManifestError.MissingRequiredToken;
            }
        }

        var comp_it = self.components.valueIterator();
        while (comp_it.next()) |component| {
            if (component.typography) |typo_name| {
                if (self.typography.get(typo_name) == null) {
                    return ManifestError.UnknownTypographyReference;
                }
            }
        }
    }

    pub fn getColor(self: *const Manifest, name: []const u8) ?Color {
        if (self.tokens.get(name)) |color| return color;
        if (self.palette.get(name)) |color| return color;
        return null;
    }

    pub fn getTypography(self: *const Manifest, name: []const u8) ?*const TypographyToken {
        return self.typography.getPtr(name);
    }

    pub fn getComponent(self: *const Manifest, name: []const u8) ?*const ComponentStyle {
        return self.components.getPtr(name);
    }

    pub fn toTheme(self: *const Manifest, allocator: std.mem.Allocator) !Theme {
        var result = Theme.init(allocator);
        errdefer result.deinit();

        if (self.name.len != 0) try result.setName(self.name);
        if (self.description.len != 0) try result.setDescription(self.description);
        result.variant = self.variant;
        result.origin = self.origin;

        var palette_it = self.palette.iterator();
        while (palette_it.next()) |entry| {
            try putColor(&result.defs, allocator, entry.key_ptr.*, entry.value_ptr.*);
        }

        var token_it = self.tokens.iterator();
        while (token_it.next()) |entry| {
            try putColor(&result.palette_tokens, allocator, entry.key_ptr.*, entry.value_ptr.*);
        }

        if (self.getColor("accent")) |accent| {
            result.colors.accent = accent;
            result.colors.primary = accent;
            result.colors.border_active = accent;
            result.syntax.keyword = accent;
            result.syntax.operator = accent;
        }
        if (self.getColor("accent_hover")) |accent_hover| {
            result.colors.secondary = accent_hover;
            result.syntax.function = accent_hover;
        } else if (self.getColor("surface_alt")) |surface_alt| {
            result.colors.secondary = surface_alt;
        }
        if (self.getColor("background")) |background| {
            result.colors.background = background;
        }
        if (self.getColor("surface")) |surface| {
            result.colors.background_panel = surface;
            result.syntax.variable = surface;
        }
        if (self.getColor("surface_alt")) |surface_alt| {
            result.colors.background_element = surface_alt;
        }
        if (self.getColor("text")) |text| {
            result.colors.text = text;
        }
        if (self.getColor("text_muted")) |muted| {
            result.colors.text_muted = muted;
            result.syntax.comment = muted;
        }
        if (self.getColor("success")) |success_color| {
            result.colors.success = success_color;
            result.syntax.string = success_color;
        }
        if (self.getColor("warning")) |warning_color| {
            result.colors.warning = warning_color;
            result.syntax.number = warning_color;
        }
        if (self.getColor("danger")) |danger_color| {
            result.colors.error_color = danger_color;
            result.syntax.constant = danger_color;
        }
        if (self.getColor("info")) |info_color| {
            result.colors.info = info_color;
        }
        if (self.getColor("border")) |border_color| {
            result.colors.border = border_color;
        }
        if (self.getColor("border_muted")) |border_muted| {
            result.colors.border_subtle = border_muted;
        }

        var typo_it = self.typography.iterator();
        while (typo_it.next()) |entry| {
            const key = entry.key_ptr.*;
            const token = entry.value_ptr.*;
            var preset = ThemeTypographyPreset{};
            preset.weight = token.weight;
            preset.tracking = token.tracking;
            preset.uppercase = token.uppercase;
            preset.attributes = token.attributes;
            if (token.family.len != 0) {
                try preset.setFamily(result.allocator, token.family);
            }
            try result.typography.set(key, preset);
        }

        var component_it = self.components.iterator();
        while (component_it.next()) |entry| {
            var component = ThemeComponentStyle{
                .fg = entry.value_ptr.*.fg,
                .bg = entry.value_ptr.*.bg,
                .attributes = entry.value_ptr.*.attributes,
            };
            if (entry.value_ptr.*.typography) |typo_name| {
                component.setTypography(result.allocator, typo_name) catch |err| {
                    component.deinit(result.allocator);
                    return err;
                };
            }
            result.setComponentStyle(entry.key_ptr.*, component) catch |err| {
                component.deinit(result.allocator);
                return err;
            };
        }

        return result;
    }

    fn putPaletteColor(self: *Manifest, key: []const u8, value: Color) !void {
        try putColor(&self.palette, self.allocator, key, value);
    }

    fn putTokenColor(self: *Manifest, key: []const u8, value: Color) !void {
        try putColor(&self.tokens, self.allocator, key, value);
    }

    fn putTypographyToken(self: *Manifest, key: []const u8, token: TypographyToken) !void {
        var entry = try self.typography.getOrPut(key);
        if (entry.found_existing) {
            entry.value_ptr.deinit(self.allocator);
        } else {
            entry.key_ptr.* = try self.allocator.dupe(u8, key);
        }
        entry.value_ptr.* = token;
    }

    fn putComponent(self: *Manifest, key: []const u8, component: ComponentStyle) !void {
        var entry = try self.components.getOrPut(key);
        if (entry.found_existing) {
            entry.value_ptr.deinit(self.allocator);
        } else {
            entry.key_ptr.* = try self.allocator.dupe(u8, key);
        }
        entry.value_ptr.* = component;
    }
};

pub const TypographyToken = struct {
    family: []const u8 = "",
    weight: u16 = 400,
    tracking: i8 = 0,
    uppercase: bool = false,
    attributes: Attributes = Attributes.none(),
    owns_family: bool = false,

    pub fn setFamily(self: *TypographyToken, allocator: std.mem.Allocator, value: []const u8) !void {
        if (self.owns_family) allocator.free(@constCast(self.family));
        self.family = try allocator.dupe(u8, value);
        self.owns_family = true;
    }

    pub fn deinit(self: *TypographyToken, allocator: std.mem.Allocator) void {
        if (self.owns_family) allocator.free(@constCast(self.family));
    }
};

pub const ComponentStyle = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    attributes: Attributes = Attributes.none(),
    typography: ?[]const u8 = null,
    owns_typography: bool = false,

    pub fn setTypography(self: *ComponentStyle, allocator: std.mem.Allocator, name: []const u8) !void {
        if (self.owns_typography) {
            if (self.typography) |existing| {
                allocator.free(@constCast(existing));
                self.typography = null;
                self.owns_typography = false;
            }
        }
        self.typography = try allocator.dupe(u8, name);
        self.owns_typography = true;
    }

    pub fn deinit(self: *ComponentStyle, allocator: std.mem.Allocator) void {
        if (self.owns_typography) {
            if (self.typography) |name| {
                allocator.free(@constCast(name));
            }
        }
    }
};

fn parsePaletteSection(manifest: *Manifest, obj: std.json.ObjectMap) ManifestError!void {
    var iter = obj.iterator();
    while (iter.next()) |entry| {
        const value = entry.value_ptr.*;
        if (value != .string) return ManifestError.InvalidPaletteEntry;
        const color = try parseColorLiteral(value.string);
        try manifest.putPaletteColor(entry.key_ptr.*, color);
    }
}

fn parseTokensSection(manifest: *Manifest, obj: std.json.ObjectMap) ManifestError!void {
    var iter = obj.iterator();
    while (iter.next()) |entry| {
        const value = entry.value_ptr.*;
        if (value != .string) return ManifestError.InvalidTokensEntry;
        const color = try resolveColorRef(&manifest.palette, &manifest.tokens, value.string);
        try manifest.putTokenColor(entry.key_ptr.*, color);
    }
}

fn parseTypographySection(manifest: *Manifest, obj: std.json.ObjectMap) ManifestError!void {
    var iter = obj.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* != .object) return ManifestError.InvalidTypographyEntry;
        const preset_obj = entry.value_ptr.*.object;

        var token = TypographyToken{};
        errdefer token.deinit(manifest.allocator);

        if (preset_obj.get("family")) |family_val| {
            if (family_val != .string) return ManifestError.InvalidTypographyEntry;
            try token.setFamily(manifest.allocator, family_val.string);
        }

        if (preset_obj.get("weight")) |weight_val| {
            switch (weight_val) {
                .integer => |int_val| {
                    const clamped = std.math.clamp(int_val, 0, @as(i64, std.math.maxInt(u16)));
                    token.weight = @intCast(clamped);
                },
                .float => |float_val| {
                    const converted: i64 = @intFromFloat(float_val);
                    const clamped = std.math.clamp(converted, 0, @as(i64, std.math.maxInt(u16)));
                    token.weight = @intCast(clamped);
                },
                else => return ManifestError.InvalidTypographyEntry,
            }
        }

        if (preset_obj.get("tracking")) |tracking_val| {
            const amount: i64 = switch (tracking_val) {
                .integer => |int_val| int_val,
                .float => |float_val| @intFromFloat(float_val),
                else => return ManifestError.InvalidTypographyEntry,
            };
            const clamped = std.math.clamp(amount, -128, 127);
            token.tracking = @intCast(clamped);
        }

        if (preset_obj.get("uppercase")) |upper_val| {
            if (upper_val != .bool) return ManifestError.InvalidTypographyEntry;
            token.uppercase = upper_val.bool;
        }

        if (preset_obj.get("attributes")) |attrs_val| {
            if (attrs_val != .array) return ManifestError.InvalidTypographyEntry;
            token.attributes = try attributesFromArray(attrs_val.array);
        }

        if (preset_obj.get("style")) |style_val| {
            if (style_val != .array) return ManifestError.InvalidTypographyEntry;
            var attrs = token.attributes;
            for (style_val.array.items) |item| {
                if (item != .string) return ManifestError.InvalidTypographyEntry;
                try applyAttributeToken(&attrs, item.string);
            }
            token.attributes = attrs;
        }

        try manifest.putTypographyToken(entry.key_ptr.*, token);
    }
}

fn parseComponentsSection(manifest: *Manifest, obj: std.json.ObjectMap) ManifestError!void {
    var iter = obj.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* != .object) return ManifestError.InvalidComponentEntry;
        const comp_obj = entry.value_ptr.*.object;

        var component = ComponentStyle{};
        errdefer component.deinit(manifest.allocator);

        if (comp_obj.get("fg")) |fg_val| {
            if (fg_val != .string) return ManifestError.InvalidComponentEntry;
            component.fg = try resolveColorRef(&manifest.palette, &manifest.tokens, fg_val.string);
        }

        if (comp_obj.get("bg")) |bg_val| {
            if (bg_val != .string) return ManifestError.InvalidComponentEntry;
            component.bg = try resolveColorRef(&manifest.palette, &manifest.tokens, bg_val.string);
        }

        if (comp_obj.get("attributes")) |attrs_val| {
            if (attrs_val != .array) return ManifestError.InvalidComponentEntry;
            component.attributes = try attributesFromArray(attrs_val.array);
        }

        if (comp_obj.get("typography")) |typo_val| {
            if (typo_val != .string) return ManifestError.InvalidComponentEntry;
            try component.setTypography(manifest.allocator, typo_val.string);
        }

        try manifest.putComponent(entry.key_ptr.*, component);
    }
}

fn attributesFromArray(array: std.json.Array) ManifestError!Attributes {
    var attrs = Attributes.none();
    for (array.items) |item| {
        if (item != .string) return ManifestError.UnknownAttributeToken;
        try applyAttributeToken(&attrs, item.string);
    }
    return attrs;
}

fn applyAttributeToken(attrs: *Attributes, token: []const u8) ManifestError!void {
    if (ascii.eqlIgnoreCase(token, "bold")) {
        attrs.bold = true;
    } else if (ascii.eqlIgnoreCase(token, "italic")) {
        attrs.italic = true;
    } else if (ascii.eqlIgnoreCase(token, "underline")) {
        attrs.underline = true;
    } else if (ascii.eqlIgnoreCase(token, "strikethrough") or ascii.eqlIgnoreCase(token, "strike")) {
        attrs.strikethrough = true;
    } else if (ascii.eqlIgnoreCase(token, "dim")) {
        attrs.dim = true;
    } else if (ascii.eqlIgnoreCase(token, "reverse")) {
        attrs.reverse = true;
    } else if (ascii.eqlIgnoreCase(token, "blink")) {
        attrs.blink = true;
    } else {
        return ManifestError.UnknownAttributeToken;
    }
}

fn parseColorLiteral(text: []const u8) ManifestError!Color {
    if (text.len == 0) return ManifestError.InvalidColorLiteral;

    if (text[0] == '#') {
        if (text.len != 7) return ManifestError.InvalidColorLiteral;
        const r = try std.fmt.parseInt(u8, text[1..3], 16);
        const g = try std.fmt.parseInt(u8, text[3..5], 16);
        const b = try std.fmt.parseInt(u8, text[5..7], 16);
        return Color{ .rgb = .{ .r = r, .g = g, .b = b } };
    }

    if (colorFromName(text)) |named| {
        return named;
    }

    if (text.len > 7 and ascii.eqlIgnoreCase(text[0..6], "index(") and text[text.len - 1] == ')') {
        const raw = text[6 .. text.len - 1];
        const value = try std.fmt.parseInt(u8, raw, 10);
        return Color{ .indexed = value };
    }

    return ManifestError.InvalidColorLiteral;
}

fn resolveColorRef(palette: *const std.StringHashMap(Color), tokens: *const std.StringHashMap(Color), reference: []const u8) ManifestError!Color {
    const literal = parseColorLiteral(reference) catch |err| switch (err) {
        ManifestError.InvalidColorLiteral => null,
        else => return err,
    };
    if (literal) |color| {
        return color;
    }

    if (tokens.get(reference)) |color| {
        return color;
    }
    if (palette.get(reference)) |color| {
        return color;
    }

    return ManifestError.UnknownColorReference;
}

fn originFromString(value: []const u8) ?ThemeOrigin {
    var buf: [32]u8 = undefined;
    const normalized = normalizeKey(value, &buf);
    if (std.mem.eql(u8, normalized, "builtin")) return .builtin;
    if (std.mem.eql(u8, normalized, "user")) return .user;
    if (std.mem.eql(u8, normalized, "dynamic")) return .dynamic;
    return null;
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

fn putColor(map: *std.StringHashMap(Color), allocator: std.mem.Allocator, key: []const u8, value: Color) !void {
    var entry = try map.getOrPut(key);
    if (!entry.found_existing) {
        entry.key_ptr.* = try allocator.dupe(u8, key);
    }
    entry.value_ptr.* = value;
}

fn freeStringKeys(comptime T: type, allocator: std.mem.Allocator, map: *std.StringHashMap(T)) void {
    var iter = map.keyIterator();
    while (iter.next()) |key| {
        allocator.free(@constCast(key.*));
    }
}

// Tests
const testing = std.testing;

fn expectRgb(color: Color, r: u8, g: u8, b: u8) !void {
    switch (color) {
        .rgb => |rgb| {
            try testing.expectEqual(r, rgb.r);
            try testing.expectEqual(g, rgb.g);
            try testing.expectEqual(b, rgb.b);
        },
        else => try testing.expect(false),
    }
}

test "manifest parse and validate" {
    const json =
        \\\{
        \\  "name": "Phantom Dark",
        \\  "description": "Default dark manifest prototype",
        \\  "variant": "dark",
        \\  "palette": {
        \\    "background": "#0d1117",
        \\    "surface": "#161b22",
        \\    "surface_alt": "#1f2933",
        \\    "accent": "#7f5af0",
        \\    "accent_hover": "#9061f9",
        \\    "text": "#e5e7eb",
        \\    "text_muted": "#94a3b8",
        \\    "success": "#2cb67d",
        \\    "warning": "#f8d477",
        \\    "danger": "#ef4565",
        \\    "info": "#3da9fc",
        \\    "border": "#30363d",
        \\    "border_muted": "#1e2430"
        \\  },
        \\  "tokens": {
        \\    "background": "background",
        \\    "surface": "surface",
        \\    "surface_alt": "surface_alt",
        \\    "accent": "accent",
        \\    "accent_hover": "accent_hover",
        \\    "text": "text",
        \\    "text_muted": "text_muted",
        \\    "success": "success",
        \\    "warning": "warning",
        \\    "danger": "danger",
        \\    "info": "info",
        \\    "border": "border",
        \\    "border_muted": "border_muted"
        \\  },
        \\  "typography": {
        \\    "heading": {"family": "JetBrains Mono", "weight": 700, "attributes": ["bold"]},
        \\    "body": {"family": "Iosevka", "weight": 400}
        \\  },
        \\  "components": {
        \\    "button.primary": {"fg": "background", "bg": "accent", "attributes": ["bold"], "typography": "heading"}
        \\  }
        \\}
    ;

    var manifest = try Manifest.parse(testing.allocator, json);
    defer manifest.deinit();

    try manifest.validate();

    const accent = manifest.getColor("accent").?;
    try expectRgb(accent, 0x7f, 0x5a, 0xf0);

    const button = manifest.getComponent("button.primary").?;
    try testing.expect(button.attributes.bold);
    try expectRgb(button.bg.?, 0x7f, 0x5a, 0xf0);
    try testing.expectEqualStrings("heading", button.typography.?);

    var theme_instance = try manifest.toTheme(testing.allocator);
    defer theme_instance.deinit();
    try expectRgb(theme_instance.colors.background, 0x0d, 0x11, 0x17);

    const resolved_button_style = theme_instance.resolveComponentStyle("button.primary").?;
    try expectRgb(resolved_button_style.bg.?, 0x7f, 0x5a, 0xf0);

    const resolved_button_typography = theme_instance.getComponentTypography("button.primary").?;
    try testing.expect(resolved_button_typography.attributes.bold);
}

test "manifest validation detects missing tokens" {
    const json =
        \\\{
        \\  "name": "Incomplete",
        \\  "palette": {
        \\    "accent": "#ffffff"
        \\  }
        \\}
    ;

    var manifest = try Manifest.parse(testing.allocator, json);
    defer manifest.deinit();

    try testing.expectError(ManifestError.MissingRequiredToken, manifest.validate());
}
