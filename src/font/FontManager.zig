//! Phantom Font Manager - Advanced font rendering system architecture
//! Ready for integration with zfont + gcode when available
//! Current status: Stub implementation with full API defined

const std = @import("std");
const gcode = @import("gcode");
const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
font_cache: FontCache,
terminal_optimized: bool,
config: FontConfig,

const FontCache = struct {
    rendered_glyphs: std.AutoHashMap(GlyphKey, RenderedGlyph),
    allocator: Allocator,

    const GlyphKey = struct {
        codepoint: u21,
        font_id: usize,
        size: u16,

        pub fn hash(self: GlyphKey) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&self.codepoint));
            hasher.update(std.mem.asBytes(&self.font_id));
            hasher.update(std.mem.asBytes(&self.size));
            return hasher.final();
        }

        pub fn eql(a: GlyphKey, b: GlyphKey) bool {
            return a.codepoint == b.codepoint and
                a.font_id == b.font_id and
                a.size == b.size;
        }
    };

    pub const RenderedGlyph = struct {
        bitmap: []u8,
        width: u32,
        height: u32,
        advance: f32,
        bearing_x: i32,
        bearing_y: i32,
    };

    pub fn init(allocator: Allocator) FontCache {
        return FontCache{
            .rendered_glyphs = std.AutoHashMap(GlyphKey, RenderedGlyph).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FontCache) void {
        var iterator = self.rendered_glyphs.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.bitmap);
        }
        self.rendered_glyphs.deinit();
    }

    pub fn get(self: *FontCache, key: GlyphKey) ?RenderedGlyph {
        return self.rendered_glyphs.get(key);
    }

    pub fn put(self: *FontCache, key: GlyphKey, glyph: RenderedGlyph) !void {
        try self.rendered_glyphs.put(key, glyph);
    }

    pub fn clearCache(self: *FontCache) void {
        var iterator = self.rendered_glyphs.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.bitmap);
        }
        self.rendered_glyphs.clearRetainingCapacity();
    }
};

pub const FontConfig = struct {
    primary_font_family: []const u8 = "JetBrains Mono",
    fallback_families: []const []const u8 = &.{
        "Fira Code",
        "Cascadia Code",
        "Hack",
        "DejaVu Sans Mono",
        "Source Code Pro",
    },
    font_size: f32 = 14.0,
    dpi: u32 = 96,
    enable_ligatures: bool = true,
    enable_nerd_font_icons: bool = true,
    enable_subpixel_rendering: bool = true,
    enable_hinting: bool = true,
    terminal_optimized: bool = true,
    gamma: f32 = 1.8,
};

pub fn init(allocator: Allocator, config: FontConfig) !Self {
    return Self{
        .allocator = allocator,
        .font_cache = FontCache.init(allocator),
        .terminal_optimized = config.terminal_optimized,
        .config = config,
    };
}

pub fn deinit(self: *Self) void {
    self.font_cache.deinit();
}

/// Render text with full Unicode, BiDi, ligature, and font fallback support
/// TODO: Implement with zfont integration
pub fn renderText(self: *Self, text: []const u8, options: RenderTextOptions) !RenderedTextResult {
    _ = self;
    _ = text;
    _ = options;
    return error.NotImplemented;
}

/// Get display width of text (terminal column width) using gcode
pub fn getTextWidth(self: *Self, text: []const u8) !u32 {
    _ = self;
    // Use gcode for Unicode-aware width calculation
    return @intCast(gcode.stringWidth(text));
}

/// Get glyph for a specific codepoint with fallback support
/// TODO: Implement with zfont integration
pub fn getGlyph(self: *Self, codepoint: u21) !FontCache.RenderedGlyph {
    _ = self;
    _ = codepoint;
    return error.NotImplemented;
}

/// Get font features (ligatures, Nerd Font icons, etc.)
/// TODO: Implement with zfont integration
pub fn getFontFeatures(self: *Self) ?FontFeatures {
    // Stub: return default features based on config
    return FontFeatures{
        .has_ligatures = self.config.enable_ligatures,
        .has_nerd_font_icons = self.config.enable_nerd_font_icons,
        .is_monospace = true,
        .programming_optimized = true,
    };
}

/// Check if current font supports ligatures
pub fn supportsLigatures(self: *Self) bool {
    return self.config.enable_ligatures;
}

/// Check if current font has Nerd Font icons
pub fn hasNerdFontIcons(self: *Self) bool {
    return self.config.enable_nerd_font_icons;
}

/// Get Nerd Font icon by name
/// TODO: Implement with zfont integration
pub fn getNerdFontIcon(self: *Self, name: []const u8) ?NerdFontIcon {
    _ = self;
    _ = name;
    return null;
}

pub const FontFeatures = struct {
    has_ligatures: bool,
    has_nerd_font_icons: bool,
    is_monospace: bool,
    programming_optimized: bool,
};

pub const NerdFontIcon = struct {
    name: []const u8,
    codepoint: u21,
    category: []const u8,
};

pub const RenderTextOptions = struct {
    optimize_for_terminal: bool = true,
    enable_ligatures: bool = true,
    max_width: ?u32 = null,
};

pub const RenderedTextResult = struct {
    runs: std.ArrayList(TextRun),
    allocator: Allocator,

    pub fn init(allocator: Allocator) RenderedTextResult {
        return RenderedTextResult{
            .runs = std.ArrayList(TextRun).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RenderedTextResult) void {
        for (self.runs.items) |*run| {
            self.allocator.free(run.glyphs);
            self.allocator.free(run.positions);
        }
        self.runs.deinit();
    }
};

pub const TextRun = struct {
    glyphs: []u32,
    positions: []f32,
    start_offset: usize,
    length: usize,
    line_height_adjustment: f32 = 0,
    character_spacing: f32 = 0,
};

test "FontManager initialization" {
    const allocator = std.testing.allocator;

    const config = FontConfig{
        .primary_font_family = "DejaVu Sans Mono",
        .terminal_optimized = true,
    };

    var manager = try init(allocator, config);
    defer manager.deinit();

    // Font manager should be initialized
    try std.testing.expect(manager.terminal_optimized == true);
}

test "FontManager text width calculation" {
    const allocator = std.testing.allocator;

    const config = FontConfig{};
    var manager = try init(allocator, config);
    defer manager.deinit();

    // Test ASCII text width using gcode
    const width = try manager.getTextWidth("hello");
    try std.testing.expect(width == 5);
}
