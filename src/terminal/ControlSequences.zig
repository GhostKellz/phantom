//! ControlSequences - Comprehensive terminal control sequences module
//! Provides all terminal escape sequences and control codes used by phantom

const std = @import("std");

/// ESC sequence builder and formatter
pub const EscapeSequence = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EscapeSequence {
        return EscapeSequence{ .allocator = allocator };
    }

    /// Format CSI sequence with parameters
    pub fn csi(self: EscapeSequence, comptime command: []const u8, params: anytype) ![]u8 {
        return self.format("\x1b[{}" ++ command, params);
    }

    /// Format OSC sequence with parameters
    pub fn osc(self: EscapeSequence, comptime command: []const u8, params: anytype) ![]u8 {
        return self.format("\x1b]" ++ command ++ "\x07", params);
    }

    /// Format DCS sequence with parameters
    pub fn dcs(self: EscapeSequence, comptime command: []const u8, params: anytype) ![]u8 {
        return self.format("\x1bP" ++ command ++ "\x1b\\", params);
    }

    /// Generic format function
    fn format(self: EscapeSequence, comptime fmt: []const u8, params: anytype) ![]u8 {
        return std.fmt.allocPrint(self.allocator, fmt, params);
    }
};

/// Cursor movement and positioning
pub const Cursor = struct {
    /// Move cursor up by n lines
    pub const UP = "\x1b[{d}A";
    /// Move cursor down by n lines
    pub const DOWN = "\x1b[{d}B";
    /// Move cursor right by n columns
    pub const RIGHT = "\x1b[{d}C";
    /// Move cursor left by n columns
    pub const LEFT = "\x1b[{d}D";

    /// Move cursor to next line, n times
    pub const NEXT_LINE = "\x1b[{d}E";
    /// Move cursor to previous line, n times
    pub const PREV_LINE = "\x1b[{d}F";
    /// Move cursor to column n
    pub const TO_COLUMN = "\x1b[{d}G";
    /// Move cursor to position (row, col)
    pub const TO_POSITION = "\x1b[{d};{d}H";

    /// Save cursor position
    pub const SAVE = "\x1b[s";
    /// Restore cursor position
    pub const RESTORE = "\x1b[u";
    /// Save cursor position (DEC)
    pub const SAVE_DEC = "\x1b7";
    /// Restore cursor position (DEC)
    pub const RESTORE_DEC = "\x1b8";

    /// Hide cursor
    pub const HIDE = "\x1b[?25l";
    /// Show cursor
    pub const SHOW = "\x1b[?25h";

    /// Enable cursor blinking
    pub const BLINK_ON = "\x1b[?12h";
    /// Disable cursor blinking
    pub const BLINK_OFF = "\x1b[?12l";

    /// Query cursor position
    pub const QUERY_POSITION = "\x1b[6n";

    /// Cursor shape sequences
    pub const SHAPE_BLOCK = "\x1b[2 q";
    pub const SHAPE_UNDERLINE = "\x1b[4 q";
    pub const SHAPE_BAR = "\x1b[6 q";

    /// Format cursor movement sequence
    pub fn up(allocator: std.mem.Allocator, lines: u16) ![]u8 {
        return std.fmt.allocPrint(allocator, UP, .{lines});
    }

    pub fn down(allocator: std.mem.Allocator, lines: u16) ![]u8 {
        return std.fmt.allocPrint(allocator, DOWN, .{lines});
    }

    pub fn right(allocator: std.mem.Allocator, cols: u16) ![]u8 {
        return std.fmt.allocPrint(allocator, RIGHT, .{cols});
    }

    pub fn left(allocator: std.mem.Allocator, cols: u16) ![]u8 {
        return std.fmt.allocPrint(allocator, LEFT, .{cols});
    }

    pub fn toPosition(allocator: std.mem.Allocator, row: u16, col: u16) ![]u8 {
        return std.fmt.allocPrint(allocator, TO_POSITION, .{ row, col });
    }

    pub fn toColumn(allocator: std.mem.Allocator, col: u16) ![]u8 {
        return std.fmt.allocPrint(allocator, TO_COLUMN, .{col});
    }
};

