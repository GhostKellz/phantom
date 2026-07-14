//! Shared conventions for widget interaction-state styling.
//!
//! Interactive widgets (button, input, textarea, pickers, ...) each track a set
//! of boolean interaction flags and derive a per-state `Style`. This module
//! centralizes that convention so widgets present consistent visual feedback:
//!
//!   * `StateFlags`  — the interaction/validation booleans a widget tracks.
//!   * `VisualState` — the single winning state after precedence resolution.
//!   * `StateStyles` — a full normal/hover/focused/pressed/disabled/invalid set
//!                     with theme-aware and theme-free default constructors.
//!   * `drawFocusRing` — draw a consistent focus ring (border box) around a rect.

const std = @import("std");
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const theme_mod = @import("../theme/mod.zig");

const Rect = geometry.Rect;
const Style = style.Style;
const Color = style.Color;

/// Interaction/validation state a widget can present, in ascending visual
/// precedence. `disabled` and `invalid` override interaction feedback.
pub const VisualState = enum { normal, focused, hovered, pressed, invalid, disabled };

/// The boolean interaction flags most widgets track. `resolve` collapses them
/// to a single `VisualState` so every widget agrees on which state wins when
/// several are active at once.
pub const StateFlags = struct {
    hovered: bool = false,
    focused: bool = false,
    pressed: bool = false,
    disabled: bool = false,
    /// Set when the widget's current content fails validation.
    invalid: bool = false,

    /// Precedence: disabled > invalid > pressed > hovered > focused > normal.
    /// Disabled wins outright (a disabled control ignores interaction), and a
    /// validation error is surfaced ahead of transient hover/focus feedback.
    pub fn resolve(self: StateFlags) VisualState {
        if (self.disabled) return .disabled;
        if (self.invalid) return .invalid;
        if (self.pressed) return .pressed;
        if (self.hovered) return .hovered;
        if (self.focused) return .focused;
        return .normal;
    }
};

/// A full set of per-state styles plus a resolver from `StateFlags`.
pub const StateStyles = struct {
    normal: Style = Style.default(),
    hovered: Style = Style.default(),
    focused: Style = Style.default(),
    pressed: Style = Style.default(),
    disabled: Style = Style.default(),
    invalid: Style = Style.default(),

    /// The concrete style for an already-resolved `VisualState`.
    pub fn styleFor(self: StateStyles, state: VisualState) Style {
        return switch (state) {
            .normal => self.normal,
            .hovered => self.hovered,
            .focused => self.focused,
            .pressed => self.pressed,
            .disabled => self.disabled,
            .invalid => self.invalid,
        };
    }

    /// Resolve interaction flags to their winning style in one step.
    pub fn resolveStyle(self: StateStyles, flags: StateFlags) Style {
        return self.styleFor(flags.resolve());
    }

    /// Theme-free defaults using basic ANSI colors. Used when no theme is
    /// registered so widgets still look reasonable out of the box.
    pub fn conventionalDefaults() StateStyles {
        const base = Style.default();

        var disabled = base.withFg(Color.bright_black);
        disabled.attributes.dim = true;

        var invalid = base.withFg(Color.red);
        invalid.attributes.underline = true;

        return .{
            .normal = base,
            .hovered = base.withBg(Color.blue),
            .focused = base.withUnderline(),
            .pressed = base.withBg(Color.cyan).withBold(),
            .disabled = disabled,
            .invalid = invalid,
        };
    }

    /// Derive a state-style set from the active theme's semantic tokens, falling
    /// back to `conventionalDefaults` when no theme is registered. Mappings:
    ///   hovered  -> background_element highlight
    ///   focused  -> border_active fg + underline
    ///   pressed  -> secondary bg + bold
    ///   disabled -> text_muted fg + dim
    ///   invalid  -> error_color fg + underline
    pub fn fromActiveTheme() StateStyles {
        const manager = theme_mod.ThemeManager.global() orelse return conventionalDefaults();
        const theme = manager.getActiveTheme();
        const c = theme.colors;

        const normal = Style{ .fg = c.text, .bg = c.background };

        var hovered = normal;
        hovered.bg = c.background_element;

        var focused = normal;
        focused.fg = c.border_active;
        focused.attributes.underline = true;

        var pressed = normal;
        pressed.bg = c.secondary;
        pressed.attributes.bold = true;

        var disabled = normal;
        disabled.fg = c.text_muted;
        disabled.attributes.dim = true;

        var invalid = normal;
        invalid.fg = c.error_color;
        invalid.attributes.underline = true;

        return .{
            .normal = normal,
            .hovered = hovered,
            .focused = focused,
            .pressed = pressed,
            .disabled = disabled,
            .invalid = invalid,
        };
    }
};

