//! Animation system for Phantom TUI
const std = @import("std");
const ArrayList = std.array_list.Managed;
const geometry = @import("geometry.zig");
const style = @import("style.zig");

const Position = geometry.Position;
const Size = geometry.Size;
const Rect = geometry.Rect;
const Style = style.Style;
const Color = style.Color;

pub const TimelineId = u64;
pub const TransitionId = u64;
pub const TransitionPhase = enum { entering, updating, exiting };

pub const TransitionEvent = union(enum) {
    started: TransitionPhase,
    finished: TransitionPhase,
    cancelled,
};

pub const TransitionCurve = enum {
    linear,
    ease,
    ease_in,
    ease_out,
    ease_in_out,
    custom,

    pub fn toEasing(self: TransitionCurve, fallback: Easing) Easing {
        return switch (self) {
            .linear => .linear,
            .ease => .ease_in_out,
            .ease_in => .ease_in,
            .ease_out => .ease_out,
            .ease_in_out => .ease_in_out,
            .custom => fallback,
        };
    }
};

pub const TransitionState = enum {
    idle,
    running,
    completed,
    cancelled,
};

pub const TransitionKind = enum {
    opacity,
    position,
    size,
    rect,
    scale,
    float,
    custom,
};

pub const TimelineDirection = enum {
    normal,
    reverse,
    alternate,
};

pub const TransitionSpec = struct {
    duration_ms: u64 = 180,
    delay_ms: u64 = 0,
    curve: TransitionCurve = .ease,
    direction: TimelineDirection = .normal,
    phase: TransitionPhase = .updating,
    repeat_count: u32 = 1,
    auto_remove: bool = true,
};

pub const TransitionTrack = struct {
    id: u32,
    kind: TransitionKind,
    easing: Easing,
    start_value: AnimationValue,
    end_value: AnimationValue,
    current_value: AnimationValue,

    pub fn init(id: u32, kind: TransitionKind, start_value: AnimationValue, end_value: AnimationValue, easing: Easing) TransitionTrack {
        return TransitionTrack{
            .id = id,
            .kind = kind,
            .easing = easing,
            .start_value = start_value,
            .end_value = end_value,
            .current_value = start_value,
        };
    }
};

pub const Transition = struct {
    allocator: std.mem.Allocator,
    id: TransitionId,
    timeline_id: ?TimelineId = null,
    spec: TransitionSpec,
    phase: TransitionPhase,
    state: TransitionState = .idle,
    progress: f32 = 0.0,
    driver: Animation,
    tracks: ArrayList(TransitionTrack),
    listeners: ArrayList(ListenerEntry),

    const ListenerEntry = struct {
        callback: *const fn (transition: *Transition, event: TransitionEvent, context: ?*anyopaque) void,
        context: ?*anyopaque,
    };

    pub fn init(allocator: std.mem.Allocator, id: TransitionId, spec: TransitionSpec) !Transition {
        if (spec.duration_ms == 0) {
            return error.InvalidDuration;
        }

        var driver = Animation.init(allocator, spec.duration_ms);
        try driver.addKeyframe(Keyframe.init(0.0, AnimationValue{ .float = 0.0 }));
        try driver.addKeyframe(Keyframe.withEasing(1.0, AnimationValue{ .float = 1.0 }, spec.curve.toEasing(.linear)));
        driver.setDelay(spec.delay_ms);
        driver.setRepeatCount(spec.repeat_count);
        driver.setFillMode(.forwards);
        driver.setDirection(switch (spec.direction) {
            .normal => .forward,
            .reverse => .reverse,
            .alternate => .alternate,
        });

        return Transition{
            .allocator = allocator,
            .id = id,
            .spec = spec,
            .phase = spec.phase,
            .driver = driver,
            .tracks = ArrayList(TransitionTrack).init(allocator),
            .listeners = ArrayList(ListenerEntry).init(allocator),
        };
    }

    pub fn deinit(self: *Transition) void {
        self.tracks.deinit();
        self.listeners.deinit();
        self.driver.deinit();
    }

    pub fn addTrack(self: *Transition, track: TransitionTrack) !void {
        try self.tracks.append(track);
    }

    pub fn start(self: *Transition) void {
        if (self.state == .running) return;
        self.driver.start();
        self.state = .running;
        self.progress = 0.0;
        self.notify(.{ .started = self.phase });
    }

    pub fn cancel(self: *Transition) void {
        if (self.state == .cancelled or self.state == .completed) return;
        self.state = .cancelled;
        self.driver.stop();
        self.notify(.cancelled);
    }

    pub fn reset(self: *Transition) void {
        self.driver.reset();
        self.state = .idle;
        self.progress = 0.0;

        for (self.tracks.items) |*track| {
            track.current_value = track.start_value;
        }
    }

    pub fn update(self: *Transition) bool {
        if (self.state != .running) return false;

        const value = self.driver.update();
        const progress = switch (value) {
            .float => |f| f,
            else => self.progress,
        };

        if (progress == self.progress and !self.driver.isRunning()) {
            self.state = if (self.driver.isCompleted()) .completed else self.state;
            if (self.state == .completed) {
                self.notify(.{ .finished = self.phase });
            }
            return false;
        }

        self.progress = @max(0.0, @min(1.0, progress));

        var changed = false;
        for (self.tracks.items) |*track| {
            const eased = track.easing.apply(self.progress);
            const next_value = track.start_value.lerp(track.end_value, eased);
            if (!animationValueEqual(track.current_value, next_value)) {
                track.current_value = next_value;
                changed = true;
            }
        }

        if (self.driver.isCompleted()) {
            self.state = .completed;
            self.notify(.{ .finished = self.phase });
        }

        return changed;
    }

    pub fn isActive(self: *const Transition) bool {
        return self.state == .running;
    }

    pub fn currentValue(self: *const Transition, track_id: u32) ?AnimationValue {
        for (self.tracks.items) |track| {
            if (track.id == track_id) return track.current_value;
        }
        return null;
    }

    pub fn currentRect(self: *const Transition) ?Rect {
        for (self.tracks.items) |track| {
            if (track.kind == .rect) {
                return switch (track.current_value) {
                    .rect => |rect| rect,
                    else => null,
                };
            }
        }
        return null;
    }

    pub fn progressValue(self: *const Transition) f32 {
        return self.progress;
    }

    pub fn on(
        self: *Transition,
        listener: *const fn (transition: *Transition, event: TransitionEvent, context: ?*anyopaque) void,
        context: ?*anyopaque,
    ) !void {
        try self.listeners.append(.{ .callback = listener, .context = context });
    }

    fn notify(self: *Transition, event: TransitionEvent) void {
        for (self.listeners.items) |entry| {
            entry.callback(self, event, entry.context);
        }
    }
};