/// Screen and buffer manipulation
pub const Screen = struct {
    /// Clear entire screen
    pub const CLEAR_ALL = "\x1b[2J";
    /// Clear from cursor to end of screen
    pub const CLEAR_TO_END = "\x1b[0J";
    /// Clear from cursor to beginning of screen
    pub const CLEAR_TO_START = "\x1b[1J";

    /// Clear entire line
    pub const CLEAR_LINE = "\x1b[2K";
    /// Clear from cursor to end of line
    pub const CLEAR_LINE_TO_END = "\x1b[0K";
    /// Clear from cursor to beginning of line
    pub const CLEAR_LINE_TO_START = "\x1b[1K";

    /// Scroll up by n lines
    pub const SCROLL_UP = "\x1b[{d}S";
    /// Scroll down by n lines
    pub const SCROLL_DOWN = "\x1b[{d}T";

    /// Enter alternate screen buffer
    pub const ALT_SCREEN_ON = "\x1b[?1049h";
    /// Exit alternate screen buffer
    pub const ALT_SCREEN_OFF = "\x1b[?1049l";

    /// Save screen
    pub const SAVE_SCREEN = "\x1b[?47h";
    /// Restore screen
    pub const RESTORE_SCREEN = "\x1b[?47l";

    /// Insert n lines
    pub const INSERT_LINES = "\x1b[{d}L";
    /// Delete n lines
    pub const DELETE_LINES = "\x1b[{d}M";
    /// Insert n characters
    pub const INSERT_CHARS = "\x1b[{d}@";
    /// Delete n characters
    pub const DELETE_CHARS = "\x1b[{d}P";
    /// Erase n characters
    pub const ERASE_CHARS = "\x1b[{d}X";

    pub fn scrollUp(allocator: std.mem.Allocator, lines: u16) ![]u8 {
        return std.fmt.allocPrint(allocator, SCROLL_UP, .{lines});
    }

    pub fn scrollDown(allocator: std.mem.Allocator, lines: u16) ![]u8 {
        return std.fmt.allocPrint(allocator, SCROLL_DOWN, .{lines});
    }

    pub fn insertLines(allocator: std.mem.Allocator, lines: u16) ![]u8 {
        return std.fmt.allocPrint(allocator, INSERT_LINES, .{lines});
    }

    pub fn deleteLines(allocator: std.mem.Allocator, lines: u16) ![]u8 {
        return std.fmt.allocPrint(allocator, DELETE_LINES, .{lines});
    }
};

/// Mouse support sequences
pub const Mouse = struct {
    /// Enable basic mouse reporting
    pub const ENABLE_BASIC = "\x1b[?1000h";
    /// Disable basic mouse reporting
    pub const DISABLE_BASIC = "\x1b[?1000l";

    /// Enable mouse button event tracking
    pub const ENABLE_BUTTON_EVENT = "\x1b[?1002h";
    /// Disable mouse button event tracking
    pub const DISABLE_BUTTON_EVENT = "\x1b[?1002l";

    /// Enable mouse motion event tracking
    pub const ENABLE_MOTION = "\x1b[?1003h";
    /// Disable mouse motion event tracking
    pub const DISABLE_MOTION = "\x1b[?1003l";

    /// Enable SGR mouse mode (better for large terminals)
    pub const ENABLE_SGR = "\x1b[?1006h";
    /// Disable SGR mouse mode
    pub const DISABLE_SGR = "\x1b[?1006l";

    /// Enable focus events
    pub const ENABLE_FOCUS = "\x1b[?1004h";
    /// Disable focus events
    pub const DISABLE_FOCUS = "\x1b[?1004l";

    /// Enable all mouse features
    pub const ENABLE_ALL = ENABLE_BASIC ++ ENABLE_BUTTON_EVENT ++ ENABLE_MOTION ++ ENABLE_SGR ++ ENABLE_FOCUS;
    /// Disable all mouse features
    pub const DISABLE_ALL = DISABLE_FOCUS ++ DISABLE_SGR ++ DISABLE_MOTION ++ DISABLE_BUTTON_EVENT ++ DISABLE_BASIC;

    /// Mouse shape sequences
    pub const SHAPE_DEFAULT = "\x1b[0 q";
    pub const SHAPE_POINTER = "\x1b[2 q";
    pub const SHAPE_HAND = "\x1b[4 q";
    pub const SHAPE_TEXT = "\x1b[6 q";
    pub const SHAPE_CROSSHAIR = "\x1b[8 q";
    pub const SHAPE_WAIT = "\x1b[10 q";
    pub const SHAPE_HELP = "\x1b[12 q";
    pub const SHAPE_PROGRESS = "\x1b[14 q";
};

