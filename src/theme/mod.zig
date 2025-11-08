//! Theme module for Phantom TUI
//! Provides theme loading, management, and switching

pub const Theme = @import("Theme.zig").Theme;
pub const ThemeColors = @import("Theme.zig").ThemeColors;
pub const SyntaxColors = @import("Theme.zig").SyntaxColors;

pub const ThemeManager = @import("ThemeManager.zig").ThemeManager;
pub const ManifestLoader = @import("ManifestLoader.zig").ManifestLoader;
