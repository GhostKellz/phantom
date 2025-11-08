//! Async module for Phantom TUI
//! Provides non-blocking operations using zsync

pub const runtime = @import("runtime.zig");
pub const AsyncRuntime = runtime.AsyncRuntime;
pub const Config = runtime.Config;
pub const TaskHandle = runtime.TaskHandle;
pub const Channel = runtime.Channel;
pub const createChannel = runtime.createChannel;
pub const RuntimeStats = runtime.RuntimeStats;
pub const LifecycleHooks = runtime.LifecycleHooks;
pub const ensureGlobal = runtime.ensureGlobal;
pub const startGlobal = runtime.startGlobal;
pub const shutdownGlobal = runtime.shutdownGlobal;
pub const globalRuntime = runtime.globalRuntime;

pub const nursery = @import("nursery.zig");
pub const Nursery = nursery.Nursery;

pub const test_harness = @import("test_harness.zig");
pub const TestHarness = test_harness.TestHarness;
pub const withTestHarness = test_harness.withTestHarness;
