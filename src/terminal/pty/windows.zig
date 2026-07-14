const std = @import("std");
const ArrayList = std.array_list.Managed;
const types = @import("types.zig");

const windows = std.os.windows;
const kernel32 = windows.kernel32;
const math = std.math;

const HRESULT = i32;
const HPCON = windows.HANDLE;
const ProcThreadAttributeList = opaque {};
const Overlapped = opaque {};

const HANDLE_FLAG_INHERIT: windows.DWORD = 0x00000001;
const PIPE_NOWAIT: windows.DWORD = 0x00000001;
const STILL_ACTIVE: windows.DWORD = 259;
const INFINITE: windows.DWORD = 0xFFFFFFFF;
const WAIT_OBJECT_0: windows.DWORD = 0x00000000;
const WAIT_TIMEOUT: windows.DWORD = 0x00000102;

extern "kernel32" fn CloseHandle(hObject: windows.HANDLE) callconv(.winapi) windows.BOOL;
extern "kernel32" fn CreatePipe(hReadPipe: *windows.HANDLE, hWritePipe: *windows.HANDLE, lpPipeAttributes: ?*windows.SECURITY_ATTRIBUTES, nSize: windows.DWORD) callconv(.winapi) windows.BOOL;
extern "kernel32" fn ReadFile(hFile: windows.HANDLE, lpBuffer: ?*anyopaque, nNumberOfBytesToRead: windows.DWORD, lpNumberOfBytesRead: *windows.DWORD, lpOverlapped: ?*Overlapped) callconv(.winapi) windows.BOOL;
extern "kernel32" fn WriteFile(hFile: windows.HANDLE, lpBuffer: ?*const anyopaque, nNumberOfBytesToWrite: windows.DWORD, lpNumberOfBytesWritten: *windows.DWORD, lpOverlapped: ?*Overlapped) callconv(.winapi) windows.BOOL;
extern "kernel32" fn WaitForSingleObject(hHandle: windows.HANDLE, dwMilliseconds: windows.DWORD) callconv(.winapi) windows.DWORD;
extern "kernel32" fn GetExitCodeProcess(hProcess: windows.HANDLE, lpExitCode: *windows.DWORD) callconv(.winapi) windows.BOOL;
extern "kernel32" fn SetHandleInformation(hObject: windows.HANDLE, dwMask: windows.DWORD, dwFlags: windows.DWORD) callconv(.winapi) windows.BOOL;
extern "kernel32" fn SetNamedPipeHandleState(hNamedPipe: windows.HANDLE, lpMode: ?*windows.DWORD, lpMaxCollectionCount: ?*windows.DWORD, lpCollectDataTimeout: ?*windows.DWORD) callconv(.winapi) windows.BOOL;
extern "kernel32" fn InitializeProcThreadAttributeList(lpAttributeList: ?*ProcThreadAttributeList, dwAttributeCount: windows.DWORD, dwFlags: windows.DWORD, lpSize: *usize) callconv(.winapi) windows.BOOL;
extern "kernel32" fn UpdateProcThreadAttribute(lpAttributeList: *ProcThreadAttributeList, dwFlags: windows.DWORD, attribute: usize, lpValue: *anyopaque, cbSize: usize, lpPreviousValue: ?*anyopaque, lpReturnSize: ?*usize) callconv(.winapi) windows.BOOL;
extern "kernel32" fn DeleteProcThreadAttributeList(lpAttributeList: *ProcThreadAttributeList) callconv(.winapi) void;

extern "kernel32" fn CreatePseudoConsole(size: windows.COORD, hInput: windows.HANDLE, hOutput: windows.HANDLE, dwFlags: windows.DWORD, phPC: *HPCON) callconv(.winapi) HRESULT;
extern "kernel32" fn ClosePseudoConsole(hPC: HPCON) callconv(.winapi) void;
extern "kernel32" fn ResizePseudoConsole(hPC: HPCON, size: windows.COORD) callconv(.winapi) HRESULT;

const STARTUPINFOEXW = extern struct {
    StartupInfo: windows.STARTUPINFOW,
    lpAttributeList: ?*ProcThreadAttributeList,
};

const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: usize = 0x00020016;

fn failed(hr: HRESULT) bool {
    return hr < 0;
}