pub const TransitionListener = *const fn (transition: *Transition, event: TransitionEvent, context: ?*anyopaque) void;

fn animationValueEqual(a: AnimationValue, b: AnimationValue) bool {
    return switch (a) {
        .position => |apos| switch (b) {
            .position => |bpos| apos.x == bpos.x and apos.y == bpos.y,
            else => false,
        },
        .size => |asz| switch (b) {
            .size => |bsz| asz.width == bsz.width and asz.height == bsz.height,
            else => false,
        },
        .rect => |arect| switch (b) {
            .rect => |brect| arect.x == brect.x and arect.y == brect.y and arect.width == brect.width and arect.height == brect.height,
            else => false,
        },
        .float => |af| switch (b) {
            .float => |bf| std.math.approxEqAbs(f32, af, bf, 0.0001),
            else => false,
        },
        .color => |acolor| switch (b) {
            .color => |bcolor| std.meta.eql(acolor, bcolor),
            else => false,
        },
        .style => |astyle| switch (b) {
            .style => |bstyle| styleEqual(astyle, bstyle),
            else => false,
        },
        .int => |ai| switch (b) {
            .int => |bi| ai == bi,
            else => false,
        },
    };
}

fn styleEqual(a: Style, b: Style) bool {
    return a.eq(b);
}

