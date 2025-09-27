//! Parser - Terminal escape sequence parser
//! Parses incoming terminal escape sequences and control codes

const std = @import("std");
const vxfw = @import("../vxfw.zig");

const Allocator = std.mem.Allocator;

/// Terminal escape sequence parser
pub const TerminalParser = struct {
    allocator: Allocator,
    state: ParserState,
    buffer: std.array_list.AlignedManaged(u8, null),
    intermediate_bytes: std.array_list.AlignedManaged(u8, null),
    parameters: std.array_list.AlignedManaged(i32, null),
    current_param: ?i32,
    utf8_decoder: UTF8Decoder,

    pub fn init(allocator: Allocator) TerminalParser {
        return TerminalParser{
            .allocator = allocator,
            .state = .normal,
            .buffer = std.array_list.AlignedManaged(u8, null).init(allocator),
            .intermediate_bytes = std.array_list.AlignedManaged(u8, null).init(allocator),
            .parameters = std.array_list.AlignedManaged(i32, null).init(allocator),
            .current_param = null,
            .utf8_decoder = UTF8Decoder.init(),
        };
    }

    pub fn deinit(self: *TerminalParser) void {
        self.buffer.deinit();
        self.intermediate_bytes.deinit();
        self.parameters.deinit();
    }

    /// Parse input bytes and return list of events
    pub fn parse(self: *TerminalParser, input: []const u8) ![]ParsedEvent {
        var events = std.array_list.AlignedManaged(ParsedEvent, null).init(self.allocator);

        for (input) |byte| {
            if (try self.processByte(byte)) |event| {
                try events.append(event);
            }
        }

        return events.toOwnedSlice();
    }

    /// Process a single byte and potentially return an event
    fn processByte(self: *TerminalParser, byte: u8) !?ParsedEvent {
        switch (self.state) {
            .normal => return self.parseNormal(byte),
            .escape => return self.parseEscape(byte),
            .csi => return self.parseCSI(byte),
            .osc => return self.parseOSC(byte),
            .dcs => return self.parseDCS(byte),
            .sos => return self.parseSOS(byte),
            .apc => return self.parseAPC(byte),
            .pm => return self.parsePM(byte),
            .utf8 => return self.parseUTF8(byte),
        }
    }

    /// Parse normal characters and control codes
    fn parseNormal(self: *TerminalParser, byte: u8) !?ParsedEvent {
        switch (byte) {
            0x00...0x06, 0x08, 0x0E...0x1A, 0x1C...0x1F => {
                // C0 control codes
                return self.parseControlCode(byte);
            },
            0x07 => return ParsedEvent{ .bell = {} }, // BEL
            0x09 => return ParsedEvent{ .tab = {} },  // HT
            0x0A => return ParsedEvent{ .linefeed = {} }, // LF
            0x0B => return ParsedEvent{ .vertical_tab = {} }, // VT
            0x0C => return ParsedEvent{ .form_feed = {} }, // FF
            0x0D => return ParsedEvent{ .carriage_return = {} }, // CR
            0x1B => {
                // ESC - Enter escape state
                self.state = .escape;
                self.resetParsing();
                return null;
            },
            0x7F => return ParsedEvent{ .delete = {} }, // DEL
            0x80...0xFF => {
                // UTF-8 or extended ASCII
                return self.parseExtendedChar(byte);
            },
            else => {
                // Regular printable ASCII
                return ParsedEvent{ .char = .{ .value = byte } };
            },
        }
    }

    /// Parse escape sequences
    fn parseEscape(self: *TerminalParser, byte: u8) !?ParsedEvent {
        switch (byte) {
            '[' => {
                self.state = .csi;
                return null;
            },
            ']' => {
                self.state = .osc;
                return null;
            },
            'P' => {
                self.state = .dcs;
                return null;
            },
            'X' => {
                self.state = .sos;
                return null;
            },
            '_' => {
                self.state = .apc;
                return null;
            },
            '^' => {
                self.state = .pm;
                return null;
            },
            'D' => {
                // IND - Index
                self.state = .normal;
                return ParsedEvent{ .index = {} };
            },
            'E' => {
                // NEL - Next Line
                self.state = .normal;
                return ParsedEvent{ .next_line = {} };
            },
            'H' => {
                // HTS - Horizontal Tab Set
                self.state = .normal;
                return ParsedEvent{ .tab_set = {} };
            },
            'M' => {
                // RI - Reverse Index
                self.state = .normal;
                return ParsedEvent{ .reverse_index = {} };
            },
            'Z' => {
                // DECID - Identify Terminal
                self.state = .normal;
                return ParsedEvent{ .identify_terminal = {} };
            },
            'c' => {
                // RIS - Reset to Initial State
                self.state = .normal;
                return ParsedEvent{ .reset_terminal = {} };
            },
            '7' => {
                // DECSC - Save Cursor
                self.state = .normal;
                return ParsedEvent{ .save_cursor = {} };
            },
            '8' => {
                // DECRC - Restore Cursor
                self.state = .normal;
                return ParsedEvent{ .restore_cursor = {} };
            },
            '=' => {
                // DECKPAM - Keypad Application Mode
                self.state = .normal;
                return ParsedEvent{ .keypad_application = {} };
            },
            '>' => {
                // DECKPNM - Keypad Numeric Mode
                self.state = .normal;
                return ParsedEvent{ .keypad_numeric = {} };
            },
            0x20...0x2F => {
                // Intermediate bytes
                try self.intermediate_bytes.append(byte);
                return null;
            },
            else => {
                // Unknown escape sequence
                self.state = .normal;
                return ParsedEvent{ .unknown_escape = .{ .sequence = try self.getCurrentSequence() } };
            },
        }
    }

    /// Parse CSI sequences
    fn parseCSI(self: *TerminalParser, byte: u8) !?ParsedEvent {
        switch (byte) {
            '0'...'9' => {
                // Parameter digit
                const digit = @as(i32, byte - '0');
                if (self.current_param) |*param| {
                    param.* = param.* * 10 + digit;
                } else {
                    self.current_param = digit;
                }
                return null;
            },
            ';' => {
                // Parameter separator
                try self.parameters.append(self.current_param orelse 0);
                self.current_param = null;
                return null;
            },
            '?' => {
                // Private parameter
                return null;
            },
            0x20...0x2F => {
                // Intermediate bytes
                try self.intermediate_bytes.append(byte);
                return null;
            },
            0x40...0x7E => {
                // Final byte - complete CSI sequence
                if (self.current_param) |param| {
                    try self.parameters.append(param);
                }

                const event = try self.parseCSICommand(byte);
                self.state = .normal;
                self.resetParsing();
                return event;
            },
            else => {
                // Invalid CSI sequence
                self.state = .normal;
                self.resetParsing();
                return ParsedEvent{ .unknown_csi = .{ .command = byte } };
            },
        }
    }

    /// Parse OSC sequences
    fn parseOSC(self: *TerminalParser, byte: u8) !?ParsedEvent {
        switch (byte) {
            0x07 => {
                // BEL terminator
                const event = try self.parseOSCCommand();
                self.state = .normal;
                self.resetParsing();
                return event;
            },
            0x1B => {
                // Potential ST terminator (ESC \)
                try self.buffer.append(byte);
                return null;
            },
            '\\' => {
                // ST terminator if preceded by ESC
                if (self.buffer.items.len > 0 and self.buffer.items[self.buffer.items.len - 1] == 0x1B) {
                    // Remove the ESC from buffer
                    _ = self.buffer.pop();
                    const event = try self.parseOSCCommand();
                    self.state = .normal;
                    self.resetParsing();
                    return event;
                } else {
                    try self.buffer.append(byte);
                    return null;
                }
            },
            else => {
                try self.buffer.append(byte);
                return null;
            },
        }
    }

    /// Parse DCS sequences
    fn parseDCS(self: *TerminalParser, byte: u8) !?ParsedEvent {
        switch (byte) {
            0x1B => {
                try self.buffer.append(byte);
                return null;
            },
            '\\' => {
                if (self.buffer.items.len > 0 and self.buffer.items[self.buffer.items.len - 1] == 0x1B) {
                    _ = self.buffer.pop();
                    const event = try self.parseDCSCommand();
                    self.state = .normal;
                    self.resetParsing();
                    return event;
                } else {
                    try self.buffer.append(byte);
                    return null;
                }
            },
            else => {
                try self.buffer.append(byte);
                return null;
            },
        }
    }

    /// Parse SOS sequences
    fn parseSOS(self: *TerminalParser, byte: u8) !?ParsedEvent {
        return self.parseStringSequence(byte, .sos);
    }

    /// Parse APC sequences
    fn parseAPC(self: *TerminalParser, byte: u8) !?ParsedEvent {
        return self.parseStringSequence(byte, .apc);
    }

    /// Parse PM sequences
    fn parsePM(self: *TerminalParser, byte: u8) !?ParsedEvent {
        return self.parseStringSequence(byte, .pm);
    }

    /// Parse UTF-8 sequences
    fn parseUTF8(self: *TerminalParser, byte: u8) !?ParsedEvent {
        if (self.utf8_decoder.addByte(byte)) {
            const codepoint = self.utf8_decoder.getCodepoint();
            self.state = .normal;
            return ParsedEvent{ .char = .{ .value = @as(u8, @intCast(codepoint & 0xFF)), .unicode = codepoint } };
        }
        return null;
    }

    /// Parse control codes
    fn parseControlCode(self: *TerminalParser, byte: u8) ParsedEvent {
        _ = self;
        return switch (byte) {
            0x00 => ParsedEvent{ .null = {} },
            0x01 => ParsedEvent{ .start_of_heading = {} },
            0x02 => ParsedEvent{ .start_of_text = {} },
            0x03 => ParsedEvent{ .end_of_text = {} },
            0x04 => ParsedEvent{ .end_of_transmission = {} },
            0x05 => ParsedEvent{ .enquiry = {} },
            0x06 => ParsedEvent{ .acknowledge = {} },
            0x08 => ParsedEvent{ .backspace = {} },
            0x0E => ParsedEvent{ .shift_out = {} },
            0x0F => ParsedEvent{ .shift_in = {} },
            0x10 => ParsedEvent{ .data_link_escape = {} },
            0x11 => ParsedEvent{ .device_control_1 = {} },
            0x12 => ParsedEvent{ .device_control_2 = {} },
            0x13 => ParsedEvent{ .device_control_3 = {} },
            0x14 => ParsedEvent{ .device_control_4 = {} },
            0x15 => ParsedEvent{ .negative_acknowledge = {} },
            0x16 => ParsedEvent{ .synchronous_idle = {} },
            0x17 => ParsedEvent{ .end_of_transmission_block = {} },
            0x18 => ParsedEvent{ .cancel = {} },
            0x19 => ParsedEvent{ .end_of_medium = {} },
            0x1A => ParsedEvent{ .substitute = {} },
            0x1C => ParsedEvent{ .file_separator = {} },
            0x1D => ParsedEvent{ .group_separator = {} },
            0x1E => ParsedEvent{ .record_separator = {} },
            0x1F => ParsedEvent{ .unit_separator = {} },
            else => ParsedEvent{ .unknown_control = .{ .code = byte } },
        };
    }

    /// Parse extended characters (UTF-8 or extended ASCII)
    fn parseExtendedChar(self: *TerminalParser, byte: u8) !?ParsedEvent {
        if (self.utf8_decoder.isUTF8Start(byte)) {
            self.state = .utf8;
            self.utf8_decoder.reset();
            _ = self.utf8_decoder.addByte(byte);
            return null;
        } else {
            // Extended ASCII
            return ParsedEvent{ .char = .{ .value = byte } };
        }
    }

    /// Parse CSI command
    fn parseCSICommand(self: *TerminalParser, command: u8) !ParsedEvent {
        const params = self.parameters.items;

        return switch (command) {
            'A' => ParsedEvent{ .cursor_up = .{ .count = self.getParam(params, 0, 1) } },
            'B' => ParsedEvent{ .cursor_down = .{ .count = self.getParam(params, 0, 1) } },
            'C' => ParsedEvent{ .cursor_right = .{ .count = self.getParam(params, 0, 1) } },
            'D' => ParsedEvent{ .cursor_left = .{ .count = self.getParam(params, 0, 1) } },
            'E' => ParsedEvent{ .cursor_next_line = .{ .count = self.getParam(params, 0, 1) } },
            'F' => ParsedEvent{ .cursor_prev_line = .{ .count = self.getParam(params, 0, 1) } },
            'G' => ParsedEvent{ .cursor_column = .{ .column = self.getParam(params, 0, 1) } },
            'H' => ParsedEvent{ .cursor_position = .{
                .row = self.getParam(params, 0, 1),
                .col = self.getParam(params, 1, 1)
            } },
            'J' => ParsedEvent{ .erase_display = .{ .mode = @as(u8, @intCast(self.getParam(params, 0, 0))) } },
            'K' => ParsedEvent{ .erase_line = .{ .mode = @as(u8, @intCast(self.getParam(params, 0, 0))) } },
            'L' => ParsedEvent{ .insert_lines = .{ .count = self.getParam(params, 0, 1) } },
            'M' => ParsedEvent{ .delete_lines = .{ .count = self.getParam(params, 0, 1) } },
            'P' => ParsedEvent{ .delete_chars = .{ .count = self.getParam(params, 0, 1) } },
            'S' => ParsedEvent{ .scroll_up = .{ .count = self.getParam(params, 0, 1) } },
            'T' => ParsedEvent{ .scroll_down = .{ .count = self.getParam(params, 0, 1) } },
            '@' => ParsedEvent{ .insert_chars = .{ .count = self.getParam(params, 0, 1) } },
            'X' => ParsedEvent{ .erase_chars = .{ .count = self.getParam(params, 0, 1) } },
            'c' => ParsedEvent{ .device_attributes = .{ .level = self.getParam(params, 0, 0) } },
            'd' => ParsedEvent{ .cursor_line = .{ .line = self.getParam(params, 0, 1) } },
            'f' => ParsedEvent{ .cursor_position = .{
                .row = self.getParam(params, 0, 1),
                .col = self.getParam(params, 1, 1)
            } },
            'h' => try self.parseMode(params, true),
            'l' => try self.parseMode(params, false),
            'm' => try self.parseAttributes(params),
            'n' => ParsedEvent{ .device_status = .{ .type = self.getParam(params, 0, 0) } },
            'r' => ParsedEvent{ .scroll_region = .{
                .top = self.getParam(params, 0, 1),
                .bottom = self.getParam(params, 1, 0)
            } },
            's' => ParsedEvent{ .save_cursor = {} },
            'u' => ParsedEvent{ .restore_cursor = {} },
            else => ParsedEvent{ .unknown_csi = .{ .command = command } },
        };
    }

    /// Parse OSC command
    fn parseOSCCommand(self: *TerminalParser) !ParsedEvent {
        const data = self.buffer.items;
        if (data.len == 0) return ParsedEvent{ .unknown_osc = .{ .data = "" } };

        // Find semicolon separator
        const semicolon_pos = std.mem.indexOf(u8, data, ";");
        if (semicolon_pos == null) {
            return ParsedEvent{ .unknown_osc = .{ .data = try self.allocator.dupe(u8, data) } };
        }

        const command_str = data[0..semicolon_pos.?];
        const payload = data[semicolon_pos.? + 1..];

        const command = std.fmt.parseInt(u16, command_str, 10) catch {
            return ParsedEvent{ .unknown_osc = .{ .data = try self.allocator.dupe(u8, data) } };
        };

        return switch (command) {
            0 => ParsedEvent{ .set_title = .{ .title = try self.allocator.dupe(u8, payload) } },
            1 => ParsedEvent{ .set_icon_title = .{ .title = try self.allocator.dupe(u8, payload) } },
            2 => ParsedEvent{ .set_window_title = .{ .title = try self.allocator.dupe(u8, payload) } },
            4 => ParsedEvent{ .set_color = .{ .data = try self.allocator.dupe(u8, payload) } },
            10 => ParsedEvent{ .color_query_fg = .{ .response = try self.allocator.dupe(u8, payload) } },
            11 => ParsedEvent{ .color_query_bg = .{ .response = try self.allocator.dupe(u8, payload) } },
            12 => ParsedEvent{ .color_query_cursor = .{ .response = try self.allocator.dupe(u8, payload) } },
            52 => ParsedEvent{ .clipboard = .{ .data = try self.allocator.dupe(u8, payload) } },
            else => ParsedEvent{ .unknown_osc = .{ .data = try self.allocator.dupe(u8, data) } },
        };
    }

    /// Parse DCS command
    fn parseDCSCommand(self: *TerminalParser) !ParsedEvent {
        return ParsedEvent{ .device_control = .{ .data = try self.allocator.dupe(u8, self.buffer.items) } };
    }

    /// Parse string sequences (SOS, APC, PM)
    fn parseStringSequence(self: *TerminalParser, byte: u8, comptime seq_type: @TypeOf(.sos)) !?ParsedEvent {
        switch (byte) {
            0x1B => {
                try self.buffer.append(byte);
                return null;
            },
            '\\' => {
                if (self.buffer.items.len > 0 and self.buffer.items[self.buffer.items.len - 1] == 0x1B) {
                    _ = self.buffer.pop();
                    const data = try self.allocator.dupe(u8, self.buffer.items);
                    self.state = .normal;
                    self.resetParsing();
                    return switch (seq_type) {
                        .sos => ParsedEvent{ .string_command = .{ .data = data } },
                        .apc => ParsedEvent{ .application_command = .{ .data = data } },
                        .pm => ParsedEvent{ .privacy_message = .{ .data = data } },
                        else => unreachable,
                    };
                } else {
                    try self.buffer.append(byte);
                    return null;
                }
            },
            else => {
                try self.buffer.append(byte);
                return null;
            },
        }
    }

    /// Parse mode setting (SM/RM)
    fn parseMode(self: *TerminalParser, params: []const i32, enable: bool) !ParsedEvent {
        if (params.len == 0) return ParsedEvent{ .unknown_csi = .{ .command = if (enable) 'h' else 'l' } };

        const mode = params[0];
        const is_private = self.intermediate_bytes.items.len > 0 and self.intermediate_bytes.items[0] == '?';

        return ParsedEvent{ .mode_setting = .{
            .mode = mode,
            .enable = enable,
            .private = is_private,
        } };
    }

    /// Parse SGR attributes
    fn parseAttributes(self: *TerminalParser, params: []const i32) !ParsedEvent {
        var attributes = std.array_list.AlignedManaged(AttributeChange, null).init(self.allocator);

        var i: usize = 0;
        while (i < params.len) {
            _ = params[i];
            const attr = try self.parseAttribute(params, &i);
            try attributes.append(attr);
        }

        return ParsedEvent{ .attributes = .{ .changes = try attributes.toOwnedSlice() } };
    }

    /// Parse single SGR attribute
    fn parseAttribute(self: *TerminalParser, params: []const i32, index: *usize) !AttributeChange {
        _ = self;
        const param = params[index.*];
        index.* += 1;

        return switch (param) {
            0 => AttributeChange{ .reset = {} },
            1 => AttributeChange{ .bold = true },
            2 => AttributeChange{ .dim = true },
            3 => AttributeChange{ .italic = true },
            4 => AttributeChange{ .underline = true },
            5 => AttributeChange{ .blink = true },
            7 => AttributeChange{ .reverse = true },
            9 => AttributeChange{ .strikethrough = true },
            22 => AttributeChange{ .bold = false },
            23 => AttributeChange{ .italic = false },
            24 => AttributeChange{ .underline = false },
            25 => AttributeChange{ .blink = false },
            27 => AttributeChange{ .reverse = false },
            29 => AttributeChange{ .strikethrough = false },
            30...37 => AttributeChange{ .fg_color = .{ .color_8 = @as(u8, @intCast(param - 30)) } },
            38 => blk: {
                if (index.* + 1 < params.len and params[index.*] == 5) {
                    // 256-color
                    index.* += 1;
                    if (index.* < params.len) {
                        const color = params[index.*];
                        index.* += 1;
                        break :blk AttributeChange{ .fg_color = .{ .color_256 = @as(u8, @intCast(color)) } };
                    }
                } else if (index.* + 2 < params.len and params[index.*] == 2) {
                    // RGB color
                    index.* += 1;
                    if (index.* + 2 < params.len) {
                        const r = @as(u8, @intCast(params[index.*]));
                        const g = @as(u8, @intCast(params[index.* + 1]));
                        const b = @as(u8, @intCast(params[index.* + 2]));
                        index.* += 3;
                        break :blk AttributeChange{ .fg_color = .{ .rgb = .{ .r = r, .g = g, .b = b } } };
                    }
                }
                break :blk AttributeChange{ .fg_color = .{ .default = {} } };
            },
            39 => AttributeChange{ .fg_color = .{ .default = {} } },
            40...47 => AttributeChange{ .bg_color = .{ .color_8 = @as(u8, @intCast(param - 40)) } },
            48 => blk: {
                // Similar to 38 but for background
                if (index.* + 1 < params.len and params[index.*] == 5) {
                    index.* += 1;
                    if (index.* < params.len) {
                        const color = params[index.*];
                        index.* += 1;
                        break :blk AttributeChange{ .bg_color = .{ .color_256 = @as(u8, @intCast(color)) } };
                    }
                } else if (index.* + 2 < params.len and params[index.*] == 2) {
                    index.* += 1;
                    if (index.* + 2 < params.len) {
                        const r = @as(u8, @intCast(params[index.*]));
                        const g = @as(u8, @intCast(params[index.* + 1]));
                        const b = @as(u8, @intCast(params[index.* + 2]));
                        index.* += 3;
                        break :blk AttributeChange{ .bg_color = .{ .rgb = .{ .r = r, .g = g, .b = b } } };
                    }
                }
                break :blk AttributeChange{ .bg_color = .{ .default = {} } };
            },
            49 => AttributeChange{ .bg_color = .{ .default = {} } },
            90...97 => AttributeChange{ .fg_color = .{ .color_8_bright = @as(u8, @intCast(param - 90)) } },
            100...107 => AttributeChange{ .bg_color = .{ .color_8_bright = @as(u8, @intCast(param - 100)) } },
            else => AttributeChange{ .unknown = param },
        };
    }

    /// Get parameter at index with default value
    fn getParam(self: *TerminalParser, params: []const i32, index: usize, default: i32) i32 {
        _ = self;
        if (index < params.len) {
            return params[index];
        }
        return default;
    }

    /// Get current sequence for error reporting
    fn getCurrentSequence(self: *TerminalParser) ![]u8 {
        var sequence = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        try sequence.append(0x1B); // ESC

        if (self.state == .csi) {
            try sequence.append('[');
        } else if (self.state == .osc) {
            try sequence.append(']');
        }

        try sequence.appendSlice(self.buffer.items);
        return sequence.toOwnedSlice();
    }

    /// Reset parsing state
    fn resetParsing(self: *TerminalParser) void {
        self.buffer.clearRetainingCapacity();
        self.intermediate_bytes.clearRetainingCapacity();
        self.parameters.clearRetainingCapacity();
        self.current_param = null;
    }
};

