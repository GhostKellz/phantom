# Widget Development Guide

This guide covers the current Phantom widget model built around `phantom.Widget`.

## Widget Shape

Every custom widget should:

1. embed a `widget: phantom.Widget` field
2. define a `WidgetVTable`
3. use `@fieldParentPtr("widget", widget)` inside vtable callbacks
4. clean up owned resources in `deinit`

## Core Interface

```zig
pub const Widget = struct {
    vtable: *const WidgetVTable,

    pub const WidgetVTable = struct {
        render: *const fn (self: *Widget, buffer: *phantom.Buffer, area: phantom.Rect) void,
        deinit: *const fn (self: *Widget) void,
        handleEvent: ?*const fn (self: *Widget, event: phantom.Event) bool = null,
        resize: ?*const fn (self: *Widget, new_area: phantom.Rect) void = null,
        getConstraints: ?*const fn (self: *Widget) phantom.SizeConstraints = null,
    };
};
```

## Minimal Example

```zig
const std = @import("std");
const phantom = @import("phantom");

pub const Counter = struct {
    widget: phantom.Widget,
    allocator: std.mem.Allocator,
    value: i32,

    const vtable = phantom.Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
    };

    pub fn init(allocator: std.mem.Allocator) !*Counter {
        const self = try allocator.create(Counter);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .value = 0,
        };
        return self;
    }

    fn render(widget: *phantom.Widget, buffer: *phantom.Buffer, area: phantom.Rect) void {
        const self: *Counter = @fieldParentPtr("widget", widget);
        var buf: [32]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "Count: {d}", .{self.value}) catch return;
        buffer.writeText(area.x, area.y, text, phantom.Style.default());
    }

    fn handleEvent(widget: *phantom.Widget, event: phantom.Event) bool {
        const self: *Counter = @fieldParentPtr("widget", widget);
        _ = self;
        _ = event;
        return false;
    }

    fn deinit(widget: *phantom.Widget) void {
        const self: *Counter = @fieldParentPtr("widget", widget);
        self.allocator.destroy(self);
    }
};
```

## Constraints

If your widget has meaningful minimum or preferred dimensions, implement `getConstraints` and return `phantom.SizeConstraints`.

Helpers:

```zig
phantom.SizeConstraints.unconstrained()
phantom.SizeConstraints.fixed(width, height)
phantom.SizeConstraints.minimum(width, height)
phantom.SizeConstraints.preferred(width, height)
```

## Best Practices

- keep rendering inside the provided `area`
- avoid leaking allocations from render-time formatting
- only implement optional callbacks you actually need
- favor simple widget state over deep inheritance-style layering
- use `phantom.layout.engine` to compose complex layouts instead of baking layout logic into widgets

## Recommended Path

For most application code, it is easier to compose existing widgets first and only write custom widgets when the built-in set no longer fits.
