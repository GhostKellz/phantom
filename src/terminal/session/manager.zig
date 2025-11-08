const std = @import("std");
const builtin = @import("builtin");
const async_mod = @import("../../async/mod.zig");
const pty = @import("../pty.zig");
const types = pty;

const runtime_mod = async_mod.runtime;
const AsyncRuntime = runtime_mod.AsyncRuntime;

pub const Config = types.Config;
pub const ExitStatus = types.ExitStatus;

pub const SessionId = u64;

pub const SessionHandle = struct {
    id: SessionId,

    pub fn init(id: SessionId) SessionHandle {
        return SessionHandle{ .id = id };
    }
};

pub const SessionEvent = struct {
    handle: SessionHandle,
    event: Event,
};

const ManagedSession = struct {
    handle: SessionHandle,
    session: *Session,
    metrics: *Metrics,
};

pub const ManagerError = error{
    UnknownSession,
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    runtime: *AsyncRuntime,
    sessions: std.AutoHashMap(SessionId, ManagedSession),
    next_id: SessionId = 1,

    pub fn init(allocator: std.mem.Allocator, runtime: *AsyncRuntime) !*Manager {
        const self = try allocator.create(Manager);
        errdefer allocator.destroy(self);

        self.* = Manager{
            .allocator = allocator,
            .runtime = runtime,
            .sessions = std.AutoHashMap(SessionId, ManagedSession).init(allocator),
            .next_id = 1,
        };

        return self;
    }

    pub fn deinit(self: *Manager) void {
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            var managed = entry.value_ptr.*;
            managed.session.deinit();
            self.allocator.destroy(managed.metrics);
        }

        self.sessions.deinit();
        self.allocator.destroy(self);
    }

    pub fn sessionCount(self: *const Manager) usize {
        return self.sessions.count();
    }

    fn ensureSession(self: *Manager, handle: SessionHandle) !*ManagedSession {
        return self.sessions.getPtr(handle.id) orelse return ManagerError.UnknownSession;
    }

    pub fn spawn(self: *Manager, config: types.Config) !SessionHandle {
        const metrics_ptr = try self.allocator.create(Metrics);
        metrics_ptr.* = Metrics{};

        const session = try Session.init(self.allocator, self.runtime, config, metrics_ptr);
        errdefer {
            session.deinit();
            self.allocator.destroy(metrics_ptr);
        }

        try session.start();

        const id = self.next_id;
        self.next_id += 1;

        try self.sessions.put(id, ManagedSession{
            .handle = SessionHandle.init(id),
            .session = session,
            .metrics = metrics_ptr,
        });

        return SessionHandle.init(id);
    }

    pub fn write(self: *Manager, handle: SessionHandle, bytes: []const u8) !usize {
        const managed = try self.ensureSession(handle);
        return managed.session.write(bytes);
    }

    pub fn resize(self: *Manager, handle: SessionHandle, columns: u16, rows: u16) !void {
        const managed = try self.ensureSession(handle);
        try managed.session.resize(columns, rows);
    }

    pub fn stop(self: *Manager, handle: SessionHandle) !void {
        const managed = try self.ensureSession(handle);
        managed.session.stop();
    }

    pub fn waitForExit(self: *Manager, handle: SessionHandle) !types.ExitStatus {
        const managed = try self.ensureSession(handle);
        return managed.session.waitForExit();
    }

    pub fn metrics(self: *Manager, handle: SessionHandle) !*Metrics {
        const managed = try self.ensureSession(handle);
        return managed.metrics;
    }

    pub fn recycleEvent(self: *Manager, handle: SessionHandle, event: Event) !void {
        const managed = try self.ensureSession(handle);
        managed.session.recycleEvent(event);
    }

    pub fn release(self: *Manager, handle: SessionHandle) void {
        if (self.sessions.fetchRemove(handle.id)) |entry| {
            entry.value.session.deinit();
            self.allocator.destroy(entry.value.metrics);
        }
    }

    pub fn tryNextEvent(self: *Manager) !?SessionEvent {
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            const managed = entry.value_ptr.*;
            const maybe_event = try managed.session.channel().tryReceive();
            if (maybe_event) |evt| {
                return SessionEvent{
                    .handle = managed.handle,
                    .event = evt,
                };
            }
        }

        return null;
    }

    pub fn getSession(self: *Manager, handle: SessionHandle) !*Session {
        const managed = try self.ensureSession(handle);
        return managed.session;
    }
};

