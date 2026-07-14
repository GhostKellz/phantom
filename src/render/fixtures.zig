//! Backend-neutral rendering fixtures.
//!
//! Each fixture describes a small scene using only the public `CellBuffer`
//! drawing API, paired with the exact byte output produced by the reference CPU
//! renderer. The scene description is backend-independent: a future GPU (or any
//! other) backend can render the same fixtures and compare its output against
//! `expected_cpu` (or against `renderCpu` at runtime) to prove output parity
//! with the CPU renderer.

const std = @import("std");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const CellBuffer = @import("../rendering/CellBuffer.zig").CellBuffer;
const renderer_mod = @import("renderer.zig");

const Size = geometry.Size;
const Style = style.Style;
const ArrayList = std.array_list.Managed;

/// A single backend-neutral rendering scenario.
pub const Fixture = struct {
    /// Stable identifier for diagnostics and golden lookup.
    name: []const u8,
    /// Surface dimensions the scene is drawn into.
    size: Size,
    /// Populates a fresh cell buffer using the public drawing API.
    build: *const fn (*CellBuffer) anyerror!void,
    /// Byte output of the reference CPU renderer for this scene, captured with
    /// the cursor hidden so the sequence is deterministic.
    expected_cpu: []const u8,
};

/// Render a fixture through the reference CPU renderer and return owned bytes.
/// New backends should render the same fixture and compare against this output.
pub fn renderCpu(allocator: std.mem.Allocator, fixture: Fixture) ![]u8 {
    var output = ArrayList(u8).init(allocator);
    defer output.deinit();

    var renderer = try renderer_mod.Renderer.init(allocator, .{
        .size = fixture.size,
        .target = .{ .buffer = &output },
        .backend = .cpu,
        .cursor_visible = false,
    });
    defer renderer.deinit();

    const frame = renderer.beginFrame();
    try fixture.build(frame);
    try renderer.flush();

    return output.toOwnedSlice();
}

fn buildAsciiLine(buf: *CellBuffer) !void {
    _ = try buf.writeText(0, 0, "Hi", Style.default());
}

fn buildStyledSpan(buf: *CellBuffer) !void {
    _ = try buf.writeText(0, 0, "A", Style.default().withBold());
    _ = try buf.writeText(1, 0, "B", Style.default());
}

fn buildWideGrapheme(buf: *CellBuffer) !void {
    _ = try buf.writeText(0, 0, "世", Style.default());
}

/// The registered fixtures. Extend this list as new reference scenes are added.
pub const all = [_]Fixture{
    .{
        .name = "ascii_line",
        .size = Size.init(4, 1),
        .build = buildAsciiLine,
        .expected_cpu = "\x1b[1;1H\x1b[0mHi  \x1b[0m",
    },
    .{
        .name = "styled_span",
        .size = Size.init(2, 1),
        .build = buildStyledSpan,
        .expected_cpu = "\x1b[1;1H\x1b[0m\x1b[1mA\x1b[0mB\x1b[0m",
    },
    .{
        .name = "wide_grapheme",
        .size = Size.init(4, 1),
        .build = buildWideGrapheme,
        // A width-2 grapheme plus its skipped continuation, then two blanks.
        .expected_cpu = "\x1b[1;1H\x1b[0m世  \x1b[0m",
    },
};

test "cpu renderer matches backend-neutral fixtures" {
    const allocator = std.testing.allocator;
    for (all) |fixture| {
        const bytes = try renderCpu(allocator, fixture);
        defer allocator.free(bytes);
        std.testing.expectEqualStrings(fixture.expected_cpu, bytes) catch |err| {
            std.debug.print("fixture '{s}' output mismatch\n", .{fixture.name});
            return err;
        };
    }
}