/// Color and styling sequences
pub const Color = struct {
    /// Reset all attributes
    pub const RESET = "\x1b[0m";

    /// Text attributes
    pub const BOLD = "\x1b[1m";
    pub const DIM = "\x1b[2m";
    pub const ITALIC = "\x1b[3m";
    pub const UNDERLINE = "\x1b[4m";
    pub const BLINK = "\x1b[5m";
    pub const REVERSE = "\x1b[7m";
    pub const STRIKETHROUGH = "\x1b[9m";

    /// Reset specific attributes
    pub const RESET_BOLD = "\x1b[22m";
    pub const RESET_DIM = "\x1b[22m";
    pub const RESET_ITALIC = "\x1b[23m";
    pub const RESET_UNDERLINE = "\x1b[24m";
    pub const RESET_BLINK = "\x1b[25m";
    pub const RESET_REVERSE = "\x1b[27m";
    pub const RESET_STRIKETHROUGH = "\x1b[29m";

    /// 8-color foreground
    pub const FG_BLACK = "\x1b[30m";
    pub const FG_RED = "\x1b[31m";
    pub const FG_GREEN = "\x1b[32m";
    pub const FG_YELLOW = "\x1b[33m";
    pub const FG_BLUE = "\x1b[34m";
    pub const FG_MAGENTA = "\x1b[35m";
    pub const FG_CYAN = "\x1b[36m";
    pub const FG_WHITE = "\x1b[37m";
    pub const FG_DEFAULT = "\x1b[39m";

    /// 8-color background
    pub const BG_BLACK = "\x1b[40m";
    pub const BG_RED = "\x1b[41m";
    pub const BG_GREEN = "\x1b[42m";
    pub const BG_YELLOW = "\x1b[43m";
    pub const BG_BLUE = "\x1b[44m";
    pub const BG_MAGENTA = "\x1b[45m";
    pub const BG_CYAN = "\x1b[46m";
    pub const BG_WHITE = "\x1b[47m";
    pub const BG_DEFAULT = "\x1b[49m";

    /// Bright 8-color foreground
    pub const FG_BRIGHT_BLACK = "\x1b[90m";
    pub const FG_BRIGHT_RED = "\x1b[91m";
    pub const FG_BRIGHT_GREEN = "\x1b[92m";
    pub const FG_BRIGHT_YELLOW = "\x1b[93m";
    pub const FG_BRIGHT_BLUE = "\x1b[94m";
    pub const FG_BRIGHT_MAGENTA = "\x1b[95m";
    pub const FG_BRIGHT_CYAN = "\x1b[96m";
    pub const FG_BRIGHT_WHITE = "\x1b[97m";

    /// Bright 8-color background
    pub const BG_BRIGHT_BLACK = "\x1b[100m";
    pub const BG_BRIGHT_RED = "\x1b[101m";
    pub const BG_BRIGHT_GREEN = "\x1b[102m";
    pub const BG_BRIGHT_YELLOW = "\x1b[103m";
    pub const BG_BRIGHT_BLUE = "\x1b[104m";
    pub const BG_BRIGHT_MAGENTA = "\x1b[105m";
    pub const BG_BRIGHT_CYAN = "\x1b[106m";
    pub const BG_BRIGHT_WHITE = "\x1b[107m";

    /// 256-color sequences
    pub const FG_256 = "\x1b[38;5;{d}m";
    pub const BG_256 = "\x1b[48;5;{d}m";

    /// True color (24-bit) sequences
    pub const FG_RGB = "\x1b[38;2;{d};{d};{d}m";
    pub const BG_RGB = "\x1b[48;2;{d};{d};{d}m";

    /// Format color sequences
    pub fn fg256(allocator: std.mem.Allocator, color: u8) ![]u8 {
        return std.fmt.allocPrint(allocator, FG_256, .{color});
    }

    pub fn bg256(allocator: std.mem.Allocator, color: u8) ![]u8 {
        return std.fmt.allocPrint(allocator, BG_256, .{color});
    }

    pub fn fgRgb(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
        return std.fmt.allocPrint(allocator, FG_RGB, .{ r, g, b });
    }

    pub fn bgRgb(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
        return std.fmt.allocPrint(allocator, BG_RGB, .{ r, g, b });
    }
};

