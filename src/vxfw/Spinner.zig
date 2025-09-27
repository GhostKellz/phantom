//! Spinner - Loading indicator animations
//! Displays animated spinners with various styles for indicating loading states

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Style = style.Style;

const Spinner = @This();

spinner_style: SpinnerStyle,
animation_style: Style,
frame_index: u8 = 0,
is_animating: bool = true,
animation_speed_ms: u32 = 100,

pub const SpinnerStyle = enum {
    /// Classic spinning line: | / - \
    line,
    /// Dots: ⠁ ⠂ ⠄ ⡀ ⢀ ⠠ ⠐ ⠈
    dots,
    /// Braille dots: various braille patterns
    braille,
    /// Blocks: ▁ ▃ ▄ ▅ ▆ ▇ █ ▇ ▆ ▅ ▄ ▃
    blocks,
    /// Arrow: ← ↖ ↑ ↗ → ↘ ↓ ↙
    arrow,
    /// Clock: 🕐 🕑 🕒 🕓 🕔 🕕 🕖 🕗 🕘 🕙 🕚 🕛
    clock,
    /// Bouncing dots: ●○○ ○●○ ○○●
    bouncing_dots,
    /// Pulse: ●○○○ ○●○○ ○○●○ ○○○●
    pulse,
    /// Bars: ▁ ▂ ▃ ▄ ▅ ▆ ▇ █
    bars,
};

/// Get animation frames for a spinner style
pub fn getFrames(spinner_style: SpinnerStyle) []const []const u8 {
    return switch (spinner_style) {
        .line => &[_][]const u8{ "|", "/", "-", "\\" },
        .dots => &[_][]const u8{ "⠁", "⠂", "⠄", "⡀", "⢀", "⠠", "⠐", "⠈" },
        .braille => &[_][]const u8{ "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
        .blocks => &[_][]const u8{ "▁", "▃", "▄", "▅", "▆", "▇", "█", "▇", "▆", "▅", "▄", "▃" },
        .arrow => &[_][]const u8{ "←", "↖", "↑", "↗", "→", "↘", "↓", "↙" },
        .clock => &[_][]const u8{ "🕐", "🕑", "🕒", "🕓", "🕔", "🕕", "🕖", "🕗", "🕘", "🕙", "🕚", "🕛" },
        .bouncing_dots => &[_][]const u8{ "●○○", "○●○", "○○●" },
        .pulse => &[_][]const u8{ "●○○○", "○●○○", "○○●○", "○○○●", "○○●○", "○●○○" },
        .bars => &[_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" },
    };
}

/// Create a Spinner with the given style
pub fn init(spinner_style: SpinnerStyle, animation_style: Style) Spinner {
    return Spinner{
        .spinner_style = spinner_style,
        .animation_style = animation_style,
    };
}

/// Create a Spinner with custom animation speed
pub fn withSpeed(spinner_style: SpinnerStyle, animation_style: Style, speed_ms: u32) Spinner {
    return Spinner{
        .spinner_style = spinner_style,
        .animation_style = animation_style,
        .animation_speed_ms = speed_ms,
    };
}

/// Create a Spinner that starts paused
pub fn paused(spinner_style: SpinnerStyle, animation_style: Style) Spinner {
    return Spinner{
        .spinner_style = spinner_style,
        .animation_style = animation_style,
        .is_animating = false,
    };
}

/// Start the animation
pub fn start(self: *Spinner) void {
    self.is_animating = true;
}

/// Stop the animation
pub fn stop(self: *Spinner) void {
    self.is_animating = false;
}

/// Reset to first frame
pub fn reset(self: *Spinner) void {
    self.frame_index = 0;
}

/// Advance to next frame
pub fn nextFrame(self: *Spinner) void {
    if (self.is_animating) {
        const frames = getFrames(self.spinner_style);
        self.frame_index = (self.frame_index + 1) % @as(u8, @intCast(frames.len));
    }
}

/// Get current frame text
pub fn getCurrentFrame(self: *const Spinner) []const u8 {
    const frames = getFrames(self.spinner_style);
    return frames[self.frame_index % @as(u8, @intCast(frames.len))];
}

/// Get recommended size for this spinner
pub fn getRecommendedSize(self: *const Spinner) Size {
    const frames = getFrames(self.spinner_style);
    var max_width: u16 = 1;

    for (frames) |frame| {
        max_width = @max(max_width, @as(u16, @intCast(frame.len)));
    }

    return Size.init(max_width, 1);
}

/// Get the widget interface for this Spinner
pub fn widget(self: *const Spinner) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .drawFn = typeErasedDrawFn,
        .eventHandlerFn = typeErasedEventHandler,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *const Spinner = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    const self: *Spinner = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx);
}

pub fn draw(self: *const Spinner, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const width = ctx.getWidth();
    const height = ctx.getHeight();

    // Create our surface
    var surface = try vxfw.Surface.initArena(
        ctx.arena,
        self.widget(),
        Size.init(width, height)
    );

    // Get current frame
    const frame_text = self.getCurrentFrame();

    // Center the spinner in available space
    const text_width = @min(@as(u16, @intCast(frame_text.len)), width);
    const x_offset = if (width > text_width) (width - text_width) / 2 else 0;
    const y_offset = if (height > 1) height / 2 else 0;

    // Draw the spinner
    _ = surface.writeText(x_offset, y_offset, frame_text, self.animation_style);

    return surface;
}

