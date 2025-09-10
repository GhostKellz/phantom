//! Emoji support utilities for Phantom TUI
const std = @import("std");

/// Common emoji sets for TUI applications
pub const Emoji = struct {
    // Status indicators
    pub const success = "✅";
    pub const err = "❌";
    pub const warning = "⚠️";
    pub const info = "ℹ️";
    pub const pending = "⏳";
    pub const running = "🔄";
    pub const cancelled = "🚫";

    // Progress indicators
    pub const download = "⬇️";
    pub const upload = "⬆️";
    pub const building = "🔨";
    pub const installing = "📦";
    pub const searching = "🔍";
    pub const updating = "🔄";

    // Package management
    pub const package = "📦";
    pub const dependency = "🔗";
    pub const security = "🔒";
    pub const trusted = "✅";
    pub const untrusted = "⚠️";
    pub const aur = "🏗️";
    pub const official = "🏛️";

    // File operations
    pub const file = "📄";
    pub const folder = "📁";
    pub const config = "⚙️";
    pub const log = "📋";
    pub const database = "🗄️";

    // System
    pub const cpu = "💻";
    pub const memory = "🧠";
    pub const disk = "💾";
    pub const network = "🌐";
    pub const terminal = "💻";

    // Navigation
    pub const up = "⬆️";
    pub const down = "⬇️";
    pub const left = "⬅️";
    pub const right = "➡️";
    pub const home = "🏠";
    pub const back = "⬅️";

    // Actions
    pub const play = "▶️";
    pub const pause = "⏸️";
    pub const stop = "⏹️";
    pub const reload = "🔄";
    pub const save = "💾";
    pub const delete = "🗑️";
    pub const edit = "✏️";
    pub const copy = "📋";
    pub const paste = "📄";

    // UI Elements
    pub const menu = "☰";
    pub const settings = "⚙️";
    pub const help = "❓";
    pub const close = "❌";
    pub const minimize = "➖";
    pub const maximize = "⬜";

    // Special
    pub const phantom = "👻";
    pub const zion = "🪐";
    pub const reaper = "⚰️";
    pub const rocket = "🚀";
    pub const star = "⭐";
    pub const lightning = "⚡";
    pub const fire = "🔥";
    pub const gem = "💎";
};

/// Progress bar emoji styles
pub const ProgressStyle = enum {
    blocks, // ████████░░
    circles, // ●●●●●○○○○○
    arrows, // >>>>>>>>--
    dots, // ••••••····
    bars, // ||||||||··

    pub fn getFilledChar(self: ProgressStyle) u21 {
        return switch (self) {
            .blocks => '█',
            .circles => '●',
            .arrows => '>',
            .dots => '•',
            .bars => '|',
        };
    }

    pub fn getEmptyChar(self: ProgressStyle) u21 {
        return switch (self) {
            .blocks => '░',
            .circles => '○',
            .arrows => '-',
            .dots => '·',
            .bars => '·',
        };
    }
};

/// Unicode box drawing characters for layouts
pub const BoxChars = struct {
    // Single line
    pub const horizontal = "─";
    pub const vertical = "│";
    pub const top_left = "┌";
    pub const top_right = "┐";
    pub const bottom_left = "└";
    pub const bottom_right = "┘";
    pub const cross = "┼";
    pub const tee_up = "┴";
    pub const tee_down = "┬";
    pub const tee_left = "┤";
    pub const tee_right = "├";

    // Double line
    pub const double_horizontal = "═";
    pub const double_vertical = "║";
    pub const double_top_left = "╔";
    pub const double_top_right = "╗";
    pub const double_bottom_left = "╚";
    pub const double_bottom_right = "╝";
    pub const double_cross = "╬";

    // Rounded corners
    pub const round_top_left = "╭";
    pub const round_top_right = "╮";
    pub const round_bottom_left = "╰";
    pub const round_bottom_right = "╯";

    // Block elements
    pub const full_block = "█";
    pub const light_shade = "░";
    pub const medium_shade = "▒";
    pub const dark_shade = "▓";

    // Arrows
    pub const arrow_up = "↑";
    pub const arrow_down = "↓";
    pub const arrow_left = "←";
    pub const arrow_right = "→";
    pub const double_arrow_up = "⇑";
    pub const double_arrow_down = "⇓";
    pub const double_arrow_left = "⇐";
    pub const double_arrow_right = "⇒";
};