/// Draw a focus ring (single-line border box) just inside `area` using
/// `ring_style`. No-op for areas too small to hold a border. Callers typically
/// invoke this when a widget is focused to give consistent focus affordance.
pub fn drawFocusRing(buffer: *Buffer, area: Rect, ring_style: Style) void {
    if (area.width < 2 or area.height < 2) return;

    const right = area.x + area.width - 1;
    const bottom = area.y + area.height - 1;

    var x = area.x;
    while (x <= right) : (x += 1) {
        buffer.setCell(x, area.y, Cell.init('─', ring_style));
        buffer.setCell(x, bottom, Cell.init('─', ring_style));
    }
    var y = area.y;
    while (y <= bottom) : (y += 1) {
        buffer.setCell(area.x, y, Cell.init('│', ring_style));
        buffer.setCell(right, y, Cell.init('│', ring_style));
    }
    buffer.setCell(area.x, area.y, Cell.init('┌', ring_style));
    buffer.setCell(right, area.y, Cell.init('┐', ring_style));
    buffer.setCell(area.x, bottom, Cell.init('└', ring_style));
    buffer.setCell(right, bottom, Cell.init('┘', ring_style));
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

const testing = std.testing;
const phantom = @import("../root.zig");

test "StateFlags precedence: disabled wins over everything" {
    const flags = StateFlags{ .hovered = true, .focused = true, .pressed = true, .invalid = true, .disabled = true };
    try testing.expectEqual(VisualState.disabled, flags.resolve());
}

test "StateFlags precedence: invalid beats interaction states" {
    const flags = StateFlags{ .hovered = true, .focused = true, .pressed = true, .invalid = true };
    try testing.expectEqual(VisualState.invalid, flags.resolve());
}

test "StateFlags precedence: pressed > hovered > focused > normal" {
    try testing.expectEqual(VisualState.pressed, (StateFlags{ .pressed = true, .hovered = true, .focused = true }).resolve());
    try testing.expectEqual(VisualState.hovered, (StateFlags{ .hovered = true, .focused = true }).resolve());
    try testing.expectEqual(VisualState.focused, (StateFlags{ .focused = true }).resolve());
    try testing.expectEqual(VisualState.normal, (StateFlags{}).resolve());
}

test "StateStyles.resolveStyle maps flags to the winning style" {
    const styles = StateStyles.conventionalDefaults();

    const disabled_style = styles.resolveStyle(.{ .disabled = true, .hovered = true });
    try testing.expect(disabled_style.attributes.dim);

    const invalid_style = styles.resolveStyle(.{ .invalid = true });
    try testing.expect(invalid_style.attributes.underline);
    try testing.expect(std.meta.activeTag(invalid_style.fg.?) == .red);

    const normal_style = styles.resolveStyle(.{});
    try testing.expect(normal_style.eq(Style.default()));
}

test "StateStyles.fromActiveTheme falls back without a theme" {
    // No global theme registered in the test process: should not crash and
    // should return the conventional defaults.
    const styles = StateStyles.fromActiveTheme();
    try testing.expect(styles.disabled.attributes.dim);
}

test "drawFocusRing draws a border box" {
    var buffer = try Buffer.init(testing.allocator, phantom.Size.init(6, 4));
    defer buffer.deinit();

    drawFocusRing(&buffer, Rect.init(0, 0, 6, 4), Style.default());

    try testing.expectEqual(@as(u21, '┌'), buffer.getCell(0, 0).?.char);
    try testing.expectEqual(@as(u21, '┐'), buffer.getCell(5, 0).?.char);
    try testing.expectEqual(@as(u21, '└'), buffer.getCell(0, 3).?.char);
    try testing.expectEqual(@as(u21, '┘'), buffer.getCell(5, 3).?.char);
    try testing.expectEqual(@as(u21, '─'), buffer.getCell(2, 0).?.char);
    try testing.expectEqual(@as(u21, '│'), buffer.getCell(0, 1).?.char);
    // Interior stays untouched.
    try testing.expectEqual(@as(u21, ' '), buffer.getCell(2, 1).?.char);
}

test "drawFocusRing is a no-op for degenerate areas" {
    var buffer = try Buffer.init(testing.allocator, phantom.Size.init(4, 4));
    defer buffer.deinit();

    drawFocusRing(&buffer, Rect.init(0, 0, 1, 3), Style.default());
    // Nothing drawn: cells remain blank.
    try testing.expectEqual(@as(u21, ' '), buffer.getCell(0, 0).?.char);
}