/// Parser states
const ParserState = enum {
    normal,    // Normal character input
    escape,    // After ESC
    csi,       // CSI sequence
    osc,       // OSC sequence
    dcs,       // DCS sequence
    sos,       // SOS sequence
    apc,       // APC sequence
    pm,        // PM sequence
    utf8,      // UTF-8 multi-byte sequence
};

/// UTF-8 decoder for multi-byte characters
const UTF8Decoder = struct {
    bytes_needed: u8,
    bytes_seen: u8,
    codepoint: u21,
    lower_boundary: u21,

    fn init() UTF8Decoder {
        return UTF8Decoder{
            .bytes_needed = 0,
            .bytes_seen = 0,
            .codepoint = 0,
            .lower_boundary = 0,
        };
    }

    fn reset(self: *UTF8Decoder) void {
        self.bytes_needed = 0;
        self.bytes_seen = 0;
        self.codepoint = 0;
        self.lower_boundary = 0;
    }

    fn isUTF8Start(self: *UTF8Decoder, byte: u8) bool {
        _ = self;
        return byte & 0x80 != 0;
    }

    fn addByte(self: *UTF8Decoder, byte: u8) bool {
        if (self.bytes_needed == 0) {
            // First byte of sequence
            if (byte & 0x80 == 0) {
                // ASCII
                self.codepoint = byte;
                return true;
            } else if (byte & 0xE0 == 0xC0) {
                // 2-byte sequence
                self.bytes_needed = 2;
                self.codepoint = @as(u21, byte & 0x1F) << 6;
                self.lower_boundary = 0x80;
            } else if (byte & 0xF0 == 0xE0) {
                // 3-byte sequence
                self.bytes_needed = 3;
                self.codepoint = @as(u21, byte & 0x0F) << 12;
                self.lower_boundary = 0x800;
            } else if (byte & 0xF8 == 0xF0) {
                // 4-byte sequence
                self.bytes_needed = 4;
                self.codepoint = @as(u21, byte & 0x07) << 18;
                self.lower_boundary = 0x10000;
            } else {
                // Invalid UTF-8
                self.reset();
                return false;
            }
            self.bytes_seen = 1;
            return false;
        } else {
            // Continuation byte
            if (byte & 0xC0 != 0x80) {
                // Invalid continuation
                self.reset();
                return false;
            }

            self.codepoint |= @as(u21, byte & 0x3F) << @as(u5, @intCast(6 * (self.bytes_needed - self.bytes_seen - 1)));
            self.bytes_seen += 1;

            if (self.bytes_seen == self.bytes_needed) {
                // Sequence complete
                const valid = self.codepoint >= self.lower_boundary and
                    self.codepoint <= 0x10FFFF and
                    !(self.codepoint >= 0xD800 and self.codepoint <= 0xDFFF);

                if (!valid) {
                    self.reset();
                    return false;
                }

                return true;
            }
            return false;
        }
    }

    fn getCodepoint(self: *const UTF8Decoder) u21 {
        return self.codepoint;
    }
};