pub fn handleEvent(self: *Spinner, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
    var commands = ctx.createCommandList();

    switch (ctx.event) {
        .tick => {
            if (self.is_animating) {
                self.nextFrame();
                try commands.append(.redraw);

                // Schedule next tick
                const tick_command = vxfw.Command{
                    .tick = .{
                        .delay_ms = self.animation_speed_ms,
                        .widget = self.widget(),
                    }
                };
                try commands.append(tick_command);
            }
        },
        .init => {
            if (self.is_animating) {
                // Start animation loop
                const tick_command = vxfw.Command{
                    .tick = .{
                        .delay_ms = self.animation_speed_ms,
                        .widget = self.widget(),
                    }
                };
                try commands.append(tick_command);
            }
        },
        else => {},
    }

    return commands;
}

/// Spinner with text label
pub const LabeledSpinner = struct {
    spinner: Spinner,
    label_text: []const u8,
    label_style: Style,
    layout: Layout = .horizontal,

    pub const Layout = enum {
        horizontal, // [spinner] text
        vertical,   // [spinner]
                   //    text
    };

    pub fn init(spinner: Spinner, label_text: []const u8, label_style: Style) LabeledSpinner {
        return LabeledSpinner{
            .spinner = spinner,
            .label_text = label_text,
            .label_style = label_style,
        };
    }

    pub fn withVerticalLayout(spinner: Spinner, label_text: []const u8, label_style: Style) LabeledSpinner {
        return LabeledSpinner{
            .spinner = spinner,
            .label_text = label_text,
            .label_style = label_style,
            .layout = .vertical,
        };
    }

    pub fn widget(self: *const LabeledSpinner) vxfw.Widget {
        return .{
            .userdata = @constCast(self),
            .drawFn = labeledDrawFn,
            .eventHandlerFn = labeledEventHandler,
        };
    }

    fn labeledDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *const LabeledSpinner = @ptrCast(@alignCast(ptr));
        const width = ctx.getWidth();
        const height = ctx.getHeight();

        var surface = try vxfw.Surface.initArena(
            ctx.arena,
            self.widget(),
            Size.init(width, height)
        );

        const frame_text = self.spinner.getCurrentFrame();

        switch (self.layout) {
            .horizontal => {
                // Draw spinner on the left, text on the right
                _ = surface.writeText(0, 0, frame_text, self.spinner.animation_style);

                const text_x = @as(u16, @intCast(frame_text.len)) + 1;
                if (text_x < width) {
                    _ = surface.writeText(text_x, 0, self.label_text, self.label_style);
                }
            },
            .vertical => {
                // Draw spinner on top, text below
                const spinner_x = if (width > frame_text.len) (width - @as(u16, @intCast(frame_text.len))) / 2 else 0;
                _ = surface.writeText(spinner_x, 0, frame_text, self.spinner.animation_style);

                if (height > 1) {
                    const text_x = if (width > self.label_text.len) (width - @as(u16, @intCast(self.label_text.len))) / 2 else 0;
                    _ = surface.writeText(text_x, 1, self.label_text, self.label_style);
                }
            },
        }

        return surface;
    }

    fn labeledEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
        const self: *LabeledSpinner = @ptrCast(@alignCast(ptr));
        return self.spinner.handleEvent(ctx);
    }
};

test "Spinner creation and animation" {
    var spinner = Spinner.init(.line, Style.default());

    // Test initial state
    try std.testing.expectEqualStrings("|", spinner.getCurrentFrame());
    try std.testing.expect(spinner.is_animating);

    // Test frame advancement
    spinner.nextFrame();
    try std.testing.expectEqualStrings("/", spinner.getCurrentFrame());

    spinner.nextFrame();
    try std.testing.expectEqualStrings("-", spinner.getCurrentFrame());

    spinner.nextFrame();
    try std.testing.expectEqualStrings("\\", spinner.getCurrentFrame());

    // Should wrap around
    spinner.nextFrame();
    try std.testing.expectEqualStrings("|", spinner.getCurrentFrame());
}

test "Spinner pause and reset" {
    var spinner = Spinner.init(.dots, Style.default());

    spinner.nextFrame();
    spinner.nextFrame();
    try std.testing.expectEqual(@as(u8, 2), spinner.frame_index);

    spinner.stop();
    spinner.nextFrame(); // Should not advance when stopped
    try std.testing.expectEqual(@as(u8, 2), spinner.frame_index);

    spinner.reset();
    try std.testing.expectEqual(@as(u8, 0), spinner.frame_index);
}

test "LabeledSpinner creation" {
    const spinner = Spinner.init(.braille, Style.default());
    const labeled = LabeledSpinner.init(spinner, "Loading...", Style.default());

    try std.testing.expectEqualStrings("Loading...", labeled.label_text);
    try std.testing.expectEqual(LabeledSpinner.Layout.horizontal, labeled.layout);
}