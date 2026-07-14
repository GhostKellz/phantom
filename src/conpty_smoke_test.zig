const std = @import("std");
const builtin = @import("builtin");
const pty = @import("terminal/pty.zig");

// std removed a blocking sleep from Thread in 0.17 (moved to the Io interface).
// This test is Windows-gated, so call the kernel32 Sleep directly.
extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;

// Windows ConPTY validation. Spawns cmd.exe through the pseudoconsole,
// captures its rendered console output, and asserts the child exit code
// is propagated.
test "conpty: spawn cmd.exe, capture output, propagate exit code" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    // Write the marker to CONOUT$ (the console device) rather than stdout: it
    // exercises the pseudoconsole render path directly and does not depend on
    // how the child's stdout handle is wired, which is unreliable when this test
    // runs nested under a parent with redirected stdio (e.g. OpenSSH pipes).
    var session = try pty.Session.spawn(alloc, .{
        .command = &.{ "cmd.exe", "/c", "echo PHANTOM_CONPTY_OK 1>CONOUT$ & exit 7" },
    });
    defer session.deinit();

    var out: [65536]u8 = undefined;
    var out_len: usize = 0;
    var buf: [4096]u8 = undefined;

    // conhost renders and flushes the ConPTY screen asynchronously, a render
    // tick or two after the child writes. Keep draining the pipe for a settle
    // window after the process exits so the final frame is captured; the
    // pseudoconsole is not closed until deinit, so conhost stays alive here.
    var status: pty.ExitStatus = .still_running;
    var quiet_after_exit: usize = 0;
    var spins: usize = 0;
    while (spins < 8000) : (spins += 1) {
        const n = try session.read(&buf);
        if (n > 0) {
            const room = out.len - out_len;
            const take = @min(room, n);
            @memcpy(out[out_len .. out_len + take], buf[0..take]);
            out_len += take;
            quiet_after_exit = 0;
            continue;
        }
        // No data available right now; check whether the child has exited.
        if (status == .still_running) status = try session.pollExit();
        if (status != .still_running) {
            quiet_after_exit += 1;
            if (quiet_after_exit > 100) break;
        }
        Sleep(2);
    }

    if (status == .still_running) status = try session.wait();

    const produced = out[0..out_len];
    try std.testing.expect(std.mem.indexOf(u8, produced, "PHANTOM_CONPTY_OK") != null);
    try std.testing.expectEqual(pty.ExitStatus{ .exited = 7 }, status);
}
