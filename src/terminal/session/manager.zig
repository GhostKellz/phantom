const std = @import("std");
const ArrayList = std.array_list.Managed;
const builtin = @import("builtin");
const async_mod = @import("../../async/mod.zig");
const pty = @import("../pty.zig");
const types = pty;
const time_utils = @import("../../time/utils.zig");

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
        // Always signal the loop to stop and tear down the reader task, even if
        // the reader already cleared `running` on child exit. Gating cleanup on
        // the previous `running` value would leak the reader task's future
        // whenever the child exited before an explicit stop. Cleanup is
        // idempotent: the handle and pty session are nulled after teardown.
        self.running.store(false, .release);

        if (self.reader_task) |*task| {
            task.cancel();
            task.wait() catch {};
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
        _ = self.metrics.bytes_written.fetchAdd(written, .monotonic);
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
            .exit => {},
        }
    }

    fn notifyExit(self: *Session, status: types.ExitStatus) void {
        _ = self.metrics.exits.fetchAdd(1, .monotonic);
        _ = self.event_channel.trySend(.{ .exit = status }) catch {};
    }

    fn drainPendingEvents(self: *Session) void {
        while (true) {
            const maybe_event = self.event_channel.tryReceive() catch break;
            const event = maybe_event orelse break;
            switch (event) {
                .data => |payload| self.allocator.free(payload),
                .exit => {},
            }
        }
    }
};

