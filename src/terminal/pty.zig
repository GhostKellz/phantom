const std = @import("std");
const builtin = @import("builtin");
const types = @import("pty/types.zig");

const unix_backend = @import("pty/unix.zig");
const windows_backend = @import("pty/windows.zig");

pub const Config = types.Config;
pub const Error = types.Error;
pub const ExitStatus = types.ExitStatus;

pub const Session = struct {
    const Impl = switch (builtin.os.tag) {
        .windows => windows_backend.Session,
        else => unix_backend.Session,
    };

    impl: Impl,

    pub fn spawn(allocator: std.mem.Allocator, config: Config) !Session {
        try config.validate();
        const impl = try Impl.spawn(allocator, config);
        return Session{ .impl = impl };
    }

    pub fn read(self: *Session, buffer: []u8) !usize {
        return self.impl.read(buffer);
    }

    pub fn write(self: *Session, bytes: []const u8) !usize {
        return self.impl.write(bytes);
    }

    pub fn resize(self: *Session, columns: u16, rows: u16) !void {
        try self.impl.resize(columns, rows);
    }

    pub fn pollExit(self: *Session) !ExitStatus {
        return self.impl.pollExit();
    }

    pub fn wait(self: *Session) !ExitStatus {
        return self.impl.wait();
    }

    pub fn deinit(self: *Session) void {
        self.impl.deinit();
    }
};
