//! StreamingText widget for real-time text updates (AI responses)
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Callback function type for when text chunk is received
pub const OnChunkFn = *const fn (streaming_text: *StreamingText, chunk: []const u8) void;

/// Callback function type for when streaming is complete
pub const OnCompleteFn = *const fn (streaming_text: *StreamingText) void;

/// StreamingText widget for real-time text updates
pub const StreamingText = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    
    // Text content
    text: std.ArrayList(u8),
    lines: std.ArrayList([]const u8),
    
    // Streaming state
    is_streaming: bool = false,
    typing_speed: u64 = 50, // Characters per second
    chunk_buffer: std.ArrayList(u8),
    current_chunk_index: usize = 0,
    last_update_time: i64 = 0,
    
    // Scrolling
    scroll_offset: usize = 0,
    auto_scroll: bool = true,
    
    // Styling
    text_style: Style,
    streaming_style: Style,
    cursor_style: Style,
    
    // Configuration
    show_cursor: bool = true,
    cursor_char: u21 = '_',
    word_wrap: bool = true,
    
    // Callbacks
    on_chunk: ?OnChunkFn = null,
    on_complete: ?OnCompleteFn = null,
    
    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*StreamingText {
        const streaming_text = try allocator.create(StreamingText);
        streaming_text.* = StreamingText{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .text = std.ArrayList(u8){},
            .lines = std.ArrayList([]const u8){},
            .chunk_buffer = std.ArrayList(u8){},
            .text_style = Style.default(),
            .streaming_style = Style.default().withFg(style.Color.cyan),
            .cursor_style = Style.default().withFg(style.Color.white).withBg(style.Color.blue),
        };
        return streaming_text;
    }

    pub fn setText(self: *StreamingText, text: []const u8) !void {
        self.text.clearAndFree(self.allocator);
        try self.text.appendSlice(self.allocator, text);
        try self.updateLines();
        self.updateScrollOffset();
    }

    pub fn getText(self: *const StreamingText) []const u8 {
        return self.text.items;
    }

    pub fn startStreaming(self: *StreamingText) void {
        self.is_streaming = true;
        self.last_update_time = std.time.milliTimestamp();
    }

    pub fn stopStreaming(self: *StreamingText) void {
        self.is_streaming = false;
        self.chunk_buffer.clearAndFree(self.allocator);
        self.current_chunk_index = 0;
        
        if (self.on_complete) |callback| {
            callback(self);
        }
    }

    pub fn addChunk(self: *StreamingText, chunk: []const u8) !void {
        try self.chunk_buffer.appendSlice(self.allocator, chunk);
        
        if (self.on_chunk) |callback| {
            callback(self, chunk);
        }
    }

    pub fn setTypingSpeed(self: *StreamingText, speed: u64) void {
        self.typing_speed = speed;
    }

    pub fn setAutoScroll(self: *StreamingText, auto_scroll: bool) void {
        self.auto_scroll = auto_scroll;
    }

    pub fn setWordWrap(self: *StreamingText, word_wrap: bool) !void {
        self.word_wrap = word_wrap;
        try self.updateLines();
    }

    pub fn setShowCursor(self: *StreamingText, show: bool) void {
        self.show_cursor = show;
    }

    pub fn setCursorChar(self: *StreamingText, cursor_char: u21) void {
        self.cursor_char = cursor_char;
    }

    pub fn setTextStyle(self: *StreamingText, text_style: Style) void {
        self.text_style = text_style;
    }

    pub fn setStreamingStyle(self: *StreamingText, streaming_style: Style) void {
        self.streaming_style = streaming_style;
    }

    pub fn setCursorStyle(self: *StreamingText, cursor_style: Style) void {
        self.cursor_style = cursor_style;
    }

    pub fn setOnChunk(self: *StreamingText, callback: OnChunkFn) void {
        self.on_chunk = callback;
    }

    pub fn setOnComplete(self: *StreamingText, callback: OnCompleteFn) void {
        self.on_complete = callback;
    }

    pub fn clear(self: *StreamingText) !void {
        self.text.clearAndFree(self.allocator);
        self.chunk_buffer.clearAndFree(self.allocator);
        self.current_chunk_index = 0;
        self.scroll_offset = 0;
        self.is_streaming = false;
        try self.updateLines();
    }

    pub fn scrollUp(self: *StreamingText) void {
        if (self.scroll_offset > 0) {
            self.scroll_offset -= 1;
        }
    }

    pub fn scrollDown(self: *StreamingText) void {
        if (self.lines.items.len > 0) {
            const visible_lines = if (self.area.height > 0) self.area.height else 1;
            const max_scroll = if (self.lines.items.len > visible_lines) 
                self.lines.items.len - visible_lines else 0;
            
            if (self.scroll_offset < max_scroll) {
                self.scroll_offset += 1;
            }
        }
    }

    pub fn scrollToTop(self: *StreamingText) void {
        self.scroll_offset = 0;
    }

    pub fn scrollToBottom(self: *StreamingText) void {
        if (self.lines.items.len > 0) {
            const visible_lines = if (self.area.height > 0) self.area.height else 1;
            self.scroll_offset = if (self.lines.items.len > visible_lines) 
                self.lines.items.len - visible_lines else 0;
        }
    }

    fn updateLines(self: *StreamingText) !void {
        // Clear existing lines
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearAndFree(self.allocator);
        
        if (!self.word_wrap) {
            // Simple line splitting by newlines
            var lines_iter = std.mem.split(u8, self.text.items, "\n");
            while (lines_iter.next()) |line| {
                const owned_line = try self.allocator.dupe(u8, line);
                try self.lines.append(self.allocator, owned_line);
            }
        } else {
            // Word wrapping
            const wrap_width = if (self.area.width > 0) self.area.width else 80;
            var lines_iter = std.mem.split(u8, self.text.items, "\n");
            
            while (lines_iter.next()) |line| {
                try self.wrapLine(line, wrap_width);
            }
        }
        
        // Ensure at least one line exists
        if (self.lines.items.len == 0) {
            const empty_line = try self.allocator.dupe(u8, "");
            try self.lines.append(self.allocator, empty_line);
        }
    }

    fn wrapLine(self: *StreamingText, line: []const u8, width: u16) !void {
        if (width == 0) return;
        
        var start: usize = 0;
        while (start < line.len) {
            const end = @min(start + width, line.len);
            
            // Try to break at word boundary
            var break_point = end;
            if (end < line.len) {
                // Look for space to break at
                var i = end;
                while (i > start and line[i] != ' ') {
                    i -= 1;
                }
                if (i > start) {
                    break_point = i;
                }
            }
            
            const wrapped_line = try self.allocator.dupe(u8, line[start..break_point]);
            try self.lines.append(self.allocator, wrapped_line);
            
            start = break_point;
            if (start < line.len and line[start] == ' ') {
                start += 1; // Skip space
            }
        }
    }

    fn updateScrollOffset(self: *StreamingText) void {
        if (self.auto_scroll) {
            self.scrollToBottom();
        }
    }

    fn updateStreaming(self: *StreamingText) !void {
        if (!self.is_streaming or self.chunk_buffer.items.len == 0) return;
        
        const current_time = std.time.milliTimestamp();
        const time_diff = current_time - self.last_update_time;
        
        if (time_diff < (1000 / self.typing_speed)) return; // Not enough time passed
        
        // Add characters from chunk buffer
        const chars_to_add = @min(1, self.chunk_buffer.items.len - self.current_chunk_index);
        
        if (chars_to_add > 0) {
            const chunk_end = self.current_chunk_index + chars_to_add;
            try self.text.appendSlice(self.allocator, self.chunk_buffer.items[self.current_chunk_index..chunk_end]);
            self.current_chunk_index = chunk_end;
            
            try self.updateLines();
            self.updateScrollOffset();
            
            self.last_update_time = current_time;
        }
        
        // Check if we've consumed all chunks
        if (self.current_chunk_index >= self.chunk_buffer.items.len) {
            self.stopStreaming();
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *StreamingText = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;

        // Update streaming animation
        self.updateStreaming() catch {};
        
        // Render visible lines
        const visible_lines = @min(area.height, self.lines.items.len);
        var y: u16 = 0;
        
        while (y < visible_lines) {
            const line_index = self.scroll_offset + y;
            if (line_index >= self.lines.items.len) break;
            
            const line = self.lines.items[line_index];
            const render_y = area.y + y;
            
            // Clear line background
            buffer.fill(Rect.init(area.x, render_y, area.width, 1), Cell.withStyle(self.text_style));
            
            // Render line text
            const line_width = @min(line.len, area.width);
            if (line_width > 0) {
                const current_style = if (self.is_streaming) self.streaming_style else self.text_style;
                buffer.writeText(area.x, render_y, line[0..line_width], current_style);
            }
            
            y += 1;
        }
        
        // Render cursor if streaming and at end of text
        if (self.is_streaming and self.show_cursor) {
            const last_line_index = if (self.lines.items.len > 0) self.lines.items.len - 1 else 0;
            const cursor_line = last_line_index;
            
            if (cursor_line >= self.scroll_offset and cursor_line < self.scroll_offset + visible_lines) {
                const cursor_y = area.y + @as(u16, @intCast(cursor_line - self.scroll_offset));
                const cursor_x = area.x + @as(u16, @intCast(@min(self.lines.items[cursor_line].len, area.width)));
                
                if (cursor_x < area.x + area.width) {
                    buffer.setCell(cursor_x, cursor_y, Cell.init(self.cursor_char, self.cursor_style));
                }
            }
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *StreamingText = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key| {
                switch (key) {
                    .up => {
                        self.scrollUp();
                        return true;
                    },
                    .down => {
                        self.scrollDown();
                        return true;
                    },
                    .page_up => {
                        const page_size = if (self.area.height > 0) self.area.height else 10;
                        var i: u16 = 0;
                        while (i < page_size) : (i += 1) {
                            self.scrollUp();
                        }
                        return true;
                    },
                    .page_down => {
                        const page_size = if (self.area.height > 0) self.area.height else 10;
                        var i: u16 = 0;
                        while (i < page_size) : (i += 1) {
                            self.scrollDown();
                        }
                        return true;
                    },
                    .home => {
                        self.scrollToTop();
                        return true;
                    },
                    .end => {
                        self.scrollToBottom();
                        return true;
                    },
                    .char => |c| {
                        switch (c) {
                            'k' => {
                                self.scrollUp();
                                return true;
                            },
                            'j' => {
                                self.scrollDown();
                                return true;
                            },
                            'g' => {
                                self.scrollToTop();
                                return true;
                            },
                            'G' => {
                                self.scrollToBottom();
                                return true;
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }

        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *StreamingText = @fieldParentPtr("widget", widget);
        self.area = area;
        self.updateLines() catch {};
        self.updateScrollOffset();
    }

    fn deinit(widget: *Widget) void {
        const self: *StreamingText = @fieldParentPtr("widget", widget);
        
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit(self.allocator);
        
        self.text.deinit(self.allocator);
        self.chunk_buffer.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

// Example callback functions
fn exampleOnChunk(streaming_text: *StreamingText, chunk: []const u8) void {
    _ = streaming_text;
    std.debug.print("Chunk received: '{}'\n", .{chunk});
}

fn exampleOnComplete(streaming_text: *StreamingText) void {
    _ = streaming_text;
    std.debug.print("Streaming complete!\n", .{});
}

test "StreamingText widget creation" {
    const allocator = std.testing.allocator;

    const streaming_text = try StreamingText.init(allocator);
    defer streaming_text.widget.deinit();

    try std.testing.expect(streaming_text.text.items.len == 0);
    try std.testing.expect(!streaming_text.is_streaming);
    try std.testing.expect(streaming_text.typing_speed == 50);
}

test "StreamingText widget text manipulation" {
    const allocator = std.testing.allocator;

    const streaming_text = try StreamingText.init(allocator);
    defer streaming_text.widget.deinit();

    try streaming_text.setText("Hello, World!");
    try std.testing.expectEqualStrings("Hello, World!", streaming_text.getText());

    try streaming_text.clear();
    try std.testing.expect(streaming_text.getText().len == 0);
}

test "StreamingText widget streaming" {
    const allocator = std.testing.allocator;

    const streaming_text = try StreamingText.init(allocator);
    defer streaming_text.widget.deinit();

    streaming_text.startStreaming();
    try std.testing.expect(streaming_text.is_streaming);

    try streaming_text.addChunk("Hello, ");
    try streaming_text.addChunk("World!");
    try std.testing.expect(streaming_text.chunk_buffer.items.len == 13);

    streaming_text.stopStreaming();
    try std.testing.expect(!streaming_text.is_streaming);
}