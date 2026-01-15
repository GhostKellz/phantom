//! Async Streaming Demo - Shows StreamingText with zsync channels
//! Perfect for AI chat interfaces, real-time logs, live data feeds

const std = @import("std");
const phantom = @import("phantom");
const async = phantom.async_runtime;

const AsyncStreamConsumer = phantom.async_streaming.AsyncStreamConsumer;
const AsyncStreamProducer = phantom.async_streaming.AsyncStreamProducer;
const StreamingText = phantom.widgets.StreamingText;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🚀 Phantom Async Streaming Demo\n", .{});
    std.debug.print("═══════════════════════════════════════\n\n", .{});

    // Initialize Phantom async runtime (zsync-backed)
    const runtime = try async.AsyncRuntime.init(allocator, .{ .worker_threads = 2 });
    defer runtime.deinit();
    try runtime.start();
    defer runtime.shutdown();

    std.debug.print("✓ Phantom async runtime initialized\n", .{});

    // Create StreamingText widget
    const widget = try StreamingText.init(allocator);

    widget.setTypingSpeed(100); // 100 characters per second
    widget.setShowCursor(true);
    widget.setCursorChar('▋');

    std.debug.print("✓ StreamingText widget created\n\n", .{});

    // Demo 1: Simulate AI chat response
    std.debug.print("📡 Demo 1: AI Chat Response Streaming\n", .{});
    std.debug.print("────────────────────────────────────────\n", .{});

    {
        const consumer = try AsyncStreamConsumer.init(allocator, runtime, widget);
        defer consumer.deinit();

        try consumer.start();

        // Simulate AI response with realistic delays
        const ai_response =
            \\AI: Let me explain async streaming in Zig...
            \\
            \\The zsync library provides a powerful async runtime
            \\with structured concurrency patterns. Key features:
            \\
            \\• Green threads with io_uring on Linux
            \\• Nursery pattern for safe task spawning
            \\• Type-safe channels for communication
            \\• Zero-cost abstractions
            \\
            \\This makes building real-time UIs incredibly easy! ✨
        ;

        var producer = AsyncStreamProducer.init(allocator, consumer, 20); // 20ms per chunk

        // Stream character by character for realistic effect
        try producer.streamText(ai_response, 3); // 3 chars at a time

        consumer.close();

        // Wait for streaming to complete
        {
            const ts = std.c.timespec{ .sec = 0, .nsec = 100 * std.time.ns_per_ms };
            _ = std.c.nanosleep(&ts, null);
        }
        consumer.stop();

        // Print the result
        std.debug.print("\n{s}\n\n", .{widget.getText()});
    }

    // Demo 2: Stream multiple responses sequentially
    std.debug.print("📡 Demo 2: Multiple Responses\n", .{});
    std.debug.print("────────────────────────────────────────\n", .{});

    {
        try widget.clear();

        const consumer = try AsyncStreamConsumer.init(allocator, runtime, widget);
        defer consumer.deinit();

        try consumer.start();

        // Spawn multiple producers
        const ProducerTask = struct {
            fn produce(alloc: std.mem.Allocator, cons: *AsyncStreamConsumer) !void {
                const messages = [_][]const u8{
                    "User: What's the weather today?\n\n",
                    "AI: Let me check... ☁️\n",
                    "It's partly cloudy with a high of 72°F.\n",
                    "Perfect weather for coding! 💻\n\n",
                    "User: Thanks!\n\n",
                    "AI: You're welcome! Happy coding! 🎉\n",
                };

                var producer = AsyncStreamProducer.init(alloc, cons, 50);

                for (messages) |msg| {
                    try producer.streamText(msg, 2);
                    {
            const ts = std.c.timespec{ .sec = 0, .nsec = 100 * std.time.ns_per_ms };
            _ = std.c.nanosleep(&ts, null);
        } // Pause between messages
                }

                cons.close();
            }
        };

        var producer_handle = try runtime.spawn(@TypeOf(ProducerTask.produce), .{ allocator, consumer });
        defer producer_handle.deinit();

        while (!producer_handle.isDone()) {
            {
            const ts = std.c.timespec{ .sec = 0, .nsec = 100 * std.time.ns_per_ms };
            _ = std.c.nanosleep(&ts, null);
        }
        }

        producer_handle.await() catch |err| {
            std.log.err("producer task failed: {s}", .{@errorName(err)});
        };

        consumer.stop();

        std.debug.print("\n{s}\n\n", .{widget.getText()});
    }

    // Demo 3: Real-time log streaming simulation
    std.debug.print("📡 Demo 3: Log Streaming Simulation\n", .{});
    std.debug.print("────────────────────────────────────────\n", .{});

    {
        try widget.clear();

        const consumer = try AsyncStreamConsumer.init(allocator, runtime, widget);
        defer consumer.deinit();

        try consumer.start();

        // Simulate log entries
        const LogTask = struct {
            fn streamLogs(_: std.mem.Allocator, cons: *AsyncStreamConsumer) !void {
                const logs = [_][]const u8{
                    "[INFO] Server starting on port 8080...\n",
                    "[INFO] Database connection established\n",
                    "[INFO] Loading configuration...\n",
                    "[WARN] Cache miss for key 'user:123'\n",
                    "[INFO] Request: GET /api/users\n",
                    "[INFO] Response: 200 OK (45ms)\n",
                    "[INFO] Request: POST /api/auth\n",
                    "[INFO] Response: 201 Created (12ms)\n",
                    "[ERROR] Connection timeout to service-A\n",
                    "[INFO] Retrying connection...\n",
                    "[INFO] Connection restored\n",
                };

                for (logs) |log| {
                    try cons.send(log);
                    {
                        const ts = std.c.timespec{ .sec = 0, .nsec = 150 * std.time.ns_per_ms };
                        _ = std.c.nanosleep(&ts, null);
                    } // 150ms between logs
                }

                cons.close();
            }
        };

        var log_handle = try runtime.spawn(@TypeOf(LogTask.streamLogs), .{ allocator, consumer });
        defer log_handle.deinit();

        while (!log_handle.isDone()) {
            {
            const ts = std.c.timespec{ .sec = 0, .nsec = 100 * std.time.ns_per_ms };
            _ = std.c.nanosleep(&ts, null);
        }
        }

        log_handle.await() catch |err| {
            std.log.err("log streaming task failed: {s}", .{@errorName(err)});
        };

        consumer.stop();

        std.debug.print("\n{s}\n\n", .{widget.getText()});
    }

    std.debug.print("════════════════════════════════════════\n", .{});
    std.debug.print("✓ All demos completed successfully!\n", .{});
    std.debug.print("\n💡 Use this pattern in Zeke for AI chat!\n\n", .{});
}
