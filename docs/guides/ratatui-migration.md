# Migrating from ratatui

This guide maps common [ratatui](https://ratatui.rs) (Rust) concepts to their Phantom
(Zig) equivalents. It is a concept map, not a line-by-line port: Phantom owns the event
loop and widget lifecycle through `App`, whereas ratatui leaves the loop to you.

## Mental Model

| ratatui | Phantom | Notes |
| --- | --- | --- |
| You write the draw loop and call `terminal.draw(\|f\| ...)` each frame | `phantom.App` owns the loop; you `addWidget` once and call `app.run()` | Phantom re-renders registered widgets for you. |
| `Frame` + `frame.render_widget(w, area)` | `app.addWidget(&w.widget)` | Widgets are persistent, heap-allocated, and caller-owned. |
| Immediate-mode widgets rebuilt every frame | Retained widgets mutated in place | Update a widget by calling its setters, not by re-creating it. |
| `ratatui::widgets::StatefulWidget` + external `State` | `phantom.StatefulWidget` + widget-owned `state()`/`applyState()` | State lives in the widget; snapshots are plain structs. |
| crossterm event polling | `phantom.Event` routed to focused widget, or `event_loop.addHandler` | See [Events](#events). |

## Widgets

| ratatui | Phantom | Header |
| --- | --- | --- |
| `Paragraph` | `phantom.widgets.Paragraph` | Block text with wrapping/alignment/scroll. |
| `Block` (borders/title) | `phantom.widgets.Block` | Container/border chrome. |
| `List` + `ListState` | `phantom.widgets.List` (`List.State`) | Selection + scroll are in the snapshot. |
| `Table` + `TableState` | `phantom.widgets.Table` (`Table.State`) | |
| `Tabs` | `phantom.widgets.Tabs` (`Tabs.State`) | |
| `Gauge` / `LineGauge` | `phantom.widgets.Gauge` | |
| `BarChart` | `phantom.widgets.BarChart` | |
| `Chart` | `phantom.widgets.Chart` | |
| `Sparkline` | `phantom.widgets.Sparkline` | |
| `Span` / `Line` / `Text` | `phantom.text.Span` / `phantom.text.Line` / `phantom.text.Text` | Same composition model. |

Widgets gated behind build flags (`Table`, `Chart`, `Gauge`, `Tabs`, ...) require the
matching feature to be enabled; see [`../reference/features.md`](../reference/features.md).

## Styling

ratatui's `Style`/`Color` map directly:

```rust
// ratatui
Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)
```

```zig
// phantom
phantom.Style.default().withFg(phantom.Color.bright_cyan).withBold()
```

Style setters are chainable (`withFg`, `withBg`, `withBold`, ...) and return a new
`Style` value, so they compose the same way as ratatui's builder methods.

## Rich Text

ratatui's `Span`/`Line`/`Text` become `phantom.text.Span`/`Line`/`Text`:

```zig
var line = phantom.text.Line.init(allocator);
defer line.deinit();
try line.appendRaw("status: ");
try line.appendStyled("ok", phantom.Style.default().withFg(phantom.Color.green));
```

`Span.raw` / `Span.styled` are the borrowed-content constructors; use `Span.dupe`
when you need an owned copy with an explicit lifetime.

## Layout

ratatui's `Layout::default().constraints([...])` maps to `phantom.layout.engine`:

```rust
// ratatui
let chunks = Layout::default()
    .direction(Direction::Horizontal)
    .constraints([Constraint::Percentage(33), Constraint::Percentage(67)])
    .split(area);
```

```zig
// phantom
const engine = phantom.layout.engine;
var builder = engine.LayoutBuilder.init(allocator);
defer builder.deinit();

const root = try builder.createNode();
const left = try builder.createNode();
const right = try builder.createNode();
try builder.row(root, &.{
    .{ .handle = left, .weight = 1.0 },
    .{ .handle = right, .weight = 2.0 },
});
```

Weights are proportional, matching ratatui's ratio-style constraints. Prefer
`phantom.layout.engine` for new code.

## Events

ratatui leaves input to crossterm and your own `match` on `KeyCode`. In Phantom:

- By default `app.run()` routes each `phantom.Event` to the focused widget's
  `handleEvent`, handles `Tab` focus movement, and quits on `Esc`/`Ctrl+C`.
- For app-global keys, disable the default handler and add your own:

```zig
fn handler(event: phantom.Event) !bool {
    switch (event) {
        .key => |key| if (key == .char and key.char == 'q') {
            // quit, etc.
            return true;
        },
        else => {},
    }
    return false; // let other handlers/widgets see it
}

var app = try phantom.App.init(allocator, .{ .add_default_handler = false });
try app.event_loop.addHandler(&handler);
try app.runWithoutDefaults();
```

Returning `true` marks the event handled and stops propagation, mirroring the way you
`break` out of a ratatui input `match`.

## Loop Ownership: the Key Difference

The biggest change from ratatui is that you do **not** write the frame loop. Instead:

1. Build widgets once and `addWidget` them.
2. Mutate widget state in event/tick handlers.
3. Call `app.run()` and let Phantom render.

If you need per-frame logic (animation, polling), use the tick event
(`tick_rate_ms` in `AppConfig`) rather than a manual `loop { terminal.draw(...) }`.

## See Also

- [`../getting-started/quickstart.md`](../getting-started/quickstart.md)
- [`../reference/api.md`](../reference/api.md)
- [`../reference/api-stability.md`](../reference/api-stability.md)
