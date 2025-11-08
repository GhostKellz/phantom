//! Terminal input parser converting raw bytes into Phantom events.
//! Handles a subset of ANSI escape sequences and control keys.

const std = @import("std");
const EventQueue = @import("EventQueue.zig").EventQueue;
const EventCoalescer = @import("EventCoalescer.zig").EventCoalescer;
const types = @import("types.zig");

const Event = types.Event;
const Key = types.Key;

/// Stateful parser that converts terminal byte streams into events.
pub const InputParser = struct {
    const Self = @This();

    const State = enum {
        idle,
        got_escape,
        csi,
        esc_o,
    };

    state: State = .idle,
    csi_buffer: [8]u8 = undefined,
    csi_len: usize = 0,
    escape_timestamp_ns: u64 = 0,
    escape_pending: bool = false,

    pub const escape_timeout_ns: u64 = 5 * std.time.ns_per_ms;

    pub fn init() Self {
        return Self{};
    }

    /// Feed a slice of bytes and emit any parsed events into the queue.
    /// Returns true if any input was consumed (including coalesced events).
    pub fn feedBytes(
        self: *Self,
        queue: *EventQueue,
        coalescer: ?*EventCoalescer,
        bytes: []const u8,
        now_ns: u64,
    ) !bool {
        var had_activity = false;
        for (bytes) |byte| {
            const activity = try self.feedByte(queue, coalescer, byte, now_ns);
            had_activity = had_activity or activity;
        }
        return had_activity;
    }

    /// Flush any pending escape sequence if it timed out. Returns true if an event was emitted.
    pub fn flushPending(
        self: *Self,
        queue: *EventQueue,
        coalescer: ?*EventCoalescer,
        now_ns: u64,
    ) !bool {
        if (self.escape_pending and now_ns - self.escape_timestamp_ns >= escape_timeout_ns) {
            self.escape_pending = false;
            self.state = .idle;
            self.csi_len = 0;
            return self.dispatch(queue, coalescer, Event.fromKey(Key.escape));
        }
        return false;
    }

    fn feedByte(
        self: *Self,
        queue: *EventQueue,
        coalescer: ?*EventCoalescer,
        byte: u8,
        now_ns: u64,
    ) !bool {
        return switch (self.state) {
            .idle => self.handleIdle(queue, coalescer, byte, now_ns),
            .got_escape => self.handleAfterEscape(queue, coalescer, byte, now_ns),
            .csi => self.handleCsi(queue, coalescer, byte),
            .esc_o => self.handleEscO(queue, coalescer, byte),
        };
    }

    fn handleIdle(
        self: *Self,
        queue: *EventQueue,
        coalescer: ?*EventCoalescer,
        byte: u8,
        now_ns: u64,
    ) !bool {
        if (byte == 0x1B) {
            self.state = .got_escape;
            self.escape_pending = true;
            self.escape_timestamp_ns = now_ns;
            return true; // input consumed, even if event not yet dispatched
        }

        if (ctrlKey(byte)) |ctrl| {
            return self.dispatch(queue, coalescer, Event.fromKey(ctrl));
        }

        return switch (byte) {
            0x7F, 0x08 => self.dispatch(queue, coalescer, Event.fromKey(Key.backspace)),
            0x09 => self.dispatch(queue, coalescer, Event.fromKey(Key.tab)),
            0x0D, 0x0A => self.dispatch(queue, coalescer, Event.fromKey(Key.enter)),
            else => {
                if (byte >= 0x20 and byte < 0x7F) {
                    return self.dispatch(queue, coalescer, Event.fromKey(Key{ .char = byte }));
                }
                return false;
            },
        };
    }

    fn handleAfterEscape(
        self: *Self,
        queue: *EventQueue,
        coalescer: ?*EventCoalescer,
        byte: u8,
        now_ns: u64,
    ) !bool {
        switch (byte) {
            '[' => {
                self.state = .csi;
                self.escape_pending = false;
                self.csi_len = 0;
                return true;
            },
            'O' => {
                self.state = .esc_o;
                self.escape_pending = false;
                return true;
            },
            else => {
                self.state = .idle;
                self.escape_pending = false;
                const produced = try self.dispatch(queue, coalescer, Event.fromKey(Key.escape));
                const rest = try self.handleIdle(queue, coalescer, byte, now_ns);
                return produced or rest;
            },
        }
    }

    fn handleEscO(
        self: *Self,
        queue: *EventQueue,
        coalescer: ?*EventCoalescer,
        byte: u8,
    ) !bool {
        self.state = .idle;
        const maybe_key = switch (byte) {
            'P' => Key.f1,
            'Q' => Key.f2,
            'R' => Key.f3,
            'S' => Key.f4,
            'H' => Key.home,
            'F' => Key.end,
            else => null,
        };
        if (maybe_key) |key| {
            return self.dispatch(queue, coalescer, Event.fromKey(key));
        }
        return false;
    }

    fn handleCsi(
        self: *Self,
        queue: *EventQueue,
        coalescer: ?*EventCoalescer,
        byte: u8,
    ) !bool {
        if (byte >= 0x40 and byte <= 0x7E) {
            const param_slice = self.csi_buffer[0..self.csi_len];
            self.state = .idle;
            self.csi_len = 0;
            const maybe_key = decodeCsi(param_slice, byte);
            if (maybe_key) |key| {
                return self.dispatch(queue, coalescer, Event.fromKey(key));
            }
            return true; // input consumed even if not translated
        } else if (self.csi_len < self.csi_buffer.len) {
            self.csi_buffer[self.csi_len] = byte;
            self.csi_len += 1;
            return true;
        } else {
            // Buffer full - reset to avoid overflow
            self.state = .idle;
            self.csi_len = 0;
            return true;
        }
    }

    fn dispatch(
        self: *Self,
        queue: *EventQueue,
        coalescer: ?*EventCoalescer,
        event: Event,
    ) !bool {
        _ = self;
        if (coalescer) |c| {
            switch (c.processEvent(event)) {
                .dispatch_now => |e| {
                    try queue.pushAuto(e);
                    return true;
                },
                .coalesced => return true,
            }
        } else {
            try queue.pushAuto(event);
            return true;
        }
    }

    fn ctrlKey(byte: u8) ?Key {
        return switch (byte) {
            0x01 => Key.ctrl_a,
            0x02 => Key.ctrl_b,
            0x03 => Key.ctrl_c,
            0x04 => Key.ctrl_d,
            0x05 => Key.ctrl_e,
            0x06 => Key.ctrl_f,
            0x07 => Key.ctrl_g,
            0x08 => Key.ctrl_h,
            0x09 => null, // tab handled separately
            0x0A => null, // newline handled separately
            0x0B => Key.ctrl_k,
            0x0C => Key.ctrl_l,
            0x0D => null, // enter handled separately
            0x0E => Key.ctrl_n,
            0x0F => Key.ctrl_o,
            0x10 => Key.ctrl_p,
            0x11 => Key.ctrl_q,
            0x12 => Key.ctrl_r,
            0x13 => Key.ctrl_s,
            0x14 => Key.ctrl_t,
            0x15 => Key.ctrl_u,
            0x16 => Key.ctrl_v,
            0x17 => Key.ctrl_w,
            0x18 => Key.ctrl_x,
            0x19 => Key.ctrl_y,
            0x1A => Key.ctrl_z,
            else => null,
        };
    }

    fn decodeCsi(params: []const u8, final_char: u8) ?Key {
        if (final_char == '~') {
            const value = parseNumericParam(params);
            return switch (value) {
                2 => Key.insert,
                3 => Key.delete,
                5 => Key.page_up,
                6 => Key.page_down,
                else => null,
            };
        }

        if (params.len == 0) {
            return switch (final_char) {
                'A' => Key.up,
                'B' => Key.down,
                'C' => Key.right,
                'D' => Key.left,
                'F' => Key.end,
                'H' => Key.home,
                'Z' => Key.shift_tab,
                else => null,
            };
        }

        // Handle sequences like ESC[1;5C (Ctrl+Right). We ignore modifiers for now.
        // Take the final character and return directional keys when recognized.
        return switch (final_char) {
            'A' => Key.up,
            'B' => Key.down,
            'C' => Key.right,
            'D' => Key.left,
            else => null,
        };
    }

    fn parseNumericParam(params: []const u8) ?u32 {
        if (params.len == 0) return null;
        var digits = params;
        const semicolon_index = std.mem.indexOfScalar(u8, params, ';');
        if (semicolon_index) |idx| {
            digits = params[0..idx];
        }
        var value: u32 = 0;
        for (digits) |c| {
            if (c < '0' or c > '9') return null;
            value = value * 10 + (@as(u32, c) - '0');
        }
        return value;
    }
};

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

