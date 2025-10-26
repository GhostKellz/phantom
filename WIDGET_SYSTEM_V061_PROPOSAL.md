# Phantom v0.6.1 - Widget System Enhancement Proposal

**Author**: Grim Editor Team
**Date**: 2025-10-25
**Target Version**: Phantom v0.6.1
**Priority**: High

---

## Executive Summary

Phantom v0.6.0 introduced excellent individual widgets (ListView, Border, Spinner, etc.) but lacks a **unified widget abstraction layer** for building complex, composable TUI applications. This proposal defines a minimal, ergonomic Widget interface that enables:

1. **Polymorphic widget trees** - Mix different widget types in containers
2. **Consistent lifecycle management** - Standard init/deinit/render/resize patterns
3. **Event delegation** - Bubble events through widget hierarchies
4. **Memory safety** - Clear ownership and cleanup semantics

---

## Current State (v0.6.0)

### What Works
- Individual widgets render correctly (ListView, Border, Spinner, RichText, etc.)
- Widgets accept `buffer: anytype` for flexibility
- App framework handles terminal, events, and main loop

### What's Missing
- **No base Widget type** - Can't store heterogeneous widgets in containers
- **No standard vtable pattern** - Each widget has different method signatures
- **No event handling interface** - Widgets can't intercept keyboard/mouse events
- **No parent-child relationship model** - Can't build widget trees

### Current Workaround
Users must manually manage each widget type separately, leading to:
```zig
// Hard to maintain - every widget needs separate handling
lsp_completion_menu: ?*LSPCompletionMenu,
lsp_hover_widget: ?*LSPHoverWidget,
diagnostics_panel: ?*DiagnosticsPanel,
status_bar: ?*StatusBar,

// Can't iterate or compose generically
```

---

## Proposed Solution: Minimal Widget Interface

### Core Types

```zig
// phantom/src/widget.zig

pub const Widget = struct {
    vtable: *const WidgetVTable,

    pub const WidgetVTable = struct {
        /// Render this widget to the buffer in the given area
        render: *const fn (self: *Widget, buffer: anytype, area: Rect) void,

        /// Handle lifecycle cleanup (called when widget is destroyed)
        deinit: *const fn (self: *Widget) void,

        /// Optional: Handle resize events
        resize: ?*const fn (self: *Widget, new_area: Rect) void = null,

        /// Optional: Handle input events (return true if consumed)
        handleEvent: ?*const fn (self: *Widget, event: Event) bool = null,

        /// Optional: Get minimum/preferred size constraints
        getConstraints: ?*const fn (self: *Widget) SizeConstraints = null,
    };
};

pub const SizeConstraints = struct {
    min_width: u16 = 0,
    min_height: u16 = 0,
    max_width: ?u16 = null,
    max_height: ?u16 = null,
    preferred_width: ?u16 = null,
    preferred_height: ?u16 = null,
};
```

### Widget Implementation Pattern

Each widget embeds a `Widget` field and implements the vtable:

```zig
// Example: ListView as a Widget
pub const ListView = struct {
    widget: Widget,  // <-- Embeddable base
    allocator: Allocator,
    items: ArrayList(ListViewItem),
    selected_index: usize,
    // ... other fields

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
    };

    pub fn init(allocator: Allocator) !*ListView {
        const self = try allocator.create(ListView);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .items = ArrayList(ListViewItem).init(allocator),
            .selected_index = 0,
        };
        return self;
    }

    fn render(widget: *Widget, buffer: anytype, area: Rect) void {
        const self = @fieldParentPtr(ListView, "widget", widget);
        // ... render implementation
    }

    fn deinit(widget: *Widget) void {
        const self = @fieldParentPtr(ListView, "widget", widget);
        self.items.deinit();
        self.allocator.destroy(self);
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self = @fieldParentPtr(ListView, "widget", widget);
        switch (event) {
            .key => |key| {
                if (key == .down) {
                    self.selectNext();
                    return true;
                }
            },
            else => {},
        }
        return false;
    }
};
```

---

## Required Changes to Phantom v0.6.0 Widgets

### 1. Add Widget Base Type

**File**: `phantom/src/widget.zig` (NEW)

```zig
const std = @import("std");
const Event = @import("event.zig").Event;
const Rect = @import("render/rect.zig").Rect;

pub const Widget = struct {
    vtable: *const WidgetVTable,

    pub const WidgetVTable = struct {
        render: *const fn (self: *Widget, buffer: anytype, area: Rect) void,
        deinit: *const fn (self: *Widget) void,
        resize: ?*const fn (self: *Widget, new_area: Rect) void = null,
        handleEvent: ?*const fn (self: *Widget, event: Event) bool = null,
        getConstraints: ?*const fn (self: *Widget) SizeConstraints = null,
    };
};

pub const SizeConstraints = struct {
    min_width: u16 = 0,
    min_height: u16 = 0,
    max_width: ?u16 = null,
    max_height: ?u16 = null,
    preferred_width: ?u16 = null,
    preferred_height: ?u16 = null,
};
```

