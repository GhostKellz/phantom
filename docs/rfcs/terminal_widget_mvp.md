# RFC: Terminal Widget MVP for Phantom TUI

**Status:** Draft  
**Authors:** Phantom team  
**Created:** 2025-11-05  
**Target Release:** v0.7.2 (Phase 1)

---

## 1. Problem Statement

Grim and Zeke both require an embedded terminal widget that matches the capabilities of Ratatui + vaxis: running real shells and subprocesses, maintaining scrollback, supporting selection/copy, and integrating with Phantom's event loop and rendering system. Lacking this widget forces downstream projects to embed external terminal emulators or shell out to tmux, breaking UX consistency.

## 2. Goals

- Provide a first-class `Terminal` widget in `phantom.widgets` with ergonomic Zig APIs.
- Support interactive PTY-backed sessions across Linux, macOS, and Windows (via ConPTY).
- Render VT/ANSI escape sequences, colors, and attributes faithfully inside Phantom's Buffer.
- Offer configurable scrollback and search, selection painting, and clipboard integration.
- Expose keyboard/mouse input plumbing with customizable key mappings.
- Ship a production-quality demo and documentation to unblock Grim/Zeke adoption.

## 3. Non-Goals (MVP)

- Advanced terminal features such as GPU acceleration, image protocol support (e.g., iTerm), or SSH multiplexing.
- Implementing a full terminal multiplexer (split panes, tabs). Initial focus is a single PTY session per widget.
- Full-fledged accessibility narration; MVP will expose hooks that later integration can build upon.
- Automatic shell profile management; users must provide shell command/env.

## 4. Requirements & Acceptance Criteria

1. **Cross-platform PTY support**
   - Linux/macOS: use `posix_openpt`, `grantpt`, `unlockpt`, and `forkpty` or manual `pty` management.
   - Windows: wrap ConPTY (CreatePseudoConsole) behind the same abstraction.
   - Provide feature toggles/build flags for unsupported platforms.
2. **Escape sequence handling**
   - Support CSI, OSC, SGR, cursor addressing, erasing, and UTF-8 glyphs.
   - Render to Phantom `Buffer` with color/style fidelity.
3. **Scrollback & resizing**
   - Configurable buffer (default 10k lines) managed as ring structure.
   - Handle terminal & widget resize events, sending appropriate `SIGWINCH`/ConPTY notifications.
4. **Input pipeline**
   - Map Phantom events (keys, mouse) to terminal sequences with configurable bindings.
   - Provide APIs to send raw bytes/strings programmatically.
5. **Selection & clipboard**
   - Support mouse drag and keyboard selection.
   - Integrate with `phantom.clipboard` for copy operations.
6. **Observability**
   - Emit events for process exit, bell, title change.
   - Provide logging hooks for debugging.
7. **Example & documentation**
   - Ship `examples/terminal_demo.zig` showing split view + command execution.
   - Update `docs/WIDGET_CATALOG.md` and integration guides.
8. **Testing**
   - Unit tests for parser, scrollback, selection.
   - Integration test that runs a simple PTY command (`printf`/`dir`) and validates output.

## 5. Architecture Overview

### 5.1 Module Breakdown

```
phantom/
└─ src/
   ├─ terminal/
   │  ├─ pty.zig          // cross-platform PTY abstraction
   │  ├─ parser.zig       // VT sequence state machine
   │  ├─ scrollback.zig   // ring buffer
   │  └─ input.zig        // key/mouse translation helpers
   └─ widgets/
      └─ terminal.zig     // Widget implementation & rendering
```

- **PTY Layer** handles spawning subprocess, piping I/O, resize, and lifecycle.
- **Parser** consumes byte stream from PTY and emits rendering operations (character write, attribute changes, cursor moves, bell, etc.).
- **Scrollback** stores logical lines with metadata (wrap, double width), enabling both viewport rendering and selection.
- **Widget** orchestrates rendering onto Phantom's `Buffer`, dispatches input, and exposes public APIs.

### 5.2 Data Flow

1. `Terminal` widget instantiates `pty.PtySession` with command/env configuration.
2. Background task (runtime/zsync) reads PTY output → `parser` transforms to operations → widget updates render grid + scrollback → schedules redraw.
3. User input triggers `input.translate(event)` → writes bytes to PTY.
4. Selection logic references scrollback and viewport to mark highlighted cells.
5. Clipboard copy uses `phantom.clipboard` when selection finalized.

### 5.3 Concurrency Model

- PTY read loop executes on async runtime (`phantom.async_runtime`), posting messages to main thread via channel.
- Widget updates stay on UI thread to avoid data races.
- Configurable backpressure to drop frames if parser outpaces render (bounded queue, metrics exposure).

## 6. API Sketch