pub const Error = error{
    AlreadyRunning,
    NotRunning,
};

pub const Metrics = struct {
    bytes_read: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    bytes_written: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    dropped_bytes: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    exits: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    pub fn reset(self: *Metrics) void {
        self.bytes_read.store(0, .release);
        self.bytes_written.store(0, .release);
        self.dropped_bytes.store(0, .release);
        self.exits.store(0, .release);
    }
};

pub const Event = union(enum) {
    data: []u8,
    exit: types.ExitStatus,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    runtime: *AsyncRuntime,
    event_channel: *runtime_mod.Channel(Event),
    metrics: *Metrics,
    config: types.Config,

    pty_session: ?pty.Session = null,
    reader_task: ?runtime_mod.TaskHandle(@TypeOf(readerLoop)) = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(
        allocator: std.mem.Allocator,
        runtime: *AsyncRuntime,
        config: types.Config,
        metrics: *Metrics,
    ) !*Session {
        const event_channel = try runtime_mod.createChannel(allocator, Event, 1024);
        errdefer event_channel.deinit();

        const self = try allocator.create(Session);
        self.* = Session{
            .allocator = allocator,
            .runtime = runtime,
            .event_channel = event_channel,
            .metrics = metrics,
            .config = config,
        };

        return self;
    }

    pub fn deinit(self: *Session) void {
        self.stop();
        self.event_channel.deinit();
        self.allocator.destroy(self);
    }

    pub fn start(self: *Session) !void {
        if (self.running.swap(true, .acquire)) return Error.AlreadyRunning;

        errdefer self.running.store(false, .release);

        self.pty_session = try pty.Session.spawn(self.allocator, self.config);
        errdefer {
            if (self.pty_session) |*sess| {
                sess.deinit();
                self.pty_session = null;
            }
        }

        self.reader_task = try self.runtime.spawn(readerLoop, .{self});
    }

    pub fn stop(self: *Session) void {
        if (!self.running.swap(false, .acquire)) return;

        if (self.reader_task) |*task| {
            task.cancel();
            task.await() catch {};
            task.deinit();
            self.reader_task = null;
        }

        if (self.pty_session) |*sess| {
            sess.deinit();
            self.pty_session = null;
        }

        self.drainPendingEvents();
    }

    pub fn isRunning(self: *const Session) bool {
        return self.running.load(.acquire);
    }

    pub fn write(self: *Session, bytes: []const u8) !usize {
        const impl = if (self.pty_session) |*sess| sess else return error.NotRunning;
        const written = try impl.write(bytes);
        self.metrics.bytes_written.fetchAdd(written, .monotonic);
        return written;
    }

    pub fn resize(self: *Session, columns: u16, rows: u16) !void {
        if (self.pty_session) |*sess| {
            try sess.resize(columns, rows);
        }
    }

    pub fn waitForExit(self: *Session) !types.ExitStatus {
        const impl = if (self.pty_session) |*sess| sess else return error.NotRunning;
        const status = try impl.wait();
        self.notifyExit(status);
        return status;
    }

    pub fn channel(self: *Session) *runtime_mod.Channel(Event) {
        return self.event_channel;
    }

    pub fn recycleEvent(self: *Session, event: Event) void {
        switch (event) {
            .data => |payload| self.allocator.free(payload),
            .exit => |_| {},
        }
    }

    fn notifyExit(self: *Session, status: types.ExitStatus) void {
        self.metrics.exits.fetchAdd(1, .monotonic);
        _ = self.event_channel.trySend(.{ .exit = status }) catch {};
    }

    fn drainPendingEvents(self: *Session) void {
        while (true) {
            const maybe_event = self.event_channel.tryReceive() catch break;
            const event = maybe_event orelse break;
            switch (event) {
                .data => |payload| self.allocator.free(payload),
                .exit => |_| {},
            }
        }
    }
};

