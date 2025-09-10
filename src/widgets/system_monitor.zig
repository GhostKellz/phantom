//! SystemMonitor widget with NVIDIA GPU support for Ghostty terminal
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const emoji = @import("../emoji.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Network statistics
pub const NetworkStats = struct {
    bytes_sent: u64 = 0,
    bytes_received: u64 = 0,
    packets_sent: u64 = 0,
    packets_received: u64 = 0,
    
    pub fn getThroughputMbps(self: *const NetworkStats, elapsed_seconds: f64) f64 {
        const total_bytes = self.bytes_sent + self.bytes_received;
        return (@as(f64, @floatFromInt(total_bytes)) * 8.0) / (elapsed_seconds * 1_000_000.0);
    }
};

/// GPU statistics (NVIDIA focused)
pub const GPUStats = struct {
    usage_percent: f64 = 0.0,
    memory_used_mb: u64 = 0,
    memory_total_mb: u64 = 0,
    temperature_c: f64 = 0.0,
    power_usage_w: f64 = 0.0,
    clock_speed_mhz: u64 = 0,
    
    pub fn getMemoryUsagePercent(self: *const GPUStats) f64 {
        if (self.memory_total_mb == 0) return 0.0;
        return (@as(f64, @floatFromInt(self.memory_used_mb)) / @as(f64, @floatFromInt(self.memory_total_mb))) * 100.0;
    }
};

/// System monitoring widget with enhanced GPU support
pub const SystemMonitor = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    
    // CPU stats
    cpu_usage: f64 = 0.0,
    cpu_cores: u32 = 0,
    
    // Memory stats
    memory_used_mb: u64 = 0,
    memory_total_mb: u64 = 0,
    
    // GPU stats (NVIDIA optimized)
    gpu_stats: GPUStats = GPUStats{},
    
    // Network stats
    network_stats: NetworkStats = NetworkStats{},
    
    // Terminal-specific stats
    render_fps: f64 = 0.0,
    frame_time_ms: f64 = 0.0,
    
    // Display options
    show_cpu: bool = true,
    show_memory: bool = true,
    show_gpu: bool = true,
    show_network: bool = true,
    show_terminal_stats: bool = true,
    compact_mode: bool = false,
    
    // Styling
    header_style: Style,
    normal_style: Style,
    warning_style: Style,
    critical_style: Style,
    
    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*SystemMonitor {
        const monitor = try allocator.create(SystemMonitor);
        monitor.* = SystemMonitor{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .header_style = Style.default().withFg(style.Color.bright_cyan).withBold(),
            .normal_style = Style.default().withFg(style.Color.white),
            .warning_style = Style.default().withFg(style.Color.bright_yellow),
            .critical_style = Style.default().withFg(style.Color.bright_red),
        };
        
        // Initialize system info
        monitor.detectSystemInfo() catch {};
        
        return monitor;
    }

    /// Update CPU usage percentage
    pub fn updateCPU(self: *SystemMonitor, usage_percent: f64) void {
        self.cpu_usage = @max(0.0, @min(100.0, usage_percent));
    }

    /// Update memory statistics
    pub fn updateMemory(self: *SystemMonitor, used_mb: u64, total_mb: u64) void {
        self.memory_used_mb = used_mb;
        self.memory_total_mb = total_mb;
    }

    /// Update GPU statistics (NVIDIA optimized)
    pub fn updateGPU(self: *SystemMonitor, gpu_stats: GPUStats) void {
        self.gpu_stats = gpu_stats;
    }

    /// Update network statistics
    pub fn updateNetwork(self: *SystemMonitor, network_stats: NetworkStats) void {
        self.network_stats = network_stats;
    }

    /// Update terminal rendering performance
    pub fn updateTerminalStats(self: *SystemMonitor, fps: f64, frame_time_ms: f64) void {
        self.render_fps = fps;
        self.frame_time_ms = frame_time_ms;
    }

    /// Enable/disable compact display mode
    pub fn setCompactMode(self: *SystemMonitor, compact: bool) void {
        self.compact_mode = compact;
    }

    /// Configure which stats to show
    pub fn setDisplayOptions(self: *SystemMonitor, options: struct {
        cpu: bool = true,
        memory: bool = true,
        gpu: bool = true,
        network: bool = true,
        terminal: bool = true,
    }) void {
        self.show_cpu = options.cpu;
        self.show_memory = options.memory;
        self.show_gpu = options.gpu;
        self.show_network = options.network;
        self.show_terminal_stats = options.terminal;
    }

    fn detectSystemInfo(self: *SystemMonitor) !void {
        // Detect CPU cores
        self.cpu_cores = @as(u32, @intCast(std.Thread.getCpuCount() catch 1));
        
        // TODO: Detect GPU info via nvidia-smi or similar
        // For now, set reasonable defaults
        self.gpu_stats.memory_total_mb = 8192; // 8GB default
    }

    fn getMemoryUsagePercent(self: *const SystemMonitor) f64 {
        if (self.memory_total_mb == 0) return 0.0;
        return (@as(f64, @floatFromInt(self.memory_used_mb)) / @as(f64, @floatFromInt(self.memory_total_mb))) * 100.0;
    }

    fn getStyleForUsage(self: *const SystemMonitor, usage_percent: f64) Style {
        return if (usage_percent >= 90.0) self.critical_style
        else if (usage_percent >= 75.0) self.warning_style
        else self.normal_style;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *SystemMonitor = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;

        var y: u16 = area.y;
        
        // Header
        if (y < area.y + area.height) {
            buffer.fill(Rect.init(area.x, y, area.width, 1), Cell.withStyle(self.header_style));
            const header = if (self.compact_mode) "🖥️ System" else "🖥️ SYSTEM MONITOR";
            buffer.writeText(area.x, y, header, self.header_style);
            y += 1;
        }

        // CPU Stats
        if (self.show_cpu and y < area.y + area.height) {
            self.renderCPUStats(buffer, area.x, y, area.width);
            y += 1;
            if (!self.compact_mode and y < area.y + area.height) {
                self.renderProgressBar(buffer, area.x + 2, y, area.width - 4, self.cpu_usage, self.getStyleForUsage(self.cpu_usage));
                y += 1;
            }
        }

        // Memory Stats
        if (self.show_memory and y < area.y + area.height) {
            const mem_percent = self.getMemoryUsagePercent();
            self.renderMemoryStats(buffer, area.x, y, area.width, mem_percent);
            y += 1;
            if (!self.compact_mode and y < area.y + area.height) {
                self.renderProgressBar(buffer, area.x + 2, y, area.width - 4, mem_percent, self.getStyleForUsage(mem_percent));
                y += 1;
            }
        }

        // GPU Stats (NVIDIA optimized)
        if (self.show_gpu and y < area.y + area.height) {
            self.renderGPUStats(buffer, area.x, y, area.width);
            y += 1;
            if (!self.compact_mode and y < area.y + area.height) {
                self.renderProgressBar(buffer, area.x + 2, y, area.width - 4, self.gpu_stats.usage_percent, self.getStyleForUsage(self.gpu_stats.usage_percent));
                y += 1;
            }
        }

        // Network Stats
        if (self.show_network and y < area.y + area.height) {
            self.renderNetworkStats(buffer, area.x, y, area.width);
            y += 1;
        }

        // Terminal Performance Stats
        if (self.show_terminal_stats and y < area.y + area.height) {
            self.renderTerminalStats(buffer, area.x, y, area.width);
            y += 1;
        }
    }

    fn renderCPUStats(self: *SystemMonitor, buffer: *Buffer, x: u16, y: u16, width: u16) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.normal_style));
        
        const cpu_text = if (self.compact_mode)
            std.fmt.allocPrint(self.allocator, "⚡ CPU: {d:.1}%", .{self.cpu_usage}) catch return
        else
            std.fmt.allocPrint(self.allocator, "⚡ CPU ({d} cores): {d:.1}%", .{ self.cpu_cores, self.cpu_usage }) catch return;
        defer self.allocator.free(cpu_text);
        
        const text_len = @min(cpu_text.len, width);
        const text_style = self.getStyleForUsage(self.cpu_usage);
        buffer.writeText(x, y, cpu_text[0..text_len], text_style);
    }

    fn renderMemoryStats(self: *SystemMonitor, buffer: *Buffer, x: u16, y: u16, width: u16, percent: f64) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.normal_style));
        
        const mem_text = if (self.compact_mode)
            std.fmt.allocPrint(self.allocator, "🧠 RAM: {d:.1}%", .{percent}) catch return
        else
            std.fmt.allocPrint(self.allocator, "🧠 Memory: {d}MB/{d}MB ({d:.1}%)", .{ self.memory_used_mb, self.memory_total_mb, percent }) catch return;
        defer self.allocator.free(mem_text);
        
        const text_len = @min(mem_text.len, width);
        const text_style = self.getStyleForUsage(percent);
        buffer.writeText(x, y, mem_text[0..text_len], text_style);
    }

    fn renderGPUStats(self: *SystemMonitor, buffer: *Buffer, x: u16, y: u16, width: u16) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.normal_style));
        
        const gpu_mem_percent = self.gpu_stats.getMemoryUsagePercent();
        const gpu_text = if (self.compact_mode)
            std.fmt.allocPrint(self.allocator, "🎮 GPU: {d:.1}%", .{self.gpu_stats.usage_percent}) catch return
        else
            std.fmt.allocPrint(self.allocator, "🎮 NVIDIA GPU: {d:.1}% | VRAM: {d:.1}% | {d:.0}°C", .{ self.gpu_stats.usage_percent, gpu_mem_percent, self.gpu_stats.temperature_c }) catch return;
        defer self.allocator.free(gpu_text);
        
        const text_len = @min(gpu_text.len, width);
        const text_style = self.getStyleForUsage(self.gpu_stats.usage_percent);
        buffer.writeText(x, y, gpu_text[0..text_len], text_style);
    }

    fn renderNetworkStats(self: *SystemMonitor, buffer: *Buffer, x: u16, y: u16, width: u16) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.normal_style));
        
        const throughput_mbps = self.network_stats.getThroughputMbps(1.0); // Assume 1 second interval
        const net_text = if (self.compact_mode)
            std.fmt.allocPrint(self.allocator, "🌐 Net: {d:.1}Mbps", .{throughput_mbps}) catch return
        else
            std.fmt.allocPrint(self.allocator, "🌐 Network: ↑{d}KB ↓{d}KB ({d:.1}Mbps)", .{ self.network_stats.bytes_sent / 1024, self.network_stats.bytes_received / 1024, throughput_mbps }) catch return;
        defer self.allocator.free(net_text);
        
        const text_len = @min(net_text.len, width);
        buffer.writeText(x, y, net_text[0..text_len], self.normal_style);
    }

    fn renderTerminalStats(self: *SystemMonitor, buffer: *Buffer, x: u16, y: u16, width: u16) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.normal_style));
        
        const term_text = if (self.compact_mode)
            std.fmt.allocPrint(self.allocator, "👻 Term: {d:.0}fps", .{self.render_fps}) catch return
        else
            std.fmt.allocPrint(self.allocator, "👻 Ghostty: {d:.0}fps | {d:.1}ms frame time", .{ self.render_fps, self.frame_time_ms }) catch return;
        defer self.allocator.free(term_text);
        
        const text_len = @min(term_text.len, width);
        const fps_style = if (self.render_fps >= 60.0) Style.default().withFg(style.Color.bright_green)
        else if (self.render_fps >= 30.0) self.warning_style
        else self.critical_style;
        buffer.writeText(x, y, term_text[0..text_len], fps_style);
    }

    fn renderProgressBar(self: *SystemMonitor, buffer: *Buffer, x: u16, y: u16, width: u16, percentage: f64, bar_style: Style) void {
        if (width == 0) return;
        
        const fill_width = @as(u16, @intFromFloat(@as(f64, @floatFromInt(width)) * (percentage / 100.0)));
        
        for (0..width) |i| {
            const char: u21 = if (i < fill_width) '█' else '░';
            const cell_style = if (i < fill_width) bar_style else self.normal_style;
            buffer.setCell(x + @as(u16, @intCast(i)), y, Cell.init(char, cell_style));
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        _ = widget;
        _ = event;
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *SystemMonitor = @fieldParentPtr("widget", widget);
        self.area = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *SystemMonitor = @fieldParentPtr("widget", widget);
        self.allocator.destroy(self);
    }
};

test "SystemMonitor widget creation" {
    const allocator = std.testing.allocator;

    const monitor = try SystemMonitor.init(allocator);
    defer monitor.widget.deinit();

    monitor.updateCPU(45.5);
    monitor.updateMemory(4096, 8192);
    
    const gpu_stats = GPUStats{
        .usage_percent = 78.3,
        .memory_used_mb = 3072,
        .memory_total_mb = 8192,
        .temperature_c = 67.5,
    };
    monitor.updateGPU(gpu_stats);
    
    try std.testing.expect(monitor.cpu_usage == 45.5);
    try std.testing.expect(monitor.getMemoryUsagePercent() == 50.0);
    try std.testing.expect(monitor.gpu_stats.getMemoryUsagePercent() == 37.5);
}
