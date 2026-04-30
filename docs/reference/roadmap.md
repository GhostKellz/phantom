# Phantom Roadmap

This document captures medium-term Phantom planning without prerelease version labels.

## Current Focus Areas

### Layout And Rendering

- harden renderer behavior across supported terminal setups
- keep animation primitives within frame budgets
- improve documentation and examples for transitions and layout composition

### Widget Quality

- improve the strongest default widget set for real application use
- curate demos around the most credible and maintainable widgets
- keep advanced and experimental widgets clearly labeled

### Data And Async Cohesion

- tighten data source lifecycle handling
- improve streaming retry/backoff and failure behavior
- expand integration coverage for dashboard-style flows

### Documentation And Packaging

- keep the recommended path centered on `App` + widgets + `layout.engine`
- maintain accurate install and verification guidance
- keep docs organized under lowercase paths, with the exception of `docs/README.md`

### Performance And Stability

- continue publishing meaningful render/layout/runtime benchmark flows
- keep local verification simple and reliable
- reduce drift between demos, docs, and the actually supported surface

## Immediate Next Actions

1. Keep polishing the flagship docs and examples.
2. Decide which demos are canonical and which should be demoted.
3. Continue simplifying the public surface around the strongest user path.
