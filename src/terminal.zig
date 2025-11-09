//! Terminal interface for Phantom TUI
const std = @import("std");
const geometry = @import("geometry.zig");
const style = @import("style.zig");

const Rect = geometry.Rect;
const Size = geometry.Size;
const Position = geometry.Position;
const Style = style.Style;

/// Terminal cell containing character and style information
pub const Cell = struct {
    char: u21 = ' ',
    style: Style = Style.default(),

    pub fn init(char: u21, cell_style: Style) Cell {
        return Cell{ .char = char, .style = cell_style };
    }

    pub fn withChar(char: u21) Cell {
        return Cell{ .char = char };
    }

    pub fn withStyle(cell_style: Style) Cell {
        return Cell{ .style = cell_style };
    }
};

/// Screen buffer for double-buffered rendering
pub const Buffer = struct {
    cells: []Cell,
    size: Size,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, size: Size) !Buffer {
        const cells = try allocator.alloc(Cell, size.area());
        @memset(cells, Cell{});

        return Buffer{
            .cells = cells,
            .size = size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.cells);
    }

    pub fn resize(self: *Buffer, new_size: Size) !void {
        if (new_size.area() == self.size.area()) {
            self.size = new_size;
            return;
        }

        self.allocator.free(self.cells);
        self.cells = try self.allocator.alloc(Cell, new_size.area());
        @memset(self.cells, Cell{});
        self.size = new_size;
    }

    pub fn getCell(self: *const Buffer, x: u16, y: u16) ?*const Cell {
        if (x >= self.size.width or y >= self.size.height) {
            return null;
        }
        const index = @as(u32, y) * @as(u32, self.size.width) + @as(u32, x);
        return &self.cells[index];
    }

    pub fn getCellMut(self: *Buffer, x: u16, y: u16) ?*Cell {
        if (x >= self.size.width or y >= self.size.height) {
            return null;
        }
        const index = @as(u32, y) * @as(u32, self.size.width) + @as(u32, x);
        return &self.cells[index];
    }

    pub fn setCell(self: *Buffer, x: u16, y: u16, cell: Cell) void {
        if (self.getCellMut(x, y)) |cell_ptr| {
            cell_ptr.* = cell;
        }
    }

    pub fn clear(self: *Buffer) void {
        @memset(self.cells, Cell{});
    }

    pub fn fill(self: *Buffer, rect: Rect, cell: Cell) void {
        const end_x = @min(rect.x + rect.width, self.size.width);
        const end_y = @min(rect.y + rect.height, self.size.height);

        var y = rect.y;
        while (y < end_y) : (y += 1) {
            var x = rect.x;
            while (x < end_x) : (x += 1) {
                self.setCell(x, y, cell);
            }
        }
    }

    /// Write text to buffer at position with style
    pub fn writeText(self: *Buffer, x: u16, y: u16, text: []const u8, text_style: Style) void {
        var current_x = x;
        var utf8_iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };

        while (utf8_iter.nextCodepoint()) |codepoint| {
            if (current_x >= self.size.width) break;

            self.setCell(current_x, y, Cell.init(codepoint, text_style));
            current_x += 1;
        }
    }
};

