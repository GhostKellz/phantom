# RFC: Unified Constraint Layout Engine for Phantom TUI

**Status:** Draft  
**Authors:** Phantom team  
**Created:** 2025-11-07  
**Target Release:** v0.8.0-alpha (Phase 2)

---

## 1. Problem Statement

Phantom currently ships multiple layout primitives (`layout/constraint.zig`, `layout/flex.zig`, `layout/grid.zig`, `layout/absolute.zig`) that evolved independently. Each exports custom APIs, duplicates sizing logic, and provides limited interoperability. Downstream applications struggle to mix paradigms (e.g., Flex rows containing Grid children) and are forced to reimplement constraint logic to achieve Ratatui-level ergonomics. The lack of a unified solver also complicates transitions, theming-aware spacing, and animation sequencing.

## 2. Goals

- Deliver a single declarative layout API that composes Flex, Grid, and absolute positioning through shared constraint primitives.
- Back the API with a Cassowary-inspired solver that handles priority strengths, inequality constraints, and fractional space distribution without layout jitter.
- Support data-driven layouts (theme tokens, responsive breakpoints) and integrations with transitions/animations.
- Maintain zero-allocation hot paths where possible and expose deterministic layout results regardless of backend (CPU/GPU).

## 3. Non-Goals (Phase 2)

- Full responsive design tooling (media queries, auto-wrap) beyond simple breakpoint hooks.
- 3D transforms or GPU-only layout features.
- Accessibility tree and semantic focus order computation (scheduled for Phase 5).

## 4. Requirements & Acceptance Criteria

1. **Unified API surface**
   - Introduce `phantom.layout.ConstraintSpace` and `LayoutNode` abstractions that describe layout trees with constraints, children, and style hooks.
   - Allow embedding Flex rows/columns, Grid containers, and absolutely positioned overlays within the same layout tree.
   - Provide a builder DSL usable from Zig compile-time contexts.

2. **Cassowary-inspired solver**
   - Support required, strong, medium, and weak strengths for constraints.
   - Handle equalities (`==`), inequalities (`>=`, `<=`), and stay constraints for preferred sizes.
   - Guarantee convergence within <0.1 ms for typical UIs (≤200 nodes) on CPU.

3. **Compatibility layer**
   - Offer adapters so existing `FlexRow`, `FlexColumn`, `Grid`, and `Absolute` helpers map to the new engine without breaking current apps.
   - Provide compile-time deprecation warnings with migration helpers.

4. **Animation & theming integration**
   - Layout results expose geometry deltas for animation manager to consume.
   - Spacing, padding, and gap values may reference theme tokens (spacing scale, typography metrics).

5. **Testing & validation**
   - Unit tests for solver primitives, constraint satisfaction, and edge cases (over-constrained, under-constrained, fractional rounding).
   - Golden tests that compare layout output against Ratatui reference snapshots (±2 cell tolerance).
   - Benchmarks ensuring solver performance stays within targets.

## 5. Current State

- `layout/constraint.zig` implements a lightweight splitter with limited constraint types (length, percentage, ratio, min, max, fill). It lacks priority strengths and mixed-direction composition.
- `layout/flex.zig` and `layout/grid.zig` define custom structs with independent measurement logic; they operate on arrays of widgets rather than abstract layout nodes.
- Animations rely on transition manager heuristics to detect layout changes, without explicit geometry diffing.
- Themes expose spacing tokens but layout primitives consume raw integers, making theme-driven layouts verbose.

## 6. Design Overview

### 6.1 High-Level Concepts

- **LayoutNode**: describes a node in the layout tree, including constraint expressions for x/y/width/height, optional intrinsic size callbacks, and child list.
- **ConstraintSpace**: orchestrates solver state, registers variables (positions/sizes), and executes solve steps.
- **ConstraintExpr**: compile-time friendly DSL capturing relationships (e.g., `node.width == parent.width * 0.5 + spacing(2)`).
- **LayoutContext**: runtime context passed during layout to allow theme lookups, breakpoints, and debug instrumentation.

### 6.2 API Sketch

```zig
const layout = @import("phantom").layout;
const theme = @import("phantom").theme;

var root = layout.Node.builder(allocator)
    .direction(.vertical)
    .gap(theme.spacing.medium)
    .child(layout.Node.flex(.{
        .grow = 1,
        .basis = layout.Size.auto(),
        .children = &.{
            layout.Node.leaf(widget_a),
            layout.Node.leaf(widget_b),
        },
    }))
    .child(layout.Node.grid(.{
        .columns = &.{ layout.Track.fr(2), layout.Track.fr(1) },
        .rows = &.{ layout.Track.auto(), layout.Track.auto() },
        .areas = &.{
            layout.Area.named("header", .{ .col = .{0, 2}, .row = .{0, 1} }),
            layout.Area.named("body", .{ .col = .{0, 1}, .row = .{1, 2} }),
        },
        .children = &.{
            layout.Node.leaf(header_widget).named("header"),
            layout.Node.leaf(body_widget).named("body"),
        },
    }))
    .child(layout.Node.absolute(.{
        .anchor = .bottom_right,
        .offset = .{ .x = theme.spacing.large, .y = theme.spacing.large },
        .child = layout.Node.leaf(status_widget),
    }))
    .build();

var solver = try layout.ConstraintSpace.init(allocator, .{});
const solution = try solver.solve(root, layout.Viewport.init(area));
solver.deinit();

for (solution.assignments()) |assignment| {
    assignment.apply(); // writes rect into widget, triggers signals
}
```

