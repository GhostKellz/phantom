const std = @import("std");

/// Returns a monotonic timestamp in nanoseconds.
/// Falls back to 0 on error.
pub inline fn monotonicTimestampNs() u64 {
    const ts = std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC) catch {
        return 0;
    };
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
    const ts = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch {
        return 0;
    };
    return @intCast(ts.sec);
}

/// Returns the current Unix timestamp in milliseconds.
/// Falls back to 0 on error.
pub inline fn unixTimestampMillis() i64 {
    const ts = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch {
        return 0;
    };
    const sec_ms = @as(i128, ts.sec) * 1000;
    const nsec_ms = @divTrunc(@as(i128, ts.nsec), std.time.ns_per_ms);
    return @intCast(sec_ms + nsec_ms);
}

inline fn timespecToNs(ts: anytype) u64 {
    const sec_ns = @as(i128, ts.sec) * std.time.ns_per_s;
    const total = sec_ns + @as(i128, ts.nsec);
    return @intCast(@max(total, 0));
}
