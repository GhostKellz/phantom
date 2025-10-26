# Migration Guide: v0.6.0 → v0.6.1

**Date**: 2025-10-25
**Target**: Phantom v0.6.1

This guide helps you migrate from Phantom v0.6.0 to v0.6.1.

---

## Summary of Changes

v0.6.1 **completes the widget system** with:

✅ **No Breaking Changes** - All v0.6.0 code continues to work
✅ **New Features** - SizeConstraints, Container, Stack, Tabs widgets
✅ **Better Organization** - Widget interface moved to dedicated `widget.zig`
✅ **Improved Composition** - Easy to build complex widget trees

---

## What's New in v0.6.1

### 1. SizeConstraints System

Widgets can now declare size preferences for layout engines:

```zig
const phantom = @import("phantom");

// Use built-in helpers
const fixed = phantom.SizeConstraints.fixed(80, 24);
const minimum = phantom.SizeConstraints.minimum(20, 5);
const preferred = phantom.SizeConstraints.preferred(40, 10);

// In your widget
fn getConstraints(widget: *Widget) SizeConstraints {
    return SizeConstraints{
        .min_width = 20,
        .min_height = 5,
        .preferred_width = 40,
        .preferred_height = 10,
    };
}
```

### 2. Container Widget

Flexible layout container for automatic child positioning:

```zig
const container = try phantom.widgets.Container.init(allocator, .vertical);

// Add children
try container.addChild(&widget1.widget);
try container.addChild(&widget2.widget);
try container.addChild(&widget3.widget);

// Configure
container.setGap(1);
container.setPadding(2);
```

**Layout Modes**:
- `.vertical` - Stack top to bottom
- `.horizontal` - Stack left to right
- `.manual` - Manual positioning

### 3. Stack Widget

Z-index layering for overlays, modals, and floating windows:

```zig
const stack = try phantom.widgets.Stack.init(allocator);

// Add layers (rendered bottom to top)
try stack.addChild(&background.widget, bg_area);
try stack.addChild(&dialog.widget, dialog_area);

// Modal layer blocks events to layers below
try stack.addModalChild(&modal.widget, modal_area);

// Z-order manipulation
stack.bringToFront(&dialog.widget);
stack.sendToBack(&background.widget);
```

### 4. Tabs Widget

Tabbed interface for multi-document editing:

```zig
const tabs = try phantom.widgets.Tabs.init(allocator);

// Add tabs
try tabs.addTab("main.zig", &editor1.widget);
try tabs.addTab("lib.zig", &editor2.widget);
try tabs.addFixedTab("Help", &help.widget);  // Non-closeable

// Navigate
tabs.nextTab();  // Ctrl+Tab
tabs.prevTab();
tabs.closeActiveTab();  // Ctrl+W
```

---

## Code Changes Required

### None! 🎉

v0.6.1 is **100% backward compatible** with v0.6.0. All existing code continues to work.

The changes are **additions only**:
- Widget interface enhancement (optional `getConstraints`)
- New container widgets (opt-in)
- Better exports in `root.zig`

---

## Recommended Updates

While not required, we recommend these improvements:

### 1. Use New Imports (Cleaner)

**Before** (v0.6.0):
```zig
const Widget = @import("phantom").App.Widget;  // From app.zig
```

**After** (v0.6.1 - Recommended):
```zig
const Widget = @import("phantom").Widget;  // From widget.zig
const SizeConstraints = @import("phantom").SizeConstraints;
```

### 2. Add Size Constraints (Optional)

If your widget has size preferences, implement `getConstraints`:

```zig
const vtable = Widget.WidgetVTable{
    .render = render,
    .deinit = deinit,
    .handleEvent = handleEvent,
    .getConstraints = getConstraints,  // NEW (optional)
};

fn getConstraints(widget: *Widget) SizeConstraints {
    return SizeConstraints.minimum(20, 5);
}
```

