# Phantom Async Streaming Integration

Comprehensive async streaming support for real-time text updates using zsync channels.

## 🎯 Overview

The Phantom async streaming integration provides a **production-ready** solution for streaming text content to TUI widgets. Perfect for:

- **AI Chat Interfaces** - Stream LLM responses character-by-character
- **Real-time Logs** - Tail log files with live updates
- **Data Feeds** - Display streaming metrics, events, or notifications
- **Progress Indicators** - Show step-by-step progress with detailed output

## 🏗️ Architecture

```
┌──────────────┐      ┌────────────────┐      ┌─────────────────┐
│   Producer   │─────▶│ Zsync Channel  │─────▶│ Stream Consumer │
│  (Any Task)  │      │  (Unbounded)   │      │  (Async Task)   │
└──────────────┘      └────────────────┘      └─────────────────┘
                                                       │
                                                       ▼
                                              ┌─────────────────┐
                                              │ StreamingText   │
                                              │    Widget       │
                                              └─────────────────┘
```

### Key Components

1. **`AsyncStreamConsumer`** - Manages the channel and feeds chunks to the widget
2. **`AsyncStreamProducer`** - Helper for common streaming patterns
3. **`StreamingText`** Widget - Renders streaming text with typing effects

## 🚀 Quick Start

### Basic Usage

```zig
const phantom = @import("phantom");
const zsync = @import("zsync");

// 1. Create zsync runtime
const runtime = try zsync.Runtime.init(allocator, .{
    .execution_model = .blocking,
});
defer runtime.deinit();

// 2. Create StreamingText widget
const widget = try phantom.widgets.StreamingText.init(allocator);
defer widget.deinit();

// 3. Create async stream consumer
const consumer = try phantom.async_streaming.AsyncStreamConsumer.init(
    allocator,
    runtime,
    widget,
);
defer consumer.deinit();

// 4. Start consuming (spawns async task)
try consumer.start();

// 5. Send chunks from any task
try consumer.send("Hello ");
try consumer.send("World!");

// 6. Close and stop when done
consumer.close();
consumer.stop();
```

### AI Chat Response Example

```zig
const consumer = try AsyncStreamConsumer.init(allocator, runtime, widget);
try consumer.start();

// Spawn producer task
const ProducerTask = struct {
    fn stream(alloc: std.mem.Allocator, cons: *AsyncStreamConsumer) !void {
        const ai_response =
            \\AI: Here's how to implement async patterns in Zig:
            \\
            \\1. Use zsync for structured concurrency
            \\2. Channels for type-safe communication
            \\3. Nursery pattern for safe task spawning
            \\
            \\That's it! 🚀
        ;

        var producer = AsyncStreamProducer.init(alloc, cons, 30); // 30ms delay
        try producer.streamText(ai_response, 2); // 2 chars at a time

        cons.close();
    }
};

_ = try runtime.spawn(ProducerTask.stream, .{ allocator, consumer });

// Consumer runs in background, widget updates automatically
```

### Real-time Log Streaming

```zig
const consumer = try AsyncStreamConsumer.init(allocator, runtime, widget);
try consumer.start();

const LogTask = struct {
    fn streamLogs(alloc: std.mem.Allocator, cons: *AsyncStreamConsumer) !void {
        const logs = [_][]const u8{
            "[INFO] Server started\n",
            "[WARN] Cache miss\n",
            "[ERROR] Connection timeout\n",
        };

        for (logs) |log| {
            try cons.send(log);
            std.posix.nanosleep(0, 100 * std.time.ns_per_ms); // 100ms delay
        }

        cons.close();
    }
};

_ = try runtime.spawn(LogTask.streamLogs, .{ allocator, consumer });
```

## 📚 API Reference

### `AsyncStreamConsumer`

```zig
pub const AsyncStreamConsumer = struct {
    /// Initialize consumer
    pub fn init(
        allocator: std.mem.Allocator,
        runtime: *zsync.Runtime,
        widget: *StreamingText,
    ) !*AsyncStreamConsumer

    /// Start consuming chunks (spawns async task)
    pub fn start(self: *AsyncStreamConsumer) !void

    /// Send a chunk to the stream (copies data)
    pub fn send(self: *AsyncStreamConsumer, chunk: []const u8) !void

    /// Close the stream (no more chunks accepted)
    pub fn close(self: *AsyncStreamConsumer) void

    /// Stop consuming and cleanup
    pub fn stop(self: *AsyncStreamConsumer) void

    /// Cleanup all resources
    pub fn deinit(self: *AsyncStreamConsumer) void
};
```

### `AsyncStreamProducer`

```zig
pub const AsyncStreamProducer = struct {
    /// Initialize producer with delay
    pub fn init(
        allocator: std.mem.Allocator,
        consumer: *AsyncStreamConsumer,
        delay_ms: u64,
    ) AsyncStreamProducer

    /// Stream text with chunking (character or word based)
    pub fn streamText(
        self: *AsyncStreamProducer,
        text: []const u8,
        chunk_size: usize,
    ) !void

    /// Stream lines from a file
    pub fn streamFile(
        self: *AsyncStreamProducer,
        file_path: []const u8,
    ) !void

    /// Stream with custom generator
    pub fn streamWithGenerator(
        self: *AsyncStreamProducer,
        comptime generator_fn: anytype,
        context: anytype,
    ) !void
};
```

### `StreamingText` Widget