pub const TransitionManager = struct {
    allocator: std.mem.Allocator,
    transitions: std.AutoHashMap(TransitionId, *Transition),
    next_transition_id: TransitionId = 1,
    next_timeline_id: TimelineId = 1,

    pub fn init(allocator: std.mem.Allocator) TransitionManager {
        return TransitionManager{
            .allocator = allocator,
            .transitions = std.AutoHashMap(TransitionId, *Transition).init(allocator),
        };
    }

    pub fn deinit(self: *TransitionManager) void {
        var iterator = self.transitions.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.transitions.deinit();
    }

    pub fn create(self: *TransitionManager, spec: TransitionSpec) !*Transition {
        const id = self.next_transition_id;
        self.next_transition_id += 1;

        const transition = try self.allocator.create(Transition);
        transition.* = try Transition.init(self.allocator, id, spec);
        try self.transitions.put(id, transition);
        return transition;
    }

    pub fn get(self: *TransitionManager, id: TransitionId) ?*Transition {
        if (self.transitions.get(id)) |transition| return transition;
        return null;
    }

    pub fn update(self: *TransitionManager) void {
        // Iterate and remove completed/cancelled transitions
        var it = self.transitions.iterator();
        var to_remove = ArrayList(TransitionId).init(self.allocator);
        defer to_remove.deinit();

        while (it.next()) |entry| {
            const id = entry.key_ptr.*;
            const transition = entry.value_ptr.*;
            const changed = transition.update();
            _ = changed;

            if ((transition.state == .completed or transition.state == .cancelled) and transition.spec.auto_remove) {
                transition.deinit();
                self.allocator.destroy(transition);
                to_remove.append(id) catch {}; // Best effort
            }
        }

        for (to_remove.items) |id| {
            _ = self.transitions.remove(id);
        }
    }

    pub fn hasActive(self: *const TransitionManager) bool {
        var iterator = self.transitions.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.*.isActive()) return true;
        }
        return false;
    }

    pub fn release(self: *TransitionManager, id: TransitionId) void {
        if (self.transitions.fetchRemove(id)) |removed| {
            removed.value.deinit();
            self.allocator.destroy(removed.value);
        }
    }

    pub fn beginTimeline(self: *TransitionManager) TimelineId {
        const id = self.next_timeline_id;
        self.next_timeline_id += 1;
        return id;
    }

    pub fn attachToTimeline(self: *TransitionManager, timeline_id: TimelineId, transition: *Transition) void {
        _ = self;
        transition.timeline_id = timeline_id;
    }

    pub fn cancelTimeline(self: *TransitionManager, timeline_id: TimelineId) void {
        var iterator = self.transitions.iterator();
        while (iterator.next()) |entry| {
            const transition = entry.value_ptr.*;
            if (transition.timeline_id != null and transition.timeline_id.? == timeline_id) {
                transition.cancel();
            }
        }
    }
};

pub const Transitions = struct {
    pub fn fade(manager: *TransitionManager, from: f32, to: f32, spec: TransitionSpec) !*Transition {
        const transition = try manager.create(spec);
        try transition.addTrack(TransitionTrack.init(0, .opacity, AnimationValue{ .float = from }, AnimationValue{ .float = to }, spec.curve.toEasing(.ease_in_out)));
        transition.start();
        return transition;
    }

    pub fn rectMorph(manager: *TransitionManager, from: Rect, to: Rect, spec: TransitionSpec) !*Transition {
        const transition = try manager.create(spec);
        try transition.addTrack(TransitionTrack.init(0, .rect, AnimationValue{ .rect = from }, AnimationValue{ .rect = to }, spec.curve.toEasing(.ease_in_out)));
        transition.start();
        return transition;
    }

    pub fn slide(manager: *TransitionManager, from: Position, to: Position, spec: TransitionSpec) !*Transition {
        const transition = try manager.create(spec);
        try transition.addTrack(TransitionTrack.init(0, .position, AnimationValue{ .position = from }, AnimationValue{ .position = to }, spec.curve.toEasing(.ease_out)));
        transition.start();
        return transition;
    }
};

/// Easing functions for animations
pub const Easing = enum {
    linear,
    ease_in,
    ease_out,
    ease_in_out,
    ease_in_quad,
    ease_out_quad,
    ease_in_out_quad,
    ease_in_cubic,
    ease_out_cubic,
    ease_in_out_cubic,
    bounce,
    elastic,

    pub fn apply(self: Easing, t: f32) f32 {
        const clamped_t = @max(0.0, @min(1.0, t));

        return switch (self) {
            .linear => clamped_t,
            .ease_in => clamped_t * clamped_t,
            .ease_out => 1.0 - (1.0 - clamped_t) * (1.0 - clamped_t),
            .ease_in_out => blk: {
                if (clamped_t < 0.5) {
                    break :blk 2.0 * clamped_t * clamped_t;
                } else {
                    break :blk 1.0 - 2.0 * (1.0 - clamped_t) * (1.0 - clamped_t);
                }
            },
            .ease_in_quad => clamped_t * clamped_t,
            .ease_out_quad => 1.0 - (1.0 - clamped_t) * (1.0 - clamped_t),
            .ease_in_out_quad => blk: {
                if (clamped_t < 0.5) {
                    break :blk 2.0 * clamped_t * clamped_t;
                } else {
                    break :blk 1.0 - 2.0 * (1.0 - clamped_t) * (1.0 - clamped_t);
                }
            },
            .ease_in_cubic => clamped_t * clamped_t * clamped_t,
            .ease_out_cubic => 1.0 - (1.0 - clamped_t) * (1.0 - clamped_t) * (1.0 - clamped_t),
            .ease_in_out_cubic => blk: {
                if (clamped_t < 0.5) {
                    break :blk 4.0 * clamped_t * clamped_t * clamped_t;
                } else {
                    const adjusted = 2.0 * clamped_t - 2.0;
                    break :blk 1.0 + adjusted * adjusted * adjusted / 2.0;
                }
            },
            .bounce => blk: {
                const n1 = 7.5625;
                const d1 = 2.75;

                if (clamped_t < 1.0 / d1) {
                    break :blk n1 * clamped_t * clamped_t;
                } else if (clamped_t < 2.0 / d1) {
                    const adjusted = clamped_t - 1.5 / d1;
                    break :blk n1 * adjusted * adjusted + 0.75;
                } else if (clamped_t < 2.5 / d1) {
                    const adjusted = clamped_t - 2.25 / d1;
                    break :blk n1 * adjusted * adjusted + 0.9375;
                } else {
                    const adjusted = clamped_t - 2.625 / d1;
                    break :blk n1 * adjusted * adjusted + 0.984375;
                }
            },
            .elastic => blk: {
                const c4 = (2.0 * std.math.pi) / 3.0;

                if (clamped_t == 0.0) {
                    break :blk 0.0;
                } else if (clamped_t == 1.0) {
                    break :blk 1.0;
                } else {
                    const pow = std.math.pow(f32, 2.0, -10.0 * clamped_t);
                    const sin = std.math.sin((clamped_t * 10.0 - 0.75) * c4);
                    break :blk pow * sin + 1.0;
                }
            },
        };
    }
};

