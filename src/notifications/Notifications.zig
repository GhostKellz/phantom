//! Notifications - Desktop notification support
//! Provides cross-platform desktop notification capabilities for terminal applications

const std = @import("std");
const vxfw = @import("../vxfw.zig");

const Allocator = std.mem.Allocator;

/// Desktop notification manager
pub const NotificationManager = struct {
    allocator: Allocator,
    backend: NotificationBackend,
    app_name: []const u8,
    notifications: std.array_list.AlignedManaged(ActiveNotification, null),

    pub fn init(allocator: Allocator, app_name: []const u8) !NotificationManager {
        const backend = try detectNotificationBackend(allocator);

        return NotificationManager{
            .allocator = allocator,
            .backend = backend,
            .app_name = try allocator.dupe(u8, app_name),
            .notifications = std.array_list.AlignedManaged(ActiveNotification, null).init(allocator),
        };
    }

    pub fn deinit(self: *NotificationManager) void {
        self.allocator.free(self.app_name);
        for (self.notifications.items) |*notif| {
            notif.deinit(self.allocator);
        }
        self.notifications.deinit();
    }

    /// Send a simple notification
    pub fn notify(self: *NotificationManager, title: []const u8, message: []const u8) !NotificationId {
        const notification = Notification{
            .title = title,
            .message = message,
            .urgency = .normal,
            .timeout_ms = 5000,
            .icon = null,
            .actions = &[_]NotificationAction{},
        };
        return self.send(notification);
    }

    /// Send a notification with custom settings
    pub fn send(self: *NotificationManager, notification: Notification) !NotificationId {
        const id = self.generateId();

        switch (self.backend) {
            .libnotify => try self.sendLibnotify(id, notification),
            .dbus => try self.sendDbus(id, notification),
            .windows => try self.sendWindows(id, notification),
            .macos => try self.sendMacOS(id, notification),
            .terminal_bell => try self.sendTerminalBell(id, notification),
            .none => return NotificationError.NotSupported,
        }

        // Track active notification
        const active = ActiveNotification{
            .id = id,
            .title = try self.allocator.dupe(u8, notification.title),
            .message = try self.allocator.dupe(u8, notification.message),
            .timestamp = std.time.timestamp(),
        };
        try self.notifications.append(active);

        return id;
    }

    /// Close a notification
    pub fn close(self: *NotificationManager, id: NotificationId) !void {
        switch (self.backend) {
            .libnotify => try self.closeLibnotify(id),
            .dbus => try self.closeDbus(id),
            .windows => try self.closeWindows(id),
            .macos => try self.closeMacOS(id),
            .terminal_bell => {}, // Can't close terminal bell
            .none => return NotificationError.NotSupported,
        }

        // Remove from active notifications
        var i: usize = 0;
        while (i < self.notifications.items.len) {
            if (self.notifications.items[i].id == id) {
                var notif = self.notifications.orderedRemove(i);
                notif.deinit(self.allocator);
                return;
            }
            i += 1;
        }
    }

    /// Get list of active notifications
    pub fn getActiveNotifications(self: *const NotificationManager) []const ActiveNotification {
        return self.notifications.items;
    }

    /// Check if notifications are supported
    pub fn isSupported(self: *const NotificationManager) bool {
        return self.backend != .none;
    }

    /// Send notification via libnotify (Linux)
    fn sendLibnotify(self: *NotificationManager, id: NotificationId, notification: Notification) !void {
        _ = id;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var cmd_args = std.array_list.AlignedManaged([]const u8, null).init(arena.allocator());
        try cmd_args.append("notify-send");

        // Add urgency
        try cmd_args.append("--urgency");
        try cmd_args.append(switch (notification.urgency) {
            .low => "low",
            .normal => "normal",
            .critical => "critical",
        });

        // Add timeout
        if (notification.timeout_ms > 0) {
            try cmd_args.append("--expire-time");
            const timeout_str = try std.fmt.allocPrint(arena.allocator(), "{d}", .{notification.timeout_ms});
            try cmd_args.append(timeout_str);
        }

        // Add icon
        if (notification.icon) |icon| {
            try cmd_args.append("--icon");
            try cmd_args.append(icon);
        }

        // Add title and message
        try cmd_args.append(notification.title);
        try cmd_args.append(notification.message);

        // Execute notify-send
        var child = std.ChildProcess.init(cmd_args.items, self.allocator);
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        _ = try child.spawnAndWait();
    }

    /// Send notification via D-Bus (Linux)
    fn sendDbus(self: *NotificationManager, id: NotificationId, notification: Notification) !void {
        _ = id;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        // Build D-Bus command
        const dbus_cmd = try std.fmt.allocPrint(arena.allocator(),
            "dbus-send --session --dest=org.freedesktop.Notifications " ++
            "/org/freedesktop/Notifications org.freedesktop.Notifications.Notify " ++
            "string:'{s}' uint32:0 string:'{s}' string:'{s}' string:'{s}' " ++
            "array:string: dict:string:variant: int32:{d}",
            .{
                self.app_name,
                notification.icon orelse "",
                notification.title,
                notification.message,
                notification.timeout_ms,
            }
        );

        var cmd_args = [_][]const u8{ "sh", "-c", dbus_cmd };
        var child = std.ChildProcess.init(&cmd_args, self.allocator);
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        _ = try child.spawnAndWait();
    }

    /// Send notification on Windows
    fn sendWindows(self: *NotificationManager, id: NotificationId, notification: Notification) !void {
        _ = id;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        // Use PowerShell to show toast notification
        const ps_script = try std.fmt.allocPrint(arena.allocator(),
            "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, " ++
            "ContentType = WindowsRuntime] > $null; " ++
            "$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(" ++
            "[Windows.UI.Notifications.ToastTemplateType]::ToastText02); " ++
            "$toastXml = [xml] $template.GetXml(); " ++
            "$toastXml.GetElementsByTagName('text')[0].AppendChild($toastXml.CreateTextNode('{s}')) > $null; " ++
            "$toastXml.GetElementsByTagName('text')[1].AppendChild($toastXml.CreateTextNode('{s}')) > $null; " ++
            "$toast = [Windows.UI.Notifications.ToastNotification]::new($toastXml); " ++
            "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{s}').Show($toast)",
            .{ notification.title, notification.message, self.app_name }
        );

        var cmd_args = [_][]const u8{ "powershell", "-Command", ps_script };
        var child = std.ChildProcess.init(&cmd_args, self.allocator);
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        _ = try child.spawnAndWait();
    }

    /// Send notification on macOS
    fn sendMacOS(self: *NotificationManager, id: NotificationId, notification: Notification) !void {
        _ = id;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var cmd_args = std.array_list.AlignedManaged([]const u8, null).init(arena.allocator());
        try cmd_args.append("osascript");
        try cmd_args.append("-e");

        const script = try std.fmt.allocPrint(arena.allocator(),
            "display notification \"{s}\" with title \"{s}\"",
            .{ notification.message, notification.title }
        );
        try cmd_args.append(script);

        var child = std.ChildProcess.init(cmd_args.items, self.allocator);
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        _ = try child.spawnAndWait();
    }

    /// Send notification via terminal bell
    fn sendTerminalBell(self: *NotificationManager, id: NotificationId, notification: Notification) !void {
        _ = self;
        _ = id;
        _ = notification;

        // Simple terminal bell
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\x07"); // Bell character
    }

    /// Close notification implementations
    fn closeLibnotify(self: *NotificationManager, id: NotificationId) !void {
        _ = self;
        _ = id;
        // libnotify doesn't have a standard way to close notifications
    }

    fn closeDbus(self: *NotificationManager, id: NotificationId) !void {

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const dbus_cmd = try std.fmt.allocPrint(arena.allocator(),
            "dbus-send --session --dest=org.freedesktop.Notifications " ++
            "/org/freedesktop/Notifications org.freedesktop.Notifications.CloseNotification " ++
            "uint32:{d}",
            .{id}
        );

        var cmd_args = [_][]const u8{ "sh", "-c", dbus_cmd };
        var child = std.ChildProcess.init(&cmd_args, self.allocator);
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        _ = try child.spawnAndWait();
    }

    fn closeWindows(self: *NotificationManager, id: NotificationId) !void {
        _ = self;
        _ = id;
        // Windows toast notifications auto-close
    }

    fn closeMacOS(self: *NotificationManager, id: NotificationId) !void {
        _ = self;
        _ = id;
        // macOS notifications auto-close
    }

    /// Generate unique notification ID
    fn generateId(self: *NotificationManager) NotificationId {
        _ = self;
        return @as(NotificationId, @intCast(std.time.timestamp()));
    }
};

