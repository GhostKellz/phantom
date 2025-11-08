//! Diff Viewer Widget - Side-by-side or unified diff display
//! Perfect for git integration, code review, file comparison
//! Supports syntax highlighting integration with Grove

const std = @import("std");
const phantom = @import("../root.zig");
const Widget = phantom.Widget;
const Buffer = phantom.Buffer;
const Cell = phantom.Cell;
const Event = phantom.Event;
const Key = phantom.Key;
const Rect = phantom.Rect;
const Style = phantom.Style;
const Color = phantom.Color;

/// Diff hunk - represents a block of changes
pub const DiffHunk = struct {
    allocator: std.mem.Allocator,
    old_start: usize,
    old_count: usize,
    new_start: usize,
    new_count: usize,
    lines: std.ArrayList(DiffLine),

    pub fn init(allocator: std.mem.Allocator, old_start: usize, old_count: usize, new_start: usize, new_count: usize) DiffHunk {
        return .{
            .allocator = allocator,
            .old_start = old_start,
            .old_count = old_count,
            .new_start = new_start,
            .new_count = new_count,
            .lines = std.ArrayList(DiffLine).init(allocator),
        };
    }

    pub fn deinit(self: *DiffHunk) void {
        for (self.lines.items) |*line| {
            self.allocator.free(line.content);
        }
        self.lines.deinit();
    }

    pub fn addLine(self: *DiffHunk, line: DiffLine) !void {
        const owned_line = DiffLine{
            .kind = line.kind,
            .content = try self.allocator.dupe(u8, line.content),
            .old_line_no = line.old_line_no,
            .new_line_no = line.new_line_no,
        };
        try self.lines.append(owned_line);
    }
};

/// Diff line type
pub const DiffLineKind = enum {
    context,  // Unchanged line (white)
    added,    // Added line (green)
    removed,  // Removed line (red)
    header,   // Hunk header (cyan)
};

/// Single line in a diff
pub const DiffLine = struct {
    kind: DiffLineKind,
    content: []const u8,
    old_line_no: ?usize,
    new_line_no: ?usize,
};

/// Diff display mode
pub const DiffMode = enum {
    unified,      // Traditional unified diff
    side_by_side, // Split view
};

/// Configuration for Diff viewer
pub const DiffConfig = struct {
    mode: DiffMode = .unified,
    context_lines: usize = 3,
    show_line_numbers: bool = true,
    syntax_highlight: bool = false, // TODO: Integrate with Grove

    /// Styles
    added_style: Style = Style.default().withFg(Color.green),
    removed_style: Style = Style.default().withFg(Color.red),
    context_style: Style = Style.default(),
    header_style: Style = Style.default().withFg(Color.cyan).withBold(),
    line_number_style: Style = Style.default().withFg(Color.bright_black),

    /// Characters
    added_char: u21 = '+',
    removed_char: u21 = '-',
    context_char: u21 = ' ',

    pub fn default() DiffConfig {
        return .{};
    }
};

/// Custom error types
pub const Error = error{
    InvalidDiff,
    ParseError,
} || std.mem.Allocator.Error;

