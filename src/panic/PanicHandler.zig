//! PanicHandler - Terminal state recovery during application panics
//! Ensures terminal is properly restored even when the application crashes

const std = @import("std");
const builtin = @import("builtin");
const time_utils = @import("../time/utils.zig");
const GlobalTTY = @import("../tty/GlobalTTY.zig");

/// Panic handler configuration
pub const PanicConfig = struct {
    /// Whether to restore terminal state on panic
    restore_terminal: bool = true,
    /// Whether to show detailed panic info
    show_panic_info: bool = true,
    /// Whether to save panic info to file
    save_panic_log: bool = false,
    /// Custom panic log file path (null = default)
    panic_log_path: ?[]const u8 = null,
    /// Custom panic message prefix
    message_prefix: ?[]const u8 = null,
    /// Whether to attempt graceful cleanup
    attempt_cleanup: bool = true,
    /// Maximum time to spend on cleanup (milliseconds)
    cleanup_timeout_ms: u32 = 500,
};

/// Global panic configuration
var panic_config: PanicConfig = .{};
var original_panic_handler: ?*const fn ([]const u8, ?*std.builtin.StackTrace, ?usize) noreturn = null;
var panic_handler_installed: bool = false;

/// Install the panic handler
pub fn install(config: PanicConfig) void {
    panic_config = config;

    if (!panic_handler_installed) {
        // Store original panic handler
        original_panic_handler = @as(?*const fn ([]const u8, ?*std.builtin.StackTrace, ?usize) noreturn, @ptrCast(std.builtin.panic));

        // Install our panic handler
        std.builtin.panic = phantomPanicHandler;
        panic_handler_installed = true;
    }
}

/// Uninstall the panic handler
pub fn uninstall() void {
    if (panic_handler_installed) {
        if (original_panic_handler) |handler| {
            std.builtin.panic = handler;
        }
        panic_handler_installed = false;
    }
}

/// Check if panic handler is installed
pub fn isInstalled() bool {
    return panic_handler_installed;
}

/// Main panic handler implementation
fn phantomPanicHandler(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    // Step 1: Emergency terminal restoration (must be first and minimal)
    if (panic_config.restore_terminal) {
        GlobalTTY.emergencyRestoreGlobal();
    }

    // Step 2: Try to log panic information
    if (panic_config.save_panic_log) {
        savePanicLog(msg, error_return_trace, ret_addr) catch {};
    }

    // Step 3: Display panic information
    if (panic_config.show_panic_info) {
        displayPanicInfo(msg, error_return_trace, ret_addr) catch {};
    }

    // Step 4: Call original panic handler or exit
    if (original_panic_handler) |handler| {
        handler(msg, error_return_trace, ret_addr);
    } else {
        std.process.exit(1);
    }
}

/// Display panic information to stderr
fn displayPanicInfo(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) !void {
    const stderr = std.io.getStdErr().writer();

    // Write panic header
    try stderr.writeAll("\n");
    try stderr.writeAll("=" * 60);
    try stderr.writeAll("\n");

    if (panic_config.message_prefix) |prefix| {
        try stderr.print("{s}: PANIC\n", .{prefix});
    } else {
        try stderr.writeAll("PHANTOM TUI PANIC\n");
    }

    try stderr.writeAll("=" * 60);
    try stderr.writeAll("\n\n");

    // Write panic message
    try stderr.print("Message: {s}\n\n", .{msg});

    // Write return address if available
    if (ret_addr) |addr| {
        try stderr.print("Return address: 0x{x}\n\n", .{addr});
    }

    // Write stack trace if available
    if (error_return_trace) |trace| {
        try stderr.writeAll("Stack trace:\n");
        try writeStackTrace(stderr, trace);
        try stderr.writeAll("\n");
    }

    // Write terminal recovery info
    if (panic_config.restore_terminal) {
        try stderr.writeAll("Terminal state has been restored.\n");
    }

    try stderr.writeAll("=" * 60);
    try stderr.writeAll("\n");

    // Flush stderr
    try stderr.context.flush();
}

