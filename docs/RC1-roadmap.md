# Phantom RC1 Readiness Roadmap

_Last updated: 2025-11-07_

This document turns the high-level RC1 readiness checklist into concrete workstreams with acceptance criteria, suggested owners, and sequencing guidance. It is meant to complement `TODO.md` by focusing on what must be true before tagging a **0.8.0-beta** and subsequently **RC1**.

---

## Guiding Principles

- **Release Candidate entry criteria**: zero P0 bugs, deterministic builds across Linux/macOS/Windows/WSL, published benchmarks within target envelopes, and complete documentation for the features that ship.
- **Beta vs RC1**: beta may carry "known gaps" so long as they are documented and blocked for RC1. RC1 should be feature-frozen, with only stabilization work permitted before GA.
- **Timeboxing**: assume two sprints (~6 weeks) to reach beta, and one stabilization sprint (~3 weeks) to promote to RC1, contingent on parallel staffing.
- **Local-first quality gating**: all validation happens through curated scripts; hosted CI is deferred until after RC1.

---

## Workstream A – Phase 2 Closure (RC Gate)

| Task | Description | Exit Criteria | Dependencies | Suggested Team |
| --- | --- | --- | --- | --- |
2| A2 | **Renderer Hardening** | (1) Add automated ANSI fallback parity test; (2) emit GPU/CPU telemetry hooks; (3) document stress benchmark procedure and publish baseline numbers. | `zig build test` executes new renderer tests; README/RENDERING.md lists metrics | A1 | Rendering |
| A3 | **Animation Primitives GA** | Implement enter/exit/morph primitives, ensure frame budget awareness, and document usage in `docs/TRANSITIONS.md`. | Demo widgets use new primitives; regression tests verify no frame budget overruns | Layout/Animation |

**Beta blocker**: All A-tasks must be complete before 0.8.0-beta cut. 

---

## Workstream B – Minimal Phase 3 Deliverables

| Task | Description | Exit Criteria | Notes |
| --- | --- | --- | --- |
| B1 | **Widget Parity Set** | Ensure charts, forms (input+validation), status dashboard, popovers are demo-ready with automated examples under `examples/`. | Widget Gallery runs end-to-end via the local harness; README updated | Coordinate with docs |
| B2 | **Data Plumbing Cohesion** | Finish virtualization hooks, observer lifecycle coverage, streaming retry/backoff policies; add integration tests that simulate producer failures. | `zig build test` includes new integration suite; coverage >70% for `data/` modules | Blocks RC |

**Beta goal**: All B tasks must be at least feature-complete (tests may be refined during stabilization).

---

## Workstream C – Release-Quality QA (Local-First)

| Task | Description | Exit Criteria |
| --- | --- | --- |
| C1 | **Local QA Harness** | Expand `scripts/run-tests.sh` (and companion helpers) so contributors can execute the full build + test matrix locally on Linux, macOS, and Windows/WSL. Document expected cadence for each platform. |
| C2 | **Visual Regression Harness** | Snapshot tests for core widgets/layouts (ties into Workstream A), invokable from the local harness. |
| C3 | **Coverage + Fuzzing** | Integrate coverage reporting (even sampling-based) and add fuzz targets for theme parsing, ANSI renderer, input parser, all runnable via local scripts. |

**RC entry**: All C tasks must be green for a full week with no intermittent failures.

---

## Workstream D – Docs & Packaging

| Task | Description | Exit Criteria |
| --- | --- | --- |
| D1 | **Quick-start Template** | `zig build init-phantom` or `templates/` repo providing starter app with local test scripts, lint, theming demo. |
| D2 | **Installation & Beta Guide** | Dedicated documentation covering install paths, migration notes, and "What’s new in 0.8 beta". |
| D3 | **CHANGELOG & Versioning** | Adopt Keep-a-Changelog format, document semver strategy, and produce signed tarballs or Zig package metadata via scripted local release steps. |

**Beta requirement**: D1–D2 must be done; D3 must be in progress with artifacts produced for beta.

---

## Workstream E – Performance & Stability Proof Points

| Task | Description | Exit Criteria |
| --- | --- | --- |
| E1 | **Benchmarks Publication** | Run render/layout/runtime benchmarks nightly; publish metrics in README and automation summary. |
| E2 | **Stress Suites in Automation** | Integrate stress/perf runs (e.g., `zig build bench-*`) into nightly pipeline with thresholds; alerts for regressions. |
| E3 | **Bug Scrub Cadence** | Weekly triage to maintain zero P0/P1 backlog entering RC stabilization sprint. |

---

## Timeline Proposal

| Sprint | Focus | Target Outcome |
| --- | --- | --- |
| Sprint 1 (Weeks 1–3) | Close Workstream A + begin B/C | Beta feature freeze candidate |
| Sprint 2 (Weeks 4–6) | Finish Workstream B/C; start D/E deliverables | Cut **0.8.0-beta** |
| Sprint 3 (Weeks 7–9) | Stabilization: finalize D/E; harden QA; bug fix only | Tag **0.8.0-rc1** |

---

## Tracking & Reporting

- Add these workstreams as epics in the issue tracker with measurable tasks.
- Require weekly status reviews referencing this roadmap.
- Update this document as deliverables land; RC1 cannot be declared until every exit criterion is checked.

---

## Immediate Next Actions

1. Create issues for A1–A3 and assign owners.
2. Finalize and publish the local test harness (`scripts/run-tests.sh`) playbook for Linux/macOS/Windows coverage.
3. Draft CHANGELOG template and add placeholder entry for upcoming beta.

Once these are underway, revisit the timeline and adjust scope as needed.