/// Animation value types
pub const AnimationValue = union(enum) {
    position: Position,
    size: Size,
    rect: Rect,
    float: f32,
    color: Color,
    style: Style,
    int: i32,

    pub fn lerp(self: AnimationValue, other: AnimationValue, t: f32) AnimationValue {
        return switch (self) {
            .position => |pos| AnimationValue{
                .position = Position.init(@as(u16, @intFromFloat(@as(f32, @floatFromInt(pos.x)) * (1.0 - t) + @as(f32, @floatFromInt(other.position.x)) * t)), @as(u16, @intFromFloat(@as(f32, @floatFromInt(pos.y)) * (1.0 - t) + @as(f32, @floatFromInt(other.position.y)) * t))),
            },
            .size => |size| AnimationValue{
                .size = Size.init(@as(u16, @intFromFloat(@as(f32, @floatFromInt(size.width)) * (1.0 - t) + @as(f32, @floatFromInt(other.size.width)) * t)), @as(u16, @intFromFloat(@as(f32, @floatFromInt(size.height)) * (1.0 - t) + @as(f32, @floatFromInt(other.size.height)) * t))),
            },
            .rect => |rect| AnimationValue{
                .rect = Rect.init(@as(u16, @intFromFloat(@as(f32, @floatFromInt(rect.x)) * (1.0 - t) + @as(f32, @floatFromInt(other.rect.x)) * t)), @as(u16, @intFromFloat(@as(f32, @floatFromInt(rect.y)) * (1.0 - t) + @as(f32, @floatFromInt(other.rect.y)) * t)), @as(u16, @intFromFloat(@as(f32, @floatFromInt(rect.width)) * (1.0 - t) + @as(f32, @floatFromInt(other.rect.width)) * t)), @as(u16, @intFromFloat(@as(f32, @floatFromInt(rect.height)) * (1.0 - t) + @as(f32, @floatFromInt(other.rect.height)) * t))),
            },
            .float => |f| AnimationValue{ .float = f * (1.0 - t) + other.float * t },
            .color => |_| other, // Color interpolation would be complex, just snap for now
            .style => |_| other, // Style interpolation would be complex, just snap for now
            .int => |i| AnimationValue{ .int = @as(i32, @intFromFloat(@as(f32, @floatFromInt(i)) * (1.0 - t) + @as(f32, @floatFromInt(other.int)) * t)) },
        };
    }
};

/// Animation keyframe
pub const Keyframe = struct {
    time: f32, // 0.0 to 1.0
    value: AnimationValue,
    easing: Easing = .linear,

    pub fn init(time: f32, value: AnimationValue) Keyframe {
        return Keyframe{
            .time = @max(0.0, @min(1.0, time)),
            .value = value,
        };
    }

    pub fn withEasing(time: f32, value: AnimationValue, easing: Easing) Keyframe {
        return Keyframe{
            .time = @max(0.0, @min(1.0, time)),
            .value = value,
            .easing = easing,
        };
    }
};

/// Animation completion callback
pub const OnCompleteCallback = *const fn (animation: *Animation) void;

