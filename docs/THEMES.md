# Themes

Phantom ships with a versatile theme system that balances quick swapping with deep customization. The core concepts are:

- **Variants** describe whether a theme is intended for dark or light terminals and help the runtime pick sensible defaults.
- **Palette tokens** expose semantic colors (surface, accent, warning, etc.) that widgets can depend on.
- **Typography presets** provide reusable font decisions (family, weight, tracking and text styling) that higher level components can consume.
- **Origins** track whether a theme is built-in, loaded from the user’s config directory, or provided dynamically at runtime.

This document walks through the default themes, the JSON schema, and the runtime APIs you can use to interact with the system.

## Built-in themes

| Name                | Variant | Origin  |
|---------------------|---------|---------|
| `ghost-hacker-blue` | Dark    | Built-in (vivid customization)
| `tokyonight-night`  | Dark    | Built-in
| `tokyonight-storm`  | Dark    | Built-in
| `tokyonight-moon`   | Dark    | Built-in
| `tokyonight-day`    | Light   | Built-in

All of these themes expose the same semantic palette so widgets can swap between them without additional work.

## Theme JSON schema

Themes are described with JSON. Each property is optional unless noted.

```jsonc
{
  "name": "My Theme",                  // optional display name
  "description": "Shown in pickers",    // optional description
  "variant": "dark",                   // "dark" or "light" (defaults to dark)
  "defs": {                             // reusable color definitions
    "primary": "#3366ff",
    "onPrimary": "#0a0a0a"
  },
  "palette": {                           // semantic tokens used by widgets
    "surface": "primary",
    "surfaceAlt": "#1f1f28",
    "accent": "onPrimary",
    "warning": "#ffc107",
    "critical": "#ff5555"
  },
  "theme": {                             // high-level semantic colors
    "primary": "primary",
    "background": "surface",
    "text": "onPrimary"
  },
  "syntax": {                            // colors for syntax highlighting
    "keyword": "accent",
    "string": "#89ddff"
  },
  "typography": {                        // reusable font presets
    "heading": {
      "family": "JetBrains Mono",
      "weight": 700,
      "style": ["bold", "uppercase"],
      "tracking": 1
    },
    "body": {
      "family": "Iosevka Term",
      "weight": 400
    }
  }
}
```

### Palette tokens

Palette values can reference entries in `defs`, semantic theme colors (e.g. `primary`, `warning`), or literal hex strings. Phantom standardises on the following tokens:

- `surface`, `surfaceAlt`, `surfaceHighlight`
- `muted`, `subtle`
- `accent`, `accentAlt`, `accentPop`
- `interactive`, `interactiveHover`
- `success`, `warning`, `critical`, `info`
- `selection`

You can add additional tokens—the lookup helpers treat the palette as a generic string-to-color map.

### Typography presets

Each preset accepts:

- `family`: font name (copied, so temporary JSON buffers are safe)
- `weight`: numeric weight (defaults to 400)
- `style`: array of flags (`bold`, `italic`, `underline`, `strikethrough`, `dim`, `reverse`, `blink`, `uppercase`)
- `uppercase`: boolean alias for the style flag
- `tracking`: letter-spacing adjustment from -128 to 127

At runtime you can fetch presets via `Theme.getTypography("heading")` and apply the stored `Attributes` on text styles.

## Runtime APIs

```zig
const phantom = @import("../root.zig");
const ThemeManager = phantom.theme.ThemeManager;
const Variant = phantom.theme.Variant;

var manager = try ThemeManager.init(allocator);
const theme = manager.getActiveTheme();
const accent = manager.getColor("accent");
const heading = theme.getTypography("heading").?;
```

### Selecting a theme

- `manager.setTheme("tokyonight-night")` picks a specific theme.
- `manager.syncVariant(.light)` chooses the first available light theme (useful when the terminal switches background modes).
- `manager.syncVariantFromEnvironment()` reads `TERM_BACKGROUND` and best-effort selects a matching variant.

Environment overrides:

- `PHANTOM_THEME`: exact theme name to load at startup.
- `PHANTOM_THEME_VARIANT`: preferred variant (`dark`/`light`).

### Dynamic themes

You can inject themes at runtime:

```zig
const bytes = try std.fs.cwd().readFileAlloc(allocator, "./my-theme.json", 128 * 1024);
try manager.loadThemeFromBytes("my-theme", bytes, .dynamic);
try manager.setTheme("my-theme");
```

User themes placed in `~/.config/phantom/themes/` are auto-loaded on startup. Call `manager.reloadUserThemes()` to rescan the directory (useful for live previews on save).

## Access from widgets

Widgets should prefer palette tokens/typography over raw colors:

```zig
const manager: *const phantom.theme.ThemeManager = app.theme_manager; // provided by runtime context
const theme = manager.getActiveTheme();
const surface = theme.getPaletteColor("surface") orelse phantom.style.Color.black;
const title_style = phantom.style.Style.default()
    .withFg(theme.getColor("text") orelse phantom.style.Color.white)
    .withBold();
```

Using semantic lookups ensures custom themes remain compatible without needing widget-specific patches.
