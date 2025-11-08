const std = @import("std");
const phantom = @import("phantom");
const Rect = phantom.Rect;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var iterations: usize = 1_000;
    if (args.len > 1) {
        iterations = std.fmt.parseInt(usize, args[1], 10) catch iterations;
    }

    var timer = try std.time.Timer.start();
    var checksum: u64 = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var builder = phantom.layout.engine.LayoutBuilder.init(allocator);
        defer builder.deinit();

        const root = try builder.createNode();
        try builder.setRect(root, Rect{ .x = 0, .y = 0, .width = 240, .height = 120 });

        var row_handles = [_]phantom.layout.engine.LayoutNodeHandle{
            try builder.createNode(),
            try builder.createNode(),
            try builder.createNode(),
        };

        var row_children = [_]phantom.layout.engine.ChildWeight{
            .{ .handle = row_handles[0], .weight = 1.0 },
            .{ .handle = row_handles[1], .weight = 1.0 },
            .{ .handle = row_handles[2], .weight = 2.0 },
        };
        try builder.row(root, &row_children);

        // Build a simple column inside the first and third segments to stress nested solves.
        {
            var col_handles = [_]phantom.layout.engine.LayoutNodeHandle{
                try builder.createNode(),
                try builder.createNode(),
            };
            var col_children = [_]phantom.layout.engine.ChildWeight{
                .{ .handle = col_handles[0], .weight = 1.0 },
                .{ .handle = col_handles[1], .weight = 1.0 },
            };
            try builder.column(row_handles[0], &col_children);
        }

        {
            var col_handles = [_]phantom.layout.engine.LayoutNodeHandle{
                try builder.createNode(),
                try builder.createNode(),
                try builder.createNode(),
            };
            var col_children = [_]phantom.layout.engine.ChildWeight{
                .{ .handle = col_handles[0], .weight = 1.0 },
                .{ .handle = col_handles[1], .weight = 2.0 },
                .{ .handle = col_handles[2], .weight = 1.0 },
            };
            try builder.column(row_handles[2], &col_children);
        }

        var resolved = try builder.solve();
        defer resolved.deinit();

        const rect = resolved.rectOf(row_handles[2]);
        checksum += rect.width;
    }

    const elapsed_ns = timer.read();
    const elapsed_ns_f = @as(f64, @floatFromInt(elapsed_ns));
    const elapsed_ms: f64 = elapsed_ns_f / @as(f64, std.time.ns_per_ms);
    const avg_ns: f64 = elapsed_ns_f / @as(f64, @floatFromInt(iterations));

    std.debug.print("layout-sandbox iterations={} elapsed_ms={d:.2} avg_ns={d:.2} checksum={}\n", .{
        iterations,
        elapsed_ms,
        avg_ns,
        checksum,
    });
}
