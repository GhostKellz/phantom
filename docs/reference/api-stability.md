# API Stability Tiers

This document defines the stability tiers Phantom uses to set expectations before
v1.0. It complements [`features.md`](features.md) (what exists) and
[`api.md`](api.md) (the public surface) by describing how much each surface may
change and how much you should rely on it.

Tiers describe **stability of the API shape**, not code quality. An advanced or
experimental API can be well-tested and still be expected to change.

## Tiers

### Stable

Recommended for production use. Breaking changes are avoided and, when unavoidable,
called out in the changelog with a migration path.

- `phantom.App`, `phantom.AppConfig`
- Core widgets: `Text`, `Block`, `List`, `Button`, `Input`, `TextArea`, `Border`,
  `Spinner`, `Scrollbar`, `ProgressBar`, `Table`
- `phantom.Style`, `phantom.Color`
- Rich text: `phantom.text.Span`, `phantom.text.Line`, `phantom.text.Text`
- `phantom.layout.engine` (constraint-based layout)
- The `StatefulWidget` contract (`State` + `state()` + `applyState()`)
- Geometry types: `Rect`, `Position`, `Point`, `Size`

### Advanced

Supported and usable in production, but lower-level or with a heavier footprint. The
API shape is mostly settled but may be refined. Prefer the Stable surface first.

- `phantom.vxfw` (Surface/DrawContext/EventContext lower-level framework)
- Data + dashboard widgets: `TaskMonitor`, `SystemMonitor`, `DataListView`,
  `DataStateIndicator`, `ThemeTokenDashboard`, `ListView`, `StreamingText`
- Visualization widgets: `BarChart`, `Chart`, `Gauge`, `Sparkline`, `Calendar`,
  `Canvas`
- Composition: `Container`, `Stack`, `Tabs`, `ScrollView`, `FlexRow`, `FlexColumn`
- Overlays/chrome: `StatusBar`, `ToastOverlay`, `Popover`, `Tree`, `Markdown`, `Diff`
- `phantom.async_runtime` and `StreamingListSource`
- Grove-backed syntax highlighting (`SyntaxHighlight`, `CodeBlock`)
- Terminal widget / PTY sessions (opt-in via `-Dterminal-widget=true`)
- Theme manifests (`phantom.theme`, `phantom.style_theme`)

### Experimental

Present but not production-ready. Initialization, resource lifecycle, or output may be
incomplete. Gated behind build flags and excluded from the recommended surface. Do not
assume these are finished; expect breaking changes without notice.

- GPU rendering backends (`phantom.gpu`: Vulkan, CUDA text rendering)
- `zfont` font loading/fallback/metrics integration in `FontManager`
- Terminal theme detection for some environments (Kitty, Alacritty, GNOME, KDE,
  Windows system themes)
- Specialized package/domain browsers: `UniversalPackageBrowser`, `AURDependencies`,
  `BlockchainPackageBrowser`, `NetworkTopology`, `CommandBuilder`

Experimental status for these surfaces tracks the boundaries in Priority 6 and
Priority 7 of the enhancement backlog.

### Migration-only

Provided solely to ease migration from an older Phantom or another library. Not for
new code, and slated for removal. Anything here should be treated as already
deprecated.

- Legacy split/layout helpers superseded by `phantom.layout.engine`
- Version-specific migration notes in
  [`../widgets/migration-v061.md`](../widgets/migration-v061.md)

> The former `phantom.layout.migration` shim has been removed. New code must use
> `phantom.layout.engine` directly.

## How to Read a Symbol's Tier

1. If it appears in the Stable list above, rely on it.
2. If it is gated behind a build flag (for example `-Dterminal-widget=true` or a GPU
   feature flag), it is at most Advanced and possibly Experimental — check the lists.
3. If it lives under `phantom.gpu`, font/glyph internals, or a specialized browser
   widget, treat it as Experimental.
4. When in doubt, `api.md` is the source of truth for what is public; this document is
   the source of truth for how stable that public surface is.

## Policy Before v1.0

- Stable APIs will not break without a changelog entry and migration guidance.
- Advanced APIs may be refined; changes will be noted in the changelog.
- Experimental APIs may change or be removed at any time.
- Marketing-style claims (for example GPU acceleration) stay out of the Stable and
  Advanced docs until backed by implementation and benchmarks.
