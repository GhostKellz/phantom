const std = @import("std");
const phantom = @import("phantom");

const SyntaxHighlight = phantom.widgets.SyntaxHighlight;
const Rect = phantom.Rect;

const sample_zig_code =
    \\const std = @import("std");
    \\
    \\pub fn main() !void {
    \\    const stdout = std.io.getStdOut().writer();
    \\    try stdout.print("Hello, {s}!\n", .{"World"});
    \\
    \\    const numbers = [_]i32{ 1, 2, 3, 4, 5 };
    \\    var sum: i32 = 0;
    \\    for (numbers) |num| {
    \\        sum += num;
    \\    }
    \\    try stdout.print("Sum: {d}\n", .{sum});
    \\}
;

var global_app: *phantom.App = undefined;
var global_highlighter: *SyntaxHighlight = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const app_config = phantom.AppConfig{
        .tick_rate_ms = 50,
        .add_default_handler = false,
    };

    var app = try phantom.App.init(allocator, app_config);
    defer app.deinit();

    var highlighter = try SyntaxHighlight.init(allocator, sample_zig_code, phantom.grove.Languages.zig);
    defer highlighter.deinit();

    try highlighter.parseWithoutHighlighting();

    global_app = &app;
    global_highlighter = &highlighter;

    try app.event_loop.addHandler(struct {
        fn handle(event: phantom.Event) !bool {
            if (event == .key) {
                const key = event.key;
                if (key.isChar('q') or key == .ctrl_c) {
                    global_app.stop();
                    return true;
                }
            } else if (event == .tick) {
                try renderFrame();
            }
            return false;
        }
    }.handle);

    try app.run();
}

fn renderFrame() !void {
    const buffer = global_app.terminal.getBackBuffer();
    const area = phantom.Rect.init(0, 0, global_app.terminal.size.width, global_app.terminal.size.height);

    buffer.clear();

    const title_style = phantom.Style.default().withFg(phantom.Color.cyan);
    buffer.writeText(
        0,
        0,
        "Grove Syntax Highlighting Demo - Zig Code (Press 'q' to quit)",
        title_style,
    );

    const content_area = Rect{
        .x = 2,
        .y = 2,
        .width = area.width -| 4,
        .height = area.height -| 3,
    };

    global_highlighter.render(buffer, content_area);

    try global_app.terminal.flush();
}
