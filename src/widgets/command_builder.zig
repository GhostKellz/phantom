//! CommandBuilder widget for interactive CLI command construction
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const emoji = @import("../emoji.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Command argument types
pub const ArgumentType = enum {
    flag,           // --flag or -f
    option,         // --option=value
    positional,     // value
    subcommand,     // subcommand
    
    pub fn getIcon(self: ArgumentType) []const u8 {
        return switch (self) {
            .flag => "🏳️",
            .option => "⚙️",
            .positional => "📝",
            .subcommand => "🔧",
        };
    }
};

/// Command suggestion with metadata
pub const Suggestion = struct {
    text: []const u8,
    description: []const u8,
    arg_type: ArgumentType,
    required: bool = false,
    
    pub fn getDisplayText(self: *const Suggestion, allocator: std.mem.Allocator) ![]const u8 {
        const req_marker = if (self.required) "*" else "";
        return std.fmt.allocPrint(allocator, "{s}{s}{s} - {s}", .{ self.arg_type.getIcon(), req_marker, self.text, self.description });
    }
};

/// Command part representing one argument or flag
pub const CommandPart = struct {
    text: []const u8,
    arg_type: ArgumentType,
    value: ?[]const u8 = null, // For options that take values
    
    pub fn getFullText(self: *const CommandPart, allocator: std.mem.Allocator) ![]const u8 {
        return if (self.value) |val|
            std.fmt.allocPrint(allocator, "{s}={s}", .{ self.text, val })
        else
            allocator.dupe(u8, self.text);
    }
};

/// Interactive command builder widget
pub const CommandBuilder = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    
    // Command state
    base_command: []const u8,       // e.g., "git", "flash"
    command_parts: std.ArrayList(CommandPart),
    current_input: std.ArrayList(u8),
    
    // Suggestions and completion
    available_suggestions: std.ArrayList(Suggestion),
    filtered_suggestions: std.ArrayList(usize), // indices into available_suggestions
    selected_suggestion: usize = 0,
    show_suggestions: bool = false,
    
    // Preview and validation
    preview_command: std.ArrayList(u8),
    command_valid: bool = true,
    validation_message: ?[]const u8 = null,
    
    // Display state
    input_focused: bool = true,
    cursor_position: usize = 0,
    scroll_offset: usize = 0,
    
    // Styling
    header_style: Style,
    input_style: Style,
    suggestion_style: Style,
    selected_suggestion_style: Style,
    preview_style: Style,
    error_style: Style,
    success_style: Style,
    
    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),
    input_area: Rect = Rect.init(0, 0, 0, 0),
    suggestions_area: Rect = Rect.init(0, 0, 0, 0),
    preview_area: Rect = Rect.init(0, 0, 0, 0),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator, base_command: []const u8) !*CommandBuilder {
        const builder = try allocator.create(CommandBuilder);
        builder.* = CommandBuilder{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .base_command = try allocator.dupe(u8, base_command),
            .command_parts = std.ArrayList(CommandPart){},
            .current_input = std.ArrayList(u8){},
            .available_suggestions = std.ArrayList(Suggestion){},
            .filtered_suggestions = std.ArrayList(usize){},
            .preview_command = std.ArrayList(u8){},
            .header_style = Style.default().withFg(style.Color.bright_cyan).withBold(),
            .input_style = Style.default().withFg(style.Color.bright_white),
            .suggestion_style = Style.default().withFg(style.Color.white),
            .selected_suggestion_style = Style.default().withFg(style.Color.bright_yellow).withBold(),
            .preview_style = Style.default().withFg(style.Color.bright_green),
            .error_style = Style.default().withFg(style.Color.bright_red),
            .success_style = Style.default().withFg(style.Color.bright_green),
        };
        
        // Initialize with base command
        try builder.updatePreview();
        
        return builder;
    }

    /// Add available command suggestions
    pub fn addSuggestion(self: *CommandBuilder, suggestion: Suggestion) !void {
        const owned_suggestion = Suggestion{
            .text = try self.allocator.dupe(u8, suggestion.text),
            .description = try self.allocator.dupe(u8, suggestion.description),
            .arg_type = suggestion.arg_type,
            .required = suggestion.required,
        };
        try self.available_suggestions.append(self.allocator, owned_suggestion);
    }

    /// Add multiple suggestions at once
    pub fn addSuggestions(self: *CommandBuilder, suggestions: []const Suggestion) !void {
        for (suggestions) |suggestion| {
            try self.addSuggestion(suggestion);
        }
    }

    /// Add a command part (argument/flag)
    pub fn addArgument(self: *CommandBuilder, text: []const u8, arg_type: ArgumentType, value: ?[]const u8) !void {
        const part = CommandPart{
            .text = try self.allocator.dupe(u8, text),
            .arg_type = arg_type,
            .value = if (value) |v| try self.allocator.dupe(u8, v) else null,
        };
        try self.command_parts.append(self.allocator, part);
        try self.updatePreview();
    }

    /// Add a simple flag
    pub fn setFlag(self: *CommandBuilder, flag: []const u8) !void {
        try self.addArgument(flag, .flag, null);
    }

    /// Add an option with value
    pub fn setOption(self: *CommandBuilder, option: []const u8, value: []const u8) !void {
        try self.addArgument(option, .option, value);
    }

    /// Add positional argument
    pub fn addPositional(self: *CommandBuilder, value: []const u8) !void {
        try self.addArgument(value, .positional, null);
    }

    /// Get the complete command string
    pub fn getPreview(self: *const CommandBuilder) []const u8 {
        return self.preview_command.items;
    }

    /// Remove the last command part
    pub fn removeLastPart(self: *CommandBuilder) void {
        if (self.command_parts.items.len > 0) {
            const last = self.command_parts.pop();
            self.allocator.free(last.text);
            if (last.value) |val| self.allocator.free(val);
            self.updatePreview() catch {};
        }
    }

    /// Clear all command parts
    pub fn clear(self: *CommandBuilder) void {
        for (self.command_parts.items) |*part| {
            self.allocator.free(part.text);
            if (part.value) |val| self.allocator.free(val);
        }
        self.command_parts.clearRetainingCapacity();
        self.current_input.clearRetainingCapacity();
        self.cursor_position = 0;
        self.updatePreview() catch {};
    }

    /// Validate the current command
    pub fn validate(self: *CommandBuilder) bool {
        // Basic validation - check for required arguments
        var required_flags = std.ArrayList([]const u8){};
        defer required_flags.deinit(self.allocator);
        
        // Collect required suggestions
        for (self.available_suggestions.items) |*suggestion| {
            if (suggestion.required) {
                required_flags.append(self.allocator, suggestion.text) catch continue;
            }
        }
        
        // Check if all required arguments are present
        for (required_flags.items) |required| {
            var found = false;
            for (self.command_parts.items) |*part| {
                if (std.mem.eql(u8, part.text, required)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                self.command_valid = false;
                self.validation_message = std.fmt.allocPrint(self.allocator, "Missing required argument: {s}", .{required}) catch null;
                return false;
            }
        }
        
        self.command_valid = true;
        self.validation_message = null;
        return true;
    }

    fn updatePreview(self: *CommandBuilder) !void {
        self.preview_command.clearRetainingCapacity();
        
        // Start with base command
        try self.preview_command.appendSlice(self.allocator, self.base_command);
        
        // Add all command parts
        for (self.command_parts.items) |*part| {
            try self.preview_command.append(self.allocator, ' ');
            const part_text = try part.getFullText(self.allocator);
            defer self.allocator.free(part_text);
            try self.preview_command.appendSlice(self.allocator, part_text);
        }
        
        // Add current input if any
        if (self.current_input.items.len > 0) {
            try self.preview_command.append(self.allocator, ' ');
            try self.preview_command.appendSlice(self.allocator, self.current_input.items);
        }
        
        // Validate the command
        _ = self.validate();
    }

    fn filterSuggestions(self: *CommandBuilder) void {
        self.filtered_suggestions.clearRetainingCapacity();
        
        const input = self.current_input.items;
        if (input.len == 0) {
            // Show all suggestions
            for (0..self.available_suggestions.items.len) |i| {
                self.filtered_suggestions.append(self.allocator, i) catch break;
            }
        } else {
            // Filter by input prefix
            for (self.available_suggestions.items, 0..) |*suggestion, i| {
                if (std.mem.startsWith(u8, suggestion.text, input)) {
                    self.filtered_suggestions.append(self.allocator, i) catch break;
                }
            }
        }
        
        // Reset selection if out of bounds
        if (self.selected_suggestion >= self.filtered_suggestions.items.len) {
            self.selected_suggestion = 0;
        }
        
        self.show_suggestions = self.filtered_suggestions.items.len > 0;
    }

    fn applySelectedSuggestion(self: *CommandBuilder) !void {
        if (self.filtered_suggestions.items.len == 0 or self.selected_suggestion >= self.filtered_suggestions.items.len) {
            return;
        }
        
        const suggestion_index = self.filtered_suggestions.items[self.selected_suggestion];
        const suggestion = &self.available_suggestions.items[suggestion_index];
        
        // Add the suggestion as a command part
        try self.addArgument(suggestion.text, suggestion.arg_type, null);
        
        // Clear current input
        self.current_input.clearRetainingCapacity();
        self.cursor_position = 0;
        self.show_suggestions = false;
        
        // Update filters for next input
        self.filterSuggestions();
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *CommandBuilder = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;

        var y: u16 = area.y;
        
        // Header
        if (y < area.y + area.height) {
            buffer.fill(Rect.init(area.x, y, area.width, 1), Cell.withStyle(self.header_style));
            const header = "🔧 COMMAND BUILDER";
            buffer.writeText(area.x, y, header, self.header_style);
            y += 1;
        }

        // Current command parts
        if (y < area.y + area.height) {
            const parts_text = std.fmt.allocPrint(self.allocator, "Built: {s}", .{self.base_command}) catch return;
            defer self.allocator.free(parts_text);
            buffer.writeText(area.x, y, parts_text, self.input_style);
            
            var x_offset = @as(u16, @intCast(parts_text.len));
            for (self.command_parts.items) |*part| {
                const part_text = part.getFullText(self.allocator) catch continue;
                defer self.allocator.free(part_text);
                
                const display_text = std.fmt.allocPrint(self.allocator, " {s}", .{part_text}) catch continue;
                defer self.allocator.free(display_text);
                
                if (area.x + x_offset + display_text.len < area.x + area.width) {
                    buffer.writeText(area.x + x_offset, y, display_text, part.arg_type.getIcon()[0] == '🏳' and true);
                    x_offset += @as(u16, @intCast(display_text.len));
                }
            }
            y += 1;
        }

        // Input line
        if (y < area.y + area.height) {
            self.input_area = Rect.init(area.x, y, area.width, 1);
            self.renderInputLine(buffer, self.input_area);
            y += 1;
        }

        // Validation message
        if (self.validation_message) |msg| {
            if (y < area.y + area.height) {
                const error_prefix = "❌ ";
                const full_msg = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ error_prefix, msg }) catch return;
                defer self.allocator.free(full_msg);
                buffer.writeText(area.x, y, full_msg, self.error_style);
                y += 1;
            }
        }

        // Suggestions panel
        if (self.show_suggestions and y < area.y + area.height) {
            const suggestions_height = @min(@as(u16, @intCast(self.filtered_suggestions.items.len + 1)), area.y + area.height - y);
            self.suggestions_area = Rect.init(area.x, y, area.width, suggestions_height);
            self.renderSuggestions(buffer, self.suggestions_area);
            y += suggestions_height;
        }

        // Preview panel
        if (y < area.y + area.height) {
            self.preview_area = Rect.init(area.x, y, area.width, area.y + area.height - y);
            self.renderPreview(buffer, self.preview_area);
        }
    }

    fn renderInputLine(self: *CommandBuilder, buffer: *Buffer, area: Rect) void {
        buffer.fill(area, Cell.withStyle(self.input_style));
        
        const prompt = "❯ ";
        buffer.writeText(area.x, area.y, prompt, self.input_style);
        
        const input_x = area.x + @as(u16, @intCast(prompt.len));
        const available_width = if (area.width > prompt.len) area.width - @as(u16, @intCast(prompt.len)) else 0;
        
        if (available_width > 0) {
            const input_text = self.current_input.items;
            const display_len = @min(input_text.len, available_width);
            
            buffer.writeText(input_x, area.y, input_text[0..display_len], self.input_style);
            
            // Draw cursor
            if (self.input_focused and self.cursor_position < available_width) {
                const cursor_x = input_x + @as(u16, @intCast(self.cursor_position));
                const cursor_char: u21 = if (self.cursor_position < input_text.len) input_text[self.cursor_position] else ' ';
                buffer.setCell(cursor_x, area.y, Cell.init(cursor_char, Style.withBg(style.Color.bright_white).withFg(style.Color.black)));
            }
        }
    }

    fn renderSuggestions(self: *CommandBuilder, buffer: *Buffer, area: Rect) void {
        if (area.height == 0) return;
        
        // Header
        buffer.writeText(area.x, area.y, "💡 Suggestions:", self.header_style);
        
        const suggestions_start_y = area.y + 1;
        const available_height = if (area.height > 1) area.height - 1 else 0;
        
        for (self.filtered_suggestions.items, 0..) |suggestion_index, i| {
            if (i >= available_height) break;
            
            const y = suggestions_start_y + @as(u16, @intCast(i));
            const suggestion = &self.available_suggestions.items[suggestion_index];
            
            const is_selected = i == self.selected_suggestion;
            const suggestion_style = if (is_selected) self.selected_suggestion_style else self.suggestion_style;
            
            const display_text = suggestion.getDisplayText(self.allocator) catch continue;
            defer self.allocator.free(display_text);
            
            const prefix = if (is_selected) "→ " else "  ";
            const full_text = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, display_text }) catch continue;
            defer self.allocator.free(full_text);
            
            const text_len = @min(full_text.len, area.width);
            buffer.writeText(area.x, y, full_text[0..text_len], suggestion_style);
        }
    }

    fn renderPreview(self: *CommandBuilder, buffer: *Buffer, area: Rect) void {
        if (area.height == 0) return;
        
        // Preview header
        const preview_header = "📋 Preview:";
        buffer.writeText(area.x, area.y, preview_header, self.header_style);
        
        if (area.height > 1) {
            const preview_style = if (self.command_valid) self.success_style else self.error_style;
            const preview_prefix = if (self.command_valid) "✅ " else "❌ ";
            
            const preview_text = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ preview_prefix, self.preview_command.items }) catch return;
            defer self.allocator.free(preview_text);
            
            const text_len = @min(preview_text.len, area.width);
            buffer.writeText(area.x, area.y + 1, preview_text[0..text_len], preview_style);
        }
        
        // Help text
        if (area.height > 3) {
            const help_text = "Tab: autocomplete | Enter: execute | Esc: clear | Backspace: remove";
            const help_len = @min(help_text.len, area.width);
            buffer.writeText(area.x, area.y + 3, help_text[0..help_len], Style.default().withFg(style.Color.bright_black));
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *CommandBuilder = @fieldParentPtr("widget", widget);
        
        switch (event) {
            .key => |key_event| {
                if (!key_event.pressed) return false;
                
                switch (key_event.key) {
                    .char => |char| {
                        // Add character to input
                        self.current_input.insert(self.cursor_position, char) catch return false;
                        self.cursor_position += 1;
                        self.filterSuggestions();
                        self.updatePreview() catch {};
                        return true;
                    },
                    .backspace => {
                        if (self.cursor_position > 0) {
                            _ = self.current_input.orderedRemove(self.cursor_position - 1);
                            self.cursor_position -= 1;
                            self.filterSuggestions();
                            self.updatePreview() catch {};
                        } else if (self.command_parts.items.len > 0) {
                            // Remove last command part
                            self.removeLastPart();
                        }
                        return true;
                    },
                    .delete => {
                        if (self.cursor_position < self.current_input.items.len) {
                            _ = self.current_input.orderedRemove(self.cursor_position);
                            self.filterSuggestions();
                            self.updatePreview() catch {};
                        }
                        return true;
                    },
                    .left => {
                        if (self.cursor_position > 0) {
                            self.cursor_position -= 1;
                        }
                        return true;
                    },
                    .right => {
                        if (self.cursor_position < self.current_input.items.len) {
                            self.cursor_position += 1;
                        }
                        return true;
                    },
                    .up => {
                        if (self.show_suggestions and self.selected_suggestion > 0) {
                            self.selected_suggestion -= 1;
                        }
                        return true;
                    },
                    .down => {
                        if (self.show_suggestions and self.selected_suggestion + 1 < self.filtered_suggestions.items.len) {
                            self.selected_suggestion += 1;
                        }
                        return true;
                    },
                    .tab => {
                        // Apply selected suggestion
                        self.applySelectedSuggestion() catch {};
                        return true;
                    },
                    .enter => {
                        if (self.current_input.items.len > 0) {
                            // Add current input as positional argument
                            const input_copy = self.allocator.dupe(u8, self.current_input.items) catch return false;
                            self.addArgument(input_copy, .positional, null) catch {
                                self.allocator.free(input_copy);
                                return false;
                            };
                            self.current_input.clearRetainingCapacity();
                            self.cursor_position = 0;
                            self.show_suggestions = false;
                        }
                        return true;
                    },
                    .escape => {
                        if (self.current_input.items.len > 0) {
                            self.current_input.clearRetainingCapacity();
                            self.cursor_position = 0;
                            self.show_suggestions = false;
                            self.updatePreview() catch {};
                        } else {
                            self.clear();
                        }
                        return true;
                    },
                    else => {},
                }
            },
            else => {},
        }
        
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *CommandBuilder = @fieldParentPtr("widget", widget);
        self.area = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *CommandBuilder = @fieldParentPtr("widget", widget);
        
        // Free command parts
        for (self.command_parts.items) |*part| {
            self.allocator.free(part.text);
            if (part.value) |val| self.allocator.free(val);
        }
        self.command_parts.deinit(self.allocator);
        
        // Free suggestions
        for (self.available_suggestions.items) |*suggestion| {
            self.allocator.free(suggestion.text);
            self.allocator.free(suggestion.description);
        }
        self.available_suggestions.deinit(self.allocator);
        
        self.filtered_suggestions.deinit(self.allocator);
        self.current_input.deinit(self.allocator);
        self.preview_command.deinit(self.allocator);
        self.allocator.free(self.base_command);
        
        if (self.validation_message) |msg| {
            self.allocator.free(msg);
        }
        
        self.allocator.destroy(self);
    }
};

test "CommandBuilder widget creation" {
    const allocator = std.testing.allocator;

    const builder = try CommandBuilder.init(allocator, "git");
    defer builder.widget.deinit();

    // Add some suggestions
    try builder.addSuggestion(Suggestion{
        .text = "commit",
        .description = "Record changes to the repository",
        .arg_type = .subcommand,
    });
    
    try builder.addSuggestion(Suggestion{
        .text = "--message",
        .description = "Commit message",
        .arg_type = .option,
        .required = true,
    });

    // Build a command
    try builder.addArgument("commit", .subcommand, null);
    try builder.setOption("--message", "Initial commit");

    const preview = builder.getPreview();
    try std.testing.expect(std.mem.indexOf(u8, preview, "git commit --message=Initial commit") != null);
}
