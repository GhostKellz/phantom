# 👻 Phantom TUI Framework v0.4.0 - Complete Integration Guide

**Version**: 0.4.0 - **PRODUCTION READY** 🎉
**Zig Compatibility**: 0.16+
**Status**: Complete vxfw-equivalent framework ready for Ghostshell migration

This guide helps you integrate Phantom TUI v0.4.0 into your Zig projects. **Phantom v0.4.0 is a MAJOR MILESTONE** - a complete, production-ready TUI framework with comprehensive widget library, advanced Unicode support, and all features needed for enterprise development.

## 🎯 What's New in v0.4.0

### **🏗️ Complete VXFW Framework (Vaxis Equivalent)**
- Complete widget framework with Surface/SubSurface rendering
- Full event system with advanced input handling
- Production-quality Unicode processing via gcode library
- Advanced fuzzy search capabilities for theme selection

### **🧱 Enterprise Widget Library (20+ Widgets)**
- All layout widgets: FlexRow, FlexColumn, Center, Padding, SizedBox, Border, SplitView
- All display widgets: TextView, CodeView, RichText with syntax highlighting
- All interaction widgets: TextField, ListView, ScrollView with virtualization
- **NEW**: ThemePicker with fuzzy search and highlighting

### **⚡ Production Systems**
- Advanced event loop with frame rate targeting
- Thread-safe event queue with priority handling
- Multi-protocol image support (Sixel, Kitty graphics, iTerm2)
- Cross-platform system integration (clipboard, notifications, themes)

## 🚀 Quick Start

### 1. Add Phantom v0.4.0 as a Dependency

#### Method 1: Using `zig fetch` (Recommended)
```bash
zig fetch --save https://github.com/ghostkellz/phantom/archive/v0.4.0.tar.gz
```

#### Method 2: Manual `build.zig.zon` Setup
```zig
.{
    .name = "your-project",
    .version = "0.1.0",
    .minimum_zig_version = "0.16.0-dev.164+bc7955306",
    .dependencies = .{
        .phantom = .{
            .url = "https://github.com/ghostkellz/phantom/archive/v0.4.0.tar.gz",
            .hash = "phantom-0.4.0-[HASH_PROVIDED_BY_ZIG_FETCH]",
        },
    },
}
```

### 2. Configure Your `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get phantom dependency with gcode Unicode support
    const phantom_dep = b.dependency("phantom", .{
        .target = target,
        .optimize = optimize,
        .preset = "full", // Include all features
    });
    const phantom_mod = phantom_dep.module("phantom");

    // Your executable
    const exe = b.addExecutable(.{
        .name = "your-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add phantom module
    exe.root_module.addImport("phantom", phantom_mod);
    exe.linkLibC(); // Required for system integration

    b.installArtifact(exe);
}
```

### 3. Basic VXFW Integration Example

```zig
const std = @import("std");
const phantom = @import("phantom");
const vxfw = phantom.vxfw;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Phantom v0.4.0 with advanced features
    var app = try phantom.App.init(allocator, phantom.AppConfig{
        .title = "Phantom v0.4.0 App",
        .tick_rate_ms = 16, // 60 FPS for smooth interactions
        .mouse_enabled = true,
        .unicode_enabled = true, // Enable gcode Unicode processing
    });
    defer app.deinit();

    // Create root widget using vxfw framework
    var root_widget = try createRootWidget(allocator);
    defer root_widget.deinit();

    app.setRootWidget(root_widget.widget());

    // Run the application
    try app.run();
}

const RootWidget = struct {
    allocator: std.mem.Allocator,
    theme_picker: phantom.widgets.ThemePicker,
    selected_theme: ?phantom.vxfw.FuzzySearch.ThemeInfo = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        var theme_picker = try phantom.widgets.ThemePicker.init(allocator);

        // Add some themes
        try theme_picker.addTheme(.{
            .name = "Dracula",
            .description = "Dark theme with vibrant colors",
            .category = .dark,
            .tags = &[_][]const u8{ "dark", "purple", "vibrant" },
        });

        return Self{
            .allocator = allocator,
            .theme_picker = theme_picker,
        };
    }

    pub fn deinit(self: *Self) void {
        self.theme_picker.deinit();
    }

    pub fn widget(self: *Self) vxfw.Widget {
        return vxfw.Widget{
            .userdata = self,
            .drawFn = draw,
            .eventHandlerFn = handleEvent,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // Create surface using vxfw
        var surface = try vxfw.Surface.init(ctx.arena, undefined, ctx.min);

        // Draw theme picker
        const picker_surface = try self.theme_picker.widget().draw(ctx);
        try surface.blit(picker_surface, .{ .x = 0, .y = 0 });

        return surface;
    }

    fn handleEvent(ptr: *anyopaque, ctx: vxfw.EventContext) std.mem.Allocator.Error!vxfw.CommandList {
        const self: *Self = @ptrCast(@alignCast(ptr));
        var commands = vxfw.CommandList.init(ctx.arena);

        // Handle theme selection
        switch (ctx.event) {
            .user => |user_event| {
                if (std.mem.eql(u8, user_event.name, "theme_selected")) {
                    self.selected_theme = @as(*const phantom.vxfw.FuzzySearch.ThemeInfo,
                                               @ptrCast(@alignCast(user_event.data.?))).*;
                    try commands.append(.redraw);
                }
            },
            else => {
                // Forward to theme picker
                const picker_commands = try self.theme_picker.widget().handleEvent(ctx);
                for (picker_commands.items) |cmd| {
                    try commands.append(cmd);
                }
            },
        }

        return commands;
    }
};

