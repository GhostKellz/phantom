# Phantom Feature Guide

This guide summarizes the current Phantom surface in terms of what is strongest today, what is advanced, and what should not define the first impression of the library.

## Strongest Today

- `App`-driven terminal UI loop
- core widgets such as `Text`, `List`, `Button`, `Input`, `TextArea`, `ProgressBar`, and `Table`
- `layout.engine` for new constraint-based layout work
- theme support and theme manifests
- async runtime helpers and streaming-aware dashboard widgets
- renderer, transitions, and Unicode-aware text handling
- PTY-backed terminal sessions when explicitly enabled

## Canonical Demos

- `zig build demo-feature-showcase`
- `zig build demo-theme-gallery`
- `zig build demo-data-dashboard`
- `zig build demo-vxfw`
- `zig build run-grove-demo`
- `zig build -Dterminal-widget=true demo-terminal-session`

## Widget Families

### Core

- `Text`
- `Block`
- `List`
- `Button`
- `Input`
- `TextArea`
- `Border`
- `Spinner`
- `Scrollbar`

### Layout And Composition

- `Container`
- `Stack`
- `Tabs`
- `ScrollView`
- `ListView`
- `FlexRow`
- `FlexColumn`

### Data And Dashboards

- `ProgressBar`
- `Table`
- `TaskMonitor`
- `ThemeTokenDashboard`
- `DataListView`
- `DataStateIndicator`
- `DataBadge`
- `DataEventOverlay`

### Visualization

- `BarChart`
- `Chart`
- `Gauge`
- `Sparkline`
- `Calendar`
- `Canvas`

### Advanced

- `StreamingText`
- `CodeBlock`
- `ThemePicker`
- `StatusBar`
- `ToastOverlay`
- `Popover`
- `SyntaxHighlight`
- `Markdown`
- `Diff`
- `Tree`

### Specialized

- `UniversalPackageBrowser`
- `AURDependencies`
- `BlockchainPackageBrowser`
- `SystemMonitor`
- `NetworkTopology`
- `CommandBuilder`

## Supporting Systems

- async runtime via `phantom.async_runtime`
- theme management via `phantom.theme` and `phantom.style_theme`
- Grove-backed syntax highlighting via `phantom.grove`
- Unicode processing via `gcode`
- font and rendering support via `zfont`
- optional higher-performance event-loop backend via `zigzag`

## Advanced Surface

### `vxfw`

Phantom ships a lower-level widget framework under `phantom.vxfw`. It is useful when you want direct control over surfaces, event contexts, and command-driven widget lifecycles, but it is not the easiest place to start for most applications.

### Grove Integration

Syntax highlighting is available through Grove and the `SyntaxHighlight` widget. This is a supported advanced feature rather than the primary onboarding path.

## Supported Advanced Surface

### Terminal Widget / PTY Sessions

The terminal widget and PTY session manager are an opt-in advanced surface.

- build with `-Dterminal-widget=true` to enable them
- use `zig build -Dterminal-widget=true demo-terminal-session` for the reference integration path
- treat them as advanced, but no longer as hidden or throwaway

## Recommended Evaluation Flow

1. Start with `README.md`.
2. Build a small `App` using `Text`, `List`, or `ProgressBar`.
3. Add `layout.engine` once the widget tree grows beyond a trivial vertical stack.
4. Pull in async dashboards, Grove, or `vxfw` only when the simpler path no longer fits.
