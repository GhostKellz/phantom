//! Notification widget for toast notifications and alerts
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Position = geometry.Position;
const Style = style.Style;

/// Notification types
pub const NotificationType = enum {
    info,
    success,
    warning,
    error,
    custom,
    
    pub fn getDefaultStyle(self: NotificationType) Style {
        return switch (self) {
            .info => Style.default().withFg(style.Color.bright_blue).withBg(style.Color.blue),
            .success => Style.default().withFg(style.Color.bright_green).withBg(style.Color.green),
            .warning => Style.default().withFg(style.Color.bright_yellow).withBg(style.Color.yellow),
            .error => Style.default().withFg(style.Color.bright_red).withBg(style.Color.red),
            .custom => Style.default(),
        };
    }
    
    pub fn getIcon(self: NotificationType) []const u8 {
        return switch (self) {
            .info => "ℹ️",
            .success => "✅",
            .warning => "⚠️",
            .error => "❌",
            .custom => "",
        };
    }
};

/// Notification positions
pub const NotificationPosition = enum {
    top_left,
    top_center,
    top_right,
    bottom_left,
    bottom_center,
    bottom_right,
    center,
    custom,
};

/// Notification animation types
pub const AnimationType = enum {
    none,
    fade,
    slide,
    bounce,
    scale,
};

/// Single notification instance
pub const Notification = struct {
    id: u32,
    title: []const u8,
    message: []const u8,
    notification_type: NotificationType,
    position: NotificationPosition,
    
    // Timing
    duration_ms: u64 = 3000, // 3 seconds default
    created_at: i64,
    auto_dismiss: bool = true,
    
    // Styling
    style: Style,
    title_style: Style,
    message_style: Style,
    border_style: Style,
    
    // Configuration
    show_icon: bool = true,
    show_close_button: bool = true,
    show_progress: bool = true,
    width: u16 = 40,
    
    // Animation
    animation: AnimationType = .slide,
    animation_duration_ms: u64 = 300,
    
    // State
    is_visible: bool = true,
    is_dismissing: bool = false,
    animation_progress: f32 = 0.0,
    
    pub fn init(id: u32, title: []const u8, message: []const u8, notification_type: NotificationType) Notification {
        const default_style = notification_type.getDefaultStyle();
        
        return Notification{
            .id = id,
            .title = title,
            .message = message,
            .notification_type = notification_type,
            .position = .top_right,
            .created_at = std.time.milliTimestamp(),
            .style = default_style,
            .title_style = default_style.withBold(),
            .message_style = default_style,
            .border_style = default_style,
        };
    }
    
    pub fn isExpired(self: *const Notification) bool {
        if (!self.auto_dismiss) return false;
        
        const current_time = std.time.milliTimestamp();
        return (current_time - self.created_at) >= self.duration_ms;
    }
    
    pub fn getRemainingTime(self: *const Notification) u64 {
        if (!self.auto_dismiss) return self.duration_ms;
        
        const current_time = std.time.milliTimestamp();
        const elapsed = @as(u64, @intCast(current_time - self.created_at));
        
        return if (elapsed >= self.duration_ms) 0 else self.duration_ms - elapsed;
    }
    
    pub fn getProgressPercentage(self: *const Notification) f32 {
        if (!self.auto_dismiss) return 0.0;
        
        const current_time = std.time.milliTimestamp();
        const elapsed = @as(f32, @floatFromInt(current_time - self.created_at));
        const total = @as(f32, @floatFromInt(self.duration_ms));
        
        return @min(elapsed / total, 1.0);
    }
};