/// Keyboard and input sequences
pub const Keyboard = struct {
    /// Enable bracketed paste mode
    pub const BRACKETED_PASTE_ON = "\x1b[?2004h";
    /// Disable bracketed paste mode
    pub const BRACKETED_PASTE_OFF = "\x1b[?2004l";

    /// Enable application keypad mode
    pub const KEYPAD_APP_ON = "\x1b[?1h";
    /// Disable application keypad mode
    pub const KEYPAD_APP_OFF = "\x1b[?1l";

    /// Enable application cursor keys
    pub const CURSOR_KEYS_APP = "\x1b[?1h";
    /// Enable normal cursor keys
    pub const CURSOR_KEYS_NORMAL = "\x1b[?1l";

    /// Auto-repeat on
    pub const AUTO_REPEAT_ON = "\x1b[?8h";
    /// Auto-repeat off
    pub const AUTO_REPEAT_OFF = "\x1b[?8l";

    /// Meta key sends escape
    pub const META_ESCAPE_ON = "\x1b[?1036h";
    /// Meta key sets 8th bit
    pub const META_ESCAPE_OFF = "\x1b[?1036l";

    /// Request kitty keyboard protocol
    pub const KITTY_KEYBOARD = "\x1b[>1u";
    /// Disable kitty keyboard protocol
    pub const KITTY_KEYBOARD_OFF = "\x1b[<u";
};

/// Window and title manipulation
pub const Window = struct {
    /// Set window title
    pub const SET_TITLE = "\x1b]0;{s}\x07";
    /// Set icon title
    pub const SET_ICON = "\x1b]1;{s}\x07";
    /// Set window title only
    pub const SET_WINDOW_TITLE = "\x1b]2;{s}\x07";

    /// Query window title
    pub const QUERY_TITLE = "\x1b]0;?\x07";
    /// Query icon title
    pub const QUERY_ICON = "\x1b]1;?\x07";
    /// Query window title only
    pub const QUERY_WINDOW_TITLE = "\x1b]2;?\x07";

    /// Window size queries
    pub const QUERY_SIZE_CHARS = "\x1b[18t";
    pub const QUERY_SIZE_PIXELS = "\x1b[14t";
    pub const QUERY_SCREEN_SIZE = "\x1b[19t";

    /// Window manipulation
    pub const MINIMIZE = "\x1b[2t";
    pub const MAXIMIZE = "\x1b[1t";
    pub const RESTORE = "\x1b[3t";
    pub const RAISE_WINDOW = "\x1b[5t";
    pub const LOWER_WINDOW = "\x1b[6t";

    pub fn setTitle(allocator: std.mem.Allocator, title: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, SET_TITLE, .{title});
    }

    pub fn setIcon(allocator: std.mem.Allocator, icon: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, SET_ICON, .{icon});
    }

    pub fn setWindowTitle(allocator: std.mem.Allocator, title: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, SET_WINDOW_TITLE, .{title});
    }
};

/// Terminal mode and feature detection
pub const Terminal = struct {
    /// Query terminal capabilities
    pub const QUERY_DA1 = "\x1b[c";
    pub const QUERY_DA2 = "\x1b[>c";
    pub const QUERY_DA3 = "\x1b[=c";

    /// Device attributes
    pub const DEVICE_ATTRS = "\x1b[0c";

    /// Query color support
    pub const QUERY_COLORS = "\x1b[4;{d};?\x07";
    pub const QUERY_FG_COLOR = "\x1b]10;?\x07";
    pub const QUERY_BG_COLOR = "\x1b]11;?\x07";
    pub const QUERY_CURSOR_COLOR = "\x1b]12;?\x07";

    /// Terminal reset sequences
    pub const SOFT_RESET = "\x1b[!p";
    pub const HARD_RESET = "\x1bc";
    pub const FULL_RESET = "\x1b[!p\x1b[?3;4l\x1b[4l\x1b>";

    /// Line drawing character set
    pub const CHARSET_DRAWING_ON = "\x1b(0";
    pub const CHARSET_DRAWING_OFF = "\x1b(B";

    /// UTF-8 mode
    pub const UTF8_ON = "\x1b%G";
    pub const UTF8_OFF = "\x1b%@";

    pub fn queryColor(allocator: std.mem.Allocator, index: u8) ![]u8 {
        return std.fmt.allocPrint(allocator, QUERY_COLORS, .{index});
    }
};

/// OSC 52 clipboard sequences
pub const Clipboard = struct {
    /// Copy to clipboard
    pub const COPY = "\x1b]52;c;{s}\x07";
    /// Copy to primary selection
    pub const COPY_PRIMARY = "\x1b]52;p;{s}\x07";
    /// Query clipboard contents
    pub const QUERY = "\x1b]52;c;?\x07";
    /// Query primary selection
    pub const QUERY_PRIMARY = "\x1b]52;p;?\x07";

    pub fn copy(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, COPY, .{data});
    }

    pub fn copyPrimary(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, COPY_PRIMARY, .{data});
    }
};