/// Animation direction
pub const AnimationDirection = enum {
    forward,
    reverse,
    alternate,
    alternate_reverse,
};

/// Animation fill mode
pub const AnimationFillMode = enum {
    none,
    forwards,
    backwards,
    both,
};

/// Animation state
pub const AnimationState = enum {
    idle,
    running,
    paused,
    completed,
};

/// Animation instance
pub const Animation = struct {
    allocator: std.mem.Allocator,

    // Keyframes
    keyframes: ArrayList(Keyframe),

    // Timing
    duration_ms: u64,
    delay_ms: u64 = 0,
    repeat_count: u32 = 1, // 0 = infinite
    direction: AnimationDirection = .forward,
    fill_mode: AnimationFillMode = .none,

    // State
    timer: std.time.Timer,
    state: AnimationState = .idle,
    current_time: f32 = 0.0,
    current_iteration: u32 = 0,
    start_time_ns: u64 = 0,

    // Callbacks
    on_complete: ?OnCompleteCallback = null,

    pub fn init(allocator: std.mem.Allocator, duration_ms: u64) Animation {
        return Animation{
            .allocator = allocator,
            .keyframes = ArrayList(Keyframe).init(allocator),
            .duration_ms = duration_ms,
            .timer = std.time.Timer.start() catch unreachable,
        };
    }

    pub fn deinit(self: *Animation) void {
        self.keyframes.deinit();
    }

    pub fn addKeyframe(self: *Animation, keyframe: Keyframe) !void {
        try self.keyframes.append(keyframe);

        // Sort keyframes by time
        std.sort.block(Keyframe, self.keyframes.items, {}, struct {
            fn lessThan(context: void, a: Keyframe, b: Keyframe) bool {
                _ = context;
                return a.time < b.time;
            }
        }.lessThan);
    }

    pub fn setDelay(self: *Animation, delay_ms: u64) void {
        self.delay_ms = delay_ms;
    }

    pub fn setRepeatCount(self: *Animation, count: u32) void {
        self.repeat_count = count;
    }

    pub fn setDirection(self: *Animation, direction: AnimationDirection) void {
        self.direction = direction;
    }

    pub fn setFillMode(self: *Animation, fill_mode: AnimationFillMode) void {
        self.fill_mode = fill_mode;
    }

    pub fn setOnComplete(self: *Animation, callback: OnCompleteCallback) void {
        self.on_complete = callback;
    }

    pub fn start(self: *Animation) void {
        self.state = .running;
        self.current_time = 0.0;
        self.current_iteration = 0;
        self.timer.reset();
        self.start_time_ns = 0;
    }

    pub fn pause(self: *Animation) void {
        if (self.state == .running) {
            self.state = .paused;
        }
    }

    pub fn resumeAnimation(self: *Animation) void {
        if (self.state == .paused) {
            self.state = .running;
        }
    }

    pub fn stop(self: *Animation) void {
        self.state = .idle;
        self.current_time = 0.0;
        self.current_iteration = 0;
    }

    pub fn reset(self: *Animation) void {
        self.stop();
    }

    pub fn update(self: *Animation) AnimationValue {
        if (self.state != .running) {
            return self.getCurrentValue();
        }

        const elapsed_ns = self.timer.read();
        const elapsed = elapsed_ns / std.time.ns_per_ms;

        // Check if we're still in delay period
        if (elapsed < self.delay_ms) {
            return self.getCurrentValue();
        }

        // Calculate animation progress
        const animation_elapsed = elapsed - self.delay_ms;
        const progress = @as(f32, @floatFromInt(animation_elapsed)) / @as(f32, @floatFromInt(self.duration_ms));

        // Check if animation is complete
        if (progress >= 1.0) {
            self.current_iteration += 1;

            // Check if we should repeat
            if (self.repeat_count == 0 or self.current_iteration < self.repeat_count) {
                // Reset for next iteration
                self.timer.reset();
                self.start_time_ns = 0;
                self.current_time = 0.0;
            } else {
                // Animation complete
                self.state = .completed;
                self.current_time = 1.0;

                if (self.on_complete) |callback| {
                    callback(self);
                }
            }
        } else {
            self.current_time = progress;
        }

        return self.getCurrentValue();
    }

    pub fn getCurrentValue(self: *Animation) AnimationValue {
        if (self.keyframes.items.len == 0) {
            return AnimationValue{ .float = 0.0 };
        }

        // Apply direction
        var effective_time = self.current_time;
        switch (self.direction) {
            .forward => {},
            .reverse => effective_time = 1.0 - effective_time,
            .alternate => {
                if (self.current_iteration % 2 == 1) {
                    effective_time = 1.0 - effective_time;
                }
            },
            .alternate_reverse => {
                if (self.current_iteration % 2 == 0) {
                    effective_time = 1.0 - effective_time;
                }
            },
        }

        // Apply fill mode
        if (self.state == .idle) {
            switch (self.fill_mode) {
                .none => return AnimationValue{ .float = 0.0 },
                .backwards, .both => effective_time = 0.0,
                .forwards => return AnimationValue{ .float = 0.0 },
            }
        } else if (self.state == .completed) {
            switch (self.fill_mode) {
                .none => return AnimationValue{ .float = 0.0 },
                .forwards, .both => effective_time = 1.0,
                .backwards => return AnimationValue{ .float = 0.0 },
            }
        }

        // Find the appropriate keyframes to interpolate between
        var prev_keyframe: ?Keyframe = null;
        var next_keyframe: ?Keyframe = null;

        for (self.keyframes.items) |keyframe| {
            if (keyframe.time <= effective_time) {
                prev_keyframe = keyframe;
            }
            if (keyframe.time >= effective_time and next_keyframe == null) {
                next_keyframe = keyframe;
                break;
            }
        }

        // Handle edge cases
        if (prev_keyframe == null and next_keyframe == null) {
            return AnimationValue{ .float = 0.0 };
        } else if (prev_keyframe == null) {
            return next_keyframe.?.value;
        } else if (next_keyframe == null) {
            return prev_keyframe.?.value;
        }

        // Interpolate between keyframes
        const prev = prev_keyframe.?;
        const next = next_keyframe.?;

        if (prev.time == next.time) {
            return next.value;
        }

        const segment_progress = (effective_time - prev.time) / (next.time - prev.time);
        const eased_progress = prev.easing.apply(segment_progress);

        return prev.value.lerp(next.value, eased_progress);
    }

    pub fn isRunning(self: *const Animation) bool {
        return self.state == .running;
    }

    pub fn isCompleted(self: *const Animation) bool {
        return self.state == .completed;
    }
};

