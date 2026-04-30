# Phantom Async Streaming Integration

Phantom's async streaming helpers connect background tasks to visible widgets without blocking the UI loop. The public path is `phantom.async_streaming`, backed by `phantom.async_runtime` and zsync channels internally.

## When to use it

- Streaming AI or assistant responses into `StreamingText`
- Feeding live logs into a widget
- Updating dashboards from background producers
- Moving incremental work off the UI thread while keeping rendering responsive

## Runtime model

- Start a Phantom async runtime before starting the consumer.
- Spawn producers through `phantom.async_runtime.AsyncRuntime` or the global runtime helpers.
- Treat Phantom's runtime wrapper as the stable surface. Do not assume direct raw zsync task-handle semantics in app code.

## Quick start

```zig
const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try phantom.async_runtime.AsyncRuntime.init(allocator, .{
        .worker_threads = 1,
    });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    const widget = try phantom.widgets.StreamingText.init(allocator);
    defer widget.deinit();

    const consumer = try phantom.async_streaming.AsyncStreamConsumer.init(
        allocator,
        runtime,
        widget,
    );
    defer consumer.deinit();

    try consumer.start();
    try consumer.send("Hello ");
    try consumer.send("Phantom");
    consumer.close();
    consumer.stop();
}
```

## Producer pattern

`AsyncStreamConsumer` owns the background consumer task. You can feed it from a producer spawned on the same runtime:

```zig
const ProducerTask = struct {
    fn run(alloc: std.mem.Allocator, cons: *phantom.async_streaming.AsyncStreamConsumer) !void {
        var producer = phantom.async_streaming.AsyncStreamProducer.init(alloc, cons, 25);
        try producer.streamText("streamed output", 2);
        cons.close();
    }
};

var handle = try runtime.spawn(ProducerTask.run, .{ allocator, consumer });
defer handle.deinit();
try handle.wait();
```

## API notes

- `AsyncStreamConsumer.init(...)` takes `*phantom.async_runtime.AsyncRuntime`.
- `start()` spawns the consumer task.
- `send()` copies the incoming chunk so the caller may reuse its own buffer.
- `close()` stops accepting new chunks.
- `stop()` waits for the consumer task to finish and logs any background failure.

## Guidance

- Start the runtime once during app bootstrap when a singleton runtime is enough.
- Prefer chunk sizes that match the presentation you want: single characters for typing effects, larger chunks for logs or dashboards.
- Keep UI updates on the Phantom side and use the runtime only for background work.
- If you need structured concurrency across several producers, use `phantom.async_runtime.Nursery`.

## Verification

- The current async/runtime path is verified against the Zig `0.17.0-dev` workspace baseline used by Phantom.
- Phantom's task-handle layer is aligned with the current zsync future API, so current Phantom code should use `handle.wait()` and `handle.deinit()`.

See `examples/async_streaming_demo.zig` for a larger end-to-end example.
