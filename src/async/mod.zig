//! Async module for Phantom TUI
//! Provides non-blocking operations using zsync

pub const runtime = @import("runtime.zig");
pub const AsyncRuntime = runtime.AsyncRuntime;
pub const Config = runtime.Config;
pub const TaskHandle = runtime.TaskHandle;
pub const Channel = runtime.Channel;
pub const createChannel = runtime.createChannel;
pub const RuntimeStats = runtime.RuntimeStats;
