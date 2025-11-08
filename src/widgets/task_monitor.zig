//! TaskMonitor widget for tracking multiple concurrent tasks
const std = @import("std");
const ArrayList = std.array_list.Managed;
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const ProgressBar = @import("progress.zig").ProgressBar;

const Rect = geometry.Rect;
const Style = style.Style;

/// Task status for tracking
pub const TaskStatus = enum {
    pending,
    running,
    completed,
    failed,
    cancelled,
};

/// Individual task information
pub const Task = struct {
    id: []const u8,
    name: []const u8,
    status: TaskStatus = .pending,
    progress: f64 = 0.0,
    message: []const u8 = "",
    timer: std.time.Timer,

    pub fn init(allocator: std.mem.Allocator, id: []const u8, name: []const u8) !Task {
        return Task{
            .id = try allocator.dupe(u8, id),
            .name = try allocator.dupe(u8, name),
            .timer = try std.time.Timer.start(),
        };
    }

    pub fn deinit(self: *Task, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        if (self.message.len > 0) {
            allocator.free(self.message);
        }
    }

    pub fn setMessage(self: *Task, allocator: std.mem.Allocator, message: []const u8) !void {
        if (self.message.len > 0) {
            allocator.free(self.message);
        }
        self.message = try allocator.dupe(u8, message);
    }

    pub fn getElapsedTime(self: *Task) i64 {
        return @intCast(self.timer.read() / std.time.ns_per_ms);
    }

    pub fn getStatusEmoji(self: *const Task) []const u8 {
        return switch (self.status) {
            .pending => "⏳",
            .running => "🔄",
            .completed => "✅",
            .failed => "❌",
            .cancelled => "🚫",
        };
    }
};

