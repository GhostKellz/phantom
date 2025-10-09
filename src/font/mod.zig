//! Phantom Font System
//! Advanced font rendering with zfont, gcode integration, ligatures, and GPU caching

pub const FontManager = @import("FontManager.zig");
pub const GlyphCache = @import("GlyphCache.zig");

// Re-export useful zfont types
pub const zfont = @import("zfont");
pub const RenderOptions = zfont.RenderOptions;
pub const FontWeight = zfont.FontWeight;
pub const FontStyle = zfont.FontStyle;

test {
    _ = FontManager;
    _ = GlyphCache;
}
