//! GlobalTTY - Global TTY instance for panic recovery and terminal state management
//! Provides a global TTY instance that can be safely accessed during panics

const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

/// Global TTY instance for emergency recovery
var global_tty: ?*TTY = null;
var global_tty_mutex = std.Thread.Mutex{};

/// TTY management structure
pub const TTY = struct {
    allocator: Allocator,
    fd: std.os.fd_t,
    original_termios: ?std.os.termios = null,
    current_termios: ?std.os.termios = null,
    is_initialized: bool = false,
    is_raw_mode: bool = false,
    alternate_screen: bool = false,
    mouse_enabled: bool = false,
    backup_state: BackupState = .{},

    /// Backup of terminal state for recovery
    const BackupState = struct {
        cursor_visible: bool = true,
        cursor_position: ?CursorPosition = null,
        window_title: ?[]u8 = null,
        icon_title: ?[]u8 = null,
    };

    const CursorPosition = struct {
        row: u16,
        col: u16,
    };

    pub fn init(allocator: Allocator, fd: std.os.fd_t) !TTY {
        var tty = TTY{
            .allocator = allocator,
            .fd = fd,
        };

        // Get original terminal attributes
        if (std.os.tcgetattr(fd)) |termios| {
            tty.original_termios = termios;
            tty.current_termios = termios;
            tty.is_initialized = true;
        } else |err| {
            std.log.warn("Failed to get terminal attributes: {}", .{err});
        }

        return tty;
    }

    pub fn deinit(self: *TTY) void {
        self.restoreState() catch |err| {
            std.log.warn("Failed to restore terminal state: {}", .{err});
        };

        if (self.backup_state.window_title) |title| {
            self.allocator.free(title);
        }
        if (self.backup_state.icon_title) |title| {
            self.allocator.free(title);
        }
    }

    /// Enter raw mode
    pub fn enterRawMode(self: *TTY) !void {
        if (!self.is_initialized or self.is_raw_mode) return;

        var raw_termios = self.original_termios.?;

        // Disable canonical mode, echo, signals, and flow control
        raw_termios.lflag &= ~@as(std.os.tcflag_t, std.os.ECHO | std.os.ICANON | std.os.ISIG | std.os.IEXTEN);
        raw_termios.iflag &= ~@as(std.os.tcflag_t, std.os.IXON | std.os.ICRNL | std.os.BRKINT | std.os.INPCK | std.os.ISTRIP);
        raw_termios.oflag &= ~@as(std.os.tcflag_t, std.os.OPOST);
        raw_termios.cflag |= std.os.CS8;

        // Set timeout for read operations
        raw_termios.cc[std.os.VMIN] = 0;  // Minimum chars to read
        raw_termios.cc[std.os.VTIME] = 1; // Timeout in tenths of seconds

        try std.os.tcsetattr(self.fd, std.os.TCSA.NOW, raw_termios);
        self.current_termios = raw_termios;
        self.is_raw_mode = true;
    }

    /// Exit raw mode
    pub fn exitRawMode(self: *TTY) !void {
        if (!self.is_initialized or !self.is_raw_mode) return;

        try std.os.tcsetattr(self.fd, std.os.TCSA.NOW, self.original_termios.?);
        self.current_termios = self.original_termios;
        self.is_raw_mode = false;
    }

    /// Enter alternate screen buffer
    pub fn enterAlternateScreen(self: *TTY) !void {
        if (self.alternate_screen) return;

        try self.writeSequence(ENTER_ALT_SCREEN);
        self.alternate_screen = true;
    }

    /// Exit alternate screen buffer
    pub fn exitAlternateScreen(self: *TTY) !void {
        if (!self.alternate_screen) return;

        try self.writeSequence(EXIT_ALT_SCREEN);
        self.alternate_screen = false;
    }

    /// Enable mouse reporting
    pub fn enableMouse(self: *TTY) !void {
        if (self.mouse_enabled) return;

        try self.writeSequence(ENABLE_MOUSE);
        self.mouse_enabled = true;
    }

    /// Disable mouse reporting
    pub fn disableMouse(self: *TTY) !void {
        if (!self.mouse_enabled) return;

        try self.writeSequence(DISABLE_MOUSE);
        self.mouse_enabled = false;
    }

    /// Hide cursor
    pub fn hideCursor(self: *TTY) !void {
        self.backup_state.cursor_visible = false;
        try self.writeSequence(HIDE_CURSOR);
    }

    /// Show cursor
    pub fn showCursor(self: *TTY) !void {
        self.backup_state.cursor_visible = true;
        try self.writeSequence(SHOW_CURSOR);
    }

    /// Save cursor position
    pub fn saveCursor(self: *TTY) !void {
        try self.writeSequence(SAVE_CURSOR);
    }

    /// Restore cursor position
    pub fn restoreCursor(self: *TTY) !void {
        try self.writeSequence(RESTORE_CURSOR);
    }

    /// Clear screen
    pub fn clearScreen(self: *TTY) !void {
        try self.writeSequence(CLEAR_SCREEN);
    }

    /// Get cursor position (requires response parsing)
    pub fn getCursorPosition(self: *TTY) !?CursorPosition {
        try self.writeSequence(QUERY_CURSOR_POS);

        // Read response (would need proper parsing in real implementation)
        var buffer: [32]u8 = undefined;
        const bytes_read = try std.os.read(self.fd, &buffer);

        if (bytes_read > 0) {
            // Parse ESC[row;colR format
            const response = buffer[0..bytes_read];
            return self.parseCursorPosition(response);
        }

        return null;
    }

    /// Parse cursor position response
    fn parseCursorPosition(self: *TTY, response: []const u8) ?CursorPosition {
        _ = self;

        if (response.len < 6) return null;
        if (!std.mem.startsWith(u8, response, "\x1b[")) return null;
        if (!std.mem.endsWith(u8, response, "R")) return null;

        const data = response[2..response.len-1];
        const semicolon_pos = std.mem.indexOf(u8, data, ";") orelse return null;

        const row_str = data[0..semicolon_pos];
        const col_str = data[semicolon_pos+1..];

        const row = std.fmt.parseInt(u16, row_str, 10) catch return null;
        const col = std.fmt.parseInt(u16, col_str, 10) catch return null;

        return CursorPosition{ .row = row, .col = col };
    }

    /// Restore terminal to original state
    pub fn restoreState(self: *TTY) !void {
        if (!self.is_initialized) return;

        // Restore terminal attributes
        if (self.is_raw_mode) {
            self.exitRawMode() catch |err| {
                std.log.warn("Failed to exit raw mode: {}", .{err});
            };
        }

        // Exit alternate screen if needed
        if (self.alternate_screen) {
            self.exitAlternateScreen() catch |err| {
                std.log.warn("Failed to exit alternate screen: {}", .{err});
            };
        }

        // Disable mouse if enabled
        if (self.mouse_enabled) {
            self.disableMouse() catch |err| {
                std.log.warn("Failed to disable mouse: {}", .{err});
            };
        }

        // Restore cursor visibility
        if (self.backup_state.cursor_visible) {
            self.showCursor() catch |err| {
                std.log.warn("Failed to show cursor: {}", .{err});
            };
        }

        // Reset terminal modes
        self.writeSequence(RESET_ALL) catch |err| {
            std.log.warn("Failed to reset terminal: {}", .{err});
        };
    }

    /// Emergency recovery - minimal operations that should always work
    pub fn emergencyRestore(self: *TTY) void {
        // Use direct system calls to avoid potential failures

        // Restore original termios
        if (self.original_termios) |termios| {
            _ = std.os.tcsetattr(self.fd, std.os.TCSA.NOW, termios) catch {};
        }

        // Send basic reset sequences
        _ = std.os.write(self.fd, EMERGENCY_RESET) catch {};
    }

    /// Write escape sequence to terminal
    fn writeSequence(self: *TTY, sequence: []const u8) !void {
        _ = try std.os.write(self.fd, sequence);
    }

    /// Get terminal window size
    pub fn getWindowSize(self: *TTY) !WindowSize {
        var winsize: std.os.winsize = undefined;
        try std.os.ioctl(self.fd, std.os.T.IOCGWINSZ, @intFromPtr(&winsize));

        return WindowSize{
            .rows = winsize.ws_row,
            .cols = winsize.ws_col,
            .pixel_width = winsize.ws_xpixel,
            .pixel_height = winsize.ws_ypixel,
        };
    }

    /// Check if terminal supports colors
    pub fn supportsColors(self: *TTY) bool {
        _ = self;
        if (std.os.getenv("COLORTERM")) |_| return true;
        if (std.os.getenv("TERM")) |term| {
            return std.mem.indexOf(u8, term, "color") != null or
                   std.mem.indexOf(u8, term, "256") != null or
                   std.mem.indexOf(u8, term, "24bit") != null;
        }
        return false;
    }
};