/// Image display protocols
pub const Images = struct {
    /// Kitty graphics protocol
    pub const KITTY_DISPLAY = "\x1b_G{s}\x1b\\";
    /// Sixel graphics
    pub const SIXEL_START = "\x1bPq";
    pub const SIXEL_END = "\x1b\\";
    /// iTerm2 inline images
    pub const ITERM2_DISPLAY = "\x1b]1337;File={s}\x07";

    pub fn kittyImage(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, KITTY_DISPLAY, .{data});
    }

    pub fn iterm2Image(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, ITERM2_DISPLAY, .{data});
    }
};

/// Common control codes
pub const ControlCodes = struct {
    pub const NUL = "\x00"; // Null
    pub const BEL = "\x07"; // Bell
    pub const BS = "\x08";  // Backspace
    pub const HT = "\x09";  // Horizontal Tab
    pub const LF = "\x0A";  // Line Feed
    pub const VT = "\x0B";  // Vertical Tab
    pub const FF = "\x0C";  // Form Feed
    pub const CR = "\x0D";  // Carriage Return
    pub const ESC = "\x1B"; // Escape
    pub const DEL = "\x7F"; // Delete

    // C1 control codes
    pub const IND = "\x1bD";  // Index
    pub const NEL = "\x1bE";  // Next Line
    pub const HTS = "\x1bH";  // Horizontal Tab Set
    pub const RI = "\x1bM";   // Reverse Index
    pub const SS2 = "\x1bN";  // Single Shift 2
    pub const SS3 = "\x1bO";  // Single Shift 3
    pub const DCS = "\x1bP";  // Device Control String
    pub const CSI = "\x1b[";  // Control Sequence Introducer
    pub const ST = "\x1b\\"; // String Terminator
    pub const OSC = "\x1b]";  // Operating System Command
    pub const SOS = "\x1bX";  // Start of String
    pub const APC = "\x1b_";  // Application Program Command
};

/// Sequence builder utility
pub const SequenceBuilder = struct {
    allocator: std.mem.Allocator,
    buffer: std.array_list.AlignedManaged(u8, null),

    pub fn init(allocator: std.mem.Allocator) SequenceBuilder {
        return SequenceBuilder{
            .allocator = allocator,
            .buffer = std.array_list.AlignedManaged(u8, null).init(allocator),
        };
    }

    pub fn deinit(self: *SequenceBuilder) void {
        self.buffer.deinit();
    }

    /// Add sequence to buffer
    pub fn add(self: *SequenceBuilder, sequence: []const u8) !*SequenceBuilder {
        try self.buffer.appendSlice(sequence);
        return self;
    }

    /// Add formatted sequence
    pub fn addFmt(self: *SequenceBuilder, comptime fmt: []const u8, args: anytype) !*SequenceBuilder {
        const formatted = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(formatted);
        try self.buffer.appendSlice(formatted);
        return self;
    }

    /// Build final sequence
    pub fn build(self: *SequenceBuilder) ![]u8 {
        return self.buffer.toOwnedSlice();
    }

    /// Reset buffer for reuse
    pub fn reset(self: *SequenceBuilder) void {
        self.buffer.clearRetainingCapacity();
    }
};

test "Cursor movement sequences" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const up_seq = try Cursor.up(arena.allocator(), 5);
    try std.testing.expectEqualStrings("\x1b[5A", up_seq);

    const pos_seq = try Cursor.toPosition(arena.allocator(), 10, 20);
    try std.testing.expectEqualStrings("\x1b[10;20H", pos_seq);
}

test "Color sequences" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const fg_seq = try Color.fg256(arena.allocator(), 42);
    try std.testing.expectEqualStrings("\x1b[38;5;42m", fg_seq);

    const rgb_seq = try Color.fgRgb(arena.allocator(), 255, 128, 64);
    try std.testing.expectEqualStrings("\x1b[38;2;255;128;64m", rgb_seq);
}

test "SequenceBuilder" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var builder = SequenceBuilder.init(arena.allocator());
    defer builder.deinit();

    const sequence = try builder
        .add(Cursor.HIDE)
        .add(Screen.CLEAR_ALL)
        .addFmt(Cursor.TO_POSITION, .{ 1, 1 })
        .add(Color.FG_RED)
        .build();

    defer arena.allocator().free(sequence);

    _ = "\x1b[?25l\x1b[2J\x1b[{d};{d}H\x1b[31m";
    try std.testing.expect(std.mem.indexOf(u8, sequence, "\x1b[?25l") != null);
    try std.testing.expect(std.mem.indexOf(u8, sequence, "\x1b[2J") != null);
}