/// Notification system manager
pub const NotificationSystem = struct {
    allocator: std.mem.Allocator,
    notifications: std.ArrayList(Notification),
    next_id: u32 = 1,
    max_notifications: u8 = 5,
    
    pub fn init(allocator: std.mem.Allocator) NotificationSystem {
        return NotificationSystem{
            .allocator = allocator,
            .notifications = std.ArrayList(Notification){},
        };
    }
    
    pub fn deinit(self: *NotificationSystem) void {
        for (self.notifications.items) |notification| {
            self.allocator.free(notification.title);
            self.allocator.free(notification.message);
        }
        self.notifications.deinit();
    }
    
    pub fn show(self: *NotificationSystem, title: []const u8, message: []const u8, notification_type: NotificationType) !u32 {
        const id = self.next_id;
        self.next_id += 1;
        
        var notification = Notification.init(id, title, message, notification_type);
        notification.title = try self.allocator.dupe(u8, title);
        notification.message = try self.allocator.dupe(u8, message);
        
        // Remove oldest notification if at capacity
        if (self.notifications.items.len >= self.max_notifications) {
            const oldest = self.notifications.orderedRemove(0);
            self.allocator.free(oldest.title);
            self.allocator.free(oldest.message);
        }
        
        try self.notifications.append(notification);
        return id;
    }
    
    pub fn showInfo(self: *NotificationSystem, title: []const u8, message: []const u8) !u32 {
        return self.show(title, message, .info);
    }
    
    pub fn showSuccess(self: *NotificationSystem, title: []const u8, message: []const u8) !u32 {
        return self.show(title, message, .success);
    }
    
    pub fn showWarning(self: *NotificationSystem, title: []const u8, message: []const u8) !u32 {
        return self.show(title, message, .warning);
    }
    
    pub fn showError(self: *NotificationSystem, title: []const u8, message: []const u8) !u32 {
        return self.show(title, message, .error);
    }
    
    pub fn dismiss(self: *NotificationSystem, id: u32) void {
        for (self.notifications.items, 0..) |*notification, i| {
            if (notification.id == id) {
                notification.is_dismissing = true;
                
                // Remove immediately for now (could add animation later)
                const removed = self.notifications.orderedRemove(i);
                self.allocator.free(removed.title);
                self.allocator.free(removed.message);
                return;
            }
        }
    }
    
    pub fn dismissAll(self: *NotificationSystem) void {
        for (self.notifications.items) |notification| {
            self.allocator.free(notification.title);
            self.allocator.free(notification.message);
        }
        self.notifications.clearAndFree();
    }
    
    pub fn update(self: *NotificationSystem) void {
        // Remove expired notifications
        var i: usize = 0;
        while (i < self.notifications.items.len) {
            if (self.notifications.items[i].isExpired()) {
                const removed = self.notifications.orderedRemove(i);
                self.allocator.free(removed.title);
                self.allocator.free(removed.message);
            } else {
                i += 1;
            }
        }
    }
    
    pub fn setMaxNotifications(self: *NotificationSystem, max: u8) void {
        self.max_notifications = max;
    }
};