### 6.3 Solver Architecture

- Use dual-simplex inspired algorithm similar to Cassowary but tuned for integer grid outputs. Represent variables as fixed-point (u32 with scale factor) to minimize rounding error.
- Maintain incremental solve capabilities: when layout tree changes slightly, reuse existing tableau to avoid full recomputation.
- Provide deterministic tie-breaking for ambiguous solutions.
- Handle intrinsic measurement by allowing leaf nodes to provide preferred width/height via callbacks executed before solve.

### 6.4 Animation Hooks

- Each solve cycle produces `LayoutAssignment` records containing previous rect, new rect, and delta.
- Expose `layout.AnimationBridge` helper that translates assignments into transition updates (e.g., slide, fade) and signals the animation manager.
- Provide optional layout tracing mode that emits assignments to telemetry for debugging.

## 7. Migration Strategy

1. **Compatibility Wrappers**: Implement `layout.flex` and `layout.grid` wrappers that construct `LayoutNode` trees under the hood to preserve existing APIs temporarily.
2. **Deprecation Window**: Emit `@compileError` suggestions by v0.9 once new API considered stable. For v0.8, show `@compileWarn` pointing users to migration guide.
3. **Migration Guide**: Publish `docs/layout/MIGRATION_V0_8.md` detailing before/after examples, theme integration, and common pitfalls.
4. **Testing**: Build sample apps that render old and new layout simultaneously to verify parity.

## 8. Performance Considerations

- Target <0.1 ms per solve for 200 nodes on 3.5 GHz CPU (baseline measured via new benchmark harness).
- Provide instrumentation counters (iterations, pivot count, degeneracy hits) accessible via telemetry.
- Support solver "lite" mode for low-power devices: degrade to greedy splitter but keep API identical.

## 9. Implementation Plan & Milestones

1. **Week 1 – RFC Approval + Prototype**
   - Finalize RFC, gather feedback from widget/layout owners.
   - Implement constraint variable/strength types and basic solver skeleton.
   - Build playground CLI (`zig build layout-sandbox`) for experimenting with constraints.

2. **Week 2 – Node Tree & Integration**
   - Implement `LayoutNode` builder and runtime solve pipeline.
   - Port FlexRow/FlexColumn using new API; verify unit tests.
   - Add theme-aware spacing helpers.

3. **Week 3 – Grid, Absolute, and Animation Bridge**
   - Port Grid/Absolute layouts, implement named areas and fractional tracks.
   - Connect to transition manager and emit geometry deltas.
   - Begin migration guide draft.

4. **Week 4 – Validation & Benchmarks**
   - Complete Ratatui parity tests and solver benchmarks.
   - Polish API docs, finalize migration guide, and mark legacy APIs with compile-time warnings.

## 10. Testing & Tooling

- Add `test/layout/constraint_solver.zig` covering constraint satisfaction scenarios.
- Leverage golden tests comparing serialized layout trees to snapshot JSON (stored under `tests/golden/layout/`).
- Create `zig build bench-layout` target measuring solve performance and logging telemetry to stdout.

## 11. Observability & Debugging

- Integrate solver stats into `phantom.metrics`, allowing `EventLoop.logMetrics` to include layout time when enabled.
- Provide optional `LAYOUT_TRACE=1` env flag to dump tableau steps for debugging.
- Hook into `std.log.scoped(.layout)` for solver warnings (over-constrained, conflicting strengths).

## 12. Risks & Mitigations

- **Solver complexity**: Start with simplified Cassowary and iterate; maintain fallback greedy mode during beta.
- **Performance regressions**: Establish baseline benchmarks before rollout; gate release on meeting targets.
- **API churn**: Ship RFC-backed design and migration guide early to collect feedback; keep wrappers until v0.9.

## 13. Open Questions

- Should we expose constraint editing at runtime (e.g., inspector) or keep compile-time only for now?
- Do we support percentage-based constraints in addition to solver relations, or translate them internally to equations?
- How do we handle widgets with asynchronous intrinsic measurement (e.g., waiting on data) without blocking layout?

## 14. References

- Cassowary Constraint Solving Algorithm — Badros & Borning (1998)
- Ratatui Layout API — https://docs.rs/ratatui/latest/ratatui/layout/index.html
- Flutter Layout Constraints — https://docs.flutter.dev/ui/layout/constraints
- AutoLayout for iOS — Apple Developer Documentation

## 15. Decision Timeline & Approvals

- **Reviewers**: Layout and rendering maintainers, animation lead, theming lead.
- **Review window**: 2025-11-07 → 2025-11-14.
- **Acceptance**: Two maintainer approvals plus verification that performance targets are realistic.

Once approved, work can begin on the Week 1 prototype tasks outlined above.
