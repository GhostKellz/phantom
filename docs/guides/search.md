# Search Guide

Phantom exposes fuzzy-search functionality through the `vxfw` search surface and widgets such as `ThemePicker`.

## Status

- advanced surface
- useful for theme pickers and interactive filtering
- not the primary entry point for new Phantom applications

## Main Entry Point

```zig
const phantom = @import("phantom");
const FuzzySearch = phantom.vxfw.FuzzySearch;
```

## Typical Uses

- theme selection
- filtering command palettes or lists
- ranked matching across labels and metadata

## Notes

- Treat this as an advanced surface rather than the primary Phantom onboarding path.
