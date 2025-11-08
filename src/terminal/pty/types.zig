const std = @import("std");

/// Configuration for spawning a PTY-backed subprocess
pub const Config = struct {
    /// Command to execute (argv[0]..argv[n-1])
    command: []const []const u8,

    /// Environment variables in KEY=VALUE form; empty inherits current env
    env: []const []const u8 = &.{},

    /// Working directory for child process (null → inherit)
    cwd: ?[]const u8 = null,

    /// Initial terminal columns/rows reported to subprocess
    columns: u16 = 80,
    rows: u16 = 24,

    /// If true, ignore parent environment when applying `env`
    clear_env: bool = false,

    /// Enable or disable echo (handled by child; here for future extensions)
    echo: bool = true,

    pub fn validate(self: Config) !void {
        if (self.command.len == 0) {
            return error.EmptyCommand;
        }
    }
};

pub const Error = error{
    EmptyCommand,
    UnsupportedPlatform,
    OpenPtyFailed,
    GrantPtyFailed,
    UnlockPtyFailed,
    PtsNameFailed,
    ForkFailed,
    ExecFailed,
    MakeControllingTerminalFailed,
    DupFailed,
    SetWindowSizeFailed,
    SetCwdFailed,
    WriteFailed,
    ReadFailed,
    ResizeFailed,
    SpawnFailed,
    InvalidEnvironmentEntry,
    ClearEnvFailed,
} || std.mem.Allocator.Error || std.posix.UnexpectedError || std.posix.OpenError || std.posix.CloseError || std.posix.ReadError || std.posix.WriteError || std.posix.WaitPidError || std.posix.ExecveError || std.posix.ForkError;

/// Result describing PTY child termination
pub const ExitStatus = union(enum) {
    still_running,
    exited: u8,
    signal: u8,
};