fn readerLoop(sess: *Session) !void {
    var buffer: [4096]u8 = undefined;

    while (sess.running.load(.acquire)) {
        const child = if (sess.pty_session) |*session| session else break;

        const amount = child.read(&buffer) catch |err| switch (err) {
            else => {
                // A read failure (e.g. EIO once the slave closes) means the child
                // is gone. Block on wait() to reap the real exit status; a
                // non-blocking poll here races the child becoming waitable and
                // would spuriously report `.still_running`.
                const status = child.wait() catch {
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
            _ = sess.metrics.dropped_bytes.fetchAdd(amount, .monotonic);
            sess.runtime.yield() catch {};
            continue;
        };

        const sent = sess.event_channel.trySend(.{ .data = duped }) catch |send_err| {
            sess.allocator.free(duped);
            return send_err;
        };

        if (!sent) {
            _ = sess.metrics.dropped_bytes.fetchAdd(amount, .monotonic);
            sess.allocator.free(duped);
            sess.runtime.yield() catch {};
        } else {
            _ = sess.metrics.bytes_read.fetchAdd(amount, .monotonic);
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

    var buffer = ArrayList(u8).init(allocator);
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
            time_utils.sleepMs(5);
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

    var buffer = ArrayList(u8).init(allocator);
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
            time_utils.sleepMs(5);
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

test "Manager resize propagates to interactive PTY session" {
    if (builtin.os.tag == .windows) return;

    const testing = std.testing;
    const allocator = testing.allocator;

    var runtime = try AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    var manager = try Manager.init(allocator, runtime);
    defer manager.deinit();

    const handle = try manager.spawn(.{
        .command = &.{ "/bin/sh", "-i" },
        .columns = 80,
        .rows = 24,
    });
    defer manager.release(handle);

    var warmup: usize = 0;
    while (warmup < 40) : (warmup += 1) {
        if (try manager.tryNextEvent()) |evt| {
            manager.recycleEvent(evt.handle, evt.event) catch {};
        } else {
            time_utils.sleepMs(5);
        }
    }

    try manager.resize(handle, 91, 33);
    _ = try manager.write(handle, "stty size\r");

    var buffer = ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var iterations: usize = 0;
    while (iterations < 400) : (iterations += 1) {
        if (try manager.tryNextEvent()) |session_event| {
            const event = session_event.event;
            switch (event) {
                .data => |payload| {
                    try buffer.appendSlice(payload);
                },
                .exit => {},
            }
            manager.recycleEvent(session_event.handle, event) catch {};

            if (std.mem.indexOf(u8, buffer.items, "33 91") != null) {
                break;
            }
        } else {
            time_utils.sleepMs(5);
        }
    }

    try testing.expect(std.mem.indexOf(u8, buffer.items, "33 91") != null);
}

test "Session reports non-zero exit status on command failure" {
    if (builtin.os.tag == .windows) return;

    const testing = std.testing;
    const allocator = testing.allocator;

    var runtime = try AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    var metrics = Metrics{};

    var session = try Session.init(allocator, runtime, .{
        .command = &.{ "/bin/sh", "-c", "exit 3" },
        .columns = 80,
        .rows = 24,
    }, &metrics);
    defer session.deinit();

    try session.start();
    const channel = session.channel();

    var exit_status: ?types.ExitStatus = null;
    var iterations: usize = 0;
    while (exit_status == null and iterations < 400) : (iterations += 1) {
        if (try channel.tryReceive()) |event| {
            switch (event) {
                .data => |payload| allocator.free(payload),
                .exit => |status| exit_status = status,
            }
        } else {
            time_utils.sleepMs(5);
        }
    }

    try testing.expect(exit_status != null);
    switch (exit_status.?) {
        .exited => |code| try testing.expectEqual(@as(u8, 3), code),
        else => try testing.expect(false),
    }
}

test "Session round-trips written input through the PTY" {
    if (builtin.os.tag == .windows) return;

    const testing = std.testing;
    const allocator = testing.allocator;

    var runtime = try AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    var metrics = Metrics{};

    // Read a line of pasted input and echo it back wrapped in markers, then exit.
    var session = try Session.init(allocator, runtime, .{
        .command = &.{ "/bin/sh", "-c", "read line; printf '[%s]' \"$line\"" },
        .columns = 80,
        .rows = 24,
    }, &metrics);
    defer session.deinit();

    try session.start();
    const channel = session.channel();

    const written = try session.write("phantom-paste\n");
    try testing.expect(written > 0);

    var buffer = ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var iterations: usize = 0;
    while (std.mem.indexOf(u8, buffer.items, "[phantom-paste]") == null and iterations < 400) : (iterations += 1) {
        if (try channel.tryReceive()) |event| {
            switch (event) {
                .data => |payload| {
                    defer allocator.free(payload);
                    try buffer.appendSlice(payload);
                },
                .exit => {},
            }
        } else {
            time_utils.sleepMs(5);
        }
    }

    try testing.expect(std.mem.indexOf(u8, buffer.items, "[phantom-paste]") != null);
    try testing.expect(metrics.bytes_written.load(.acquire) >= written);
}

test "Session delivers large output without dropping the tail" {
    if (builtin.os.tag == .windows) return;

    const testing = std.testing;
    const allocator = testing.allocator;

    var runtime = try AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    var metrics = Metrics{};

    // Emit a long, deterministic stream. The final marker proves the tail
    // survived the channel round-trip.
    var session = try Session.init(allocator, runtime, .{
        .command = &.{ "/bin/sh", "-c", "i=1; while [ $i -le 500 ]; do echo line-$i; i=$((i+1)); done; echo DONE-MARKER" },
        .columns = 80,
        .rows = 24,
    }, &metrics);
    defer session.deinit();

    try session.start();
    const channel = session.channel();

    var buffer = ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var saw_exit = false;
    var iterations: usize = 0;
    while ((!saw_exit or std.mem.indexOf(u8, buffer.items, "DONE-MARKER") == null) and iterations < 2000) : (iterations += 1) {
        if (try channel.tryReceive()) |event| {
            switch (event) {
                .data => |payload| {
                    defer allocator.free(payload);
                    try buffer.appendSlice(payload);
                },
                .exit => saw_exit = true,
            }
        } else {
            time_utils.sleepMs(2);
        }
    }

    try testing.expect(std.mem.indexOf(u8, buffer.items, "line-1\r") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "line-500") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "DONE-MARKER") != null);
    try testing.expect(metrics.bytes_read.load(.acquire) > 0);
}

test "Session recycles data events without leaking payloads" {
    if (builtin.os.tag == .windows) return;

    const testing = std.testing;
    const allocator = testing.allocator;

    var runtime = try AsyncRuntime.init(allocator, .{ .worker_threads = 1 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    var metrics = Metrics{};

    var session = try Session.init(allocator, runtime, .{
        .command = &.{ "/bin/sh", "-c", "i=1; while [ $i -le 50 ]; do echo chunk-$i; i=$((i+1)); done" },
        .columns = 80,
        .rows = 24,
    }, &metrics);
    defer session.deinit();

    try session.start();
    const channel = session.channel();

    // Return every payload to the session via recycleEvent; the testing
    // allocator asserts nothing is leaked once the loop drains.
    var data_events: usize = 0;
    var saw_exit = false;
    var iterations: usize = 0;
    while (!saw_exit and iterations < 1000) : (iterations += 1) {
        if (try channel.tryReceive()) |event| {
            switch (event) {
                .data => data_events += 1,
                .exit => saw_exit = true,
            }
            session.recycleEvent(event);
        } else {
            time_utils.sleepMs(2);
        }
    }

    try testing.expect(saw_exit);
    try testing.expect(data_events > 0);
}