```zig
pub const TerminalConfig = struct {
    command: []const []const u8 = &.{ "/bin/zsh" },
    env: []const []const u8 = &.{},
    cwd: ?[]const u8 = null,
    scrollback_limit: usize = 10_000,
    bell_handler: ?fn() void = null,
    title_handler: ?fn([]const u8) void = null,
    keymap: ?*const KeyMap = null,
    theme_override: ?TerminalTheme = null,
};

pub const Terminal = struct {
    pub fn init(allocator: std.mem.Allocator, config: TerminalConfig) !*Terminal;
    pub fn spawn(self: *Terminal) !void;
    pub fn write(self: *Terminal, bytes: []const u8) !void;
    pub fn resize(self: *Terminal, width: u16, height: u16) !void;
    pub fn getScrollback(self: *Terminal) []const Line;
    pub fn clearScrollback(self: *Terminal) void;
    pub fn setSelection(self: *Terminal, start: Position, end: Position) void;
    pub fn render(self: *Terminal, buffer: *Buffer, area: Rect) void;
    pub fn deinit(self: *Terminal) void;
};
```

## 7. PTY Abstraction Strategy

- **Linux/macOS**: build on libc `posix_openpt` or `forkpty`. We will prefer manual `posix_openpt` to avoid forking complexities, managing child process via `execve`. Signals handled with `std.posix` wrappers.
- **Windows**: use Win32 ConPTY (`CreatePseudoConsole`, `CreateProcess`, `ResizePseudoConsole`). Wrap in Zig FFI layer inside `pty/windows.zig`. Provide stub implementation raising `error.UnsupportedPlatform` when ConPTY unavailable (e.g., old Windows builds).
- **Build Options**: `phantom_config` gains `enable_terminal_widget` flag; Windows builds require `-Dconpty` if toolchain lacks headers.
- **Testing**: exercise PTY spawn locally on Linux, macOS, and Windows/WSL using the scripted harness; document any platform-specific prerequisites so contributors can reproduce without hosted runners.
- **References**:
   - POSIX PTY background: [The Open Group Base Specifications Issue 7, IEEE Std 1003.1-2017](https://pubs.opengroup.org/onlinepubs/9699919799/functions/posix_openpt.html)
   - Linux `forkpty` semantics: `man 3 forkpty`
   - Windows ConPTY API: [Microsoft Docs: Pseudo Console](https://learn.microsoft.com/windows/console/creating-a-pseudoconsole-session)
   - Zig examples: `ziglang/zig` issue #12220 (community ConPTY bindings)

## 8. Rendering Considerations

- Use Phantom `Cell` structure; maintain viewport grid sized to widget area.
- Support double-width characters (CJK) via width table (reuse `gcode`).
- Implement blinking cursor with `phantom.animation` timer; optional config to disable.
- Scrollback accessible via keyboard (PageUp/PageDown) and mouse wheel; maintain offset separate from PTY cursor when user is viewing history.

## 9. Selection & Clipboard

- Selection states: `idle`, `selecting`, `selected`.
- Mouse drag adjusts selection anchors; keyboard (Shift+Arrow) supported.
- On copy command (`Ctrl+Shift+C` default) serialize selected lines, normalize whitespace, and send to `phantom.clipboard`.
- Provide API to retrieve selection text for programmatic use.

## 10. Error Handling & Recovery

- Bubble PTY spawn failures as `Terminal.Error.SpawnFailed`.
- When child process exits, emit event and optionally restart if `config.auto_restart` set (future extension).
- Gracefully handle parser errors by logging and skipping invalid sequences.
- Resilience to OOM: drop oldest scrollback lines prior to panic.

## 11. Instrumentation

- Expose metrics via `phantom.metrics` (frames dropped, bytes read, scrollback usage).
- Debug logging toggle to trace terminal output <-> render.

## 12. Testing Plan

- **Unit Tests**: parser fixture coverage (CSI moves, color changes), scrollback ring overflow behavior, selection bounding cases.
- **Integration**: spawn `/bin/echo` and capture output; spawn interactive shell with scripted input verifying prompt rendering.
- **Benchmark**: measure parser throughput (bytes -> operations) and render cost per frame with 80x24 and 160x48 grids.

## 13. Documentation & Demo

- Create `examples/terminal_demo.zig` featuring a split layout with editor stub and terminal.
- Update docs:
  - `docs/WIDGET_CATALOG.md` entry with screenshots.
  - `docs/integrations/GRIM_INTEGRATION.md` section about hooking LSP diagnostics to terminal.
  - `docs/integrations/ZEKE_INTEGRATION.md` for streaming command responses.
- Record short screencast once feature stabilizes (Phase 2 deliverable).

## 14. Rollout & Risks

- **Dependencies**: requires zsync runtime for async tasks; ensure Windows builds bring in required libs.
- **Risks**: Cross-platform quirks (ConPTY vs POSIX). Mitigation: start with Linux/Mac support, guard Windows behind optional flag until stable.
- **Fallback Plan**: Provide noop terminal stub returning `error.Unsupported` if build config disables feature; downstream apps can detect and degrade gracefully.

## 15. Milestones & Timeline

1. RFC approval (this document) — Week 0.
2. PTY abstraction + parser prototype — Week 1.
3. Rendering & scrollback integrated — Week 2.
4. Input, selection, clipboard — Week 3.
5. Demo + docs + tests — Week 4.

## 16. Open Questions

- Do we need multiplexed sessions (tabs) in MVP or defer to later phase?
- Should we reuse existing open-source VT parsers via C interop (e.g., libvterm) or maintain native Zig implementation?
- How do we expose theme overrides (full custom palette vs limited SGR mapping)?

Please review and provide feedback; once accepted we will lock scope and start implementation.