/// Spinner animation frames
pub const Spinner = struct {
    pub const dots = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
    pub const line = [_][]const u8{ "|", "/", "-", "\\" };
    pub const circle = [_][]const u8{ "◐", "◓", "◑", "◒" };
    pub const arrows = [_][]const u8{ "←", "↖", "↑", "↗", "→", "↘", "↓", "↙" };
    pub const clock = [_][]const u8{ "🕐", "🕑", "🕒", "🕓", "🕔", "🕕", "🕖", "🕗", "🕘", "🕙", "🕚", "🕛" };
    pub const moon = [_][]const u8{ "🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘" };

    pub fn getFrame(comptime frames: []const []const u8, index: usize) []const u8 {
        return frames[index % frames.len];
    }
};

/// Status emoji helpers
pub const Status = struct {
    pub fn getTaskEmoji(status: anytype) []const u8 {
        return switch (status) {
            .pending => Emoji.pending,
            .running => Emoji.running,
            .completed => Emoji.success,
            .failed => Emoji.err,
            .cancelled => Emoji.cancelled,
            else => Emoji.info,
        };
    }

    pub fn getPackageEmoji(package_type: anytype) []const u8 {
        return switch (package_type) {
            .official => Emoji.official,
            .aur => Emoji.aur,
            .local => Emoji.file,
            .dependency => Emoji.dependency,
            else => Emoji.package,
        };
    }

    pub fn getTrustEmoji(trust_level: anytype) []const u8 {
        return switch (trust_level) {
            .trusted => Emoji.trusted,
            .untrusted => Emoji.untrusted,
            .unknown => Emoji.warning,
            else => Emoji.info,
        };
    }
};

/// Helper for measuring emoji width in terminal
pub fn getDisplayWidth(text: []const u8) usize {
    // Simplified emoji width calculation
    // Most emoji are 2 characters wide in terminals
    var width: usize = 0;
    var i: usize = 0;

    while (i < text.len) {
        const byte = text[i];
        if (byte < 0x80) {
            // ASCII character
            width += 1;
            i += 1;
        } else {
            // Multi-byte character (likely emoji)
            // Skip UTF-8 sequence and assume width of 2
            if (byte >= 0xF0) {
                i += 4; // 4-byte sequence
            } else if (byte >= 0xE0) {
                i += 3; // 3-byte sequence
            } else if (byte >= 0xC0) {
                i += 2; // 2-byte sequence
            } else {
                i += 1; // Invalid, treat as 1 byte
            }
            width += 2; // Assume emoji width
        }
    }

    return width;
}

/// Helper for truncating text with emoji awareness
pub fn truncateText(allocator: std.mem.Allocator, text: []const u8, max_width: usize) ![]const u8 {
    if (getDisplayWidth(text) <= max_width) {
        return try allocator.dupe(u8, text);
    }

    // Simple truncation - could be improved with proper Unicode handling
    var result = std.ArrayList(u8){};
    var width: usize = 0;
    var i: usize = 0;

    while (i < text.len and width < max_width) {
        const byte = text[i];
        var char_len: usize = 1;
        var char_width: usize = 1;

        if (byte >= 0xF0) {
            char_len = 4;
            char_width = 2;
        } else if (byte >= 0xE0) {
            char_len = 3;
            char_width = 2;
        } else if (byte >= 0xC0) {
            char_len = 2;
            char_width = 1;
        }

        if (width + char_width > max_width) break;

        try result.appendSlice(allocator, text[i .. i + char_len]);
        width += char_width;
        i += char_len;
    }

    if (i < text.len) {
        try result.appendSlice(allocator, "…");
    }

    return result.toOwnedSlice(allocator);
}

test "emoji display width calculation" {
    try std.testing.expect(getDisplayWidth("hello") == 5);
    try std.testing.expect(getDisplayWidth("👻") == 2);
    try std.testing.expect(getDisplayWidth("📦 Package") == 10); // 2 + 1 + 7
}

test "progress style characters" {
    try std.testing.expect(ProgressStyle.blocks.getFilledChar() == '█');
    try std.testing.expect(ProgressStyle.blocks.getEmptyChar() == '░');
    try std.testing.expect(ProgressStyle.circles.getFilledChar() == '●');
    try std.testing.expect(ProgressStyle.circles.getEmptyChar() == '○');
}