```zig
pub const StreamingText = struct {
    /// Start streaming mode
    pub fn startStreaming(self: *StreamingText) void

    /// Stop streaming mode
    pub fn stopStreaming(self: *StreamingText) void

    /// Add chunk to buffer (called by consumer)
    pub fn addChunk(self: *StreamingText, chunk: []const u8) !void

    /// Set typing speed (characters per second)
    pub fn setTypingSpeed(self: *StreamingText, speed: u64) void

    /// Enable/disable cursor display
    pub fn setShowCursor(self: *StreamingText, show: bool) void

    /// Set cursor character
    pub fn setCursorChar(self: *StreamingText, cursor_char: u21) void

    /// Set callbacks
    pub fn setOnChunk(self: *StreamingText, callback: OnChunkFn) void
    pub fn setOnComplete(self: *StreamingText, callback: OnCompleteFn) void
};
```

## 🎨 Configuration Options

### StreamingText Widget Options

```zig
widget.setTypingSpeed(100);          // 100 chars/second
widget.setShowCursor(true);           // Show blinking cursor
widget.setCursorChar('▋');            // Set cursor character
widget.setAutoScroll(true);           // Auto-scroll to bottom
widget.setWordWrap(true);             // Enable word wrapping
widget.setTextStyle(style);           // Set text style
widget.setStreamingStyle(stream_style); // Style while streaming
widget.setCursorStyle(cursor_style);  // Cursor style
```

### Callbacks

```zig
// Called when each chunk is received
widget.setOnChunk(struct {
    fn onChunk(w: *StreamingText, chunk: []const u8) void {
        std.debug.print("Received: {s}\n", .{chunk});
    }
}.onChunk);

// Called when streaming completes
widget.setOnComplete(struct {
    fn onComplete(w: *StreamingText) void {
        std.debug.print("Streaming done!\n", .{});
    }
}.onComplete);
```

## 💡 Best Practices

### 1. **Chunk Size Selection**

- **Character-by-character** (1-3 chars): Realistic typing effect for AI chat
- **Word-by-word** (5-10 chars): Faster streaming while maintaining readability
- **Line-by-line** (full lines): Log files and structured output

### 2. **Delay Tuning**

```zig
// Fast typing (AI chat)
var producer = AsyncStreamProducer.init(allocator, consumer, 20); // 20ms

// Medium speed (general streaming)
var producer = AsyncStreamProducer.init(allocator, consumer, 50); // 50ms

// Slow, deliberate (emphasis)
var producer = AsyncStreamProducer.init(allocator, consumer, 100); // 100ms
```

### 3. **Memory Management**

The consumer **automatically copies** chunks, so producers can reuse buffers:

```zig
// ✅ GOOD: Reuse buffer
var buffer: [256]u8 = undefined;
for (items) |item| {
    const chunk = try std.fmt.bufPrint(&buffer, "{s}\n", .{item});
    try consumer.send(chunk); // Copied internally
}

// ❌ BAD: Don't allocate per chunk
for (items) |item| {
    const chunk = try allocator.alloc(u8, item.len);
    try consumer.send(chunk); // Wastes memory!
    allocator.free(chunk);
}
```

### 4. **Error Handling**

```zig
const consumer = try AsyncStreamConsumer.init(allocator, runtime, widget);
errdefer consumer.deinit(); // Cleanup on error

try consumer.start();
errdefer consumer.stop(); // Stop task on error

// ... streaming logic ...

consumer.close();
consumer.stop();
consumer.deinit();
```

## 🔧 Advanced Patterns

### Custom Generator

```zig
const Generator = struct {
    index: usize = 0,
    items: []const []const u8,

    fn next(self: *Generator) ?[]const u8 {
        if (self.index >= self.items.len) return null;
        defer self.index += 1;
        return self.items[self.index];
    }
};

var gen = Generator{ .items = &[_][]const u8{ "one", "two", "three" } };
var producer = AsyncStreamProducer.init(allocator, consumer, 50);
try producer.streamWithGenerator(Generator.next, &gen);
```

### File Tailing

```zig
pub fn tailFile(
    allocator: std.mem.Allocator,
    consumer: *AsyncStreamConsumer,
    file_path: []const u8,
) !void {
    var producer = AsyncStreamProducer.init(allocator, consumer, 0);
    try producer.streamFile(file_path);
}
```

### Network Stream Integration

```zig
// Integrate with zsync HTTP client
const response_stream = try http_client.get("/api/stream");
while (try response_stream.next()) |chunk| {
    try consumer.send(chunk);
}
consumer.close();
```

## 🧪 Testing

Run the example to see it in action:

```bash
zig build
./zig-out/bin/async_streaming_demo
```

## 📖 Examples

See `/examples/async_streaming_demo.zig` for complete examples of:

1. AI chat response streaming
2. Multiple sequential responses
3. Real-time log streaming

## 🔗 Integration with Zeke

To use in Zeke for AI chat:

```zig
// In Zeke's session module:
const streaming_widget = try phantom.widgets.StreamingText.init(allocator);
const consumer = try phantom.async_streaming.AsyncStreamConsumer.init(
    allocator,
    runtime,
    streaming_widget,
);

try consumer.start();

// When AI response arrives:
try consumer.send(ai_response_chunk);

// When done:
consumer.close();
```

## 🎯 Performance

- **Zero-copy channel**: Chunks are only copied once (from sender to channel)
- **Non-blocking**: Producer and consumer run asynchronously
- **Memory efficient**: Bounded memory usage with channel back-pressure
- **Thread-safe**: All operations are thread-safe via zsync channels

## 📝 License

Part of the Phantom TUI framework.

---

**Built with ❤️ using zsync v0.7.0 and Phantom v0.7.1**
