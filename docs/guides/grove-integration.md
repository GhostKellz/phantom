# Grove Integration Guide

Phantom integrates Grove for Tree-sitter-based syntax highlighting.

This is a supported advanced surface, not the primary onboarding path.

## What It Gives You

- bundled Tree-sitter language support through Grove
- the `phantom.widgets.SyntaxHighlight` widget
- direct access to Grove via `phantom.grove`

## Basic Usage

```zig
const phantom = @import("phantom");

var highlighter = try phantom.widgets.SyntaxHighlight.init(
    allocator,
    source_code,
    phantom.grove.Languages.zig,
);
defer highlighter.deinit();

try highlighter.parseWithoutHighlighting();
highlighter.render(buffer, area);
```

## With Highlight Queries

```zig
const rules = [_]phantom.grove.Highlight.HighlightRule{
    .{ .capture = "keyword", .class = "keyword" },
    .{ .capture = "function", .class = "function" },
    .{ .capture = "type", .class = "type" },
    .{ .capture = "string", .class = "string" },
    .{ .capture = "number", .class = "number" },
    .{ .capture = "comment", .class = "comment" },
};

try highlighter.parseWithQuery(query_source, &rules);
```

## Demo

```bash
zig build run-grove-demo
```

## Notes

- Grove support is available through `phantom.grove` when advanced widgets are enabled.
