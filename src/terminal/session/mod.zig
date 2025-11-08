//! PTY session management utilities for Phantom terminal widget
//! Provides async bridge between `pty.Session` and higher-level terminal components.

const manager = @import("manager.zig");

pub const Manager = manager.Manager;
pub const Session = manager.Session;
pub const SessionId = manager.SessionId;
pub const SessionHandle = manager.SessionHandle;
pub const SessionEvent = manager.SessionEvent;
pub const Event = manager.Event;
pub const Metrics = manager.Metrics;
pub const Error = manager.Error;
pub const ManagerError = manager.ManagerError;
pub const Config = manager.Config;
pub const ExitStatus = manager.ExitStatus;