const testing = std.testing;

test "InputParser maps printable characters" {
    var parser = InputParser.init();
    var queue = EventQueue.init(testing.allocator);
    defer queue.deinit();

    const now: u64 = 0;
    _ = try parser.feedBytes(&queue, null, "a", now);

    try testing.expectEqual(@as(usize, 1), queue.size());
    const queued = queue.popEvent().?;
    try testing.expect(queued.event == Event.fromKey(Key{ .char = 'a' }));
}

test "InputParser parses arrow keys" {
    var parser = InputParser.init();
    var queue = EventQueue.init(testing.allocator);
    defer queue.deinit();

    const now: u64 = 0;
    _ = try parser.feedBytes(&queue, null, "\x1b[A", now);

    try testing.expectEqual(@as(usize, 1), queue.size());
    const queued = queue.popEvent().?;
    try testing.expect(queued.event == Event.fromKey(Key.up));
}

test "InputParser flushes standalone escape" {
    var parser = InputParser.init();
    var queue = EventQueue.init(testing.allocator);
    defer queue.deinit();

    const now: u64 = 0;
    _ = try parser.feedBytes(&queue, null, "\x1b", now);
    try testing.expectEqual(@as(usize, 0), queue.size());

    // Advance time beyond timeout and flush
    _ = try parser.flushPending(&queue, null, now + InputParser.escape_timeout_ns + 1);

    try testing.expectEqual(@as(usize, 1), queue.size());
    const queued = queue.popEvent().?;
    try testing.expect(queued.event == Event.fromKey(Key.escape));
}
