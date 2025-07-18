//! Clipboard integration for Phantom TUI
//! Cross-platform clipboard support for copy/paste operations

const std = @import("std");
const builtin = @import("builtin");

/// Clipboard error types
pub const ClipboardError = error{
    NotAvailable,
    PermissionDenied,
    SystemError,
    UnsupportedFormat,
    OutOfMemory,
};

/// Clipboard content types
pub const ClipboardFormat = enum {
    text,
    html,
    rtf,
    image,
    custom,
};

/// Clipboard content
pub const ClipboardContent = struct {
    format: ClipboardFormat,
    data: []const u8,
    
    pub fn init(format: ClipboardFormat, data: []const u8) ClipboardContent {
        return ClipboardContent{
            .format = format,
            .data = data,
        };
    }
    
    pub fn deinit(self: *ClipboardContent, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Cross-platform clipboard implementation
pub const Clipboard = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) Clipboard {
        return Clipboard{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Clipboard) void {
        _ = self;
        // Cleanup resources if needed
    }
    
    /// Copy text to clipboard
    pub fn copyText(self: *Clipboard, text: []const u8) ClipboardError!void {
        return switch (builtin.os.tag) {
            .linux => self.copyTextLinux(text),
            .macos => self.copyTextMacOS(text),
            .windows => self.copyTextWindows(text),
            else => ClipboardError.NotAvailable,
        };
    }
    
    /// Paste text from clipboard
    pub fn pasteText(self: *Clipboard) ClipboardError![]u8 {
        return switch (builtin.os.tag) {
            .linux => self.pasteTextLinux(),
            .macos => self.pasteTextMacOS(),
            .windows => self.pasteTextWindows(),
            else => ClipboardError.NotAvailable,
        };
    }
    
    /// Check if clipboard has text content
    pub fn hasText(self: *Clipboard) bool {
        return switch (builtin.os.tag) {
            .linux => self.hasTextLinux(),
            .macos => self.hasTextMacOS(),
            .windows => self.hasTextWindows(),
            else => false,
        };
    }
    
    /// Clear clipboard contents
    pub fn clear(self: *Clipboard) ClipboardError!void {
        return switch (builtin.os.tag) {
            .linux => self.clearLinux(),
            .macos => self.clearMacOS(),
            .windows => self.clearWindows(),
            else => ClipboardError.NotAvailable,
        };
    }
    
    // Linux implementation using xclip/xsel
    fn copyTextLinux(self: *Clipboard, text: []const u8) ClipboardError!void {
        // Try xclip first
        const xclip_result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "xclip", "-selection", "clipboard" },
            .stdin_behavior = .Pipe,
        });
        
        if (xclip_result) |result| {
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);
            
            if (result.term.Exited == 0) {
                // Write text to xclip stdin
                return;
            }
        } else |_| {}
        
        // Fallback to xsel
        const xsel_result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "xsel", "--clipboard", "--input" },
            .stdin_behavior = .Pipe,
        });
        
        if (xsel_result) |result| {
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);
            
            if (result.term.Exited == 0) {
                // Write text to xsel stdin
                return;
            }
        } else |_| {}
        
        // If both fail, try using /proc/self/fd/0 approach
        const proc_result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "sh", "-c", "echo -n \"" ++ text ++ "\" | xclip -selection clipboard" },
        });
        
        if (proc_result) |result| {
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);
            
            if (result.term.Exited == 0) {
                return;
            }
        } else |_| {}
        
        return ClipboardError.SystemError;
    }
    
    fn pasteTextLinux(self: *Clipboard) ClipboardError![]u8 {
        // Try xclip first
        const xclip_result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "xclip", "-selection", "clipboard", "-o" },
        });
        
        if (xclip_result) |result| {
            defer self.allocator.free(result.stderr);
            
            if (result.term.Exited == 0) {
                return result.stdout;
            }
        } else |_| {}
        
        // Fallback to xsel
        const xsel_result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "xsel", "--clipboard", "--output" },
        });
        
        if (xsel_result) |result| {
            defer self.allocator.free(result.stderr);
            
            if (result.term.Exited == 0) {
                return result.stdout;
            }
        } else |_| {}
        
        return ClipboardError.SystemError;
    }
    
    fn hasTextLinux(self: *Clipboard) bool {
        const result = self.pasteTextLinux();
        if (result) |text| {
            self.allocator.free(text);
            return true;
        } else |_| {
            return false;
        }
    }
    
    fn clearLinux(self: *Clipboard) ClipboardError!void {
        return self.copyTextLinux("");
    }
    
    // macOS implementation using pbcopy/pbpaste
    fn copyTextMacOS(self: *Clipboard, text: []const u8) ClipboardError!void {
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"pbcopy"},
            .stdin_behavior = .Pipe,
        });
        
        if (result) |proc_result| {
            defer self.allocator.free(proc_result.stdout);
            defer self.allocator.free(proc_result.stderr);
            
            if (proc_result.term.Exited == 0) {
                // Write text to pbcopy stdin
                return;
            }
        } else |_| {}
        
        // Fallback using echo
        const echo_cmd = try std.fmt.allocPrint(self.allocator, "echo -n '{s}' | pbcopy", .{text});
        defer self.allocator.free(echo_cmd);
        
        const echo_result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "sh", "-c", echo_cmd },
        });
        
        if (echo_result) |proc_result| {
            defer self.allocator.free(proc_result.stdout);
            defer self.allocator.free(proc_result.stderr);
            
            if (proc_result.term.Exited == 0) {
                return;
            }
        } else |_| {}
        
        return ClipboardError.SystemError;
    }
    
    fn pasteTextMacOS(self: *Clipboard) ClipboardError![]u8 {
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"pbpaste"},
        });
        
        if (result) |proc_result| {
            defer self.allocator.free(proc_result.stderr);
            
            if (proc_result.term.Exited == 0) {
                return proc_result.stdout;
            }
        } else |_| {}
        
        return ClipboardError.SystemError;
    }
    
    fn hasTextMacOS(self: *Clipboard) bool {
        const result = self.pasteTextMacOS();
        if (result) |text| {
            self.allocator.free(text);
            return true;
        } else |_| {
            return false;
        }
    }
    
    fn clearMacOS(self: *Clipboard) ClipboardError!void {
        return self.copyTextMacOS("");
    }
    
    // Windows implementation using clip.exe and powershell
    fn copyTextWindows(self: *Clipboard, text: []const u8) ClipboardError!void {
        const cmd = try std.fmt.allocPrint(self.allocator, "echo {s} | clip", .{text});
        defer self.allocator.free(cmd);
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "cmd", "/c", cmd },
        });
        
        if (result) |proc_result| {
            defer self.allocator.free(proc_result.stdout);
            defer self.allocator.free(proc_result.stderr);
            
            if (proc_result.term.Exited == 0) {
                return;
            }
        } else |_| {}
        
        return ClipboardError.SystemError;
    }
    
    fn pasteTextWindows(self: *Clipboard) ClipboardError![]u8 {
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "powershell", "-Command", "Get-Clipboard" },
        });
        
        if (result) |proc_result| {
            defer self.allocator.free(proc_result.stderr);
            
            if (proc_result.term.Exited == 0) {
                return proc_result.stdout;
            }
        } else |_| {}
        
        return ClipboardError.SystemError;
    }
    
    fn hasTextWindows(self: *Clipboard) bool {
        const result = self.pasteTextWindows();
        if (result) |text| {
            self.allocator.free(text);
            return true;
        } else |_| {
            return false;
        }
    }
    
    fn clearWindows(self: *Clipboard) ClipboardError!void {
        return self.copyTextWindows("");
    }
};