fn createRootWidget(allocator: std.mem.Allocator) !*RootWidget {
    const widget = try allocator.create(RootWidget);
    widget.* = try RootWidget.init(allocator);
    return widget;
}
```

## 🧩 Complete Widget Library (v0.4.0)

### VXFW Framework Widgets (Production Ready)
- **Surface/SubSurface**: Composable rendering system
- **DrawContext/EventContext**: Advanced widget communication
- **Widget Lifecycle**: Complete lifecycle management with ticks and timers

### Layout Widgets (Professional Quality)
- **FlexRow/FlexColumn**: Flexible layout containers with proper sizing
- **Center**: Widget centering with alignment options
- **Padding**: Configurable padding container
- **SizedBox**: Fixed size constraints
- **Border**: Customizable border decoration
- **SplitView**: Resizable split pane container

### Display Widgets (Advanced Features)
- **TextView**: Multi-line text with Unicode support via gcode
- **CodeView**: Syntax-highlighted code display (Zig support included)
- **RichText**: Styled text with markdown formatting
- **View**: Base component for custom widgets

### Interaction Widgets (Full Featured)
- **TextField**: Advanced text input with validation
- **ListView**: Virtualized list with efficient scrolling
- **ScrollView**: Smooth scrolling with momentum
- **Scrollbar**: Visual scroll indicators

### Advanced Widgets (Cutting Edge)
- **ThemePicker**: Fuzzy search theme selection with highlighting ⭐ NEW
- **Spinner**: 9 animation styles for loading indicators
- **StreamingText**: Real-time text streaming for AI applications
- **CodeBlock**: Multi-language syntax highlighting
- **TaskMonitor**: Multi-task progress tracking

### System Widgets (Enterprise Ready)
- **SystemMonitor**: Real-time system metrics
- **NetworkTopology**: Network visualization
- **CommandBuilder**: Interactive command construction
- **UniversalPackageBrowser**: Multi-source package management

## 🎨 Advanced Styling & Theming

### Theme System with Fuzzy Search
```zig
// Create theme picker with advanced search
var theme_picker = try phantom.widgets.ThemePicker.init(allocator);

// Add custom themes
try theme_picker.addTheme(.{
    .name = "Custom Dark Pro",
    .description = "Professional dark theme for coding",
    .category = .dark,
    .tags = &[_][]const u8{ "dark", "professional", "coding", "minimal" },
});

// Search themes (supports fuzzy matching)
try theme_picker.setQuery("dark pro"); // Matches "Custom Dark Pro"

// Handle selection
const selected = theme_picker.getSelectedTheme();
if (selected) |theme| {
    std.debug.print("Selected: {s}\n", .{theme.name});
}
```

### Advanced Styling API
```zig
// Modern fluent API
const style = phantom.Style.default()
    .withFg(phantom.Color.bright_cyan)
    .withBg(phantom.Color.rgb(25, 25, 35)) // True color support
    .withBold()
    .withItalic();

// Color utilities (new in v0.4.0)
const is_light = color.isLight();
const contrast_ratio = color1.getContrastRatio(color2);
const accessible = contrast_ratio >= 4.5; // WCAG AA compliance
```

### System Theme Detection
```zig
// Automatic theme detection
const system_theme = try phantom.detectSystemTheme();
const style = switch (system_theme) {
    .dark => phantom.Style.darkTheme(),
    .light => phantom.Style.lightTheme(),
    .auto => phantom.Style.adaptiveTheme(),
};
```

## 🔧 Advanced Features (v0.4.0)

### Unicode Processing with gcode
```zig
const gcode = phantom.vxfw.GcodeIntegration;

// Advanced text processing
var cache = gcode.GcodeGraphemeCache.init(allocator);
defer cache.deinit();

var display_width = gcode.GcodeDisplayWidth.init(&cache);

// Accurate width calculation for all Unicode
const width = try display_width.getStringWidth("Hello 世界! 🌟 مرحبا");

// Advanced text wrapping with word boundaries
const wrapped = try display_width.wrapTextAdvanced(text, 40, allocator);

