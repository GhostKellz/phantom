# Widget Inventory

This catalogue groups Phantom widgets by how they should be presented to users today.

## Canonical Surface

- Core text and input: `Text`, `Paragraph`, `Block`, `List`, `Button`, `Input`, `TextArea`, `Border`, `Spinner`, `Scrollbar`
- Data and status: `ProgressBar`, `Table`, `TaskMonitor`, `ThemeTokenDashboard`, `DataListView`, `DataStateIndicator`, `DataBadge`, `DataEventOverlay`
- Composition: `Container`, `ScrollView`, `ListView`, `layout.engine`

These are the widgets and APIs that should anchor the README, integration guide, and canonical demos.

## Supported Advanced Surface

| Category | Widgets | Coverage |
| --- | --- | --- |
| Text & form controls | `RichText`, `ContextMenu`, `Dialog` | Useful but not the primary onboarding widgets |
| Layout containers | `FlexRow`/`FlexColumn`, `Stack`, `Tabs`, `Canvas` | Advanced composition tools |
| Lists & trees | `Tree`, `Diff` | Supported specialized viewers |

## Visualization And Specialist Widgets

| Category | Widgets | Coverage |
| --- | --- | --- |
| Charts & sparklines | `Chart`, `BarChart`, `Sparkline`, `Gauge`, `Calendar` | Strong dashboard story |
| Progress & status | `SystemMonitor`, `NetworkTopology`, `StreamingText`, `StatusBar`, `ToastOverlay`, `Popover` | Supported advanced status/overlay widgets |
| Data-bound lists | `DataListView`, `dataListView` adapters | Strong data-dashboard support |
| Dashboards & presets | `presets.DashboardLayouts`, `CommandBuilder`, `TaskMonitor`, `SystemMonitor` | Useful when paired with curated examples |

## Specialized Surface

- Package management: `UniversalPackageBrowser`, `AURDependencies`, `BlockchainPackageBrowser`
- Developer tooling: `CodeBlock`, `SyntaxHighlight`, `Diff`, `CommandBuilder`
- Observability: `SystemMonitor`, `NetworkTopology`, `TaskMonitor`
- Terminal: `Terminal`, `terminal_session.Manager` when built with `-Dterminal-widget=true`

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
