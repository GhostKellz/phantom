# Changelog

All notable changes to Phantom TUI Framework will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.8.9] - 2026-07-13

### Added
- Validated the Windows ConPTY (pseudoconsole) backend on a real Windows host (Zig `0.17.0-dev.1397`): `Session.spawn` attaches the child to the pseudoconsole via `CreatePseudoConsole` + `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`, its rendered output reaches the read pipe, and the child exit code propagates
- Added `src/conpty_smoke_test.zig` and a Windows-only `zig build test-conpty` step that spawns `cmd.exe` through the pseudoconsole, captures the marker written to `CONOUT$`, and asserts the exit code propagates

### Changed
- Ported the build script to the Zig `0.17.0-dev.857+2b2b85c5f` declarative configurer/maker build system
- Raised `minimum_zig_version` to `0.17.0-dev.857+2b2b85c5f`
- Rewrote `src/async/runtime.zig` for the `zsync` `0.8.3` `std.Io` rebase
- Updated `zsync` to `v0.8.3`
- Updated `gcode` to `v0.1.5`
- Updated `zfont` to `v0.1.7`
- Updated `zigzag` to `v0.1.8`
- Updated `grove` to `v0.2.11`
- Migrated `std.ArrayList` usage to the unmanaged API (explicit allocator on `append`/`deinit`) across widgets, layout, rendering, and unicode modules
- Updated `std.Io`, allocator, and formatting call sites throughout the widget, event, theme, and rendering code for the current standard library
- Wired `std.testing.refAllDecls(@This())` into the root test block so every module is type-checked and tested

### Fixed
- Fixed a crash in fuzzy search: `SearchResult.deinit` freed `self.text`, which only borrows the caller's candidate slice (often a read-only string literal), causing an invalid free / ABRT; it now frees only the heap-owned `highlight_positions`
- Fixed the Windows ConPTY child stdio not binding to the pseudoconsole: `src/terminal/pty/windows.zig` set `STARTF_USESTDHANDLES` with zeroed (NULL) standard handles, which overrode the pseudoconsole's automatic stdio binding and detached the child's output so it never reached the render pipe; removed the flag so the `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE` binding takes effect

### Removed
- Deleted the obsolete `src/layout/migration.zig` shim and its export

### Verification
- Verified `zig build`
- Verified `zig build test` (all tests pass, 0 failures)
- Verified `zig build test -Dterminal-widget=true` (all tests pass, 0 failures)
- Verified the Windows ConPTY smoke test on a real Windows host (`zig build test-conpty` — spawn, capture, exit-code propagation all pass)

---

## [0.8.7] - 2026-04-30

### Added
- `SECURITY.md`
- Build-time translated-C PTY bindings for the Unix terminal backend instead of source-level `@cImport`
- Curated widget convenience APIs including `Block.setTitle`, `Block.setBorderStyle`, `Block.setStyle`, and `ScrollbarState.init`
- Stronger widget coverage with terminal scrollback and idle-placeholder tests plus dashboard preset coverage
- A real PTY-backed terminal session integration example and a more focused curated feature showcase demo

### Changed
- Verified Phantom against the current Zig `0.17.0-dev` workspace baseline
- Updated `zsync` to `v0.8.0`
- Updated `gcode` to `v0.1.2`
- Updated `zfont` to `v0.1.4`
- Updated `zigzag` to `v0.1.4`
- Updated `flash` to `v0.3.4`
- Updated `grove` to `v0.2.7`
- Removed the archived `zontom` dependency and related stale public surface
- Narrowed the default build/install graph so `zig build` no longer installs optional demos and benchmarks by default
- Kept terminal widget support opt-in in presets while preserving explicit `-Dterminal-widget=true` enablement
- Curated the root export surface to better match the intended public API
- Reworked the README around the current supported path, current package metadata, curated demos, theming, and support expectations
- Added routed workspace polish including tab overflow windowing, per-line editor diagnostics, richer terminal mouse forwarding, and real filesystem-backed workspace file open/save in the canonical demo

### Fixed
- Restored the main build and test path on the current Zig baseline
- Fixed stale fuzz-test callback usage in `src/main.zig`
- Fixed `scripts/run-tests.sh` to use valid current optimize flags
- Migrated Phantom PTY integration away from removed `@cImport` patterns
- Updated parts of the async and terminal session path for current `zsync` and Zig call conventions
- Fixed the supported workspace path so `examples/workspace_demo.zig` reflects real file-backed editor behavior rather than seeded in-memory buffers

### Documentation
- Reorganized docs into a cleaner structure under `docs/`
- Kept `docs/README.md` as the uppercase entry point and normalized the rest of the docs tree to lowercase kebab-case names
- Replaced stale high-drift docs with shorter current references across getting started, reference, guides, architecture, and widgets sections
- Removed stale version references and prerelease framing from the roadmap and package guidance
- Tightened workspace and API docs to reflect the current supported editor, terminal, and stateful-widget path more honestly

### Verification
- Verified `zig build`
- Verified `zig build test`
- Verified `zig build -Dterminal-widget=true demo-workspace`
- Verified `scripts/run-tests.sh`

---

## [0.8.0-rc8] - 2025-11-08

### 🎯 Release Focus
This release candidate focuses on **Zig 0.16.0-dev compatibility** and **production readiness**. All 44 build steps now pass, and the test suite is fully green.

### ✨ Added
- Full Zig 0.16.0-dev support (0.16.0-dev.1225+bf9082518)
- New layout.engine API with constraint solver
- Theme hot-reload with file watching
- Enhanced event system with priority queue
- 22 working demo applications

### 🔄 Changed (Zig 0.16 API Migration)
- ArrayList: std.array_list.Unmanaged → std.ArrayListUnmanaged
- Builtins: std.math.{max,min,round} → @max, @min, @round
- File I/O: file.readToEndAlloc() → dir.readFileAlloc()
- Time API: mtime.sec/nsec → mtime.nanoseconds
- Sort: std.sort.sort → std.mem.sort
- Error sets: Removed Interrupted, OperationAborted

### 🐛 Fixed
- Animation HashMap.retain() replacement
- Event loop nanosleep error handling
- Theme manager iterator const issues
- StatusBar render visibility
- Type inference edge cases

### 📚 Documentation
- Comprehensive Zig API migration guide
- Sprint planning for v0.8.0 production readiness
- Quick-start implementation guide

### ⚡ Performance
- Layout benchmark: ~77μs average (1000 iterations)
- Zero memory leaks in core functionality
- 44/44 build steps passing

### 🚨 Breaking Changes
- Minimum Zig version: 0.16.0-dev
- Layout.split() deprecated (still functional, see migration guide)

---

See SPRINT_V0.8.0_RC.md for production readiness roadmap.