/// Parsed events from terminal input
pub const ParsedEvent = union(enum) {
    // Characters
    char: CharEvent,

    // Control codes
    null: void,
    bell: void,
    backspace: void,
    tab: void,
    linefeed: void,
    vertical_tab: void,
    form_feed: void,
    carriage_return: void,
    delete: void,

    // Extended control codes
    start_of_heading: void,
    start_of_text: void,
    end_of_text: void,
    end_of_transmission: void,
    enquiry: void,
    acknowledge: void,
    shift_out: void,
    shift_in: void,
    data_link_escape: void,
    device_control_1: void,
    device_control_2: void,
    device_control_3: void,
    device_control_4: void,
    negative_acknowledge: void,
    synchronous_idle: void,
    end_of_transmission_block: void,
    cancel: void,
    end_of_medium: void,
    substitute: void,
    file_separator: void,
    group_separator: void,
    record_separator: void,
    unit_separator: void,

    // Escape sequences
    index: void,
    next_line: void,
    tab_set: void,
    reverse_index: void,
    identify_terminal: void,
    reset_terminal: void,
    save_cursor: void,
    restore_cursor: void,
    keypad_application: void,
    keypad_numeric: void,

    // CSI sequences
    cursor_up: CursorMove,
    cursor_down: CursorMove,
    cursor_left: CursorMove,
    cursor_right: CursorMove,
    cursor_next_line: CursorMove,
    cursor_prev_line: CursorMove,
    cursor_column: CursorColumn,
    cursor_line: CursorLine,
    cursor_position: CursorPosition,
    erase_display: EraseDisplay,
    erase_line: EraseLine,
    insert_lines: InsertLines,
    delete_lines: DeleteLines,
    insert_chars: InsertChars,
    delete_chars: DeleteChars,
    erase_chars: EraseChars,
    scroll_up: ScrollMove,
    scroll_down: ScrollMove,
    scroll_region: ScrollRegion,
    device_attributes: DeviceAttributes,
    device_status: DeviceStatus,
    mode_setting: ModeSetting,
    attributes: AttributeSequence,

    // OSC sequences
    set_title: SetTitle,
    set_icon_title: SetTitle,
    set_window_title: SetTitle,
    set_color: SetColor,
    color_query_fg: ColorQuery,
    color_query_bg: ColorQuery,
    color_query_cursor: ColorQuery,
    clipboard: ClipboardData,

    // DCS sequences
    device_control: DeviceControl,

    // String sequences
    string_command: StringCommand,
    application_command: ApplicationCommand,
    privacy_message: PrivacyMessage,

    // Unknown/error sequences
    unknown_escape: UnknownSequence,
    unknown_csi: UnknownCSI,
    unknown_osc: UnknownOSC,
    unknown_control: UnknownControl,

    // Event data structures
    pub const CharEvent = struct {
        value: u8,
        unicode: ?u21 = null,
    };

    pub const CursorMove = struct { count: i32 };
    pub const CursorColumn = struct { column: i32 };
    pub const CursorLine = struct { line: i32 };
    pub const CursorPosition = struct { row: i32, col: i32 };
    pub const EraseDisplay = struct { mode: u8 };
    pub const EraseLine = struct { mode: u8 };
    pub const InsertLines = struct { count: i32 };
    pub const DeleteLines = struct { count: i32 };
    pub const InsertChars = struct { count: i32 };
    pub const DeleteChars = struct { count: i32 };
    pub const EraseChars = struct { count: i32 };
    pub const ScrollMove = struct { count: i32 };
    pub const ScrollRegion = struct { top: i32, bottom: i32 };
    pub const DeviceAttributes = struct { level: i32 };
    pub const DeviceStatus = struct { type: i32 };
    pub const ModeSetting = struct { mode: i32, enable: bool, private: bool };
    pub const AttributeSequence = struct { changes: []AttributeChange };
    pub const SetTitle = struct { title: []u8 };
    pub const SetColor = struct { data: []u8 };
    pub const ColorQuery = struct { response: []u8 };
    pub const ClipboardData = struct { data: []u8 };
    pub const DeviceControl = struct { data: []u8 };
    pub const StringCommand = struct { data: []u8 };
    pub const ApplicationCommand = struct { data: []u8 };
    pub const PrivacyMessage = struct { data: []u8 };
    pub const UnknownSequence = struct { sequence: []u8 };
    pub const UnknownCSI = struct { command: u8 };
    pub const UnknownOSC = struct { data: []u8 };
    pub const UnknownControl = struct { code: u8 };
};