/// Detect available notification backend
fn detectNotificationBackend(allocator: Allocator) !NotificationBackend {
    const builtin = @import("builtin");

    switch (builtin.os.tag) {
        .linux => {
            // Try libnotify first
            if (commandExists(allocator, "notify-send")) {
                return .libnotify;
            }
            // Try D-Bus
            if (commandExists(allocator, "dbus-send")) {
                return .dbus;
            }
            return .terminal_bell;
        },
        .windows => return .windows,
        .macos => {
            if (commandExists(allocator, "osascript")) {
                return .macos;
            }
            return .terminal_bell;
        },
        else => return .terminal_bell,
    }
}

/// Check if a command exists in PATH
fn commandExists(allocator: Allocator, command: []const u8) bool {
    var child = std.ChildProcess.init(&[_][]const u8{ "which", command }, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    if (child.spawnAndWait()) |result| {
        return result == .Exited and result.Exited == 0;
    } else |_| {
        return false;
    }
}

/// Notification backend types
pub const NotificationBackend = enum {
    libnotify,  // Linux - notify-send
    dbus,       // Linux - D-Bus notifications
    windows,    // Windows - Toast notifications
    macos,      // macOS - osascript
    terminal_bell, // Fallback - terminal bell
    none,       // No support
};

/// Notification configuration
pub const Notification = struct {
    title: []const u8,
    message: []const u8,
    urgency: Urgency = .normal,
    timeout_ms: u32 = 5000, // 0 = no timeout
    icon: ?[]const u8 = null,
    actions: []const NotificationAction = &[_]NotificationAction{},
};

/// Notification urgency levels
pub const Urgency = enum {
    low,
    normal,
    critical,
};

/// Notification action (for interactive notifications)
pub const NotificationAction = struct {
    id: []const u8,
    label: []const u8,
};

/// Unique notification identifier
pub const NotificationId = u64;

/// Active notification tracking
pub const ActiveNotification = struct {
    id: NotificationId,
    title: []u8,
    message: []u8,
    timestamp: i64,

    pub fn deinit(self: *ActiveNotification, allocator: Allocator) void {
        allocator.free(self.title);
        allocator.free(self.message);
    }
};

/// Notification errors
pub const NotificationError = error{
    NotSupported,
    BackendError,
    InvalidId,
};

/// Widget mixin for notification support
pub fn NotificationWidget(comptime WidgetType: type) type {
    return struct {
        widget: WidgetType,
        notification_manager: *NotificationManager,

        const Self = @This();

        pub fn init(widget: WidgetType, notification_manager: *NotificationManager) Self {
            return Self{
                .widget = widget,
                .notification_manager = notification_manager,
            };
        }

        /// Send notification from this widget
        pub fn sendNotification(self: *Self, title: []const u8, message: []const u8) !NotificationId {
            return self.notification_manager.notify(title, message);
        }

        /// Send custom notification
        pub fn sendCustomNotification(self: *Self, notification: Notification) !NotificationId {
            return self.notification_manager.send(notification);
        }

        pub fn widget_interface(self: *const Self) vxfw.Widget {
            return .{
                .userdata = @constCast(self),
                .drawFn = typeErasedDrawFn,
                .eventHandlerFn = typeErasedEventHandler,
            };
        }

        fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
            const self: *const Self = @ptrCast(@alignCast(ptr));
            return self.widget.draw(ctx);
        }

        fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
            const self: *Self = @ptrCast(@alignCast(ptr));
            return self.widget.handleEvent(ctx);
        }
    };
}

test "NotificationManager creation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var manager = try NotificationManager.init(arena.allocator(), "TestApp");
    defer manager.deinit();

    try std.testing.expectEqualStrings("TestApp", manager.app_name);
    try std.testing.expectEqual(@as(usize, 0), manager.notifications.items.len);
}

test "Notification configuration" {
    const notification = Notification{
        .title = "Test Title",
        .message = "Test Message",
        .urgency = .critical,
        .timeout_ms = 10000,
        .icon = "info",
        .actions = &[_]NotificationAction{},
    };

    try std.testing.expectEqualStrings("Test Title", notification.title);
    try std.testing.expectEqualStrings("Test Message", notification.message);
    try std.testing.expectEqual(Urgency.critical, notification.urgency);
    try std.testing.expectEqual(@as(u32, 10000), notification.timeout_ms);
}

test "Backend detection" {
    const backend = try detectNotificationBackend(std.testing.allocator);

    // Should detect some backend (at least terminal_bell)
    try std.testing.expect(backend != .none);
}