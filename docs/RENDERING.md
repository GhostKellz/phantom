# Rendering Pipeline Notes

Phantom's renderer works off a double-buffered terminal backend with a few helpers that keep frame pacing smooth and avoid redundant work.

## Render cache timestamp precision

`RenderCache.put` now stamps entries with `std.time.nanoTimestamp()` instead of the millisecond helper. The higher resolution prevents two back-to-back entries from colliding in eviction order when the renderer runs faster than 1 kHz. The eviction logic still walks the cache to discard the oldest entry, it just has nanosecond precision to work with now.

## Frame pacing and sleep strategy

`FrameTimer.waitForNextFrame` has been hardened for longer frame budgets:

- The remaining frame budget is broken down into whole seconds plus nanoseconds so we feed `std.posix.nanosleep` the shape it expects.
- If we ever target Windows, we fall back to `std.time.sleep`, because `nanosleep` is POSIX-only.
- Very long sleeps are chunked so we never overflow the `u32` seconds argument accepted by `nanosleep`.

The end result is more accurate pacing on slow machines (or intentionally low FPS modes) without risking overflow in the OS syscall shim.

## Virtualized lists and buffering

`ListView` exposes `setVirtualTotal` and `setVirtualWindowStart`, and `DataListView` now keeps the backing window hydrated automatically based on viewport height plus a preload margin. When a data source fires updates, the virtual window marks itself dirty and reloads just enough rows on the next render.

Because virtualization short-circuits filtering, call `disableVirtualization` on `ListView` (or construct `DataListView` without virtualization options) if you need client-side filtering in the same view.
