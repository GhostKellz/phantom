# Phantom Widget Development Guide

**Version**: 0.6.1
**Date**: 2025-10-25

This guide explains how to create custom widgets using Phantom's unified Widget interface.

---

## Table of Contents

1. [Widget Interface Overview](#widget-interface-overview)
2. [Creating a Basic Widget](#creating-a-basic-widget)
3. [Widget VTable Methods](#widget-vtable-methods)
4. [Size Constraints](#size-constraints)
5. [Event Handling](#event-handling)
6. [Container Widgets](#container-widgets)
7. [Best Practices](#best-practices)
8. [Complete Examples](#complete-examples)

---

## Widget Interface Overview

All Phantom widgets implement a common interface defined in `src/widget.zig`:

```zig
pub const Widget = struct {
    vtable: *const WidgetVTable,

    pub const WidgetVTable = struct {
        /// Render this widget to the buffer (REQUIRED)
        render: *const fn (self: *Widget, buffer: anytype, area: Rect) void,

        /// Handle lifecycle cleanup (REQUIRED)
        deinit: *const fn (self: *Widget) void,

        /// Handle input events - return true if consumed (OPTIONAL)
        handleEvent: ?*const fn (self: *Widget, event: Event) bool = null,

        /// Handle resize events (OPTIONAL)
        resize: ?*const fn (self: *Widget, new_area: Rect) void = null,

        /// Get size constraints for layout (OPTIONAL)
        getConstraints: ?*const fn (self: *Widget) SizeConstraints = null,
    };
};
```

### Key Principles

1. **Embed Widget** - All widgets embed a `widget: Widget` field
2. **Use VTable** - Implement a const vtable with your widget's methods
3. **@fieldParentPtr** - Use this to get your widget from the Widget pointer
4. **Optional Methods** - Only implement what you need

---

## Creating a Basic Widget

### Step 1: Define Your Widget Struct

```zig
const std = @import("std");
const phantom = @import("phantom");
const Widget = phantom.Widget;
const Event = phantom.Event;
const Rect = phantom.Rect;
const Style = phantom.Style;

pub const Counter = struct {
    widget: Widget,              // Embedded Widget field (REQUIRED)
    allocator: std.mem.Allocator,
    count: i32,
    style: Style,

    // ... continue below
};
```

### Step 2: Create the VTable

```zig
const vtable = Widget.WidgetVTable{
    .render = render,
    .deinit = deinit,
    .handleEvent = handleEvent,  // Optional
    // resize and getConstraints can be omitted if not needed
};
```

### Step 3: Implement init()

```zig
pub fn init(allocator: std.mem.Allocator) !*Counter {
    const self = try allocator.create(Counter);
    self.* = .{
        .widget = .{ .vtable = &vtable },  // Initialize embedded Widget
        .allocator = allocator,
        .count = 0,
        .style = Style.default(),
    };
    return self;
}
```

### Step 4: Implement VTable Methods

```zig
fn render(widget: *Widget, buffer: anytype, area: Rect) void {
    const self = @fieldParentPtr(Counter, "widget", widget);

    const text = std.fmt.allocPrint(
        self.allocator,
        "Count: {d}",
        .{self.count},
    ) catch return;
    defer self.allocator.free(text);

    buffer.writeText(area.x, area.y, text, self.style);
}

fn deinit(widget: *Widget) void {
    const self = @fieldParentPtr(Counter, "widget", widget);
    self.allocator.destroy(self);
}

fn handleEvent(widget: *Widget, event: Event) bool {
    const self = @fieldParentPtr(Counter, "widget", widget);

    switch (event) {
        .key => |key| {
            switch (key) {
                .char => |c| {
                    if (c == '+') {
                        self.count += 1;
                        return true;  // Event consumed
                    } else if (c == '-') {
                        self.count -= 1;
                        return true;
                    }
                },
                else => {},
            }
        },
        else => {},
    }
    return false;  // Event not handled
}
```

### Step 5: Add Widget-Specific Public Methods

```zig
/// Widget-specific public API (not part of vtable)
pub fn increment(self: *Counter) void {
    self.count += 1;
}

pub fn decrement(self: *Counter) void {
    self.count -= 1;
}

pub fn reset(self: *Counter) void {
    self.count = 0;
}

pub fn getValue(self: *Counter) i32 {
    return self.count;
}
```

---

## Widget VTable Methods

### render() - REQUIRED

Renders the widget to the buffer in the given area.

```zig
fn render(widget: *Widget, buffer: anytype, area: Rect) void {
    const self = @fieldParentPtr(MyWidget, "widget", widget);
    // Draw your widget using buffer.writeText, buffer.setCell, etc.
}
```

**Important**:
- Always respect the `area` boundaries
- Don't draw outside the provided area
- Use `buffer.writeText()` for text rendering
- Use `self.allocator` for temporary allocations (remember to free!)

### deinit() - REQUIRED

Cleans up widget resources.

```zig
fn deinit(widget: *Widget) void {
    const self = @fieldParentPtr(MyWidget, "widget", widget);

    // Free any owned resources
    self.items.deinit(self.allocator);
    self.text.deinit(self.allocator);

    // Destroy the widget itself
    self.allocator.destroy(self);
}
```

**Important**:
- Free all allocated memory
- Don't forget to `destroy(self)` at the end
- Use the same allocator that created the widget

### handleEvent() - OPTIONAL

Handles input events (keyboard, mouse, etc.).

```zig
fn handleEvent(widget: *Widget, event: Event) bool {
    const self = @fieldParentPtr(MyWidget, "widget", widget);

    switch (event) {
        .key => |key| {
            switch (key) {
                .up => {
                    self.moveUp();
                    return true;  // Event consumed
                },
                .down => {
                    self.moveDown();
                    return true;
                },
                else => {},
            }
        },
        .mouse => |mouse| {
            // Handle mouse events
        },
        else => {},
    }

    return false;  // Event not handled
}
```

**Return Value**:
- `true` - Event was handled, stop propagation
- `false` - Event not handled, continue to other widgets

### resize() - OPTIONAL

Notifies widget of area changes.

```zig
fn resize(widget: *Widget, new_area: Rect) void {
    const self = @fieldParentPtr(MyWidget, "widget", widget);

    // Update internal layout based on new area
    self.viewport_width = new_area.width;
    self.viewport_height = new_area.height;

    // Recalculate any cached positions
    self.calculateLayout(new_area);
}
```

### getConstraints() - OPTIONAL

Provides size constraints for layout engines.

```zig
fn getConstraints(widget: *Widget) SizeConstraints {
    const self = @fieldParentPtr(MyWidget, "widget", widget);

    return SizeConstraints{
        .min_width = 20,
        .min_height = 5,
        .preferred_width = 40,
        .preferred_height = 10,
    };
}
```

---

## Size Constraints

`SizeConstraints` help layout engines size your widget appropriately.

```zig
pub const SizeConstraints = struct {
    min_width: u16 = 0,
    min_height: u16 = 0,
    max_width: ?u16 = null,
    max_height: ?u16 = null,
    preferred_width: ?u16 = null,
    preferred_height: ?u16 = null,
};
```

### Helper Constructors

```zig
// Unconstrained (default)
const unconstrained = SizeConstraints.unconstrained();

// Fixed size
const fixed = SizeConstraints.fixed(80, 24);

// Minimum size
const minimum = SizeConstraints.minimum(20, 5);

// Preferred size
const preferred = SizeConstraints.preferred(40, 10);
```

---

## Event Handling

### Event Types

```zig
pub const Event = union(enum) {
    key: Key,           // Keyboard input
    mouse: MouseEvent,  // Mouse input
    system: SystemEvent, // Resize, etc.
    tick: void,         // Periodic tick
};
```

### Keyboard Events

```zig
fn handleEvent(widget: *Widget, event: Event) bool {
    const self = @fieldParentPtr(MyWidget, "widget", widget);

    switch (event) {
        .key => |key| {
            switch (key) {
                .up, .down, .left, .right => |arrow| {
                    // Handle arrow keys
                    return true;
                },
                .char => |c| {
                    if (c == 'q') {
                        // Handle 'q' key
                        return true;
                    }
                },
                .enter => {
                    // Handle enter
                    return true;
                },
                .escape => {
                    // Handle escape
                    return true;
                },
                else => {},
            }
        },
        else => {},
    }
    return false;
}
```

### Mouse Events

```zig
fn handleEvent(widget: *Widget, event: Event) bool {
    const self = @fieldParentPtr(MyWidget, "widget", widget);

    switch (event) {
        .mouse => |mouse| {
            // Check if mouse is within widget area
            if (self.isInBounds(mouse.x, mouse.y)) {
                switch (mouse.kind) {
                    .press => {
                        // Handle mouse click
                        return true;
                    },
                    .scroll_up, .scroll_down => {
                        // Handle scroll
                        return true;
                    },
                    else => {},
                }
            }
        },
        else => {},
    }
    return false;
}
```

---

## Container Widgets

Container widgets manage child widgets. Phantom v0.6.1 includes:

### Container - Flexible Layout

```zig
const container = try phantom.widgets.Container.init(allocator, .vertical);
defer container.widget.deinit();

// Add children
try container.addChild(&child1.widget);
try container.addChild(&child2.widget);
try container.addChild(&child3.widget);

// Configure layout
container.setGap(1);      // Space between children
container.setPadding(2);  // Padding around content
```

**Layout Modes**:
- `.vertical` - Stack children top to bottom
- `.horizontal` - Stack children left to right
- `.manual` - Manual positioning

### Stack - Z-Index Layers

```zig
const stack = try phantom.widgets.Stack.init(allocator);
defer stack.widget.deinit();

// Add background layer
try stack.addChild(&background.widget, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });

// Add floating dialog (modal - blocks events)
try stack.addModalChild(&dialog.widget, Rect{ .x = 20, .y = 8, .width = 40, .height = 10 });

// Bring dialog to front
stack.bringToFront(&dialog.widget);
```

### Tabs - Tabbed Interface

```zig
const tabs = try phantom.widgets.Tabs.init(allocator);
defer tabs.widget.deinit();

// Add tabs
try tabs.addTab("Editor", &editor.widget);
try tabs.addTab("Terminal", &terminal.widget);
try tabs.addFixedTab("Help", &help.widget);  // Non-closeable

// Navigate
tabs.nextTab();
tabs.prevTab();
tabs.setActiveTab(0);

// Close active tab
tabs.closeActiveTab();
```

---

## Best Practices

### 1. Memory Management

✅ **DO**:
- Always use the same allocator for allocation and deallocation
- Free all resources in `deinit()`
- Use `defer` for cleanup in `render()` temporary allocations

❌ **DON'T**:
- Leak memory
- Mix allocators
- Forget to `destroy(self)` in deinit

### 2. Rendering

✅ **DO**:
- Respect the `area` parameter
- Use efficient rendering (minimize allocations)
- Cache layout calculations when possible

❌ **DON'T**:
- Draw outside the provided area
- Allocate without freeing in `render()`
- Recalculate layout on every render (cache it!)

### 3. Event Handling

✅ **DO**:
- Return `true` only when event is actually handled
- Check bounds for mouse events
- Implement only if your widget needs events

❌ **DON'T**:
- Always return `true` (blocks other widgets)
- Handle events outside your widget area
- Implement if not needed (leave vtable field as null)

### 4. Widget Composition

✅ **DO**:
- Use Container/Stack/Tabs for complex layouts
- Store children as `*Widget` for polymorphism
- Delegate events to children appropriately

❌ **DON'T**:
- Hardcode widget types in containers
- Forget to deinit child widgets
- Block events from reaching children

---

## Complete Examples

### Example 1: Simple Label Widget

```zig
const std = @import("std");
const phantom = @import("phantom");
const Widget = phantom.Widget;
const Rect = phantom.Rect;
const Style = phantom.Style;

pub const Label = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    text: []const u8,
    style: Style,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator, text: []const u8) !*Label {
        const self = try allocator.create(Label);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .text = try allocator.dupe(u8, text),
            .style = Style.default(),
        };
        return self;
    }

    pub fn setText(self: *Label, text: []const u8) !void {
        self.allocator.free(self.text);
        self.text = try self.allocator.dupe(u8, text);
    }

    fn render(widget: *Widget, buffer: anytype, area: Rect) void {
        const self = @fieldParentPtr(Label, "widget", widget);
        buffer.writeText(area.x, area.y, self.text, self.style);
    }

    fn deinit(widget: *Widget) void {
        const self = @fieldParentPtr(Label, "widget", widget);
        self.allocator.free(self.text);
        self.allocator.destroy(self);
    }
};
```

### Example 2: Interactive Button Widget

```zig
pub const Button = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    label: []const u8,
    on_click: ?*const fn () void,
    is_hovered: bool,
    is_pressed: bool,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
    };

    pub fn init(allocator: std.mem.Allocator, label: []const u8) !*Button {
        const self = try allocator.create(Button);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .label = try allocator.dupe(u8, label),
            .on_click = null,
            .is_hovered = false,
            .is_pressed = false,
        };
        return self;
    }

    pub fn onClick(self: *Button, callback: *const fn () void) void {
        self.on_click = callback;
    }

    fn render(widget: *Widget, buffer: anytype, area: Rect) void {
        const self = @fieldParentPtr(Button, "widget", widget);

        const style = if (self.is_pressed)
            Style.default().withBg(phantom.Color.bright_blue).withFg(phantom.Color.white)
        else if (self.is_hovered)
            Style.default().withBg(phantom.Color.blue).withFg(phantom.Color.white)
        else
            Style.default().withBg(phantom.Color.black).withFg(phantom.Color.white);

        const btn_text = std.fmt.allocPrint(
            self.allocator,
            "[ {s} ]",
            .{self.label},
        ) catch return;
        defer self.allocator.free(btn_text);

        buffer.writeText(area.x, area.y, btn_text, style);
    }

    fn handleEvent(widget: *Widget, event: phantom.Event) bool {
        const self = @fieldParentPtr(Button, "widget", widget);

        switch (event) {
            .key => |key| {
                if (key == .enter or key == .char and key.char == ' ') {
                    if (self.on_click) |callback| {
                        callback();
                    }
                    return true;
                }
            },
            else => {},
        }
        return false;
    }

    fn deinit(widget: *Widget) void {
        const self = @fieldParentPtr(Button, "widget", widget);
        self.allocator.free(self.label);
        self.allocator.destroy(self);
    }
};
```

### Example 3: Container with Children

```zig
const container = try phantom.widgets.Container.init(allocator, .vertical);
defer container.widget.deinit();

// Create children
const label = try Label.init(allocator, "Welcome to Phantom!");
const button = try Button.init(allocator, "Click Me");

// Add to container
try container.addChild(&label.widget);
try container.addChild(&button.widget);

// Configure layout
container.setGap(1);
container.setPadding(2);

// Render (container will layout and render children)
container.widget.render(buffer, area);
```

---

## Migration from v0.6.0

If you have existing widgets, update them to use the new Widget interface:

### Before (v0.6.0)

```zig
pub const MyWidget = struct {
    // No embedded widget field

    pub fn render(self: *MyWidget, buffer: anytype, area: Rect) void {
        // ...
    }
};
```

### After (v0.6.1)

```zig
pub const MyWidget = struct {
    widget: Widget,  // Add this

    const vtable = Widget.WidgetVTable{  // Add this
        .render = render,
        .deinit = deinit,
    };

    pub fn init(allocator: Allocator) !*MyWidget {
        const self = try allocator.create(MyWidget);
        self.* = .{
            .widget = .{ .vtable = &vtable },  // Add this
            // ... other fields
        };
        return self;
    }

    fn render(widget: *Widget, buffer: anytype, area: Rect) void {
        const self = @fieldParentPtr(MyWidget, "widget", widget);  // Add this
        // ... existing render code
    }

    fn deinit(widget: *Widget) void {
        const self = @fieldParentPtr(MyWidget, "widget", widget);
        // ... cleanup
        self.allocator.destroy(self);
    }
};
```

---

## Getting Help

- **Examples**: Check `examples/v0_6_demo.zig` for working examples
- **Source**: Browse `src/widgets/` for reference implementations
- **Issues**: https://github.com/ghostkellz/phantom/issues

---

Built with 👻 by the Phantom TUI Framework team
