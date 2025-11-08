# Changelog

All notable changes to Phantom TUI Framework will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