/// Window size information
pub const WindowSize = struct {
    rows: u16,
    cols: u16,
    pixel_width: u16,
    pixel_height: u16,
};

// Terminal escape sequences
const ENTER_ALT_SCREEN = "\x1b[?1049h";
const EXIT_ALT_SCREEN = "\x1b[?1049l";
const ENABLE_MOUSE = "\x1b[?1000;1002;1003;1006h";
const DISABLE_MOUSE = "\x1b[?1000;1002;1003;1006l";
const HIDE_CURSOR = "\x1b[?25l";
const SHOW_CURSOR = "\x1b[?25h";
const SAVE_CURSOR = "\x1b[s";
const RESTORE_CURSOR = "\x1b[u";
const CLEAR_SCREEN = "\x1b[2J\x1b[H";
const QUERY_CURSOR_POS = "\x1b[6n";
const RESET_ALL = "\x1b[!p\x1b[?3;4l\x1b[4l\x1b>";
const EMERGENCY_RESET = "\x1b[!p\x1b[?1049l\x1b[?25h\x1b[0m";

/// Initialize global TTY instance
pub fn initGlobal(allocator: Allocator, fd: std.os.fd_t) !void {
    global_tty_mutex.lock();
    defer global_tty_mutex.unlock();

    if (global_tty != null) {
        return; // Already initialized
    }

    const tty = try allocator.create(TTY);
    tty.* = try TTY.init(allocator, fd);
    global_tty = tty;
}