/// Attribute change for SGR sequences
pub const AttributeChange = union(enum) {
    reset: void,
    bold: bool,
    dim: bool,
    italic: bool,
    underline: bool,
    blink: bool,
    reverse: bool,
    strikethrough: bool,
    fg_color: ColorValue,
    bg_color: ColorValue,
    unknown: i32,
};

/// Color value types
pub const ColorValue = union(enum) {
    default: void,
    color_8: u8,
    color_8_bright: u8,
    color_256: u8,
    rgb: RGBColor,
};

pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,
};

test "Parser basic character input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = TerminalParser.init(arena.allocator());
    defer parser.deinit();

    const events = try parser.parse("Hello");
    defer arena.allocator().free(events);

    try std.testing.expectEqual(@as(usize, 5), events.len);
    try std.testing.expectEqual(@as(u8, 'H'), events[0].char.value);
    try std.testing.expectEqual(@as(u8, 'e'), events[1].char.value);
}

test "Parser CSI cursor movement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = TerminalParser.init(arena.allocator());
    defer parser.deinit();

    const events = try parser.parse("\x1b[5A");
    defer arena.allocator().free(events);

    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqual(@as(i32, 5), events[0].cursor_up.count);
}

test "Parser OSC title setting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = TerminalParser.init(arena.allocator());
    defer parser.deinit();

    const events = try parser.parse("\x1b]0;Test Title\x07");
    defer arena.allocator().free(events);

    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqualStrings("Test Title", events[0].set_title.title);
}