// BiDi text support
var bidi = gcode.GcodeBiDi.init(allocator);
const reordered = try bidi.reorderForDisplay("مرحبا Hello");
```

### Event System with Advanced Handling
```zig
// Enhanced event handling
fn advancedEventHandler(ctx: vxfw.EventContext) !vxfw.CommandList {
    var commands = vxfw.CommandList.init(ctx.arena);

    switch (ctx.event) {
        .key_press => |key| {
            // Handle key with modifiers
            if (key.mods.ctrl and key.key == .c) {
                try commands.append(.{ .copy_to_clipboard = getSelectedText() });
            }
        },
        .mouse => |mouse| {
            // Advanced mouse handling
            switch (mouse.action) {
                .drag => try handleDrag(mouse.position),
                .wheel_up => try commands.append(.{ .scroll = .up }),
                else => {},
            }
        },
        .paste => |text| {
            // Bracketed paste support
            try commands.append(.{ .insert_text = text });
        },
        .color_report => |report| {
            // Terminal color capability detection
            try updateColorScheme(report);
        },
        else => {},
    }

    return commands;
}
```

### System Integration
```zig
// Cross-platform clipboard
try phantom.clipboard.copyText("Hello from Phantom!");
const clipboard_text = try phantom.clipboard.pasteText(allocator);

// Desktop notifications
try phantom.notifications.show(.{
    .title = "Phantom App",
    .body = "Task completed successfully!",
    .icon = .success,
});

// Terminal title management
try phantom.terminal.setTitle("My Phantom App v0.4.0");
```

## 💡 Common Use Cases (v0.4.0)

### 1. Advanced Theme Picker Interface

```zig
pub fn createThemePickerApp(allocator: std.mem.Allocator) !*phantom.App {
    var app = try phantom.App.init(allocator, .{
        .title = "🎨 Advanced Theme Picker",
        .tick_rate_ms = 16,
        .mouse_enabled = true,
    });

    // Create theme picker with fuzzy search
    var theme_picker = try phantom.widgets.ThemePicker.init(allocator);

    // Add comprehensive theme collection
    const themes = [_]phantom.vxfw.FuzzySearch.ThemeInfo{
        .{ .name = "Dracula", .description = "Dark theme with vibrant colors",
           .category = .dark, .tags = &[_][]const u8{ "dark", "purple", "vibrant" } },
        .{ .name = "Solarized Dark", .description = "Balanced dark theme",
           .category = .dark, .tags = &[_][]const u8{ "dark", "balanced", "professional" } },
        .{ .name = "Tokyo Night", .description = "Modern neon theme",
           .category = .dark, .tags = &[_][]const u8{ "dark", "neon", "modern" } },
        .{ .name = "Catppuccin", .description = "Soothing pastel theme",
           .category = .dark, .tags = &[_][]const u8{ "dark", "pastel", "soothing" } },
    };

    for (themes) |theme| {
        try theme_picker.addTheme(theme);
    }

    app.setRootWidget(theme_picker.widget());
    return app;
}
```

### 2. Unicode-Aware Text Editor

```zig
pub fn createUnicodeEditor(allocator: std.mem.Allocator) !*phantom.App {
    var app = try phantom.App.init(allocator, .{
        .title = "📝 Unicode Text Editor",
        .unicode_enabled = true,
    });

    // Create text editor with gcode Unicode support
    var editor = try phantom.widgets.TextArea.init(allocator);
    editor.setUnicodeProcessing(true); // Enable gcode processing
    editor.setBiDiSupport(true);       // Enable BiDi text support

    try editor.setText("Hello World! 世界 مرحبا 🌟");

    app.setRootWidget(editor.widget());
    return app;
}
```

### 3. Real-time System Dashboard

```zig
pub fn createSystemDashboard(allocator: std.mem.Allocator) !*phantom.App {
    var app = try phantom.App.init(allocator, .{
        .title = "📊 System Dashboard",
        .tick_rate_ms = 100, // Update every 100ms
    });

    // Create layout using vxfw
    var dashboard = try DashboardWidget.init(allocator);
    app.setRootWidget(dashboard.widget());

    return app;
}

const DashboardWidget = struct {
    allocator: std.mem.Allocator,
    system_monitor: phantom.widgets.SystemMonitor,
    network_topology: phantom.widgets.NetworkTopology,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return @This(){
            .allocator = allocator,
            .system_monitor = try phantom.widgets.SystemMonitor.init(allocator),
            .network_topology = try phantom.widgets.NetworkTopology.init(allocator),
        };
    }

    pub fn widget(self: *@This()) vxfw.Widget {
        return vxfw.Widget{
            .userdata = self,
            .drawFn = draw,
            .eventHandlerFn = handleEvent,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *@This() = @ptrCast(@alignCast(ptr));

        // Use FlexColumn for vertical layout
        var flex_column = try vxfw.FlexColumn.init(ctx.arena, .{});

        try flex_column.addItem(.{
            .widget = self.system_monitor.widget(),
            .flex = 1,
        });

        try flex_column.addItem(.{
            .widget = self.network_topology.widget(),
            .flex = 1,
        });

        return flex_column.widget().draw(ctx);
    }
};
```

## 🔧 Build Configuration (v0.4.0)

### Feature-based Builds
```bash
# Minimal build for basic TUI apps
zig build -Dpreset=basic

