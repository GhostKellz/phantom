# Transitions

Phantom's animation system now includes dedicated transition tooling for animating layout changes, widget entrance/exit effects, and bespoke motion on any property backed by `AnimationValue`.

## Core pieces

- **`TransitionSpec`** – describes the timing, easing curve, and phase (entering/updating/exiting) of a transition.
- **`TransitionTrack`** – pairs a start/end value for a property such as opacity, position, size, or rectangle.
- **`Transition`** – runtime controller that advances one or more tracks using a timeline-driven `Animation`.
- **`TransitionManager`** – keeps active transitions updated each frame and handles their lifetime.
- **`Transitions` helpers** – convenience builders for common effects like fades, slides, and rectangle morphs.

```zig
const anim = phantom.animation;

var manager = anim.TransitionManager.init(allocator);
defer manager.deinit();

const spec = anim.TransitionSpec{
    .duration_ms = 200,
    .phase = .entering,
    .curve = .ease_out,
    .auto_remove = false,
};

const transition = try anim.Transitions.rectMorph(&manager,
    Rect.init(0, 0, 40, 0),
    Rect.init(0, 0, 40, 10),
    spec,
);

// Drive the timeline each frame (App does this automatically)
manager.update();
if (transition.currentRect()) |rect| {
    // Use `rect` to render your widget at an interpolated size
}
```

## App integration

`App` wires layout transitions in automatically when `enable_transitions` is true (the default). Vertical layouts animate new widgets expanding into place and existing widgets morphing between sizes. Tweak behaviour via `AppConfig`:

```zig
const app = try phantom.App.init(allocator, .{
    .enable_transitions = true,
    .transition_duration_ms = 180,
    .transition_delay_ms = 20,
    .transition_curve = phantom.animation.TransitionCurve.ease_in_out,
});
```

When you remove a widget with `App.removeWidget`, any pending transition is cleaned up automatically.

## Custom listeners

Attach callbacks to a transition to react when it starts, finishes, or is cancelled:

```zig
const listener: phantom.animation.TransitionListener = struct {
    fn onEvent(t: *phantom.animation.Transition, event: phantom.animation.TransitionEvent, ctx: ?*anyopaque) void {
        _ = ctx;
        switch (event) {
            .started => |phase| std.log.info("transition started: {s}", .{@tagName(phase)}),
            .finished => |phase| std.log.info("transition finished: {s}", .{@tagName(phase)}),
            .cancelled => std.log.info("transition cancelled", .{}),
        }
    }
}.onEvent;

try transition.on(listener, null);
```

## Tips

- Use `.auto_remove = false` on `TransitionSpec` when you need to inspect the final value after completion. Call `TransitionManager.release(id)` once you're done.
- Need a one-off easing for a track? Pass a bespoke `Easing` when constructing the `TransitionTrack` rather than relying on the `TransitionSpec` curve.
- Combine multiple tracks in a single transition (for example, fade + slide) by calling `transition.addTrack` before `transition.start()`.