/// Save panic information to log file
fn savePanicLog(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) !void {
    const log_path = panic_config.panic_log_path orelse "phantom_panic.log";

    var file = std.Io.Dir.cwd().createFile(log_path, .{ .truncate = false }) catch return;
    defer file.close();

    // Seek to end of file for appending
    try file.seekFromEnd(0);

    const writer = file.writer();

    // Write timestamp
    const timestamp = time_utils.unixTimestampSeconds();
    try writer.print("\n[PANIC] {d} - ", .{timestamp});

    // Write panic message
    try writer.print("{s}\n", .{msg});

    // Write return address
    if (ret_addr) |addr| {
        try writer.print("Return address: 0x{x}\n", .{addr});
    }

    // Write stack trace
    if (error_return_trace) |trace| {
        try writer.writeAll("Stack trace:\n");
        try writeStackTrace(writer, trace);
    }

    try writer.writeAll("\n" ++ "-" * 40 ++ "\n");
}

/// Write stack trace to writer
fn writeStackTrace(writer: anytype, trace: *std.builtin.StackTrace) !void {
    var frame_index: usize = 0;
    var frames_it = std.debug.StackIterator.init(@returnAddress(), null);

    while (frames_it.next()) |frame| : (frame_index += 1) {
        if (frame_index >= trace.index) break;

        const return_address = frame - 1;
        try writer.print("  {d}: 0x{x}", .{ frame_index, return_address });

        // Try to get symbol information if available
        if (std.debug.getSelfDebugInfo()) |debug_info| {
            if (debug_info.getSymbolAtAddress(return_address)) |symbol| {
                try writer.print(" in {s}", .{symbol.symbol_name});
                if (symbol.source_location) |loc| {
                    try writer.print(" at {s}:{d}:{d}", .{ loc.file_name, loc.line, loc.column });
                }
            } else |_| {}
        } else |_| {}

        try writer.writeAll("\n");
    }
}

/// Register cleanup function to be called on panic
pub const CleanupRegistry = struct {
    cleanup_functions: std.array_list.AlignedManaged(CleanupFunction, null),
    mutex: std.Thread.Mutex = .{},

    const CleanupFunction = struct {
        func: *const fn ([]const u8) void,
        name: []const u8,
    };

    var global_registry: ?CleanupRegistry = null;

    pub fn init(allocator: std.mem.Allocator) CleanupRegistry {
        return CleanupRegistry{
            .cleanup_functions = std.array_list.AlignedManaged(CleanupFunction, null).init(allocator),
        };
    }

    pub fn deinit(self: *CleanupRegistry) void {
        self.cleanup_functions.deinit();
    }

    /// Initialize global cleanup registry
    pub fn initGlobal(allocator: std.mem.Allocator) !void {
        if (global_registry == null) {
            global_registry = init(allocator);
        }
    }

    /// Deinitialize global cleanup registry
    pub fn deinitGlobal() void {
        if (global_registry) |*registry| {
            registry.deinit();
            global_registry = null;
        }
    }

    /// Register a cleanup function
    pub fn registerCleanup(self: *CleanupRegistry, name: []const u8, func: *const fn ([]const u8) void) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.cleanup_functions.append(CleanupFunction{
            .func = func,
            .name = name,
        });
    }

    /// Register cleanup function with global registry
    pub fn registerGlobalCleanup(name: []const u8, func: *const fn ([]const u8) void) !void {
        if (global_registry) |*registry| {
            try registry.registerCleanup(name, func);
        }
    }

    /// Run all cleanup functions
    pub fn runCleanup(self: *CleanupRegistry, panic_msg: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.cleanup_functions.items) |cleanup| {
            cleanup.func(panic_msg);
        }
    }

    /// Run global cleanup functions
    pub fn runGlobalCleanup(panic_msg: []const u8) void {
        if (global_registry) |*registry| {
            registry.runCleanup(panic_msg);
        }
    }
};