### 3. Use Container Widgets (Where Appropriate)

**Before** (v0.6.0 - Manual Layout):
```zig
pub const MyUI = struct {
    widget1: *SomeWidget,
    widget2: *AnotherWidget,
    widget3: *ThirdWidget,

    pub fn render(self: *MyUI, buffer: anytype, area: Rect) !void {
        // Manual layout calculation
        const area1 = Rect{ .x = 0, .y = 0, .width = 80, .height = 8 };
        const area2 = Rect{ .x = 0, .y = 8, .width = 80, .height = 8 };
        const area3 = Rect{ .x = 0, .y = 16, .width = 80, .height = 8 };

        self.widget1.render(buffer, area1);
        self.widget2.render(buffer, area2);
        self.widget3.render(buffer, area3);
    }
};
```

**After** (v0.6.1 - Automatic Layout):
```zig
pub const MyUI = struct {
    widget: Widget,
    container: *phantom.widgets.Container,

    const vtable = Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
    };

    pub fn init(allocator: Allocator) !*MyUI {
        const container = try phantom.widgets.Container.init(allocator, .vertical);
        try container.addChild(&widget1.widget);
        try container.addChild(&widget2.widget);
        try container.addChild(&widget3.widget);
        container.setGap(0);

        const self = try allocator.create(MyUI);
        self.* = .{
            .widget = .{ .vtable = &vtable },
            .container = container,
        };
        return self;
    }

    fn render(widget: *Widget, buffer: anytype, area: Rect) void {
        const self = @fieldParentPtr(MyUI, "widget", widget);
        self.container.widget.render(buffer, area);
    }

    fn deinit(widget: *Widget) void {
        const self = @fieldParentPtr(MyUI, "widget", widget);
        self.container.widget.deinit();
        self.allocator.destroy(self);
    }
};
```

---

## New Capabilities

### 1. Polymorphic Widget Trees

```zig
// Before: Type-specific storage
pub const Editor = struct {
    completion_menu: ?*LSPCompletionMenu,
    hover_widget: ?*LSPHoverWidget,
    diagnostics: ?*DiagnosticsPanel,
    // ...
};

// After: Polymorphic storage
pub const Editor = struct {
    widget: Widget,
    lsp_widgets: std.ArrayList(*Widget),  // Any widget type!

    pub fn addLSPWidget(self: *Editor, widget: *Widget) !void {
        try self.lsp_widgets.append(widget);
    }

    pub fn renderLSPWidgets(self: *Editor, buffer: anytype, area: Rect) void {
        for (self.lsp_widgets.items) |child| {
            child.render(buffer, area);
        }
    }
};
```

### 2. Modal Dialogs with Stack

```zig
const editor_ui = try Stack.init(allocator);

// Main editor
try editor_ui.addChild(&editor.widget, full_screen);

// Show LSP completion (floating)
const completion_area = Rect{ .x = cursor_x, .y = cursor_y + 1, .width = 40, .height = 10 };
try editor_ui.addChild(&completion_menu.widget, completion_area);

// Show error dialog (modal - blocks editor input)
if (has_error) {
    const dialog_area = Rect{ .x = 20, .y = 10, .width = 40, .height = 8 };
    try editor_ui.addModalChild(&error_dialog.widget, dialog_area);
}
```

### 3. Tabbed Editors

```zig
const tabs = try phantom.widgets.Tabs.init(allocator);

// Open files as tabs
for (open_files) |file| {
    const editor = try TextEditor.loadFile(allocator, file.path);
    try tabs.addTab(file.name, &editor.widget);
}

// User can:
// - Ctrl+Tab to switch tabs
// - Ctrl+W to close tabs
tabs.nextTab();
tabs.closeActiveTab();
```

---

## Common Patterns

### Pattern 1: LSP Completion Menu

