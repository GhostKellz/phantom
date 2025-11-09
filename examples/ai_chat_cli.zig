//! Professional AI Chat CLI - Similar to claude-code/gemini-cli
//! Features:
//! - Streaming responses with typewriter effect
//! - Syntax highlighting for code blocks
//! - Command history
//! - Multi-line input
//! - Token usage display

const std = @import("std");
const phantom = @import("phantom");

const MessageRole = enum { user, assistant, system };

const Message = struct {
    role: MessageRole,
    content: []const u8,
    sequence: u64,
};

const ChatState = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayList(Message),
    input_buffer: std.ArrayList(u8),
    command_history: std.ArrayList([]const u8),
    history_index: usize,
    scroll_offset: u16,
    is_streaming: bool,
    cursor_pos: usize,
    sequence_counter: u64,

    pub fn init(allocator: std.mem.Allocator) !*ChatState {
        const state = try allocator.create(ChatState);

        state.* = .{
            .allocator = allocator,
            .messages = .{},
            .input_buffer = .{},
            .command_history = .{},
            .history_index = 0,
            .scroll_offset = 0,
            .is_streaming = false,
            .cursor_pos = 0,
            .sequence_counter = 0,
        };

        // Add welcome message
        state.sequence_counter += 1;
        const welcome_msg = try allocator.dupe(u8, "AI Assistant v0.8.0 - Press Ctrl+C to exit, Enter to send");
        try state.messages.append(allocator, .{
            .role = .system,
            .content = welcome_msg,
            .sequence = state.sequence_counter,
        });

        return state;
    }

    pub fn deinit(self: *ChatState) void {
        for (self.messages.items) |msg| {
            self.allocator.free(msg.content);
        }
        self.messages.deinit(self.allocator);

        for (self.command_history.items) |cmd| {
            self.allocator.free(cmd);
        }
        self.command_history.deinit(self.allocator);

        self.input_buffer.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn addMessage(self: *ChatState, role: MessageRole, content: []const u8) !void {
        const owned_content = try self.allocator.dupe(u8, content);
        self.sequence_counter += 1;
        try self.messages.append(self.allocator, .{
            .role = role,
            .content = owned_content,
            .sequence = self.sequence_counter,
        });
    }

    pub fn submitInput(self: *ChatState) !void {
        if (self.input_buffer.items.len == 0) return;

        const input = try self.allocator.dupe(u8, self.input_buffer.items);
        try self.addMessage(.user, input);

        // Add to history
        try self.command_history.append(self.allocator, input);
        self.history_index = self.command_history.items.len;

        // Simulate AI response (in real app, this would call an API)
        const response = try std.fmt.allocPrint(
            self.allocator,
            "Echo: {s}\n\nThis is a demo response. In production, this would call an AI API like Claude or Gemini.",
            .{input}
        );
        defer self.allocator.free(response);
        try self.addMessage(.assistant, response);

        self.input_buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
    }

    pub fn historyUp(self: *ChatState) !void {
        if (self.history_index > 0) {
            self.history_index -= 1;
            const cmd = self.command_history.items[self.history_index];
            self.input_buffer.clearRetainingCapacity();
            try self.input_buffer.appendSlice(self.allocator, cmd);
            self.cursor_pos = self.input_buffer.items.len;
        }
    }

    pub fn historyDown(self: *ChatState) !void {
        if (self.history_index < self.command_history.items.len - 1) {
            self.history_index += 1;
            const cmd = self.command_history.items[self.history_index];
            self.input_buffer.clearRetainingCapacity();
            try self.input_buffer.appendSlice(self.allocator, cmd);
            self.cursor_pos = self.input_buffer.items.len;
        } else if (self.history_index == self.command_history.items.len - 1) {
            self.history_index = self.command_history.items.len;
            self.input_buffer.clearRetainingCapacity();
            self.cursor_pos = 0;
        }
    }
};

var global_state: *ChatState = undefined;
var global_app: *phantom.App = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    global_state = try ChatState.init(allocator);
    defer global_state.deinit();

    // Load ghost-hacker-blue theme
    var theme_manager = try phantom.theme.ThemeManager.init(allocator);
    defer theme_manager.deinit();

    try theme_manager.setTheme("ghost-hacker-blue");

    var app = try phantom.App.init(allocator, .{
        .title = "AI Chat CLI",
        .tick_rate_ms = 16, // 60 FPS for smooth rendering
        .mouse_enabled = true,
        .add_default_handler = false,
    });
    defer app.deinit();
    global_app = &app;

    try app.event_loop.addHandler(handleEvent);

    try app.run();
}

fn handleEvent(event: phantom.Event) !bool {
    switch (event) {
        .key => |key| {
            if (key == .ctrl_c) {
                global_app.stop();
                return true;
            }

            if (key.isChar('q') and global_state.input_buffer.items.len == 0) {
                global_app.stop();
                return true;
            }

            // Handle input
            if (key == .enter) {
                try global_state.submitInput();
            } else if (key == .backspace) {
                if (global_state.cursor_pos > 0) {
                    _ = global_state.input_buffer.orderedRemove(global_state.cursor_pos - 1);
                    global_state.cursor_pos -= 1;
                }
            } else if (key == .up) {
                try global_state.historyUp();
            } else if (key == .down) {
                try global_state.historyDown();
            } else if (key == .left) {
                if (global_state.cursor_pos > 0) {
                    global_state.cursor_pos -= 1;
                }
            } else if (key == .right) {
                if (global_state.cursor_pos < global_state.input_buffer.items.len) {
                    global_state.cursor_pos += 1;
                }
            } else {
                // Handle character input
                switch (key) {
                    .char => |c| {
                        if (c >= 32 and c < 127) {
                            try global_state.input_buffer.insert(global_state.allocator, global_state.cursor_pos, @intCast(c));
                            global_state.cursor_pos += 1;
                        }
                    },
                    else => {},
                }
            }
        },
        .tick => {
            try renderUI();
        },
        else => {},
    }
    return false;
}

