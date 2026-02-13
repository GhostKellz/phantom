const std = @import("std");
const builtin = @import("builtin");

/// Simple timer for measuring elapsed time.
/// Replacement for the removed std.time.Timer in Zig 0.16.
pub const Timer = struct {
    start_time: u64,

    const Self = @This();

    /// Start a new timer. Returns error if clock is unavailable.
    pub fn start() error{TimerUnsupported}!Self {
        const now = monotonicTimestampNs();
        if (now == 0) return error.TimerUnsupported;
        return Self{ .start_time = now };
    }

    /// Read elapsed time in nanoseconds since start or last reset.
    pub fn read(self: *const Self) u64 {
        const now = monotonicTimestampNs();
        return now -| self.start_time;
    }

    /// Reset the timer and return elapsed time since last reset.
    pub fn lap(self: *Self) u64 {
        const now = monotonicTimestampNs();
        const elapsed = now -| self.start_time;
        self.start_time = now;
        return elapsed;
    }

    /// Reset the timer to current time.
    pub fn reset(self: *Self) void {
        self.start_time = monotonicTimestampNs();
    }
};

/// Returns a monotonic timestamp in nanoseconds.
/// Falls back to 0 on error.
pub inline fn monotonicTimestampNs() u64 {
    var ts: std.c.timespec = undefined;
    const rc = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    if (rc != 0) return 0;
    return timespecToNs(ts);
}

/// Returns a monotonic timestamp in milliseconds.
pub inline fn monotonicTimestampMs() u64 {
    const ns = monotonicTimestampNs();
    return ns / std.time.ns_per_ms;
}

/// Returns the current Unix timestamp (seconds since Unix epoch).
/// Falls back to 0 on error.
pub inline fn unixTimestampSeconds() i64 {
    var ts: std.c.timespec = undefined;
    const rc = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
    if (rc != 0) return 0;
    return @intCast(ts.sec);
}

/// Returns the current Unix timestamp in milliseconds.
/// Falls back to 0 on error.
pub inline fn unixTimestampMillis() i64 {
    var ts: std.c.timespec = undefined;
    const rc = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
    if (rc != 0) return 0;
    const sec_ms = @as(i128, ts.sec) * 1000;
    const nsec_ms = @divTrunc(@as(i128, ts.nsec), std.time.ns_per_ms);
    return @intCast(sec_ms + nsec_ms);
}

inline fn timespecToNs(ts: std.c.timespec) u64 {
    const sec_ns = @as(i128, ts.sec) * std.time.ns_per_s;
    const total = sec_ns + @as(i128, ts.nsec);
    return @intCast(@max(total, 0));
}

/// Sleep for the specified number of nanoseconds.
/// Replacement for the removed std.time.sleep in Zig 0.16.
pub fn sleep(ns: u64) void {
    const sec: isize = @intCast(ns / std.time.ns_per_s);
    const nsec: isize = @intCast(ns % std.time.ns_per_s);
    const req = std.c.timespec{ .sec = sec, .nsec = nsec };
    _ = std.c.nanosleep(&req, null);
}

/// Sleep for the specified number of milliseconds.
pub fn sleepMs(ms: u64) void {
    sleep(ms * std.time.ns_per_ms);
}