# Full-featured build for advanced applications
zig build -Dpreset=full

# Custom build for specific needs
zig build -Dadvanced=true -Dsystem=true -Dcrypto=false
```

### Build Options
```zig
// In your build.zig
const phantom_dep = b.dependency("phantom", .{
    .target = target,
    .optimize = optimize,
    .preset = "full",           // or "basic", "system", etc.
    .unicode_support = true,    // Enable gcode integration
    .theme_picker = true,       // Enable fuzzy search theme picker
    .system_integration = true, // Enable clipboard, notifications
});
```

## 🧪 Testing & Quality (v0.4.0)

### Comprehensive Testing
```zig
test "theme picker fuzzy search" {
    var theme_picker = try phantom.widgets.ThemePicker.init(std.testing.allocator);
    defer theme_picker.deinit();

    try theme_picker.addTheme(.{
        .name = "Dark Professional",
        .description = "Professional dark theme",
        .category = .dark,
        .tags = &[_][]const u8{ "dark", "professional" },
    });

    // Test fuzzy search
    try theme_picker.setQuery("dark pro");
    const results = theme_picker.getSearchResults();
    try std.testing.expect(results.len > 0);
    try std.testing.expectEqualStrings("Dark Professional", results[0].theme.name);
}

test "unicode text processing" {
    const gcode = phantom.vxfw.GcodeIntegration;

    var cache = gcode.GcodeGraphemeCache.init(std.testing.allocator);
    defer cache.deinit();

    const width = try cache.getTextWidth("Hello 世界! 🌟");
    try std.testing.expect(width > 0);

    const clusters = try cache.getGraphemes("Hello 世界!");
    defer std.testing.allocator.free(clusters);
    try std.testing.expect(clusters.len > 0);
}
```

### Performance Benchmarks
```bash
# Run performance tests
zig build test -Doptimize=ReleaseFast

# Benchmark rendering performance
zig build benchmark --benchmark-rendering

# Profile memory usage
zig build profile --profile-memory
```

## 🚀 Migration from v0.3.x to v0.4.0

### Major Changes
1. **VXFW Framework**: New widget system with Surface/SubSurface rendering
2. **Unicode Integration**: gcode library for production-quality text processing
3. **Theme System**: Advanced theme picker with fuzzy search
4. **Event System**: Enhanced event handling with more event types
5. **System Integration**: Comprehensive clipboard, notifications, and terminal control

### Migration Steps
```zig
// Old v0.3.x style
const text = try phantom.widgets.Text.init(allocator, "Hello");
try app.addWidget(&text.widget);

// New v0.4.0 vxfw style
const MyWidget = struct {
    pub fn widget(self: *@This()) vxfw.Widget {
        return vxfw.Widget{
            .userdata = self,
            .drawFn = draw,
            .eventHandlerFn = handleEvent,
        };
    }
};
```

## 📚 Documentation & Resources

### Complete Documentation
- **[API Reference](API.md)**: Complete v0.4.0 API documentation
- **[VXFW Guide](VXFW.md)**: Widget framework system guide
- **[Unicode Guide](UNICODE.md)**: gcode integration and Unicode handling
- **[Theme Guide](THEMES.md)**: Theme system and fuzzy search
- **[Migration Guide](MIGRATION.md)**: Upgrade from v0.3.x to v0.4.0

### Demo Applications
```bash
# Run v0.4.0 demos
zig build demo-fuzzy     # Fuzzy search theme picker
zig build demo-vxfw      # VXFW framework demonstration
zig build demo-unicode   # Unicode text processing
zig build demo-system    # System integration features
```

## 🆘 Support & Community

- **GitHub**: https://github.com/ghostkellz/phantom
- **Issues**: Report bugs and request features
- **Discussions**: Ask questions and share projects
- **Examples**: 7+ complete demo applications
- **Wiki**: Community-driven documentation

---

**🎉 Phantom v0.4.0 is production-ready for enterprise TUI development!**

**Ready for Ghostshell Migration**: Complete vxfw equivalence with advanced features
**Enterprise Ready**: Comprehensive widget library and system integration
**Performance Optimized**: 60+ FPS rendering with efficient memory management
**Unicode Complete**: Production-quality text processing via gcode library

Start building amazing TUI applications with Phantom v0.4.0! 👻✨