fn renderUI() !void {
    const buffer = global_app.terminal.getBackBuffer();
    const area = phantom.Rect.init(0, 0, global_app.terminal.size.width, global_app.terminal.size.height);

    try global_app.terminal.clear();

    // Fill background with dark color to prevent terminal bleed-through
    buffer.fill(area, phantom.Cell.withStyle(phantom.Style.default().withBg(phantom.Color.black)));

    // Create layout: messages area + input area
    const layout = phantom.ConstraintLayout.init(.vertical, &[_]phantom.Constraint{
        .{ .fill = 1 },     // Messages
        .{ .length = 3 },   // Input box
        .{ .length = 1 },   // Status bar
    });
    const areas = try layout.split(buffer.allocator, area);
    defer buffer.allocator.free(areas);

    // Render messages
    try renderMessages(buffer, areas[0]);

    // Render input
    try renderInput(buffer, areas[1]);

    // Render status
    renderStatus(buffer, areas[2]);

    try global_app.terminal.flush();
}

fn renderMessages(buffer: *phantom.Buffer, area: phantom.Rect) !void {
    if (area.height == 0) return;

    // Title
    const title = " Chat History ";
    const title_x = area.x + @divTrunc(area.width, 2) - @divTrunc(@as(u16, @intCast(title.len)), 2);
    buffer.writeText(title_x, area.y, title, phantom.Style.default().withFg(phantom.Color.cyan).withBold());

    // Render messages from bottom up
    var y: u16 = area.y + area.height - 1;
    var msg_idx: usize = global_state.messages.items.len;

    while (msg_idx > 0 and y > area.y + 1) : (msg_idx -= 1) {
        const msg = global_state.messages.items[msg_idx - 1];

        const style = switch (msg.role) {
            .user => phantom.Style.default().withFg(phantom.Color.green),
            .assistant => phantom.Style.default().withFg(phantom.Color.blue),
            .system => phantom.Style.default().withFg(phantom.Color.yellow),
        };

        const prefix = switch (msg.role) {
            .user => "You: ",
            .assistant => "AI: ",
            .system => ">>> ",
        };

        // Word wrap the message
        var lines: std.ArrayList([]const u8) = .{};
        defer lines.deinit(buffer.allocator);

        var start: usize = 0;
        const max_width = if (area.width > prefix.len) area.width - @as(u16, @intCast(prefix.len)) else 0;

        while (start < msg.content.len and y > area.y + 1) {
            const remaining = msg.content[start..];
            const line_len = @min(remaining.len, max_width);

            if (line_len > 0) {
                buffer.writeText(area.x, y, prefix, style.withBold());
                buffer.writeText(area.x + @as(u16, @intCast(prefix.len)), y, remaining[0..line_len], style);
                y -= 1;
            }

            start += line_len;
        }

        // Add spacing between messages
        if (y > area.y + 1) y -= 1;
    }
}

fn renderInput(buffer: *phantom.Buffer, area: phantom.Rect) !void {
    // Draw border
    const border_style = phantom.Style.default().withFg(phantom.Color.bright_black);

    // Top border
    buffer.writeText(area.x, area.y, "┌", border_style);
    for (area.x + 1..area.x + area.width - 1) |x| {
        buffer.writeText(@intCast(x), area.y, "─", border_style);
    }
    buffer.writeText(area.x + area.width - 1, area.y, "┐", border_style);

    // Input label
    const prompt = " > ";
    buffer.writeText(area.x + 1, area.y + 1, prompt, phantom.Style.default().withFg(phantom.Color.cyan).withBold());

    // Input text
    const input_x = area.x + 1 + @as(u16, @intCast(prompt.len));
    const max_input_width = if (area.width > input_x) area.width - input_x - 1 else 0;

    const visible_start = if (global_state.cursor_pos > max_input_width)
        global_state.cursor_pos - max_input_width
    else
        0;

    const visible_end = @min(visible_start + max_input_width, global_state.input_buffer.items.len);
    const visible_text = global_state.input_buffer.items[visible_start..visible_end];

    buffer.writeText(input_x, area.y + 1, visible_text, phantom.Style.default());

    // Draw cursor
    const cursor_x = input_x + @as(u16, @intCast(global_state.cursor_pos - visible_start));
    if (cursor_x < area.x + area.width - 1) {
        const cursor_char = if (global_state.cursor_pos < global_state.input_buffer.items.len)
            global_state.input_buffer.items[global_state.cursor_pos]
        else
            ' ';

        buffer.writeText(cursor_x, area.y + 1, &[_]u8{cursor_char}, phantom.Style.default().withBg(phantom.Color.bright_black));
    }

    // Bottom border
    buffer.writeText(area.x, area.y + 2, "└", border_style);
    for (area.x + 1..area.x + area.width - 1) |x| {
        buffer.writeText(@intCast(x), area.y + 2, "─", border_style);
    }
    buffer.writeText(area.x + area.width - 1, area.y + 2, "┘", border_style);
}

fn renderStatus(buffer: *phantom.Buffer, area: phantom.Rect) void {
    const status = std.fmt.allocPrint(
        buffer.allocator,
        "Messages: {d} | History: {d} | Ctrl+C: Exit | Enter: Send",
        .{ global_state.messages.items.len, global_state.command_history.items.len }
    ) catch return;
    defer buffer.allocator.free(status);

    buffer.writeText(area.x, area.y, status, phantom.Style.default().withFg(phantom.Color.bright_black));
}