/// Diff viewer widget
pub const Diff = struct {
    widget: Widget,
    allocator: std.mem.Allocator,

    hunks: std.ArrayList(DiffHunk),
    current_hunk: usize,
    scroll_offset: usize,
    viewport_height: u16,

    config: DiffConfig,

    // File info
    old_file: ?[]const u8,
    new_file: ?[]const u8,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator, config: DiffConfig) Error!*Diff {
        const diff = try allocator.create(Diff);
        diff.* = .{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .hunks = .{},
            .current_hunk = 0,
            .scroll_offset = 0,
            .viewport_height = 10,
            .config = config,
            .old_file = null,
            .new_file = null,
        };
        return diff;
    }

    /// Set file names
    pub fn setFiles(self: *Diff, old_file: []const u8, new_file: []const u8) !void {
        if (self.old_file) |old| self.allocator.free(old);
        if (self.new_file) |new| self.allocator.free(new);

        self.old_file = try self.allocator.dupe(u8, old_file);
        self.new_file = try self.allocator.dupe(u8, new_file);
    }

    /// Add a hunk to the diff
    pub fn addHunk(self: *Diff, hunk: DiffHunk) !void {
        try self.hunks.append(self.allocator, hunk);
    }

    /// Parse unified diff format
    pub fn parseUnifiedDiff(self: *Diff, diff_text: []const u8) !void {
        var lines = std.mem.tokenizeScalar(u8, diff_text, '\n');

        var current_hunk: ?DiffHunk = null;
        var old_line_no: usize = 0;
        var new_line_no: usize = 0;

        while (lines.next()) |line| {
            if (line.len == 0) continue;

            // File headers
            if (std.mem.startsWith(u8, line, "---")) {
                // Old file
                const filename = std.mem.trimLeft(u8, line[3..], " \t");
                try self.setFiles(filename, self.new_file orelse "");
                continue;
            }
            if (std.mem.startsWith(u8, line, "+++")) {
                // New file
                const filename = std.mem.trimLeft(u8, line[3..], " \t");
                if (self.old_file) |old| {
                    try self.setFiles(old, filename);
                }
                continue;
            }

            // Hunk header: @@ -old_start,old_count +new_start,new_count @@
            if (std.mem.startsWith(u8, line, "@@")) {
                // Save previous hunk
                if (current_hunk) |*hunk| {
                    try self.addHunk(hunk.*);
                }

                // Parse hunk header
                var parts = std.mem.tokenizeAny(u8, line, " @,-+");
                _ = parts.next(); // Skip "@@"

                const old_start_str = parts.next() orelse return Error.ParseError;
                const old_count_str = parts.next() orelse return Error.ParseError;
                const new_start_str = parts.next() orelse return Error.ParseError;
                const new_count_str = parts.next() orelse return Error.ParseError;

                const old_start = try std.fmt.parseInt(usize, old_start_str, 10);
                const old_count = try std.fmt.parseInt(usize, old_count_str, 10);
                const new_start = try std.fmt.parseInt(usize, new_start_str, 10);
                const new_count = try std.fmt.parseInt(usize, new_count_str, 10);

                current_hunk = DiffHunk.init(self.allocator, old_start, old_count, new_start, new_count);
                old_line_no = old_start;
                new_line_no = new_start;

                // Add header line
                try current_hunk.?.addLine(.{
                    .kind = .header,
                    .content = line,
                    .old_line_no = null,
                    .new_line_no = null,
                });
                continue;
            }

            // Diff lines
            if (current_hunk != null) {
                const kind: DiffLineKind = if (line[0] == '+')
                    .added
                else if (line[0] == '-')
                    .removed
                else
                    .context;

                const content = if (line.len > 1) line[1..] else "";

                const diff_line = DiffLine{
                    .kind = kind,
                    .content = content,
                    .old_line_no = if (kind != .added) blk: {
                        defer old_line_no += 1;
                        break :blk old_line_no;
                    } else null,
                    .new_line_no = if (kind != .removed) blk: {
                        defer new_line_no += 1;
                        break :blk new_line_no;
                    } else null,
                };

                try current_hunk.?.addLine(diff_line);
            }
        }

        // Add final hunk
        if (current_hunk) |*hunk| {
            try self.addHunk(hunk.*);
        }
    }

    /// Navigate to next hunk
    pub fn nextHunk(self: *Diff) void {
        if (self.current_hunk + 1 < self.hunks.items.len) {
            self.current_hunk += 1;
            // Scroll to show hunk
            self.scroll_offset = self.getHunkStartLine(self.current_hunk);
        }
    }

    /// Navigate to previous hunk
    pub fn prevHunk(self: *Diff) void {
        if (self.current_hunk > 0) {
            self.current_hunk -= 1;
            self.scroll_offset = self.getHunkStartLine(self.current_hunk);
        }
    }

    fn getHunkStartLine(self: *const Diff, hunk_idx: usize) usize {
        var line: usize = 0;
        for (self.hunks.items[0..hunk_idx]) |hunk| {
            line += hunk.lines.items.len;
        }
        return line;
    }

    fn getTotalLines(self: *const Diff) usize {
        var total: usize = 0;
        for (self.hunks.items) |hunk| {
            total += hunk.lines.items.len;
        }
        return total;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *Diff = @fieldParentPtr("widget", widget);

        self.viewport_height = area.height;

        if (self.hunks.items.len == 0) {
            buffer.writeText(area.x, area.y, "No diff to display", Style.default().withFg(Color.bright_black));
            return;
        }

        // Render file header
        var y: u16 = 0;
        if (self.old_file) |old| {
            const header = std.fmt.allocPrint(self.allocator, "--- {s}", .{old}) catch return;
            defer self.allocator.free(header);
            buffer.writeText(area.x, area.y + y, header, self.config.header_style);
            y += 1;
        }
        if (self.new_file) |new| {
            const header = std.fmt.allocPrint(self.allocator, "+++ {s}", .{new}) catch return;
            defer self.allocator.free(header);
            buffer.writeText(area.x, area.y + y, header, self.config.header_style);
            y += 1;
        }

        // Render diff lines
        const total_lines = self.getTotalLines();
        const end_line = @min(self.scroll_offset + (area.height - y), total_lines);

        var current_line: usize = 0;
        for (self.hunks.items) |hunk| {
            for (hunk.lines.items) |line| {
                if (current_line >= self.scroll_offset and current_line < end_line and y < area.height) {
                    self.renderLine(buffer, area.x, area.y + y, area.width, &line);
                    y += 1;
                }
                current_line += 1;
            }
        }
    }

    fn renderLine(self: *const Diff, buffer: *Buffer, x: u16, y: u16, width: u16, line: *const DiffLine) void {
        const style = switch (line.kind) {
            .added => self.config.added_style,
            .removed => self.config.removed_style,
            .context => self.config.context_style,
            .header => self.config.header_style,
        };

        const marker = switch (line.kind) {
            .added => self.config.added_char,
            .removed => self.config.removed_char,
            .context => self.config.context_char,
            .header => '@',
        };

        var current_x = x;

        // Line numbers (if enabled)
        if (self.config.show_line_numbers and line.kind != .header) {
            const old_no = if (line.old_line_no) |no| std.fmt.allocPrint(self.allocator, "{d:4}", .{no}) catch return else std.fmt.allocPrint(self.allocator, "    ", .{}) catch return;
            defer self.allocator.free(old_no);
            buffer.writeText(current_x, y, old_no, self.config.line_number_style);
            current_x += 5;

            const new_no = if (line.new_line_no) |no| std.fmt.allocPrint(self.allocator, "{d:4}", .{no}) catch return else std.fmt.allocPrint(self.allocator, "    ", .{}) catch return;
            defer self.allocator.free(new_no);
            buffer.writeText(current_x, y, new_no, self.config.line_number_style);
            current_x += 5;
        }

        // Marker
        buffer.setCell(current_x, y, Cell.init(marker, style));
        current_x += 1;

        // Content
        const remaining_width = width -| (current_x - x);
        const content_to_show = if (line.content.len > remaining_width)
            line.content[0..remaining_width]
        else
            line.content;

        buffer.writeText(current_x, y, content_to_show, style);
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *Diff = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key| {
                switch (key) {
                    .up, .char => |c| {
                        if (key == .up or (key == .char and c == 'k')) {
                            if (self.scroll_offset > 0) {
                                self.scroll_offset -= 1;
                            }
                            return true;
                        }
                    },
                    .down => {
                        const total = self.getTotalLines();
                        if (self.scroll_offset + self.viewport_height < total) {
                            self.scroll_offset += 1;
                        }
                        return true;
                    },
                    .page_up => {
                        self.scroll_offset -|= self.viewport_height;
                        return true;
                    },
                    .page_down => {
                        const total = self.getTotalLines();
                        self.scroll_offset = @min(self.scroll_offset + self.viewport_height, total -| self.viewport_height);
                        return true;
                    },
                    else => {
                        if (key == .char) {
                            const c = key.char;
                            if (c == 'j') {
                                const total = self.getTotalLines();
                                if (self.scroll_offset + self.viewport_height < total) {
                                    self.scroll_offset += 1;
                                }
                                return true;
                            } else if (c == 'n') {
                                self.nextHunk();
                                return true;
                            } else if (c == 'p') {
                                self.prevHunk();
                                return true;
                            }
                        }
                    },
                }
            },
            .mouse => |mouse| {
                if (mouse.button == .wheel_up and self.scroll_offset > 0) {
                    self.scroll_offset -= 1;
                    return true;
                }
                if (mouse.button == .wheel_down) {
                    const total = self.getTotalLines();
                    if (self.scroll_offset + self.viewport_height < total) {
                        self.scroll_offset += 1;
                    }
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *Diff = @fieldParentPtr("widget", widget);
        self.viewport_height = area.height;
    }

    fn deinit(widget: *Widget) void {
        const self: *Diff = @fieldParentPtr("widget", widget);

        for (self.hunks.items) |*hunk| {
            hunk.deinit();
        }
        self.hunks.deinit();

        if (self.old_file) |old| self.allocator.free(old);
        if (self.new_file) |new| self.allocator.free(new);

        self.allocator.destroy(self);
    }
};

// Tests
test "Diff basic operations" {
    const testing = std.testing;

    const diff = try Diff.init(testing.allocator, DiffConfig.default());
    defer diff.widget.vtable.deinit(&diff.widget);

    try diff.setFiles("old.txt", "new.txt");
    try testing.expectEqualStrings("old.txt", diff.old_file.?);
    try testing.expectEqualStrings("new.txt", diff.new_file.?);
}

test "Diff parse unified format" {
    const testing = std.testing;

    const diff_text =
        \\--- old.txt
        \\+++ new.txt
        \\@@ -1,3 +1,3 @@
        \\ context line
        \\-removed line
        \\+added line
        \\ context line
    ;

    const diff = try Diff.init(testing.allocator, DiffConfig.default());
    defer diff.widget.vtable.deinit(&diff.widget);

    try diff.parseUnifiedDiff(diff_text);

    try testing.expectEqual(@as(usize, 1), diff.hunks.items.len);
    try testing.expect(diff.hunks.items[0].lines.items.len > 0);
}