/// Notification widget for rendering notifications
pub const NotificationWidget = struct {
    widget: Widget,
    system: *NotificationSystem,
    
    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),
    spacing: u16 = 1,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator, system: *NotificationSystem) !*NotificationWidget {
        const widget = try allocator.create(NotificationWidget);
        widget.* = NotificationWidget{
            .widget = Widget{ .vtable = &vtable },
            .system = system,
        };
        return widget;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *NotificationWidget = @fieldParentPtr("widget", widget);
        self.area = area;
        
        // Update system (remove expired notifications)
        self.system.update();
        
        // Render each notification
        var current_y = area.y;
        
        for (self.system.notifications.items) |notification| {
            current_y = self.renderNotification(buffer, notification, current_y);
            current_y += self.spacing;
            
            // Stop if we've run out of space
            if (current_y >= area.y + area.height) break;
        }
    }
    
    fn renderNotification(self: *NotificationWidget, buffer: *Buffer, notification: Notification, y: u16) u16 {
        if (!notification.is_visible) return y;
        
        // Calculate notification area
        const notification_height = self.calculateNotificationHeight(notification);
        const notification_x = self.calculateNotificationX(notification);
        
        const notification_area = Rect.init(
            notification_x,
            y,
            notification.width,
            notification_height
        );
        
        // Render background
        buffer.fill(notification_area, Cell.withStyle(notification.style));
        
        // Render border
        self.renderNotificationBorder(buffer, notification_area, notification);
        
        // Calculate content area
        const content_area = Rect.init(
            notification_area.x + 1,
            notification_area.y + 1,
            notification_area.width - 2,
            notification_area.height - 2
        );
        
        var content_y = content_area.y;
        
        // Render icon and title
        if (notification.show_icon and notification.notification_type.getIcon().len > 0) {
            const icon = notification.notification_type.getIcon();
            buffer.writeText(content_area.x, content_y, icon, notification.title_style);
            
            const title_x = content_area.x + @as(u16, @intCast(icon.len)) + 1;
            const title_width = content_area.width - @as(u16, @intCast(icon.len)) - 1;
            
            if (notification.show_close_button) {
                buffer.writeText(content_area.x + content_area.width - 1, content_y, "×", notification.border_style);
                // Adjust title width to account for close button
                const available_title_width = title_width - 2;
                const title_text = if (notification.title.len > available_title_width) 
                    notification.title[0..available_title_width] 
                else 
                    notification.title;
                buffer.writeText(title_x, content_y, title_text, notification.title_style);
            } else {
                const title_text = if (notification.title.len > title_width) 
                    notification.title[0..title_width] 
                else 
                    notification.title;
                buffer.writeText(title_x, content_y, title_text, notification.title_style);
            }
        } else {
            // No icon, just title
            const title_width = if (notification.show_close_button) 
                content_area.width - 2 
            else 
                content_area.width;
            
            const title_text = if (notification.title.len > title_width) 
                notification.title[0..title_width] 
            else 
                notification.title;
            
            buffer.writeText(content_area.x, content_y, title_text, notification.title_style);
            
            if (notification.show_close_button) {
                buffer.writeText(content_area.x + content_area.width - 1, content_y, "×", notification.border_style);
            }
        }
        
        content_y += 1;
        
        // Render message (with word wrapping)
        content_y = self.renderWrappedText(buffer, notification.message, content_area.x, content_y, content_area.width, notification.message_style);
        
        // Render progress bar if enabled
        if (notification.show_progress and notification.auto_dismiss) {
            const progress_y = notification_area.y + notification_area.height - 2;
            const progress_width = notification_area.width - 2;
            const progress_x = notification_area.x + 1;
            
            self.renderProgressBar(buffer, progress_x, progress_y, progress_width, notification.getProgressPercentage(), notification.style);
        }
        
        return notification_area.y + notification_area.height;
    }
    
    fn renderNotificationBorder(self: *NotificationWidget, buffer: *Buffer, area: Rect, notification: Notification) void {
        _ = self;
        
        // Top and bottom borders
        for (0..area.width) |x| {
            const x_pos = area.x + @as(u16, @intCast(x));
            buffer.setCell(x_pos, area.y, Cell.init('─', notification.border_style));
            buffer.setCell(x_pos, area.y + area.height - 1, Cell.init('─', notification.border_style));
        }
        
        // Left and right borders
        for (0..area.height) |y| {
            const y_pos = area.y + @as(u16, @intCast(y));
            buffer.setCell(area.x, y_pos, Cell.init('│', notification.border_style));
            buffer.setCell(area.x + area.width - 1, y_pos, Cell.init('│', notification.border_style));
        }
        
        // Corners
        buffer.setCell(area.x, area.y, Cell.init('┌', notification.border_style));
        buffer.setCell(area.x + area.width - 1, area.y, Cell.init('┐', notification.border_style));
        buffer.setCell(area.x, area.y + area.height - 1, Cell.init('└', notification.border_style));
        buffer.setCell(area.x + area.width - 1, area.y + area.height - 1, Cell.init('┘', notification.border_style));
    }
    
    fn renderWrappedText(self: *NotificationWidget, buffer: *Buffer, text: []const u8, x: u16, start_y: u16, width: u16, text_style: Style) u16 {
        _ = self;
        
        var current_y = start_y;
        var current_x = x;
        var line_start: usize = 0;
        
        for (text, 0..) |char, i| {
            if (char == '\n' or current_x >= x + width) {
                // Render current line
                if (i > line_start) {
                    const line_text = text[line_start..i];
                    buffer.writeText(x, current_y, line_text, text_style);
                }
                
                current_y += 1;
                current_x = x;
                line_start = if (char == '\n') i + 1 else i;
            } else {
                current_x += 1;
            }
        }
        
        // Render final line
        if (line_start < text.len) {
            const line_text = text[line_start..];
            buffer.writeText(x, current_y, line_text, text_style);
            current_y += 1;
        }
        
        return current_y;
    }
    
    fn renderProgressBar(self: *NotificationWidget, buffer: *Buffer, x: u16, y: u16, width: u16, progress: f32, bar_style: Style) void {
        _ = self;
        
        const filled_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(width)) * (1.0 - progress)));
        
        // Render filled portion
        for (0..filled_width) |i| {
            buffer.setCell(x + @as(u16, @intCast(i)), y, Cell.init('█', bar_style));
        }
        
        // Render empty portion
        for (filled_width..width) |i| {
            buffer.setCell(x + @as(u16, @intCast(i)), y, Cell.init('░', bar_style));
        }
    }
    
    fn calculateNotificationHeight(self: *NotificationWidget, notification: Notification) u16 {
        _ = self;
        
        var height: u16 = 2; // Border
        height += 1; // Title
        
        // Message height (with word wrapping)
        const message_lines = (notification.message.len + notification.width - 3) / (notification.width - 2);
        height += @as(u16, @intCast(message_lines));
        
        // Progress bar
        if (notification.show_progress and notification.auto_dismiss) {
            height += 1;
        }
        
        return @max(height, 4); // Minimum height
    }
    
    fn calculateNotificationX(self: *NotificationWidget, notification: Notification) u16 {
        return switch (notification.position) {
            .top_left, .bottom_left => self.area.x,
            .top_center, .bottom_center => self.area.x + (self.area.width - notification.width) / 2,
            .top_right, .bottom_right => self.area.x + self.area.width - notification.width,
            .center => self.area.x + (self.area.width - notification.width) / 2,
            .custom => self.area.x, // Could be customized
        };
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *NotificationWidget = @fieldParentPtr("widget", widget);
        
        switch (event) {
            .mouse => |mouse| {
                if (mouse.button == .left and mouse.pressed) {
                    // Check if click is on a close button
                    var current_y = self.area.y;
                    
                    for (self.system.notifications.items) |notification| {
                        if (!notification.is_visible) continue;
                        
                        const notification_height = self.calculateNotificationHeight(notification);
                        const notification_x = self.calculateNotificationX(notification);
                        
                        // Check if click is on close button
                        if (notification.show_close_button and
                            mouse.position.x == notification_x + notification.width - 2 and
                            mouse.position.y == current_y + 1) {
                            self.system.dismiss(notification.id);
                            return true;
                        }
                        
                        current_y += notification_height + self.spacing;
                        if (current_y >= self.area.y + self.area.height) break;
                    }
                }
            },
            else => {},
        }
        
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *NotificationWidget = @fieldParentPtr("widget", widget);
        self.area = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *NotificationWidget = @fieldParentPtr("widget", widget);
        // Note: NotificationSystem is owned externally, don't free it here
        self.system.allocator.destroy(self);
    }
};