/// RAII guard for automatic panic handler management
pub const PanicGuard = struct {
    config: PanicConfig,
    was_installed: bool,

    pub fn init(config: PanicConfig) PanicGuard {
        const was_installed = isInstalled();
        install(config);
        return PanicGuard{
            .config = config,
            .was_installed = was_installed,
        };
    }

    pub fn deinit(self: *PanicGuard) void {
        if (!self.was_installed) {
            uninstall();
        }
    }
};

/// Safe panic with terminal restoration
pub fn safePanic(comptime fmt: []const u8, args: anytype) noreturn {
    // Ensure terminal is restored before panicking
    if (panic_config.restore_terminal) {
        GlobalTTY.emergencyRestoreGlobal();
    }

    // Format the panic message
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const message = std.fmt.allocPrint(arena.allocator(), fmt, args) catch "Failed to format panic message";

    // Call the standard panic
    std.builtin.panic(message, null, null);
}

/// Assert with terminal restoration
pub fn safeAssert(condition: bool, comptime fmt: []const u8, args: anytype) void {
    if (!condition) {
        safePanic("Assertion failed: " ++ fmt, args);
    }
}

/// Debug utilities for panic situations
pub const PanicDebug = struct {
    /// Try to dump application state
    pub fn dumpState(writer: anytype) !void {
        try writer.writeAll("=== APPLICATION STATE DUMP ===\n");

        // Memory information
        if (builtin.mode == .Debug) {
            try writer.writeAll("Memory allocations:\n");
            // Would need custom allocator tracking for detailed memory info
            try writer.writeAll("  (Memory tracking not implemented)\n");
        }

        // TTY state
        try writer.writeAll("TTY state:\n");
        if (GlobalTTY.getGlobal()) |tty| {
            try writer.print("  Raw mode: {}\n", .{tty.is_raw_mode});
            try writer.print("  Alternate screen: {}\n", .{tty.alternate_screen});
            try writer.print("  Mouse enabled: {}\n", .{tty.mouse_enabled});
        } else {
            try writer.writeAll("  TTY not initialized\n");
        }

        // Environment information
        try writer.writeAll("Environment:\n");
        if (std.c.getenv("TERM")) |term_ptr| {
            try writer.print("  TERM={s}\n", .{std.mem.span(term_ptr)});
        }
        if (std.c.getenv("COLORTERM")) |colorterm_ptr| {
            try writer.print("  COLORTERM={s}\n", .{std.mem.span(colorterm_ptr)});
        }

        try writer.writeAll("==============================\n");
    }

    /// Write minimal crash report
    pub fn writeCrashReport(msg: []const u8) void {
        var file = std.Io.Dir.cwd().createFile("phantom_crash_report.txt", .{}) catch return;
        defer file.close();

        const writer = file.writer();
        writer.writeAll("PHANTOM TUI CRASH REPORT\n") catch return;
        writer.writeAll("========================\n\n") catch return;
        writer.print("Crash message: {s}\n\n", .{msg}) catch return;

        dumpState(writer) catch return;
    }
};

/// Example cleanup functions
pub fn exampleFileCleanup(panic_msg: []const u8) void {
    _ = panic_msg;
    // Clean up temporary files
    std.Io.Dir.cwd().deleteFile("temp_file.tmp") catch {};
}

pub fn exampleNetworkCleanup(panic_msg: []const u8) void {
    _ = panic_msg;
    // Close network connections
    // (Implementation would depend on networking library)
}

test "Panic handler installation" {
    const config = PanicConfig{
        .restore_terminal = true,
        .show_panic_info = false,
        .save_panic_log = false,
    };

    try std.testing.expect(!isInstalled());

    install(config);
    try std.testing.expect(isInstalled());

    uninstall();
    try std.testing.expect(!isInstalled());
}

test "PanicGuard RAII" {
    const config = PanicConfig{};

    {
        var guard = PanicGuard.init(config);
        defer guard.deinit();
        try std.testing.expect(isInstalled());
    }

    try std.testing.expect(!isInstalled());
}

test "CleanupRegistry" {
    var registry = CleanupRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.registerCleanup("test", exampleFileCleanup);
    try std.testing.expectEqual(@as(usize, 1), registry.cleanup_functions.items.len);
}