fn appendCommandLineArg(command_line: *ArrayList(u8), arg: []const u8) !void {
    if (arg.len != 0 and std.mem.indexOfAny(u8, arg, " \t\"") == null) {
        try command_line.appendSlice(arg);
        return;
    }

    try command_line.append('"');
    var backslashes: usize = 0;
    for (arg) |byte| {
        switch (byte) {
            '\\' => backslashes += 1,
            '"' => {
                try command_line.appendNTimes('\\', backslashes * 2 + 1);
                try command_line.append('"');
                backslashes = 0;
            },
            else => {
                try command_line.appendNTimes('\\', backslashes);
                try command_line.append(byte);
                backslashes = 0;
            },
        }
    }
    try command_line.appendNTimes('\\', backslashes * 2);
    try command_line.append('"');
}

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
        sa.bInheritHandle = .TRUE;

        var input_read: windows.HANDLE = undefined;
        var input_write: windows.HANDLE = undefined;
        if (CreatePipe(&input_read, &input_write, &sa, 0) == .FALSE) {
            return error.SpawnFailed;
        }
        var input_read_open = true;
        errdefer {
            if (input_read_open) _ = CloseHandle(input_read);
            _ = CloseHandle(input_write);
        }

        var output_read: windows.HANDLE = undefined;
        var output_write: windows.HANDLE = undefined;
        if (CreatePipe(&output_read, &output_write, &sa, 0) == .FALSE) {
            return error.SpawnFailed;
        }
        var output_write_open = true;
        errdefer {
            _ = CloseHandle(output_read);
            if (output_write_open) _ = CloseHandle(output_write);
        }

        _ = SetHandleInformation(output_read, HANDLE_FLAG_INHERIT, 0);
        _ = SetHandleInformation(input_write, HANDLE_FLAG_INHERIT, 0);

        const size = windows.COORD{
            .X = @intCast(config.columns),
            .Y = @intCast(config.rows),
        };

        var hpc: HPCON = undefined;
        const hr = CreatePseudoConsole(size, input_read, output_write, 0, &hpc);
        if (failed(hr)) {
            return error.SpawnFailed;
        }
        errdefer ClosePseudoConsole(hpc);

        _ = CloseHandle(input_read);
        input_read_open = false;
        _ = CloseHandle(output_write);
        output_write_open = false;

        var mode: windows.DWORD = PIPE_NOWAIT;
        _ = SetNamedPipeHandleState(output_read, &mode, null, null);

        var cmd_builder = ArrayList(u8).init(allocator);
        defer cmd_builder.deinit();

        for (config.command, 0..) |arg, i| {
            if (i != 0) try cmd_builder.append(' ');
            try appendCommandLineArg(&cmd_builder, arg);
        }

        const cmd_utf8 = cmd_builder.items;
        const cmd_utf16 = try std.unicode.utf8ToUtf16LeAllocZ(allocator, cmd_utf8);
        defer allocator.free(cmd_utf16);
        const command_line = @constCast(cmd_utf16.ptr);

        var cwd_utf16: ?[:0]u16 = null;
        if (config.cwd) |cwd| {
            cwd_utf16 = try std.unicode.utf8ToUtf16LeAllocZ(allocator, cwd);
        }
        defer if (cwd_utf16) |dir| allocator.free(dir);
        const cwd_ptr: ?[*:0]u16 = if (cwd_utf16) |dir| dir.ptr else null;

        var attr_list_size: usize = 0;
        _ = InitializeProcThreadAttributeList(null, 1, 0, &attr_list_size);
        if (windows.GetLastError() != .INSUFFICIENT_BUFFER) {
            return error.SpawnFailed;
        }

        const attr_list_buf = try allocator.alloc(u8, attr_list_size);
        defer allocator.free(attr_list_buf);
        @memset(attr_list_buf, 0);
        const attr_list: *ProcThreadAttributeList = @ptrCast(attr_list_buf.ptr);

        if (InitializeProcThreadAttributeList(attr_list, 1, 0, &attr_list_size) == .FALSE) {
            return error.SpawnFailed;
        }
        defer DeleteProcThreadAttributeList(attr_list);

        // lpValue for PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE is the HPCON handle
        // value itself (not a pointer to it). Passing &hpc stores our stack
        // address as the console handle and the child fails with
        // STATUS_DLL_INIT_FAILED (0xC0000142).
        if (UpdateProcThreadAttribute(
            attr_list,
            0,
            PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            hpc,
            @sizeOf(HPCON),
            null,
            null,
        ) == .FALSE) {
            return error.SpawnFailed;
        }

        var startup_info_ex = std.mem.zeroes(STARTUPINFOEXW);
        startup_info_ex.StartupInfo.cb = @sizeOf(STARTUPINFOEXW);
        // Do NOT set STARTF_USESTDHANDLES: the PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE
        // attribute already binds the child's standard streams to the attached
        // pseudoconsole. Forcing USESTDHANDLES here (with the zeroed, i.e. NULL,
        // std handles) overrides that binding and detaches the child's stdio from
        // the ConPTY, so its output never reaches the render pipe.
        startup_info_ex.lpAttributeList = attr_list;

        var proc_info = std.mem.zeroes(windows.PROCESS.INFORMATION);

        if (kernel32.CreateProcessW(
            null,
            command_line,
            null,
            null,
            .FALSE,
            .{ .extended_startupinfo_present = true },
            null,
            cwd_ptr,
            &startup_info_ex.StartupInfo,
            &proc_info,
        ) == .FALSE) {
            return error.SpawnFailed;
        }

        _ = CloseHandle(proc_info.hThread);

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
        if (ReadFile(
            self.output_read,
            read_ptr,
            to_read,
            &bytes_read,
            null,
        ) == .FALSE) {
            const err = windows.GetLastError();
            switch (err) {
                .NO_DATA, .PIPE_LISTENING, .BROKEN_PIPE => return 0,
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
            if (WriteFile(
                self.input_write,
                chunk_ptr,
                chunk_len_dword,
                &bytes_written,
                null,
            ) == .FALSE) {
                const err = windows.GetLastError();
                switch (err) {
                    .NO_DATA, .PIPE_LISTENING => {
                        if (offset == 0) return error.WriteFailed;
                        return offset;
                    },
                    .BROKEN_PIPE => return error.WriteFailed,
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
        if (failed(hr)) {
            return error.ResizeFailed;
        }
    }

    pub fn pollExit(self: *Session) !types.ExitStatus {
        const wait_result = WaitForSingleObject(self.process_handle, 0);
        switch (wait_result) {
            WAIT_TIMEOUT => return .still_running,
            WAIT_OBJECT_0 => {
                var exit_code: windows.DWORD = 0;
                if (GetExitCodeProcess(self.process_handle, &exit_code) == .FALSE) {
                    return error.WaitPidError;
                }
                if (exit_code == STILL_ACTIVE) {
                    return .still_running;
                }
                const code: u8 = @intCast(@min(exit_code, 255));
                return .{ .exited = code };
            },
            else => return error.WaitPidError,
        }
    }

    pub fn wait(self: *Session) !types.ExitStatus {
        const wait_result = WaitForSingleObject(self.process_handle, INFINITE);
        if (wait_result != WAIT_OBJECT_0) {
            return error.WaitPidError;
        }

        var exit_code: windows.DWORD = 0;
        if (GetExitCodeProcess(self.process_handle, &exit_code) == .FALSE) {
            return error.WaitPidError;
        }

        const code: u8 = @intCast(@min(exit_code, 255));
        return .{ .exited = code };
    }

    pub fn deinit(self: *Session) void {
        if (self.input_write != windows.INVALID_HANDLE_VALUE) {
            _ = CloseHandle(self.input_write);
            self.input_write = windows.INVALID_HANDLE_VALUE;
        }
        if (self.output_read != windows.INVALID_HANDLE_VALUE) {
            _ = CloseHandle(self.output_read);
            self.output_read = windows.INVALID_HANDLE_VALUE;
        }
        if (self.process_handle != windows.INVALID_HANDLE_VALUE) {
            _ = CloseHandle(self.process_handle);
            self.process_handle = windows.INVALID_HANDLE_VALUE;
        }
        if (self.hpc != windows.INVALID_HANDLE_VALUE) {
            ClosePseudoConsole(self.hpc);
            self.hpc = windows.INVALID_HANDLE_VALUE;
        }
    }
};