/// Clipboard manager for handling clipboard operations in widgets
pub const ClipboardManager = struct {
    clipboard: Clipboard,
    enabled: bool = true,
    
    pub fn init(allocator: std.mem.Allocator) ClipboardManager {
        return ClipboardManager{
            .clipboard = Clipboard.init(allocator),
        };
    }
    
    pub fn deinit(self: *ClipboardManager) void {
        self.clipboard.deinit();
    }
    
    /// Copy text to clipboard with error handling
    pub fn copy(self: *ClipboardManager, text: []const u8) bool {
        if (!self.enabled) return false;
        
        self.clipboard.copyText(text) catch |err| {
            std.log.warn("Failed to copy to clipboard: {}", .{err});
            return false;
        };
        
        return true;
    }
    
    /// Paste text from clipboard with error handling
    pub fn paste(self: *ClipboardManager) ?[]u8 {
        if (!self.enabled) return null;
        
        return self.clipboard.pasteText() catch |err| {
            std.log.warn("Failed to paste from clipboard: {}", .{err});
            return null;
        };
    }
    
    /// Check if clipboard has text
    pub fn hasText(self: *ClipboardManager) bool {
        if (!self.enabled) return false;
        
        return self.clipboard.hasText();
    }
    
    /// Clear clipboard
    pub fn clear(self: *ClipboardManager) bool {
        if (!self.enabled) return false;
        
        self.clipboard.clear() catch |err| {
            std.log.warn("Failed to clear clipboard: {}", .{err});
            return false;
        };
        
        return true;
    }
    
    /// Enable/disable clipboard functionality
    pub fn setEnabled(self: *ClipboardManager, enabled: bool) void {
        self.enabled = enabled;
    }
    
    /// Check if clipboard is available on this system
    pub fn isAvailable(self: *ClipboardManager) bool {
        _ = self;
        return switch (builtin.os.tag) {
            .linux, .macos, .windows => true,
            else => false,
        };
    }
};