/// TaskMonitor widget for tracking multiple concurrent operations
pub const TaskMonitor = struct {
    widget: Widget,
    allocator: std.mem.Allocator,

    // Task management
    tasks: ArrayList(Task),
    max_visible_tasks: u16 = 10,

    // Display options
    show_progress: bool = true,
    show_time: bool = true,
    show_emoji: bool = true,
    compact_mode: bool = false,

    // Styling
    header_style: Style,
    task_style: Style,
    progress_style: Style,
    completed_style: Style,
    failed_style: Style,

    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*TaskMonitor {
        const monitor = try allocator.create(TaskMonitor);
        monitor.* = TaskMonitor{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .tasks = ArrayList(Task).init(allocator),
            .header_style = Style.default().withFg(style.Color.bright_cyan).withBold(),
            .task_style = Style.default(),
            .progress_style = Style.default().withFg(style.Color.green),
            .completed_style = Style.default().withFg(style.Color.bright_green),
            .failed_style = Style.default().withFg(style.Color.bright_red),
        };
        return monitor;
    }

    /// Add a new task to monitor
    pub fn addTask(self: *TaskMonitor, id: []const u8, name: []const u8) !void {
        const task = try Task.init(self.allocator, id, name);
        try self.tasks.append(task);
    }

    /// Update task progress (0.0 to 100.0)
    pub fn updateProgress(self: *TaskMonitor, id: []const u8, progress: f64) void {
        for (self.tasks.items) |*task| {
            if (std.mem.eql(u8, task.id, id)) {
                task.progress = @max(0.0, @min(100.0, progress));
                task.status = if (progress >= 100.0) .completed else .running;
                return;
            }
        }
    }

    /// Update task status and message
    pub fn updateTask(self: *TaskMonitor, id: []const u8, status: TaskStatus, message: []const u8) !void {
        for (self.tasks.items) |*task| {
            if (std.mem.eql(u8, task.id, id)) {
                task.status = status;
                try task.setMessage(self.allocator, message);
                return;
            }
        }
    }

    /// Mark task as completed
    pub fn completeTask(self: *TaskMonitor, id: []const u8) void {
        self.updateProgress(id, 100.0);
    }

    /// Mark task as failed
    pub fn failTask(self: *TaskMonitor, id: []const u8, error_msg: []const u8) !void {
        try self.updateTask(id, .failed, error_msg);
    }

    /// Remove completed tasks
    pub fn clearCompleted(self: *TaskMonitor) void {
        var i: usize = 0;
        while (i < self.tasks.items.len) {
            if (self.tasks.items[i].status == .completed) {
                var task = self.tasks.swapRemove(i);
                task.deinit(self.allocator);
            } else {
                i += 1;
            }
        }
    }

    /// Get active task count
    pub fn getActiveCount(self: *const TaskMonitor) u32 {
        var count: u32 = 0;
        for (self.tasks.items) |task| {
            if (task.status == .running or task.status == .pending) {
                count += 1;
            }
        }
        return count;
    }

    /// Get overall progress (0.0 to 100.0)
    pub fn getOverallProgress(self: *const TaskMonitor) f64 {
        if (self.tasks.items.len == 0) return 100.0;

        var total_progress: f64 = 0.0;
        for (self.tasks.items) |task| {
            total_progress += task.progress;
        }
        return total_progress / @as(f64, @floatFromInt(self.tasks.items.len));
    }

    pub fn setCompactMode(self: *TaskMonitor, compact: bool) void {
        self.compact_mode = compact;
    }

    pub fn setMaxVisibleTasks(self: *TaskMonitor, max_tasks: u16) void {
        self.max_visible_tasks = max_tasks;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *TaskMonitor = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;

        var y: u16 = area.y;
        const max_y = area.y + area.height;

        // Render header
        if (y < max_y) {
            const active_count = self.getActiveCount();
            const overall_progress = self.getOverallProgress();

            var header_buf = ArrayList(u8).init(self.allocator);
            defer header_buf.deinit();

            if (self.show_emoji) {
                header_buf.appendSlice("📋 ") catch {};
            }

            const header_text = std.fmt.allocPrint(self.allocator, "Tasks: {}/{} active • {d:.1}% complete", .{ active_count, self.tasks.items.len, overall_progress }) catch "Tasks";
            defer self.allocator.free(header_text);

            header_buf.appendSlice(header_text) catch {};

            // Clear header line
            buffer.fill(Rect.init(area.x, y, area.width, 1), Cell.withStyle(self.header_style));

            // Render header text
            const header_len = @min(header_buf.items.len, area.width);
            if (header_len > 0) {
                buffer.writeText(area.x, y, header_buf.items[0..header_len], self.header_style);
            }
            y += 1;
        }

        // Render tasks
        const visible_tasks = @min(self.max_visible_tasks, @as(u16, @intCast(self.tasks.items.len)));
        var task_index: u16 = 0;

        while (task_index < visible_tasks and y < max_y) {
            const task = &self.tasks.items[task_index];

            if (self.compact_mode) {
                self.renderCompactTask(buffer, area.x, y, area.width, task);
                y += 1;
            } else {
                const lines_used = self.renderDetailedTask(buffer, area.x, y, area.width, max_y - y, task);
                y += lines_used;
            }

            task_index += 1;
        }
    }

    fn renderCompactTask(self: *TaskMonitor, buffer: *Buffer, x: u16, y: u16, width: u16, task: *Task) void {
        if (width == 0) return;

        // Clear line
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.task_style));

        var line_buf = ArrayList(u8).init(self.allocator);
        defer line_buf.deinit();

        // Status emoji
        if (self.show_emoji) {
            line_buf.appendSlice(task.getStatusEmoji()) catch {};
            line_buf.appendSlice(" ") catch {};
        }

        // Task name
        line_buf.appendSlice(task.name) catch {};

        // Progress
        if (self.show_progress and task.status == .running) {
            const progress_text = std.fmt.allocPrint(self.allocator, " ({d:.1}%)", .{task.progress}) catch "";
            defer self.allocator.free(progress_text);
            line_buf.appendSlice(progress_text) catch {};
        }

        // Time
        if (self.show_time and task.status == .running) {
            const elapsed = task.getElapsedTime();
            const elapsed_sec = @divFloor(elapsed, 1000);
            const time_text = std.fmt.allocPrint(self.allocator, " [{d}s]", .{elapsed_sec}) catch "";
            defer self.allocator.free(time_text);
            line_buf.appendSlice(time_text) catch {};
        }

        // Choose style
        const task_style = switch (task.status) {
            .completed => self.completed_style,
            .failed => self.failed_style,
            .running => self.progress_style,
            else => self.task_style,
        };

        // Render text
        const line_len = @min(line_buf.items.len, width);
        if (line_len > 0) {
            buffer.writeText(x, y, line_buf.items[0..line_len], task_style);
        }
    }

    fn renderDetailedTask(self: *TaskMonitor, buffer: *Buffer, x: u16, y: u16, width: u16, max_height: u16, task: *const Task) u16 {
        if (width == 0 or max_height == 0) return 0;

        var lines_used: u16 = 0;
        var current_y = y;

        // Task name line
        if (lines_used < max_height) {
            buffer.fill(Rect.init(x, current_y, width, 1), Cell.withStyle(self.task_style));

            var name_buf = ArrayList(u8).init(self.allocator);
            defer name_buf.deinit();

            if (self.show_emoji) {
                name_buf.appendSlice(task.getStatusEmoji()) catch {};
                name_buf.appendSlice(" ") catch {};
            }

            name_buf.appendSlice(task.name) catch {};

            const task_style = switch (task.status) {
                .completed => self.completed_style,
                .failed => self.failed_style,
                .running => self.progress_style,
                else => self.task_style,
            };

            const name_len = @min(name_buf.items.len, width);
            if (name_len > 0) {
                buffer.writeText(x, current_y, name_buf.items[0..name_len], task_style);
            }

            current_y += 1;
            lines_used += 1;
        }

        // Progress bar line (for running tasks)
        if (lines_used < max_height and task.status == .running and self.show_progress) {
            buffer.fill(Rect.init(x, current_y, width, 1), Cell.withStyle(self.task_style));

            // Render mini progress bar
            const progress_width = if (width > 10) width - 10 else width;
            const fill_width = @as(u16, @intFromFloat(@as(f64, @floatFromInt(progress_width)) * (task.progress / 100.0)));

            // Progress bar area
            var px: u16 = x + 2; // Indent
            while (px < x + 2 + progress_width) : (px += 1) {
                const char: u21 = if (px < x + 2 + fill_width) '█' else '░';
                const bar_style = if (px < x + 2 + fill_width) self.progress_style else self.task_style;
                buffer.setCell(px, current_y, Cell.init(char, bar_style));
            }

            // Progress percentage
            if (width > progress_width + 8) {
                const percent_text = std.fmt.allocPrint(self.allocator, " {d:.1}%", .{task.progress}) catch "";
                defer self.allocator.free(percent_text);
                buffer.writeText(x + 2 + progress_width + 1, current_y, percent_text, self.progress_style);
            }

            current_y += 1;
            lines_used += 1;
        }

        // Message line
        if (lines_used < max_height and task.message.len > 0) {
            buffer.fill(Rect.init(x, current_y, width, 1), Cell.withStyle(self.task_style));

            const message_text = std.fmt.allocPrint(self.allocator, "  └─ {s}", .{task.message}) catch task.message;
            defer if (!std.mem.eql(u8, message_text, task.message)) self.allocator.free(message_text);

            const msg_len = @min(message_text.len, width);
            if (msg_len > 0) {
                buffer.writeText(x, current_y, message_text[0..msg_len], Style.default().withFg(style.Color.bright_black));
            }

            current_y += 1;
            lines_used += 1;
        }

        return lines_used;
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        _ = widget;
        _ = event;
        // TaskMonitor doesn't handle events by default
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *TaskMonitor = @fieldParentPtr("widget", widget);
        self.area = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *TaskMonitor = @fieldParentPtr("widget", widget);

        for (self.tasks.items) |*task| {
            task.deinit(self.allocator);
        }
        self.tasks.deinit();

        self.allocator.destroy(self);
    }
};

test "TaskMonitor widget creation" {
    const allocator = std.testing.allocator;

    const monitor = try TaskMonitor.init(allocator);
    defer monitor.widget.deinit();

    try std.testing.expect(monitor.tasks.items.len == 0);
    try std.testing.expect(monitor.getActiveCount() == 0);
    try std.testing.expect(monitor.getOverallProgress() == 100.0);
}

test "TaskMonitor task management" {
    const allocator = std.testing.allocator;

    const monitor = try TaskMonitor.init(allocator);
    defer monitor.widget.deinit();

    try monitor.addTask("firefox", "Building firefox...");
    try monitor.addTask("discord", "Building discord...");

    try std.testing.expect(monitor.tasks.items.len == 2);
    try std.testing.expect(monitor.getActiveCount() == 2);

    monitor.updateProgress("firefox", 50.0);
    try std.testing.expect(monitor.tasks.items[0].progress == 50.0);
    try std.testing.expect(monitor.tasks.items[0].status == .running);

    monitor.completeTask("firefox");
    try std.testing.expect(monitor.tasks.items[0].progress == 100.0);
    try std.testing.expect(monitor.tasks.items[0].status == .completed);
    try std.testing.expect(monitor.getActiveCount() == 1);
}
