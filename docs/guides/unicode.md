# Unicode Guide

Phantom relies on `gcode` and related helpers for Unicode-aware text handling.

## Status

- supported core capability
- relevant to text rendering, wrapping, emoji, width calculations, and editor-like widgets

## What It Covers

- grapheme-aware text handling
- Unicode display width calculations
- emoji-heavy terminal output
- richer text processing for advanced widgets and editors

## Notes

- This is part of Phantom's core quality story, but most consumers do not need to interact with the lower-level Unicode helpers directly on day one.
- Start with the normal widget APIs first; drop lower only when you need custom text behavior.