/// Clipboard shortcuts for common operations
pub const ClipboardShortcuts = struct {
    /// Standard copy shortcut (Ctrl+C)
    pub const COPY_SHORTCUT = struct {
        pub const ctrl = true;
        pub const key = 'c';
    };
    
    /// Standard paste shortcut (Ctrl+V)
    pub const PASTE_SHORTCUT = struct {
        pub const ctrl = true;
        pub const key = 'v';
    };
    
    /// Standard cut shortcut (Ctrl+X)
    pub const CUT_SHORTCUT = struct {
        pub const ctrl = true;
        pub const key = 'x';
    };
    
    /// Standard select all shortcut (Ctrl+A)
    pub const SELECT_ALL_SHORTCUT = struct {
        pub const ctrl = true;
        pub const key = 'a';
    };
};

/// Clipboard event for widget integration
pub const ClipboardEvent = struct {
    operation: Operation,
    text: ?[]const u8 = null,
    
    pub const Operation = enum {
        copy,
        paste,
        cut,
        clear,
    };
    
    pub fn init(operation: Operation, text: ?[]const u8) ClipboardEvent {
        return ClipboardEvent{
            .operation = operation,
            .text = text,
        };
    }
};

/// Utility functions for clipboard integration
pub const ClipboardUtils = struct {
    /// Sanitize text for clipboard (remove null bytes, etc.)
    pub fn sanitizeText(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        var sanitized = std.ArrayList(u8).init(allocator);
        defer sanitized.deinit();
        
        for (text) |char| {
            if (char != 0 and char != '\r') {
                try sanitized.append(char);
            }
        }
        
        return sanitized.toOwnedSlice();
    }
    
    /// Convert line endings to platform-specific format
    pub fn normalizeLineEndings(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        const line_ending = switch (builtin.os.tag) {
            .windows => "\r\n",
            else => "\n",
        };
        
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        var i: usize = 0;
        while (i < text.len) {
            if (text[i] == '\n') {
                try result.appendSlice(line_ending);
            } else if (text[i] == '\r') {
                // Skip \r if followed by \n
                if (i + 1 < text.len and text[i + 1] == '\n') {
                    try result.appendSlice(line_ending);
                    i += 1; // Skip the \n
                } else {
                    try result.appendSlice(line_ending);
                }
            } else {
                try result.append(text[i]);
            }
            i += 1;
        }
        
        return result.toOwnedSlice();
    }
    
    /// Escape special characters for shell commands
    pub fn escapeForShell(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        for (text) |char| {
            switch (char) {
                '"', '\'', '\\', '$', '`', '!', '&', '|', ';', '<', '>', '(', ')', '{', '}', '[', ']', '*', '?' => {
                    try result.append('\\');
                    try result.append(char);
                },
                else => try result.append(char),
            }
        }
        
        return result.toOwnedSlice();
    }
};

test "Clipboard manager initialization" {
    const allocator = std.testing.allocator;
    
    var manager = ClipboardManager.init(allocator);
    defer manager.deinit();
    
    // Test basic functionality
    try std.testing.expect(manager.enabled == true);
    
    // Test enable/disable
    manager.setEnabled(false);
    try std.testing.expect(manager.enabled == false);
    
    manager.setEnabled(true);
    try std.testing.expect(manager.enabled == true);
}

test "Clipboard text sanitization" {
    const allocator = std.testing.allocator;
    
    const input = "Hello\x00World\r\nTest";
    const sanitized = try ClipboardUtils.sanitizeText(allocator, input);
    defer allocator.free(sanitized);
    
    try std.testing.expectEqualStrings("HelloWorld\nTest", sanitized);
}

test "Line ending normalization" {
    const allocator = std.testing.allocator;
    
    const input = "Line1\nLine2\r\nLine3\rLine4";
    const normalized = try ClipboardUtils.normalizeLineEndings(allocator, input);
    defer allocator.free(normalized);
    
    // Result depends on platform
    const expected = switch (builtin.os.tag) {
        .windows => "Line1\r\nLine2\r\nLine3\r\nLine4",
        else => "Line1\nLine2\nLine3\nLine4",
    };
    
    try std.testing.expectEqualStrings(expected, normalized);
}

test "Shell escaping" {
    const allocator = std.testing.allocator;
    
    const input = "Hello \"World\" & $TEST";
    const escaped = try ClipboardUtils.escapeForShell(allocator, input);
    defer allocator.free(escaped);
    
    try std.testing.expectEqualStrings("Hello \\\"World\\\" \\& \\$TEST", escaped);
}

test "Clipboard event creation" {
    const event = ClipboardEvent.init(.copy, "test text");
    
    try std.testing.expect(event.operation == .copy);
    try std.testing.expectEqualStrings("test text", event.text.?);
}

test "Clipboard availability check" {
    const allocator = std.testing.allocator;
    
    var manager = ClipboardManager.init(allocator);
    defer manager.deinit();
    
    // Availability depends on platform
    const available = manager.isAvailable();
    const expected = switch (builtin.os.tag) {
        .linux, .macos, .windows => true,
        else => false,
    };
    
    try std.testing.expect(available == expected);
}