### 2. Export Widget from Root

**File**: `phantom/src/root.zig`

```zig
// Add to exports
pub const Widget = @import("widget.zig").Widget;
pub const SizeConstraints = @import("widget.zig").SizeConstraints;
```

### 3. Update Existing Widgets

All existing widgets need to embed `Widget` and implement the vtable:

#### ListView (example)

**File**: `phantom/src/widgets/list_view.zig`

```zig
const Widget = @import("../widget.zig").Widget;

pub const ListView = struct {
    widget: Widget,  // ADD THIS
    allocator: std.mem.Allocator,
    // ... existing fields

    const vtable = Widget.WidgetVTable{  // ADD THIS
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
    };

    pub fn init(allocator: std.mem.Allocator) !*ListView {
        const self = try allocator.create(ListView);
        self.* = .{
            .widget = .{ .vtable = &vtable },  // ADD THIS
            .allocator = allocator,
            // ... existing initialization
        };
        return self;
    }

    // CHANGE: fn render -> matches vtable signature
    fn render(widget: *Widget, buffer: anytype, area: Rect) void {
        const self = @fieldParentPtr(ListView, "widget", widget);
        // ... existing render code
    }

    // CHANGE: fn deinit -> matches vtable signature
    fn deinit(widget: *Widget) void {
        const self = @fieldParentPtr(ListView, "widget", widget);
        // ... existing deinit code
    }

    // ADD: Event handling
    fn handleEvent(widget: *Widget, event: Event) bool {
        const self = @fieldParentPtr(ListView, "widget", widget);
        switch (event) {
            .key => |key| {
                switch (key) {
                    .down => { self.selectNext(); return true; },
                    .up => { self.selectPrev(); return true; },
                    else => {},
                }
            },
            else => {},
        }
        return false;
    }
};
```

#### Apply Same Pattern To:
- ✅ `Border` - Add widget field, vtable
- ✅ `Spinner` - Add widget field, vtable
- ✅ `RichText` - Add widget field, vtable
- ✅ `ScrollView` - Add widget field, vtable, handleEvent for scrolling
- ✅ `FlexRow`/`FlexColumn` - Add widget field, vtable, child event delegation

---

## Usage Example: Grim Editor

### Before (v0.6.0 - Impossible)
```zig
// Can't store different widget types together
var completion_menu: *LSPCompletionMenu = ...;
var hover_widget: *LSPHoverWidget = ...;
var diagnostics: *DiagnosticsPanel = ...;

// Must render each manually - no abstraction
completion_menu.render(buffer, area1);
hover_widget.render(buffer, area2);
diagnostics.render(buffer, area3);
```

### After (v0.6.1 - Clean)
```zig
pub const GrimEditorWidget = struct {
    widget: Widget,
    allocator: Allocator,
    lsp_widgets: ArrayList(*Widget),  // Polymorphic!

    pub fn init(allocator: Allocator) !*GrimEditorWidget {
        var self = try allocator.create(GrimEditorWidget);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .lsp_widgets = ArrayList(*Widget).init(allocator),
        };

        // Add widgets polymorphically
        const completion = try LSPCompletionMenu.init(allocator);
        try self.lsp_widgets.append(&completion.widget);

        const hover = try LSPHoverWidget.init(allocator);
        try self.lsp_widgets.append(&hover.widget);

        return self;
    }

    fn render(widget: *Widget, buffer: anytype, area: Rect) void {
        const self = @fieldParentPtr(GrimEditorWidget, "widget", widget);

        // Render all LSP widgets generically
        for (self.lsp_widgets.items) |child| {
            child.vtable.render(child, buffer, area);
        }
    }

    fn deinit(widget: *Widget) void {
        const self = @fieldParentPtr(GrimEditorWidget, "widget", widget);

        // Clean up all widgets generically
        for (self.lsp_widgets.items) |child| {
            child.vtable.deinit(child);
        }
        self.lsp_widgets.deinit();
        self.allocator.destroy(self);
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self = @fieldParentPtr(GrimEditorWidget, "widget", widget);

        // Delegate to children (reverse order for z-index)
        var i = self.lsp_widgets.items.len;
        while (i > 0) {
            i -= 1;
            const child = self.lsp_widgets.items[i];
            if (child.vtable.handleEvent) |handler| {
                if (handler(child, event)) {
                    return true;  // Event consumed
                }
            }
        }
        return false;  // Event not handled
    }
};
```

---

## Migration Path

