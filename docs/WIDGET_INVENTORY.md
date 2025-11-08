# Widget Inventory – Phase 3 Baseline

This catalogue captures the current widget fleet and highlights the remaining gaps called out in the Phase 3 roadmap.

## Core primitives

| Category | Widgets | Coverage |
| --- | --- | --- |
| Text & form controls | `Text`, `RichText`, `Input`, `TextArea`, `Button`, `Spinner`, `ContextMenu`, `Dialog` | ✅ Forms largely covered (no dedicated combo/select yet) |
| Layout containers | `Block`, `Border`, `Container`, `FlexRow`/`FlexColumn`, `Stack`, `Tabs`, `ScrollView`, `ListView`, `Canvas` | ✅ |
| Lists & trees | `List`, `ListView`, `Tree`, `Table`, `Diff` | ✅ (ListView virtual windowing shipped; tree/table hybrids present) |

## Data visualization & status

| Category | Widgets | Coverage |
| --- | --- | --- |
| Charts & sparklines | `Chart`, `BarChart`, `Sparkline`, `Gauge`, `Calendar` | ✅ |
| Progress & status | `ProgressBar`, `TaskMonitor`, `SystemMonitor`, `NetworkTopology`, `StreamingText`, `StatusBar`, `ToastOverlay`, `Popover`, `DataStateIndicator`, `DataBadge`, `DataEventOverlay` | ✅ |
| Data-bound lists | `DataListView`, `dataListView` adapters | ✅ (async updates, empty/failed handling baked in; virtualization windowing now supported) |
| Dashboards & presets | `presets.DashboardLayouts`, `CommandBuilder`, `TaskMonitor`, `SystemMonitor` | ✅ (needs curated examples) |

## Domain bundles

- Package management: `UniversalPackageBrowser`, `AURDependencies`, `BlockchainPackageBrowser`
- Developer tooling: `CodeBlock`, `SyntaxHighlight`, `Diff`, `CommandBuilder`
- Observability: `SystemMonitor`, `NetworkTopology`, `TaskMonitor`

## Identified gaps (Phase 3 targets)

| Gap | Notes |
| --- | --- |
| Fine-grained list diffing | Virtualization is in place; incremental diffing to minimize adapter churn is still pending. |
| Widget inspector tooling | Need developer HUD to introspect layout/virtual windows at runtime. |

### Recently delivered

- ✅ Data binding abstractions via `data.ListDataSource` + `InMemoryListSource` with observer events.
- ✅ Dashboard showcase in `examples/data_dashboard_demo.zig` pairing `DataListView` with status widgets and overlays.
- ✅ StatusBar plus toast/popover overlays for layered notifications.
- ✅ ListView/DataListView virtualization windowing with preload controls and tests.
