# Widget API Audit - v0.7.2 Standardization

**Date**: 2025-11-04
**Goal**: Ensure all 41 widgets have consistent, ergonomic APIs

---

## API Standards

### 1. Initialization Pattern
**Standard**: All widgets use `Config` struct + `.init(allocator, config)` pattern

```zig
pub const MyWidgetConfig = struct {
    // Required fields
    title: []const u8,

    // Optional fields with defaults
    width: ?u16 = null,
    height: ?u16 = null,
    style: Style = Style.default(),

    pub fn default() MyWidgetConfig {
        return .{
            .title = "",
        };
    }
};

pub fn init(allocator: std.mem.Allocator, config: MyWidgetConfig) !*MyWidget {
    // Implementation
}
```

### 2. Builder Pattern (Complex Widgets)
**Standard**: Widgets with >5 config options or dynamic setup use builder pattern

```zig
pub const Builder = struct {
    allocator: std.mem.Allocator,
    config: MyWidgetConfig,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{
            .allocator = allocator,
            .config = MyWidgetConfig.default(),
        };
    }

    pub fn setTitle(self: *Builder, title: []const u8) *Builder {
        self.config.title = title;
        return self;
    }

    pub fn build(self: *Builder) !*MyWidget {
        return MyWidget.init(self.allocator, self.config);
    }
};
```

### 3. Error Handling
**Standard**: Custom error types per widget category

```zig
pub const Error = error{
    InvalidConfiguration,
    ItemNotFound,
    IndexOutOfBounds,
    RenderFailed,
} || std.mem.Allocator.Error;
```

### 4. Memory Management
**Standard**: All widgets implement proper cleanup

```zig
pub fn deinit(self: *MyWidget) void {
    // Free all owned memory
    self.items.deinit(self.allocator);
    self.allocator.destroy(self);
}
```

---

## Widget Audit Checklist

### Layout Widgets (6)

#### ✅ Container (`container.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Stack (`stack.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Tabs (`tabs.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ ScrollView (`scroll_view.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Flex (FlexRow/FlexColumn) (`flex.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Border (`border.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

---

### Input Widgets (5)

#### ✅ Input (`input.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ TextArea (`textarea.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Button (`button.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ ContextMenu (`context_menu.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Dialog (`dialog.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

---

### Display Widgets (7)

#### ✅ Text (`text.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ RichText (`rich_text.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ CodeBlock (`code_block.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ SyntaxHighlight (`syntax_highlight.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ StreamingText (`streaming_text.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Block (`block.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Notification (`notification.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

---

### Data Visualization Widgets (6)

#### ⚠️ BarChart (`bar_chart.zig`) - NEEDS BUILDER PATTERN
- [ ] Has Config struct?
- [ ] Uses builder pattern? **MISSING**
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ⚠️ Chart (`chart.zig`) - PARTIAL BUILDER (has setXAxis but not full builder)
- [ ] Has Config struct?
- [ ] Uses builder pattern? **INCOMPLETE**
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Gauge (`gauge.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Sparkline (`sparkline.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Calendar (`calendar.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ⚠️ Canvas (`canvas.zig`) - NEEDS BUILDER PATTERN
- [ ] Has Config struct?
- [ ] Uses builder pattern? **MISSING**
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

---

### List/Table Widgets (3)

#### ⚠️ List (`list.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ⚠️ ListView (`list_view.zig`) - NEEDS CONFIG STRUCT
- [x] Has Config struct? **MISSING - uses direct init**
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Table (`table.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

---

### Utility Widgets (6)

#### ✅ Spinner (`spinner.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ Progress (`progress.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ TaskMonitor (`task_monitor.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ ThemePicker (`theme_picker.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ SystemMonitor (`system_monitor.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ CommandBuilder (`command_builder.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

---

### Advanced/Specialized Widgets (8)

#### ✅ NetworkTopology (`network_topology.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ UniversalPackageBrowser (`universal_package_browser.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ AURDependencies (`aur_dependencies.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

#### ✅ BlockchainPackageBrowser (`blockchain_package_browser.zig`)
- [ ] Has Config struct?
- [ ] Uses builder pattern?
- [ ] Custom error types?
- [ ] Proper deinit?
- [ ] Tests exist?

---

## Priority Actions

### HIGH PRIORITY (Critical for v0.7.2)

1. **ListView** - Add Config struct
2. **Chart** - Complete builder pattern
3. **BarChart** - Add builder pattern
4. **Canvas** - Add builder pattern
5. **All widgets** - Add custom error types
6. **All widgets** - Verify deinit() works correctly

### MEDIUM PRIORITY

1. Review all specialized widgets (Network, Package browsers)
2. Add comprehensive unit tests for each widget
3. Document ownership rules in each widget file

### LOW PRIORITY

1. Add builder patterns to simple widgets (nice-to-have)
2. Refactor internal implementations for consistency

---

## Next Steps

1. ✅ Create this audit document
2. [ ] Fix HIGH PRIORITY widgets first (ListView, Chart, BarChart, Canvas)
3. [ ] Add custom error types to all widgets
4. [ ] Memory audit - verify all deinit() implementations
5. [ ] Create test suite template
6. [ ] Write unit tests for each widget
7. [ ] Update TODO.md as items complete

---

**Status**: 🔄 In Progress - Phase 1.3 of v0.7.2 roadmap