// Example usage functions
pub fn exampleNotificationUsage(allocator: std.mem.Allocator) !void {
    var system = NotificationSystem.init(allocator);
    defer system.deinit();
    
    // Show different types of notifications
    _ = try system.showInfo("Info", "This is an informational message");
    _ = try system.showSuccess("Success", "Operation completed successfully!");
    _ = try system.showWarning("Warning", "This is a warning message");
    _ = try system.showError("Error", "Something went wrong");
    
    // Custom notification
    const custom_id = try system.show("Custom", "Custom notification message", .custom);
    
    // Later dismiss the custom notification
    system.dismiss(custom_id);
}

test "NotificationSystem basic operations" {
    const allocator = std.testing.allocator;
    
    var system = NotificationSystem.init(allocator);
    defer system.deinit();
    
    // Test showing notifications
    const id1 = try system.showInfo("Test", "Test message");
    const id2 = try system.showSuccess("Success", "Success message");
    
    try std.testing.expect(system.notifications.items.len == 2);
    try std.testing.expect(id1 != id2);
    
    // Test dismissing notifications
    system.dismiss(id1);
    try std.testing.expect(system.notifications.items.len == 1);
    
    // Test dismiss all
    system.dismissAll();
    try std.testing.expect(system.notifications.items.len == 0);
}

test "Notification expiration" {
    const allocator = std.testing.allocator;
    
    var system = NotificationSystem.init(allocator);
    defer system.deinit();
    
    // Create a notification with very short duration
    var notification = Notification.init(1, "Test", "Test message", .info);
    notification.duration_ms = 1; // 1ms
    notification.created_at = std.time.milliTimestamp() - 10; // 10ms ago
    
    try std.testing.expect(notification.isExpired());
    try std.testing.expect(notification.getRemainingTime() == 0);
}