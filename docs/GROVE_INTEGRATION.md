# Grove Integration Guide

Phantom integrates Grove for Tree-sitter syntax highlighting support.

## Overview

The `SyntaxHighlight` widget provides syntax highlighting for 15+ programming languages using Tree-sitter grammars via the Grove library.

## Supported Languages

- Zig, Rust, C
- TypeScript, TSX, JavaScript
- Python, Bash
- JSON, TOML, YAML, Markdown, CMake
- Ghostlang, GShell

## Basic Usage

```zig
const phantom = @import("phantom");
const SyntaxHighlight = phantom.widgets.SyntaxHighlight;

// Initialize with source code and language
var highlighter = try SyntaxHighlight.init(
    allocator,
    source_code,
    phantom.grove.Languages.zig
);
defer highlighter.deinit();

// Parse without highlighting (plain text with line numbers)
try highlighter.parseWithoutHighlighting();

// Render to buffer
highlighter.render(buffer, area);
```

## Syntax Highlighting with Queries

For full syntax highlighting, provide a Tree-sitter query and highlight rules:

```zig
const query_source = @embedFile("path/to/highlights.scm");

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

## Configuration

```zig
// Show/hide line numbers
_ = highlighter.setShowLineNumbers(true);

// Set line number column width
_ = highlighter.setLineNumberWidth(6);

// Set scroll offsets
_ = highlighter.setScrollY(10);
_ = highlighter.setScrollX(0);
```

## Color Mapping

Default color mapping for syntax classes:

| Class | Color |
|-------|-------|
| `keyword` | Magenta |
| `function` | Blue |
| `type` | Cyan |
| `string` | Green |
| `number` | Yellow |
| `comment` | Bright Black |
| `variable` | White |
| `operator` | Red |
| `punctuation` | White |

## Example Application

See `examples/grove_syntax_demo.zig` for a complete working example.

```bash
zig build run-grove-demo
```

## Architecture

The SyntaxHighlight widget:

1. Parses source code using Grove's Tree-sitter wrapper
2. Stores the abstract syntax tree (AST)
3. Optionally runs highlight queries to generate HighlightSpans
4. Renders each character with appropriate styling based on byte position
5. Displays line numbers in a separate column

## Performance

- Line-by-line rendering with byte position tracking
- LRU-cached glyph rendering (from parent framework)
- Efficient highlight span lookups via binary search on byte positions
- Minimal memory overhead for plain text mode

## Limitations

- Highlight queries must be provided by the user for full highlighting
- Character-by-character rendering (may be slower for very large files)
- Currently supports single-file highlighting only

## ZonTOM Integration

Phantom also includes ZonTOM for TOML parsing:

```zig
const phantom = @import("phantom");
const zontom = phantom.zontom;

// Parse TOML configuration files
var parsed = try zontom.parse(allocator, toml_source);
defer parsed.deinit();
```

## Grove API Reference

Grove is exposed via `phantom.grove`:

```zig
const grove = phantom.grove;

// Core types
grove.Parser
grove.Tree
grove.Node
grove.Language
grove.Languages  // Bundled language enum
grove.Query
grove.QueryCursor
grove.Highlight.HighlightEngine
grove.Highlight.HighlightSpan
grove.Highlight.HighlightRule
```

See the Grove repository for detailed API documentation.