fn readerLoop(sess: *Session) !void {
    var buffer: [4096]u8 = undefined;

    while (sess.running.load(.acquire)) {
        const child = if (sess.pty_session) |*session| session else break;

        const amount = child.read(&buffer) catch |err| switch (err) {
            error.WouldBlock => {
                sess.runtime.yield() catch {};
                continue;
            },
            else => {
                const status = child.pollExit() catch {
                    sess.notifyExit(.still_running);
                    sess.running.store(false, .release);
                    return;
                };
                sess.notifyExit(status);
                sess.running.store(false, .release);
                return;
            },
        };

        if (amount == 0) {
            const status = child.pollExit() catch {
                sess.runtime.yield() catch {};
                continue;
            };

            switch (status) {
                .still_running => sess.runtime.yield() catch {},
                else => {
                    sess.notifyExit(status);
                    sess.running.store(false, .release);
                    return;
                },
            }

            continue;
        }

        const duped = sess.allocator.dupe(u8, buffer[0..amount]) catch {
            sess.metrics.dropped_bytes.fetchAdd(amount, .monotonic);
            sess.runtime.yield() catch {};
            continue;
        };

        const sent = sess.event_channel.trySend(.{ .data = duped }) catch |send_err| {
            sess.allocator.free(duped);
            return send_err;
        };

        if (!sent) {
            sess.metrics.dropped_bytes.fetchAdd(amount, .monotonic);
            sess.allocator.free(duped);
            sess.runtime.yield() catch {};
        } else {
            sess.metrics.bytes_read.fetchAdd(amount, .monotonic);
        }
    }

    if (sess.pty_session) |*child| {
        const status = child.pollExit() catch {
            return;
        };
        if (status != .still_running) {
            sess.notifyExit(status);
            sess.running.store(false, .release);
        }
    }
}

test "Session pumps PTY output to channel" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var runtime = try AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    var metrics = Metrics{};

    const command = switch (builtin.os.tag) {
        .windows => &.{ "cmd.exe", "/C", "echo phantom" },
        else => &.{ "/bin/sh", "-c", "printf phantom" },
    };

    const config = types.Config{
        .command = command,
        .columns = 80,
        .rows = 24,
    };

    var session = try Session.init(allocator, runtime, config, &metrics);
    defer session.deinit();

    try session.start();

    const channel = session.channel();

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var exit_status: ?types.ExitStatus = null;
    var iterations: usize = 0;

    while ((buffer.items.len == 0 or exit_status == null) and iterations < 200) {
        const maybe_event = try channel.tryReceive();
        if (maybe_event) |event| {
            switch (event) {
                .data => |payload| {
                    defer allocator.free(payload);
                    try buffer.appendSlice(payload);
                },
                .exit => |status| {
                    exit_status = status;
                },
            }
        } else {
            std.time.sleep(5 * std.time.ns_per_ms);
        }
        iterations += 1;
    }

    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "phantom") != null);

    try testing.expect(exit_status != null);
    switch (exit_status.?) {
        .exited => |code| try testing.expect(code == 0),
        else => try testing.expect(false),
    }

    try testing.expect(metrics.dropped_bytes.load(.acquire) == 0);
}

test "Manager orchestrates PTY sessions" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var runtime = try AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    const command = switch (builtin.os.tag) {
        .windows => &.{ "cmd.exe", "/C", "echo phantom" },
        else => &.{ "/bin/sh", "-c", "printf phantom" },
    };

    const config = types.Config{
        .command = command,
        .columns = 80,
        .rows = 24,
    };

    var manager = try Manager.init(allocator, runtime);
    defer manager.deinit();

    const handle = try manager.spawn(config);
    try testing.expectEqual(@as(usize, 1), manager.sessionCount());

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var exit_status: ?types.ExitStatus = null;
    var iterations: usize = 0;

    while ((buffer.items.len == 0 or exit_status == null) and iterations < 400) {
        if (try manager.tryNextEvent()) |session_event| {
            const event = session_event.event;
            switch (event) {
                .data => |payload| {
                    try buffer.appendSlice(payload);
                },
                .exit => |status| {
                    exit_status = status;
                },
            }
            manager.recycleEvent(session_event.handle, event) catch {};
        } else {
            std.time.sleep(5 * std.time.ns_per_ms);
        }
        iterations += 1;
    }

    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "phantom") != null);

    try testing.expect(exit_status != null);
    switch (exit_status.?) {
        .exited => |code| try testing.expect(code == 0),
        else => try testing.expect(false),
    }

    const metrics = try manager.metrics(handle);
    try testing.expect(metrics.dropped_bytes.load(.acquire) == 0);

    manager.release(handle);
    try testing.expectEqual(@as(usize, 0), manager.sessionCount());
}