```zig
const stack = try Stack.init(allocator);

// Editor layer
try stack.addChild(&editor.widget, editor_area);

// Completion menu (shown when typing)
if (show_completion) {
    const menu_area = calculateMenuPosition(cursor_pos);
    try stack.addChild(&completion_menu.widget, menu_area);
}

// Hover docs (shown on hover)
if (show_hover) {
    const hover_area = calculateHoverPosition(hover_pos);
    try stack.addChild(&hover_widget.widget, hover_area);
}
```

### Pattern 2: Status Bar + Editor + Sidebar

```zig
const main_container = try Container.init(allocator, .vertical);

// Status bar at top (fixed height)
try main_container.addChild(&status_bar.widget);

// Content area (flexible)
const content = try Container.init(allocator, .horizontal);
try content.addChild(&sidebar.widget);   // Sidebar
try content.addChild(&editor.widget);    // Main editor
try main_container.addChild(&content.widget);

// Footer at bottom
try main_container.addChild(&footer.widget);
```

### Pattern 3: Multi-Panel Layout

```zig
const panels = try Container.init(allocator, .horizontal);
panels.setGap(1);

// Left panel (flex=1)
try panels.addChildWithFlex(&explorer.widget, 1);

// Middle panel (flex=3 - larger)
try panels.addChildWithFlex(&editor.widget, 3);

// Right panel (flex=1)
try panels.addChildWithFlex(&outline.widget, 1);
```

---

## Performance Notes

### Container Widget

- **Layout calculation**: O(n) where n = number of children
- **Cached**: Layout is recalculated only on resize or child changes
- **Efficient**: No allocations in render path (layout cached)

### Stack Widget

- **Event handling**: O(n) in reverse order (top to bottom)
- **Modal optimization**: Stops event propagation at modal layers
- **Rendering**: O(n) painters algorithm (bottom to top)

### Tabs Widget

- **Active tab**: Only the active tab is rendered
- **Memory**: All tab content kept in memory
- **Switching**: O(1) tab switching

---

## Testing Your Migration

### 1. Build Test

```bash
cd phantom
zig build

# Should compile without errors
```

### 2. Run v0.6.0 Demo

```bash
zig build run-v0_6_demo

# Should work exactly as before
```

### 3. Run New v0.6.1 Demo

```bash
zig build run  # Runs updated demo with new widgets

# Should show new container/stack/tabs features
```

### 4. Memory Leak Test

```bash
# Your tests should pass with GeneralPurposeAllocator
zig build test
```

---

## Troubleshooting

### Issue: Widget import not found

**Error**:
```
error: container 'phantom' has no member named 'Widget'
```

**Solution**:
Update your `build.zig.zon` to use v0.6.1:
```bash
zig fetch --save https://github.com/ghostkellz/phantom/archive/refs/tags/v0.6.1.tar.gz
```

### Issue: Container doesn't lay out children

**Problem**: Children not visible in Container

**Solution**: Make sure you're rendering the container widget:
```zig
// Wrong
container.addChild(&child.widget);
child.widget.render(buffer, area);  // Don't render children directly

// Correct
container.addChild(&child.widget);
container.widget.render(buffer, area);  // Container renders children
```

### Issue: Stack modal not blocking events

**Problem**: Events reach widgets behind modal

**Solution**: Use `addModalChild` instead of `addChild`:
```zig
// Wrong
try stack.addChild(&modal.widget, area);

// Correct
try stack.addModalChild(&modal.widget, area);
```

---

## Getting Help

- **Widget Guide**: `docs/widgets/WIDGET_GUIDE.md`
- **Examples**: `examples/v0_6_demo.zig`
- **API Reference**: `src/widget.zig`
- **Issues**: https://github.com/ghostkellz/phantom/issues

---

## What's Next

### v0.7.0 (Planned)

- Focus management system
- Accessibility support
- Advanced layout constraints
- Animation helpers for widgets
- Widget themes and styling presets

---

Built with 👻 by the Phantom TUI Framework team