/// Deinitialize global TTY instance
pub fn deinitGlobal() void {
    global_tty_mutex.lock();
    defer global_tty_mutex.unlock();

    if (global_tty) |tty| {
        const allocator = tty.allocator;
        tty.deinit();
        allocator.destroy(tty);
        global_tty = null;
    }
}

/// Get global TTY instance (thread-safe)
pub fn getGlobal() ?*TTY {
    global_tty_mutex.lock();
    defer global_tty_mutex.unlock();
    return global_tty;
}

/// Emergency restore function for panic situations
pub fn emergencyRestoreGlobal() void {
    // Don't use mutex in emergency situations to avoid deadlocks
    if (global_tty) |tty| {
        tty.emergencyRestore();
    }
}

/// Check if global TTY is initialized
pub fn isGlobalInitialized() bool {
    global_tty_mutex.lock();
    defer global_tty_mutex.unlock();
    return global_tty != null;
}

/// Safe wrapper for terminal operations
pub fn withGlobalTTY(comptime operation: fn(*TTY) anyerror!void) !void {
    if (getGlobal()) |tty| {
        try operation(tty);
    } else {
        return TTYError.NotInitialized;
    }
}

/// TTY errors
pub const TTYError = error{
    NotInitialized,
    AlreadyInitialized,
    InvalidTerminal,
    OperationFailed,
};

/// RAII wrapper for terminal state management
pub const TTYGuard = struct {
    tty: *TTY,
    should_restore: bool = true,

    pub fn init(tty: *TTY) TTYGuard {
        return TTYGuard{ .tty = tty };
    }

    pub fn deinit(self: *TTYGuard) void {
        if (self.should_restore) {
            self.tty.restoreState() catch |err| {
                std.log.warn("TTYGuard failed to restore state: {}", .{err});
            };
        }
    }

    pub fn disableRestore(self: *TTYGuard) void {
        self.should_restore = false;
    }

    /// Enter raw mode with automatic restoration
    pub fn enterRawMode(self: *TTYGuard) !void {
        try self.tty.enterRawMode();
    }

    /// Enter alternate screen with automatic restoration
    pub fn enterAlternateScreen(self: *TTYGuard) !void {
        try self.tty.enterAlternateScreen();
    }
};

test "TTY initialization" {
    // Use stdin for testing (might not be a TTY in test environment)
    if (builtin.os.tag == .linux) {
        var tty = TTY.init(std.testing.allocator, std.os.STDIN_FILENO) catch return;
        defer tty.deinit();

        // Basic tests that don't require actual TTY
        try std.testing.expect(!tty.is_raw_mode);
        try std.testing.expect(!tty.alternate_screen);
        try std.testing.expect(!tty.mouse_enabled);
    }
}

test "Global TTY management" {
    // Test global TTY initialization
    if (builtin.os.tag == .linux) {
        try initGlobal(std.testing.allocator, std.os.STDIN_FILENO);
        defer deinitGlobal();

        try std.testing.expect(isGlobalInitialized());
        try std.testing.expect(getGlobal() != null);
    }
}

test "Window size detection" {
    if (builtin.os.tag == .linux) {
        var tty = TTY.init(std.testing.allocator, std.os.STDIN_FILENO) catch return;
        defer tty.deinit();

        // Window size detection may fail in test environment
        _ = tty.getWindowSize() catch {};
    }
}

test "TTYGuard RAII" {
    if (builtin.os.tag == .linux) {
        var tty = TTY.init(std.testing.allocator, std.os.STDIN_FILENO) catch return;
        defer tty.deinit();

        {
            var guard = TTYGuard.init(&tty);
            defer guard.deinit();

            // Test that guard initializes properly
            try std.testing.expect(guard.should_restore);
        }
    }
}