/// Animation manager for handling multiple animations
pub const AnimationManager = struct {
    allocator: std.mem.Allocator,
    animations: ArrayList(*Animation),

    pub fn init(allocator: std.mem.Allocator) AnimationManager {
        return AnimationManager{
            .allocator = allocator,
            .animations = ArrayList(*Animation).init(allocator),
        };
    }

    pub fn deinit(self: *AnimationManager) void {
        self.animations.deinit();
    }

    pub fn addAnimation(self: *AnimationManager, animation: *Animation) !void {
        try self.animations.append(animation);
    }

    pub fn removeAnimation(self: *AnimationManager, animation: *Animation) void {
        for (self.animations.items, 0..) |anim, i| {
            if (anim == animation) {
                _ = self.animations.swapRemove(i);
                return;
            }
        }
    }

    pub fn update(self: *AnimationManager) void {
        for (self.animations.items) |animation| {
            _ = animation.update();
        }

        // Remove completed animations
        var i: usize = 0;
        while (i < self.animations.items.len) {
            if (self.animations.items[i].isCompleted()) {
                _ = self.animations.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn clear(self: *AnimationManager) void {
        self.animations.clearAndFree();
    }

    pub fn getAnimationCount(self: *const AnimationManager) usize {
        return self.animations.items.len;
    }
};

/// Common animation builders
pub const AnimationBuilder = struct {
    pub fn fadeIn(allocator: std.mem.Allocator, duration_ms: u64) !*Animation {
        var animation = try allocator.create(Animation);
        animation.* = Animation.init(allocator, duration_ms);

        try animation.addKeyframe(Keyframe.init(0.0, AnimationValue{ .float = 0.0 }));
        try animation.addKeyframe(Keyframe.withEasing(1.0, AnimationValue{ .float = 1.0 }, .ease_out));

        return animation;
    }

    pub fn fadeOut(allocator: std.mem.Allocator, duration_ms: u64) !*Animation {
        var animation = try allocator.create(Animation);
        animation.* = Animation.init(allocator, duration_ms);

        try animation.addKeyframe(Keyframe.init(0.0, AnimationValue{ .float = 1.0 }));
        try animation.addKeyframe(Keyframe.withEasing(1.0, AnimationValue{ .float = 0.0 }, .ease_in));

        return animation;
    }

    pub fn slideIn(allocator: std.mem.Allocator, duration_ms: u64, from: Position, to: Position) !*Animation {
        var animation = try allocator.create(Animation);
        animation.* = Animation.init(allocator, duration_ms);

        try animation.addKeyframe(Keyframe.init(0.0, AnimationValue{ .position = from }));
        try animation.addKeyframe(Keyframe.withEasing(1.0, AnimationValue{ .position = to }, .ease_out));

        return animation;
    }

    pub fn bounce(allocator: std.mem.Allocator, duration_ms: u64, start_pos: Position, end_pos: Position) !*Animation {
        var animation = try allocator.create(Animation);
        animation.* = Animation.init(allocator, duration_ms);

        try animation.addKeyframe(Keyframe.init(0.0, AnimationValue{ .position = start_pos }));
        try animation.addKeyframe(Keyframe.withEasing(1.0, AnimationValue{ .position = end_pos }, .bounce));

        return animation;
    }

    pub fn scale(allocator: std.mem.Allocator, duration_ms: u64, from_size: Size, to_size: Size) !*Animation {
        var animation = try allocator.create(Animation);
        animation.* = Animation.init(allocator, duration_ms);

        try animation.addKeyframe(Keyframe.init(0.0, AnimationValue{ .size = from_size }));
        try animation.addKeyframe(Keyframe.withEasing(1.0, AnimationValue{ .size = to_size }, .ease_in_out));

        return animation;
    }
};

test "Easing functions" {
    try std.testing.expect(Easing.linear.apply(0.0) == 0.0);
    try std.testing.expect(Easing.linear.apply(0.5) == 0.5);
    try std.testing.expect(Easing.linear.apply(1.0) == 1.0);

    try std.testing.expect(Easing.ease_in.apply(0.0) == 0.0);
    try std.testing.expect(Easing.ease_in.apply(1.0) == 1.0);
}

test "Animation value interpolation" {
    const pos1 = AnimationValue{ .position = Position.init(0, 0) };
    const pos2 = AnimationValue{ .position = Position.init(10, 10) };

    const interpolated = pos1.lerp(pos2, 0.5);
    try std.testing.expect(interpolated.position.x == 5);
    try std.testing.expect(interpolated.position.y == 5);
}

test "Animation keyframes" {
    const allocator = std.testing.allocator;

    var animation = Animation.init(allocator, 1000);
    defer animation.deinit();

    try animation.addKeyframe(Keyframe.init(0.0, AnimationValue{ .float = 0.0 }));
    try animation.addKeyframe(Keyframe.init(1.0, AnimationValue{ .float = 1.0 }));

    try std.testing.expect(animation.keyframes.items.len == 2);
}

test "Transition rect morph" {
    const allocator = std.testing.allocator;
    var manager = TransitionManager.init(allocator);
    defer manager.deinit();

    const spec = TransitionSpec{
        .duration_ms = 30,
        .curve = .ease_out,
        .phase = .entering,
        .auto_remove = false,
    };

    const from = Rect.init(0, 0, 10, 0);
    const to = Rect.init(0, 0, 10, 10);

    const transition = try Transitions.rectMorph(&manager, from, to, spec);

    std.time.sleep(50 * std.time.ns_per_ms);
    manager.update();

    const mid_rect = transition.currentRect().?;
    try std.testing.expect(mid_rect.height > from.height);
    try std.testing.expect(mid_rect.height <= to.height);

    std.time.sleep(80 * std.time.ns_per_ms);
    manager.update();

    try std.testing.expect(transition.state == .completed);
    const final_rect = transition.currentRect().?;
    try std.testing.expectEqual(to.height, final_rect.height);

    manager.release(transition.id);
}

test "Transition manager auto remove" {
    const allocator = std.testing.allocator;
    var manager = TransitionManager.init(allocator);
    defer manager.deinit();

    const transition = try Transitions.fade(&manager, 0.0, 1.0, TransitionSpec{ .duration_ms = 10, .auto_remove = true });
    const id = transition.id;
    std.time.sleep(50 * std.time.ns_per_ms);
    manager.update();
    try std.testing.expect(manager.get(id) == null);
}

/// Smooth scrolling helper
pub const SmoothScroll = struct {
    current_value: f32,
    target_value: f32,
    start_value: f32,
    duration_ms: u64,
    elapsed_ms: u64,
    easing: Easing,
    active: bool,

    pub fn init(initial_value: f32) SmoothScroll {
        return SmoothScroll{
            .current_value = initial_value,
            .target_value = initial_value,
            .start_value = initial_value,
            .duration_ms = 0,
            .elapsed_ms = 0,
            .easing = .ease_out,
            .active = false,
        };
    }

    pub fn scrollTo(self: *SmoothScroll, target: f32, duration_ms: u64) void {
        self.start_value = self.current_value;
        self.target_value = target;
        self.duration_ms = duration_ms;
        self.elapsed_ms = 0;
        self.active = true;
    }

    pub fn update(self: *SmoothScroll, delta_ms: u64) void {
        if (!self.active) return;

        self.elapsed_ms += delta_ms;
        if (self.elapsed_ms >= self.duration_ms) {
            self.current_value = self.target_value;
            self.active = false;
            return;
        }

        const t = @as(f32, @floatFromInt(self.elapsed_ms)) / @as(f32, @floatFromInt(self.duration_ms));
        const eased = self.easing.apply(t);
        self.current_value = self.start_value + (self.target_value - self.start_value) * eased;
    }

    pub fn getValue(self: *const SmoothScroll) f32 {
        return self.current_value;
    }

    pub fn isActive(self: *const SmoothScroll) bool {
        return self.active;
    }
};

/// Fade effect helper
pub const Fade = struct {
    opacity: f32,
    target_opacity: f32,
    start_opacity: f32,
    duration_ms: u64,
    elapsed_ms: u64,
    easing: Easing,
    active: bool,

    pub fn init() Fade {
        return Fade{
            .opacity = 1.0,
            .target_opacity = 1.0,
            .start_opacity = 1.0,
            .duration_ms = 0,
            .elapsed_ms = 0,
            .easing = .ease_in_out,
            .active = false,
        };
    }

    pub fn fadeIn(self: *Fade, duration_ms: u64) void {
        self.start_opacity = self.opacity;
        self.target_opacity = 1.0;
        self.duration_ms = duration_ms;
        self.elapsed_ms = 0;
        self.active = true;
    }

    pub fn fadeOut(self: *Fade, duration_ms: u64) void {
        self.start_opacity = self.opacity;
        self.target_opacity = 0.0;
        self.duration_ms = duration_ms;
        self.elapsed_ms = 0;
        self.active = true;
    }

    pub fn fadeTo(self: *Fade, target: f32, duration_ms: u64) void {
        self.start_opacity = self.opacity;
        self.target_opacity = @max(0.0, @min(1.0, target));
        self.duration_ms = duration_ms;
        self.elapsed_ms = 0;
        self.active = true;
    }

    pub fn update(self: *Fade, delta_ms: u64) void {
        if (!self.active) return;

        self.elapsed_ms += delta_ms;
        if (self.elapsed_ms >= self.duration_ms) {
            self.opacity = self.target_opacity;
            self.active = false;
            return;
        }

        const t = @as(f32, @floatFromInt(self.elapsed_ms)) / @as(f32, @floatFromInt(self.duration_ms));
        const eased = self.easing.apply(t);
        self.opacity = self.start_opacity + (self.target_opacity - self.start_opacity) * eased;
    }

    pub fn getOpacity(self: *const Fade) f32 {
        return self.opacity;
    }

    pub fn isActive(self: *const Fade) bool {
        return self.active;
    }

    pub fn setEasing(self: *Fade, easing: Easing) void {
        self.easing = easing;
    }
};

test "SmoothScroll" {
    var scroll = SmoothScroll.init(0.0);
    try std.testing.expect(scroll.getValue() == 0.0);
    try std.testing.expect(!scroll.isActive());

    scroll.scrollTo(100.0, 1000);
    try std.testing.expect(scroll.isActive());

    scroll.update(500); // Half way
    try std.testing.expect(scroll.getValue() > 0.0);
    try std.testing.expect(scroll.getValue() < 100.0);

    scroll.update(500); // Complete
    try std.testing.expect(scroll.getValue() == 100.0);
    try std.testing.expect(!scroll.isActive());
}

test "Fade" {
    var fade = Fade.init();
    try std.testing.expect(fade.getOpacity() == 1.0);
    try std.testing.expect(!fade.isActive());

    fade.fadeOut(1000);
    try std.testing.expect(fade.isActive());

    fade.update(500); // Half way
    try std.testing.expect(fade.getOpacity() > 0.0);
    try std.testing.expect(fade.getOpacity() < 1.0);

    fade.update(500); // Complete
    try std.testing.expect(fade.getOpacity() == 0.0);
    try std.testing.expect(!fade.isActive());
}

test "Animation manager" {
    const allocator = std.testing.allocator;

    var manager = AnimationManager.init(allocator);
    defer manager.deinit();

    var animation = Animation.init(allocator, 1000);
    defer animation.deinit();

    try manager.addAnimation(&animation);
    try std.testing.expect(manager.getAnimationCount() == 1);

    manager.removeAnimation(&animation);
    try std.testing.expect(manager.getAnimationCount() == 0);
}
