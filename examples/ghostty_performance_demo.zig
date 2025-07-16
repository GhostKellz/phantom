//! Ghostty Terminal Performance Demo - NVIDIA GPU monitoring
const std = @import("std");
const phantom = @import("phantom");

const App = phantom.App;
const TaskMonitor = phantom.widgets.TaskMonitor;

// Temporarily create a simplified SystemMonitor for this demo
const SystemMonitor = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !*SystemMonitor {
        const monitor = try allocator.create(SystemMonitor);
        monitor.* = SystemMonitor{
            .allocator = allocator,
        };
        return monitor;
    }
    
    pub fn updateCPU(self: *SystemMonitor, usage: f64) void {
        _ = self;
        _ = usage;
    }
    
    pub fn updateMemory(self: *SystemMonitor, used: u64, total: u64) void {
        _ = self;
        _ = used;
        _ = total;
    }
    
    pub fn updateGPU(self: *SystemMonitor, stats: GPUStats) void {
        _ = self;
        _ = stats;
    }
    
    pub fn updateNetwork(self: *SystemMonitor, stats: NetworkStats) void {
        _ = self;
        _ = stats;
    }
    
    pub fn updateTerminalStats(self: *SystemMonitor, fps: f64, frame_time: f64) void {
        _ = self;
        _ = fps;
        _ = frame_time;
    }
    
    pub fn setDisplayOptions(self: *SystemMonitor, options: anytype) void {
        _ = self;
        _ = options;
    }
    
    pub fn deinit(self: *SystemMonitor) void {
        self.allocator.destroy(self);
    }
    
    pub const GPUStats = struct {
        usage_percent: f64 = 0.0,
        memory_used_mb: u64 = 0,
        memory_total_mb: u64 = 0,
        temperature_c: f64 = 0.0,
        power_usage_w: f64 = 0.0,
        clock_speed_mhz: u64 = 0,
    };
    
    pub const NetworkStats = struct {
        bytes_sent: u64 = 0,
        bytes_received: u64 = 0,
        packets_sent: u64 = 0,
        packets_received: u64 = 0,
    };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Phantom app
    var app = try App.init(allocator, .{});
    defer app.deinit();

    // Create system monitor with NVIDIA optimizations
    const system_monitor = try SystemMonitor.init(allocator);
    defer system_monitor.deinit();
    
    system_monitor.setDisplayOptions(.{
        .cpu = true,
        .memory = true,
        .gpu = true,
        .network = true,
        .terminal = true,
    });

    // Simulate Ghostty terminal stats and NVIDIA GPU data
    std.log.info("🚀 Starting Ghostty Performance Monitor...\n", .{});
    std.log.info("💡 This demo shows NVIDIA GPU monitoring for terminal rendering\n", .{});
    std.log.info("⚡ Optimized for high-performance terminal rendering\n", .{});

    var frame_count: u64 = 0;
    var last_update = std.time.milliTimestamp();

    while (true) {
        const current_time = std.time.milliTimestamp();
        const elapsed = @as(f64, @floatFromInt(current_time - last_update)) / 1000.0;

        if (elapsed >= 0.1) { // Update every 100ms
            frame_count += 1;
            
            // Simulate realistic system stats
            const cpu_usage = 15.0 + 20.0 * @sin(@as(f64, @floatFromInt(frame_count)) * 0.1);
            const memory_used: u64 = 2048 + @as(u64, @intFromFloat(512.0 * @sin(@as(f64, @floatFromInt(frame_count)) * 0.05)));
            const memory_total: u64 = 16384; // 16GB
            
            // NVIDIA GPU stats (realistic for terminal rendering)
            const gpu_usage = 25.0 + 15.0 * @sin(@as(f64, @floatFromInt(frame_count)) * 0.08);
            const vram_used: u64 = 1024 + @as(u64, @intFromFloat(512.0 * @cos(@as(f64, @floatFromInt(frame_count)) * 0.06)));
            const vram_total: u64 = 8192; // 8GB
            const gpu_temp = 45.0 + 15.0 * @sin(@as(f64, @floatFromInt(frame_count)) * 0.03);
            const gpu_power = 75.0 + 25.0 * @cos(@as(f64, @floatFromInt(frame_count)) * 0.04);
            
            // Terminal rendering performance (high for smooth rendering)
            const render_fps = 144.0 + 16.0 * @sin(@as(f64, @floatFromInt(frame_count)) * 0.12);
            const frame_time = 1000.0 / render_fps; // ms
            
            // Network stats (moderate terminal traffic)
            const bytes_sent: u64 = @as(u64, @intFromFloat(1024.0 * @as(f64, @floatFromInt(frame_count))));
            const bytes_received: u64 = @as(u64, @intFromFloat(2048.0 * @as(f64, @floatFromInt(frame_count))));
            
            // Update system monitor
            system_monitor.updateCPU(cpu_usage);
            system_monitor.updateMemory(memory_used, memory_total);
            
            const gpu_stats = SystemMonitor.GPUStats{
                .usage_percent = gpu_usage,
                .memory_used_mb = vram_used,
                .memory_total_mb = vram_total,
                .temperature_c = gpu_temp,
                .power_usage_w = gpu_power,
                .clock_speed_mhz = 1785, // Typical GPU clock
            };
            system_monitor.updateGPU(gpu_stats);
            
            const network_stats = SystemMonitor.NetworkStats{
                .bytes_sent = bytes_sent,
                .bytes_received = bytes_received,
                .packets_sent = frame_count * 10,
                .packets_received = frame_count * 15,
            };
            system_monitor.updateNetwork(network_stats);
            
            system_monitor.updateTerminalStats(render_fps, frame_time);
            
            last_update = current_time;
        }

        // Render the app
        try app.render();

        // Check for quit
        if (!app.running) break;

        // Small delay to prevent spinning
        std.time.sleep(16_000_000); // ~60 FPS update loop
    }

    std.log.info("👻 Ghostty Performance Monitor terminated gracefully\n", .{});
}

// Simulation helper to generate realistic NVIDIA GPU metrics
fn simulateNvidiaMetrics(frame: u64) SystemMonitor.GPUStats {
    const time = @as(f64, @floatFromInt(frame)) * 0.016; // Assume 60 FPS
    
    return SystemMonitor.GPUStats{
        // GPU usage varies with terminal rendering load
        .usage_percent = 20.0 + 30.0 * @sin(time * 0.5) + 10.0 * @cos(time * 1.2),
        
        // VRAM usage for terminal buffers and textures
        .memory_used_mb = 800 + @as(u64, @intFromFloat(400.0 * @sin(time * 0.3))),
        .memory_total_mb = 8192,
        
        // Temperature responds to load
        .temperature_c = 42.0 + 18.0 * @sin(time * 0.2),
        
        // Power usage correlates with GPU activity
        .power_usage_w = 65.0 + 35.0 * @cos(time * 0.4),
        
        // Clock speed can vary with boost
        .clock_speed_mhz = 1650 + @as(u64, @intFromFloat(200.0 * @sin(time * 0.8))),
    };
}

// Helper to simulate terminal rendering performance
fn simulateTerminalPerformance(frame: u64) struct { fps: f64, frame_time: f64 } {
    const time = @as(f64, @floatFromInt(frame)) * 0.016;
    
    // High FPS for smooth terminal experience
    const base_fps = 120.0;
    const fps_variation = 24.0 * @sin(time * 0.6); // Slight variation
    const fps = base_fps + fps_variation;
    
    return .{
        .fps = fps,
        .frame_time = 1000.0 / fps,
    };
}
