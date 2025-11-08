const std = @import("std");
const types = @import("types.zig");

const windows = std.os.windows;
const kernel32 = windows.kernel32;
const math = std.math;

const HPCON = windows.HANDLE;

extern "kernel32" fn CreatePseudoConsole(size: windows.COORD, hInput: windows.HANDLE, hOutput: windows.HANDLE, dwFlags: windows.DWORD, phPC: *HPCON) callconv(.Stdcall) windows.HRESULT;
extern "kernel32" fn ClosePseudoConsole(hPC: HPCON) callconv(.Stdcall) void;
extern "kernel32" fn ResizePseudoConsole(hPC: HPCON, size: windows.COORD) callconv(.Stdcall) windows.HRESULT;

const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: usize = 0x00020016;

pub const Session = struct {
    allocator: std.mem.Allocator,
    input_write: windows.HANDLE,
    output_read: windows.HANDLE,
    hpc: HPCON,
    process_handle: windows.HANDLE,

    pub fn spawn(allocator: std.mem.Allocator, config: types.Config) !Session {
        try config.validate();

        if (config.env.len != 0 or config.clear_env) {
            return error.UnsupportedPlatform;
        }

        var sa = std.mem.zeroes(windows.SECURITY_ATTRIBUTES);
        sa.nLength = @sizeOf(windows.SECURITY_ATTRIBUTES);
        sa.bInheritHandle = windows.TRUE;

        var input_read: windows.HANDLE = null;
        var input_write: windows.HANDLE = null;
        if (kernel32.CreatePipe(&input_read, &input_write, &sa, 0) == 0) {
            return error.SpawnFailed;
        }
        errdefer {
            if (input_read != null and input_read != windows.INVALID_HANDLE_VALUE) {
                _ = kernel32.CloseHandle(input_read);
            }
            if (input_write != null and input_write != windows.INVALID_HANDLE_VALUE) {
                _ = kernel32.CloseHandle(input_write);
            }
        }

        var output_read: windows.HANDLE = null;
        var output_write: windows.HANDLE = null;
        if (kernel32.CreatePipe(&output_read, &output_write, &sa, 0) == 0) {
            return error.SpawnFailed;
        }
        errdefer {
            if (output_read != null and output_read != windows.INVALID_HANDLE_VALUE) {
                _ = kernel32.CloseHandle(output_read);
            }
            if (output_write != null and output_write != windows.INVALID_HANDLE_VALUE) {
                _ = kernel32.CloseHandle(output_write);
            }
        }

        _ = kernel32.SetHandleInformation(output_read, windows.HANDLE_FLAG_INHERIT, 0);
        _ = kernel32.SetHandleInformation(input_write, windows.HANDLE_FLAG_INHERIT, 0);

        const size = windows.COORD{
            .X = @intCast(config.columns),
            .Y = @intCast(config.rows),
        };

        var hpc: HPCON = null;
        const hr = CreatePseudoConsole(size, input_read, output_write, 0, &hpc);
        if (windows.FAILED(hr)) {
            return error.SpawnFailed;
        }
        errdefer ClosePseudoConsole(hpc);

        _ = kernel32.CloseHandle(input_read);
        input_read = null;
        _ = kernel32.CloseHandle(output_write);
        output_write = null;

        var mode: windows.DWORD = windows.PIPE_NOWAIT;
        _ = kernel32.SetNamedPipeHandleState(output_read, &mode, null, null);

        var cmd_builder = std.ArrayList(u8).init(allocator);
        defer cmd_builder.deinit();

        for (config.command, 0..) |arg, i| {
            if (i != 0) try cmd_builder.append(' ');
            try windows.quoteCommandLineArg(arg, cmd_builder.writer());
        }

        const cmd_utf8 = cmd_builder.items;
        var cmd_utf16 = try std.unicode.utf8ToUtf16LeWithNull(allocator, cmd_utf8);
        defer allocator.free(cmd_utf16);
        const command_line = @constCast(cmd_utf16.ptr);

        var cwd_utf16: ?[:0]u16 = null;
        if (config.cwd) |cwd| {
            cwd_utf16 = try std.unicode.utf8ToUtf16LeWithNull(allocator, cwd);
        }
        defer if (cwd_utf16) |dir| allocator.free(dir);
        const cwd_ptr: ?[*:0]u16 = if (cwd_utf16) |dir| dir.ptr else null;

        var attr_list_size: usize = 0;
        _ = kernel32.InitializeProcThreadAttributeList(null, 1, 0, &attr_list_size);
        if (kernel32.GetLastError() != windows.ERROR_INSUFFICIENT_BUFFER) {
            return error.SpawnFailed;
        }

        var attr_list_buf = try allocator.alloc(u8, attr_list_size);
        defer allocator.free(attr_list_buf);
        std.mem.set(u8, attr_list_buf, 0);
        const attr_list: windows.LPPROC_THREAD_ATTRIBUTE_LIST = @ptrCast(attr_list_buf.ptr);

        if (kernel32.InitializeProcThreadAttributeList(attr_list, 1, 0, &attr_list_size) == 0) {
            return error.SpawnFailed;
        }
        defer kernel32.DeleteProcThreadAttributeList(attr_list);

        if (kernel32.UpdateProcThreadAttribute(
            attr_list,
            0,
            PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            &hpc,
            @sizeOf(HPCON),
            null,
            null,
        ) == 0) {
            return error.SpawnFailed;
        }

        var startup_info_ex = std.mem.zeroes(windows.STARTUPINFOEXW);
        startup_info_ex.StartupInfo.cb = @sizeOf(windows.STARTUPINFOEXW);
        startup_info_ex.lpAttributeList = attr_list;
        startup_info_ex.StartupInfo.dwFlags = windows.STARTF_USESTDHANDLES;
        startup_info_ex.StartupInfo.hStdInput = windows.INVALID_HANDLE_VALUE;
        startup_info_ex.StartupInfo.hStdOutput = windows.INVALID_HANDLE_VALUE;
        startup_info_ex.StartupInfo.hStdError = windows.INVALID_HANDLE_VALUE;

        var proc_info = std.mem.zeroes(windows.PROCESS_INFORMATION);

        if (kernel32.CreateProcessW(
            null,
            command_line,
            null,
            null,
            windows.FALSE,
            windows.EXTENDED_STARTUPINFO_PRESENT,
            null,
            cwd_ptr,
            &startup_info_ex.StartupInfo,
            &proc_info,
        ) == 0) {
            return error.SpawnFailed;
        }

        _ = kernel32.CloseHandle(proc_info.hThread);

        return Session{
            .allocator = allocator,
            .input_write = input_write,
            .output_read = output_read,
            .hpc = hpc,
            .process_handle = proc_info.hProcess,
        };
    }

    pub fn read(self: *Session, buffer: []u8) !usize {
        if (buffer.len == 0) return 0;

        var bytes_read: windows.DWORD = 0;
        const to_read: windows.DWORD = @intCast(@min(buffer.len, math.maxInt(u32)));
        const read_ptr: ?*anyopaque = @ptrCast(buffer.ptr);
        if (kernel32.ReadFile(
            self.output_read,
            read_ptr,
            to_read,
            &bytes_read,
            null,
        ) == 0) {
            const err = kernel32.GetLastError();
            switch (err) {
                windows.ERROR_NO_DATA, windows.ERROR_PIPE_LISTENING => return 0,
                windows.ERROR_BROKEN_PIPE => return 0,
                else => return error.ReadFailed,
            }
        }

        const result: usize = @intCast(bytes_read);
        return result;
    }

    pub fn write(self: *Session, bytes: []const u8) !usize {
        var offset: usize = 0;
        while (offset < bytes.len) {
            const remaining = bytes.len - offset;
            const chunk_len: usize = @min(remaining, math.maxInt(u32));
            var bytes_written: windows.DWORD = 0;

            const chunk_ptr: ?*const anyopaque = @ptrCast(bytes[offset..].ptr);
            const chunk_len_dword: windows.DWORD = @intCast(chunk_len);
            if (kernel32.WriteFile(
                self.input_write,
                chunk_ptr,
                chunk_len_dword,
                &bytes_written,
                null,
            ) == 0) {
                const err = kernel32.GetLastError();
                switch (err) {
                    windows.ERROR_NO_DATA, windows.ERROR_PIPE_LISTENING => {
                        if (offset == 0) return error.WriteFailed;
                        return offset;
                    },
                    windows.ERROR_BROKEN_PIPE => return error.WriteFailed,
                    else => return error.WriteFailed,
                }
            }

            if (bytes_written == 0) return error.WriteFailed;
            offset += bytes_written;
        }

        return bytes.len;
    }

    pub fn resize(self: *Session, columns: u16, rows: u16) !void {
        const size = windows.COORD{
            .X = @intCast(columns),
            .Y = @intCast(rows),
        };

        const hr = ResizePseudoConsole(self.hpc, size);
        if (windows.FAILED(hr)) {
            return error.ResizeFailed;
        }
    }

    pub fn pollExit(self: *Session) !types.ExitStatus {
        const wait_result = kernel32.WaitForSingleObject(self.process_handle, 0);
        switch (wait_result) {
            windows.WAIT_TIMEOUT => return .still_running,
            windows.WAIT_OBJECT_0 => {
                var exit_code: windows.DWORD = 0;
                if (kernel32.GetExitCodeProcess(self.process_handle, &exit_code) == 0) {
                    return error.WaitPidError;
                }
                if (exit_code == windows.STILL_ACTIVE) {
                    return .still_running;
                }
                const code: u8 = @intCast(@min(exit_code, 255));
                return .{ .exited = code };
            },
            else => return error.WaitPidError,
        }
    }

    pub fn wait(self: *Session) !types.ExitStatus {
        const wait_result = kernel32.WaitForSingleObject(self.process_handle, windows.INFINITE);
        if (wait_result != windows.WAIT_OBJECT_0) {
            return error.WaitPidError;
        }

        var exit_code: windows.DWORD = 0;
        if (kernel32.GetExitCodeProcess(self.process_handle, &exit_code) == 0) {
            return error.WaitPidError;
        }

        const code: u8 = @intCast(@min(exit_code, 255));
        return .{ .exited = code };
    }

    pub fn deinit(self: *Session) void {
        if (self.input_write != null and self.input_write != windows.INVALID_HANDLE_VALUE) {
            _ = kernel32.CloseHandle(self.input_write);
            self.input_write = null;
        }
        if (self.output_read != null and self.output_read != windows.INVALID_HANDLE_VALUE) {
            _ = kernel32.CloseHandle(self.output_read);
            self.output_read = null;
        }
        if (self.process_handle != null and self.process_handle != windows.INVALID_HANDLE_VALUE) {
            _ = kernel32.CloseHandle(self.process_handle);
            self.process_handle = null;
        }
        if (self.hpc != null) {
            ClosePseudoConsole(self.hpc);
            self.hpc = null;
        }
    }
};