### Phase 1: Add Core Types (Non-Breaking)
1. Add `phantom/src/widget.zig` with Widget base type
2. Export from `phantom/src/root.zig`
3. Document the pattern in `WIDGET_GUIDE.md`

### Phase 2: Update Existing Widgets (Breaking - Major Version)
1. Update all widgets in `phantom/src/widgets/` to embed `Widget`
2. Add vtables to each widget
3. Convert public methods to vtable callbacks where appropriate
4. Add event handlers for interactive widgets

### Phase 3: Add Container Widgets
1. Create `Container` widget for arbitrary child layouts
2. Create `Stack` widget for overlays (modal dialogs, popups)
3. Create `Tabs` widget for tabbed interfaces

---

## Benefits

### For Users
✅ **Composability** - Build complex UIs from simple widgets
✅ **Type Safety** - Compile-time widget tree validation
✅ **Memory Safety** - Clear ownership via vtable.deinit
✅ **Event Handling** - Natural keyboard/mouse delegation

### For Phantom
✅ **Ecosystem Growth** - Easier third-party widget development
✅ **API Consistency** - All widgets follow same pattern
✅ **Future-Proof** - Foundation for advanced features (focus management, accessibility)

---

## Open Questions

1. **Should Widget be opaque or expose vtable?**
   - Proposal: Expose vtable for transparency and debugging

2. **Should we support widget inheritance/composition?**
   - Proposal: Start with composition (embed Widget field) only

3. **How to handle widget-specific methods?**
   - Proposal: Keep widget-specific methods as public functions (e.g., `ListView.addItem`)
   - Vtable only for polymorphic operations (render, deinit, events)

4. **Should resize be mandatory or optional?**
   - Proposal: Optional - many widgets don't need resize logic

---

## Implementation Checklist

### Core Infrastructure
- [ ] Create `phantom/src/widget.zig`
- [ ] Add Widget exports to `phantom/src/root.zig`
- [ ] Add SizeConstraints type
- [ ] Document widget implementation pattern

### Update Existing Widgets
- [ ] ListView - Add widget field, vtable, handleEvent
- [ ] Border - Add widget field, vtable
- [ ] Spinner - Add widget field, vtable
- [ ] RichText - Add widget field, vtable
- [ ] ScrollView - Add widget field, vtable, handleEvent
- [ ] FlexRow/FlexColumn - Add widget field, vtable, child delegation
- [ ] Text - Add widget field, vtable
- [ ] Block - Add widget field, vtable
- [ ] Input - Add widget field, vtable, handleEvent
- [ ] TextArea - Add widget field, vtable, handleEvent
- [ ] Button - Add widget field, vtable, handleEvent

### New Container Widgets
- [ ] Container - Generic child container
- [ ] Stack - Z-index overlay system
- [ ] Tabs - Tabbed interface widget

### Documentation
- [ ] WIDGET_GUIDE.md - How to create custom widgets
- [ ] MIGRATION_V061.md - Upgrade guide for v0.6.0 users
- [ ] Update examples to use Widget interface

### Testing
- [ ] Widget vtable dispatch tests
- [ ] Event delegation tests
- [ ] Memory leak tests (deinit called correctly)
- [ ] Polymorphic widget tree tests

---

## Example: Complete Widget Implementation

```zig
// phantom/src/widgets/example_counter.zig
const std = @import("std");
const phantom = @import("../root.zig");
const Widget = phantom.Widget;
const Event = phantom.Event;
const Rect = phantom.Rect;
const Style = phantom.Style;

pub const Counter = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    count: i32,
    style: Style,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
    };

    pub fn init(allocator: std.mem.Allocator) !*Counter {
        const self = try allocator.create(Counter);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .count = 0,
            .style = Style.default(),
        };
        return self;
    }

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
                if (key == .char and key.char == '+') {
                    self.count += 1;
                    return true;
                } else if (key == .char and key.char == '-') {
                    self.count -= 1;
                    return true;
                }
            },
            else => {},
        }
        return false;
    }

    // Widget-specific public API
    pub fn increment(self: *Counter) void {
        self.count += 1;
    }

    pub fn decrement(self: *Counter) void {
        self.count -= 1;
    }

    pub fn reset(self: *Counter) void {
        self.count = 0;
    }
};
```

---

## References

- Phantom v0.6.0 widgets: `phantom/src/widgets/`
- Similar systems: SwiftUI, React, Elm, ImGui
- Zig patterns: vtable dispatch, `@fieldParentPtr`

---

## Contact

For questions or feedback on this proposal:
- GitHub Issues: https://github.com/ghostty-org/phantom
- Grim Editor Team: Using this pattern in production

---

**Status**: Draft - Awaiting Phantom maintainer feedback
**Last Updated**: 2025-10-25