/// Terminal state and operations
pub const Terminal = struct {
    size: Size,
    front_buffer: Buffer,
    back_buffer: Buffer,
    allocator: std.mem.Allocator,
    raw_mode: bool = false,
    original_termios: ?std.posix.termios = null,

    pub fn init(allocator: std.mem.Allocator) !Terminal {
        const size = try getTerminalSize();

        return Terminal{
            .size = size,
            .front_buffer = try Buffer.init(allocator, size),
            .back_buffer = try Buffer.init(allocator, size),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Terminal) void {
        if (self.raw_mode) {
            self.disableRawMode() catch {};
        }
        self.front_buffer.deinit();
        self.back_buffer.deinit();
    }

    pub fn enableRawMode(self: *Terminal) !void {
        if (self.raw_mode) return;

        // Save original terminal attributes
        const stdin_fd = std.posix.STDIN_FILENO;
        var termios = try std.posix.tcgetattr(stdin_fd);
        self.original_termios = termios;

        // Configure raw mode
        termios.lflag.ECHO = false;
        termios.lflag.ICANON = false;
        termios.lflag.ISIG = false;
        termios.lflag.IEXTEN = false;

        termios.iflag.IXON = false;
        termios.iflag.ICRNL = false;
        termios.iflag.BRKINT = false;
        termios.iflag.INPCK = false;
        termios.iflag.ISTRIP = false;

        termios.oflag.OPOST = false;
        termios.cflag.CSIZE = .CS8;

        termios.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        termios.cc[@intFromEnum(std.posix.V.TIME)] = 1;

        try std.posix.tcsetattr(stdin_fd, .NOW, termios);

        // Hide cursor and enable alternative screen
        try self.writeAnsi("\x1b[?25l\x1b[?1049h");

        self.raw_mode = true;
    }

    pub fn disableRawMode(self: *Terminal) !void {
        if (!self.raw_mode) return;

        // Clear alternate screen before exiting
        try self.writeAnsi("\x1b[2J\x1b[H");

        // Show cursor and disable alternative screen
        try self.writeAnsi("\x1b[?25h\x1b[?1049l");

        // Restore original terminal attributes
        if (self.original_termios) |termios| {
            try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, termios);
        }

        self.raw_mode = false;
    }

    pub fn resize(self: *Terminal, new_size: Size) !void {
        self.size = new_size;
        try self.front_buffer.resize(new_size);
        try self.back_buffer.resize(new_size);
    }

    pub fn clear(self: *Terminal) !void {
        self.back_buffer.clear();
    }

    pub fn getBackBuffer(self: *Terminal) *Buffer {
        return &self.back_buffer;
    }

    /// Swap buffers and render changes to terminal
    pub fn flush(self: *Terminal) !void {
        try self.renderDiff();

        // Swap buffers
        const temp = self.front_buffer;
        self.front_buffer = self.back_buffer;
        self.back_buffer = temp;
    }

    fn renderDiff(self: *Terminal) !void {
        var last_style: ?Style = null;
        var y: u16 = 0;

        while (y < self.size.height) : (y += 1) {
            var x: u16 = 0;
            while (x < self.size.width) : (x += 1) {
                const front_cell = self.front_buffer.getCell(x, y) orelse continue;
                const back_cell = self.back_buffer.getCell(x, y) orelse continue;

                // Only render if cell changed
                if (std.meta.eql(front_cell.*, back_cell.*)) continue;

                // Move cursor to position
                var buf: [32]u8 = undefined;
                const cursor_move = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y + 1, x + 1 });
                try self.writeAnsi(cursor_move);

                // Apply style if different from last
                if (last_style == null or !std.meta.eql(last_style.?, back_cell.style)) {
                    const style_codes = try back_cell.style.ansiCodes(self.allocator);
                    defer self.allocator.free(style_codes);
                    try self.writeAnsi(style_codes);
                    last_style = back_cell.style;
                }

                // Write character
                var char_buf: [4]u8 = undefined;
                const char_len = try std.unicode.utf8Encode(back_cell.char, &char_buf);
                try self.writeAnsi(char_buf[0..char_len]);
            }
        }

        // Reset style at end
        try self.writeAnsi("\x1b[0m");
    }

    fn writeAnsi(self: *Terminal, data: []const u8) !void {
        _ = self;
        try std.fs.File.stdout().writeAll(data);
    }
};

/// Get current terminal size using ioctl
pub fn getTerminalSize() !Size {
    if (@import("builtin").os.tag == .windows) {
        // Windows implementation would use GetConsoleScreenBufferInfo
        return Size.init(80, 24); // Default fallback for Windows
    }
    
    // Unix/Linux implementation using ioctl TIOCGWINSZ
    const c = std.c;
    const TIOCGWINSZ = if (@import("builtin").os.tag == .linux) 0x5413 else 0x40087468;
    
    const WinSize = extern struct {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16,
        ws_ypixel: u16,
    };
    
    var ws: WinSize = undefined;
    const stdout_file = std.fs.File.stdout;
    const stdout = stdout_file();
    
    const result = c.ioctl(stdout.handle, TIOCGWINSZ, &ws);
    if (result == -1) {
        // Fallback: try parsing environment variables
        if (std.posix.getenv("COLUMNS")) |cols_str| {
            if (std.posix.getenv("LINES")) |lines_str| {
                const cols = std.fmt.parseInt(u16, cols_str, 10) catch 80;
                const lines = std.fmt.parseInt(u16, lines_str, 10) catch 24;
                return Size.init(cols, lines);
            }
        }
        // Final fallback
        return Size.init(80, 24);
    }
    
    // Ensure minimum size
    const width = if (ws.ws_col > 0) ws.ws_col else 80;
    const height = if (ws.ws_row > 0) ws.ws_row else 24;
    
    return Size.init(width, height);
}

test "Buffer operations" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, Size.init(10, 5));
    defer buffer.deinit();

    try std.testing.expect(buffer.size.width == 10);
    try std.testing.expect(buffer.size.height == 5);

    const cell = Cell.withChar('A');
    buffer.setCell(5, 2, cell);

    const retrieved = buffer.getCell(5, 2).?;
    try std.testing.expect(retrieved.char == 'A');
}

test "Buffer text writing" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, Size.init(20, 5));
    defer buffer.deinit();

    buffer.writeText(0, 0, "Hello", Style.default());

    try std.testing.expect(buffer.getCell(0, 0).?.char == 'H');
    try std.testing.expect(buffer.getCell(4, 0).?.char == 'o');
}
