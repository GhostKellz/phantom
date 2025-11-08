const std = @import("std");
const types = @import("types.zig");
const builtin = @import("builtin");

const posix = std.posix;

const c = @cImport({
    @cDefine("_GNU_SOURCE", "1");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("sys/ioctl.h");
    @cInclude("sys/wait.h");
    @cInclude("termios.h");
    @cInclude("pty.h");
});

fn makeWinsize(columns: u16, rows: u16) c.struct_winsize {
    return c.struct_winsize{
        .ws_row = rows,
        .ws_col = columns,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
}

fn decodeStatus(status: c_int) types.ExitStatus {
    const status_int: u32 = @as(u32, @bitCast(status));
    const term_signal = status_int & 0x7f;
    if (term_signal == 0) {
        const code: u8 = @intCast((status_int >> 8) & 0xff);
        return .{ .exited = code };
    }
    return .{ .signal = @intCast(term_signal) };
}

fn dupZ(allocator: std.mem.Allocator, text: []const u8) ![:0]u8 {
    var buf = try allocator.allocSentinel(u8, text.len, 0);
    std.mem.copyForwards(u8, buf[0..text.len], text);
    return buf;
}

pub const Session = struct {
    allocator: std.mem.Allocator,
    master_fd: posix.fd_t,
    child_pid: posix.pid_t,

    pub fn spawn(allocator: std.mem.Allocator, config: types.Config) !Session {
        try config.validate();

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const arg_count = config.command.len;
        var argv_ptrs = try arena_allocator.alloc(?[*:0]const u8, arg_count + 1);
        var argv_storage = try arena_allocator.alloc([:0]u8, arg_count);

        var i: usize = 0;
        while (i < arg_count) : (i += 1) {
            argv_storage[i] = try dupZ(arena_allocator, config.command[i]);
            argv_ptrs[i] = argv_storage[i].ptr;
        }
        argv_ptrs[arg_count] = null;

        var cwd_z: ?[:0]u8 = null;
        if (config.cwd) |cwd| {
            cwd_z = try dupZ(arena_allocator, cwd);
        }

        if (config.clear_env and !@hasDecl(c, "clearenv")) {
            return error.ClearEnvFailed;
        }

        var env_storage = try arena_allocator.alloc([:0]u8, config.env.len);
        i = 0;
        while (i < config.env.len) : (i += 1) {
            const entry = config.env[i];
            if (std.mem.indexOfScalar(u8, entry, '=') == null) {
                return error.InvalidEnvironmentEntry;
            }
            env_storage[i] = try dupZ(arena_allocator, entry);
        }

        var master_fd: c_int = undefined;
        var slave_fd: c_int = undefined;
        if (c.openpty(&master_fd, &slave_fd, null, null, null) != 0) {
            return error.OpenPtyFailed;
        }

        const winsize = makeWinsize(config.columns, config.rows);
        if (c.ioctl(slave_fd, c.TIOCSWINSZ, &winsize) != 0) {
            _ = c.close(master_fd);
            _ = c.close(slave_fd);
            return error.SetWindowSizeFailed;
        }

        const pid = c.fork();
        if (pid == -1) {
            _ = c.close(master_fd);
            _ = c.close(slave_fd);
            return error.ForkFailed;
        }

        if (pid == 0) {
            // Child process
            _ = c.close(master_fd);

            if (c.setsid() == -1) c._exit(1);
            if (c.ioctl(slave_fd, c.TIOCSCTTY, @as(c_int, 0)) != 0) c._exit(1);

            if (c.dup2(slave_fd, std.posix.STDIN_FILENO) == -1) c._exit(1);
            if (c.dup2(slave_fd, std.posix.STDOUT_FILENO) == -1) c._exit(1);
            if (c.dup2(slave_fd, std.posix.STDERR_FILENO) == -1) c._exit(1);

            if (c.close(slave_fd) != 0) c._exit(1);

            if (cwd_z) |cwd_path| {
                const cwd_ptr: [*c]const u8 = @ptrCast(cwd_path.ptr);
                if (c.chdir(cwd_ptr) != 0) c._exit(1);
            }

            if (config.clear_env) {
                if (@hasDecl(c, "clearenv")) {
                    if (c.clearenv() != 0) c._exit(1);
                } else {
                    c._exit(1);
                }
            }

            var env_idx: usize = 0;
            while (env_idx < env_storage.len) : (env_idx += 1) {
                const env_ptr: [*c]u8 = @ptrCast(env_storage[env_idx].ptr);
                if (c.putenv(env_ptr) != 0) c._exit(1);
            }

            const file_ptr: [*c]const u8 = @ptrCast(argv_ptrs[0].?);
            const argv_ptr: [*c]?[*c]const u8 = @ptrCast(argv_ptrs.ptr);
            _ = c.execvp(file_ptr, argv_ptr);
            c._exit(127);
        }

        // Parent process
        _ = c.close(slave_fd);

        // Set master to non-blocking mode
        const fd = @as(posix.fd_t, master_fd);
        errdefer posix.close(fd);
        const flags = try posix.fcntl(fd, posix.F.GETFL, 0);
        const non_block = @as(usize, @intCast(@intFromEnum(posix.O.NONBLOCK)));
        try posix.fcntl(fd, posix.F.SETFL, flags | non_block);

        return Session{
            .allocator = allocator,
            .master_fd = fd,
            .child_pid = @as(posix.pid_t, pid),
        };
    }

    pub fn read(self: *Session, buffer: []u8) !usize {
        while (true) {
            const result = posix.read(self.master_fd, buffer) catch |err| switch (err) {
                error.Interrupted => continue,
                error.WouldBlock => return 0,
                else => return err,
            };
            return result;
        }
    }

    pub fn write(self: *Session, bytes: []const u8) !usize {
        var offset: usize = 0;
        while (offset < bytes.len) {
            const slice = bytes[offset..];
            const written = posix.write(self.master_fd, slice) catch |err| switch (err) {
                error.Interrupted => continue,
                error.WouldBlock => return if (offset == 0) err else offset,
                else => return err,
            };
            if (written == 0) return error.WriteFailed;
            offset += written;
        }
        return bytes.len;
    }

    pub fn resize(self: *Session, columns: u16, rows: u16) !void {
        var winsize = makeWinsize(columns, rows);
        const rc = c.ioctl(self.master_fd, c.TIOCSWINSZ, &winsize);
        if (rc != 0) {
            return error.ResizeFailed;
        }
    }

    pub fn pollExit(self: *Session) !types.ExitStatus {
        var status: c_int = undefined;
        const pid = c.waitpid(self.child_pid, &status, c.WNOHANG);
        if (pid == 0) return .still_running;
        if (pid == -1) {
            return error.WaitPidError;
        }
        return decodeStatus(status);
    }

    pub fn wait(self: *Session) !types.ExitStatus {
        var status: c_int = undefined;
        const pid = c.waitpid(self.child_pid, &status, 0);
        if (pid == -1) {
            return error.WaitPidError;
        }
        return decodeStatus(status);
    }

    pub fn deinit(self: *Session) void {
        if (self.master_fd != -1) {
            _ = posix.close(self.master_fd);
            self.master_fd = -1;
        }
    }
};

const testing = std.testing;

test "Session applies environment overrides" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var session = try Session.spawn(testing.allocator, .{
        .command = &.{ "/bin/sh", "-c", "printf %s \"$FOO\"" },
        .env = &.{"FOO=ziggy"},
        .clear_env = true,
    });
    defer session.deinit();

    var buffer: [128]u8 = undefined;
    var total: usize = 0;
    var attempts: usize = 0;

    while (total < buffer.len and attempts < 200) : (attempts += 1) {
        const written = try session.read(buffer[total..]);
        if (written == 0) {
            std.time.sleep(5 * std.time.ns_per_ms);
            continue;
        }
        total += written;
        if (total > 0) break;
    }

    try testing.expect(total > 0);
    try testing.expect(std.mem.startsWith(u8, buffer[0..total], "ziggy"));

    const status = try session.wait();
    switch (status) {
        .exited => |code| try testing.expect(code == 0),
        else => try testing.expect(false),
    }
}
