//! Theme system for Phantom TUI
const std = @import("std");
const style = @import("style.zig");

const Color = style.Color;
const Style = style.Style;
const Attributes = style.Attributes;

/// Theme definition for consistent styling across the application
pub const Theme = struct {
    // Base colors
    primary: Color = Color.blue,
    secondary: Color = Color.cyan,
    accent: Color = Color.green,
    
    // Semantic colors
    success: Color = Color.green,
    warning: Color = Color.yellow,
    error: Color = Color.red,
    info: Color = Color.blue,
    
    // UI colors
    background: Color = Color.black,
    foreground: Color = Color.white,
    muted: Color = Color.bright_black,
    
    // Border colors
    border: Color = Color.bright_blue,
    border_focused: Color = Color.bright_cyan,
    border_disabled: Color = Color.bright_black,
    
    // Text colors
    text: Color = Color.white,
    text_secondary: Color = Color.bright_black,
    text_muted: Color = Color.bright_black,
    text_disabled: Color = Color.bright_black,
    
    // Interactive colors
    hover: Color = Color.bright_blue,
    active: Color = Color.cyan,
    selected: Color = Color.blue,
    disabled: Color = Color.bright_black,
    
    // Syntax highlighting colors (for code blocks)
    syntax_keyword: Color = Color.blue,
    syntax_string: Color = Color.green,
    syntax_number: Color = Color.cyan,
    syntax_comment: Color = Color.bright_black,
    syntax_operator: Color = Color.yellow,
    syntax_identifier: Color = Color.white,
    syntax_type: Color = Color.magenta,
    syntax_function: Color = Color.bright_green,
    syntax_constant: Color = Color.bright_cyan,
    syntax_error: Color = Color.red,
    
    pub fn getStyle(self: *const Theme, component: ThemeComponent) Style {
        return switch (component) {
            // Base styles
            .background => Style.default().withBg(self.background),
            .foreground => Style.default().withFg(self.foreground),
            .text => Style.default().withFg(self.text),
            .text_secondary => Style.default().withFg(self.text_secondary),
            .text_muted => Style.default().withFg(self.text_muted),
            .text_disabled => Style.default().withFg(self.text_disabled),
            
            // Interactive styles
            .button => Style.default().withFg(self.foreground).withBg(self.primary),
            .button_hover => Style.default().withFg(self.foreground).withBg(self.hover),
            .button_active => Style.default().withFg(self.foreground).withBg(self.active),
            .button_disabled => Style.default().withFg(self.text_disabled).withBg(self.disabled),
            
            // Input styles
            .input => Style.default().withFg(self.text).withBg(self.background),
            .input_focused => Style.default().withFg(self.text).withBg(self.background),
            .input_placeholder => Style.default().withFg(self.text_muted).withBg(self.background),
            .input_selection => Style.default().withFg(self.foreground).withBg(self.selected),
            
            // Border styles
            .border => Style.default().withFg(self.border),
            .border_focused => Style.default().withFg(self.border_focused),
            .border_disabled => Style.default().withFg(self.border_disabled),
            
            // List styles
            .list_item => Style.default().withFg(self.text).withBg(self.background),
            .list_item_selected => Style.default().withFg(self.foreground).withBg(self.selected),
            .list_item_hover => Style.default().withFg(self.foreground).withBg(self.hover),
            
            // Table styles
            .table_header => Style.default().withFg(self.foreground).withBg(self.primary).withBold(),
            .table_row => Style.default().withFg(self.text).withBg(self.background),
            .table_row_selected => Style.default().withFg(self.foreground).withBg(self.selected),
            .table_row_hover => Style.default().withFg(self.foreground).withBg(self.hover),
            
            // Progress bar styles
            .progress_bar => Style.default().withFg(self.muted).withBg(self.background),
            .progress_fill => Style.default().withFg(self.success).withBg(self.success),
            .progress_text => Style.default().withFg(self.text).withBg(self.background),
            
            // Dialog styles
            .dialog_background => Style.default().withFg(self.text).withBg(self.background),
            .dialog_title => Style.default().withFg(self.foreground).withBg(self.background).withBold(),
            .dialog_border => Style.default().withFg(self.border),
            .dialog_overlay => Style.default().withBg(self.muted),
            
            // Notification styles
            .notification_info => Style.default().withFg(self.foreground).withBg(self.info),
            .notification_success => Style.default().withFg(self.foreground).withBg(self.success),
            .notification_warning => Style.default().withFg(self.background).withBg(self.warning),
            .notification_error => Style.default().withFg(self.foreground).withBg(self.error),
            
            // Code block styles
            .code_background => Style.default().withFg(self.text).withBg(self.background),
            .code_keyword => Style.default().withFg(self.syntax_keyword).withBold(),
            .code_string => Style.default().withFg(self.syntax_string),
            .code_number => Style.default().withFg(self.syntax_number),
            .code_comment => Style.default().withFg(self.syntax_comment).withItalic(),
            .code_operator => Style.default().withFg(self.syntax_operator),
            .code_identifier => Style.default().withFg(self.syntax_identifier),
            .code_type => Style.default().withFg(self.syntax_type),
            .code_function => Style.default().withFg(self.syntax_function),
            .code_constant => Style.default().withFg(self.syntax_constant),
            .code_error => Style.default().withFg(self.syntax_error).withBold(),
            
            // Streaming text styles
            .streaming_text => Style.default().withFg(self.text).withBg(self.background),
            .streaming_cursor => Style.default().withFg(self.background).withBg(self.foreground),
            
            // Context menu styles
            .context_menu_background => Style.default().withFg(self.text).withBg(self.background),
            .context_menu_item => Style.default().withFg(self.text).withBg(self.background),
            .context_menu_selected => Style.default().withFg(self.foreground).withBg(self.selected),
            .context_menu_disabled => Style.default().withFg(self.text_disabled).withBg(self.background),
            .context_menu_separator => Style.default().withFg(self.border),
            .context_menu_shortcut => Style.default().withFg(self.text_secondary).withBg(self.background),
        };
    }
};

/// Theme component identifiers
pub const ThemeComponent = enum {
    // Base
    background,
    foreground,
    text,
    text_secondary,
    text_muted,
    text_disabled,
    
    // Interactive
    button,
    button_hover,
    button_active,
    button_disabled,
    
    // Input
    input,
    input_focused,
    input_placeholder,
    input_selection,
    
    // Border
    border,
    border_focused,
    border_disabled,
    
    // List
    list_item,
    list_item_selected,
    list_item_hover,
    
    // Table
    table_header,
    table_row,
    table_row_selected,
    table_row_hover,
    
    // Progress bar
    progress_bar,
    progress_fill,
    progress_text,
    
    // Dialog
    dialog_background,
    dialog_title,
    dialog_border,
    dialog_overlay,
    
    // Notification
    notification_info,
    notification_success,
    notification_warning,
    notification_error,
    
    // Code block
    code_background,
    code_keyword,
    code_string,
    code_number,
    code_comment,
    code_operator,
    code_identifier,
    code_type,
    code_function,
    code_constant,
    code_error,
    
    // Streaming text
    streaming_text,
    streaming_cursor,
    
    // Context menu
    context_menu_background,
    context_menu_item,
    context_menu_selected,
    context_menu_disabled,
    context_menu_separator,
    context_menu_shortcut,
};

/// Pre-defined themes
pub const Themes = struct {
    /// Default dark theme
    pub fn dark() Theme {
        return Theme{
            .primary = Color.blue,
            .secondary = Color.cyan,
            .accent = Color.green,
            .success = Color.green,
            .warning = Color.yellow,
            .error = Color.red,
            .info = Color.blue,
            .background = Color.black,
            .foreground = Color.white,
            .muted = Color.bright_black,
            .border = Color.bright_blue,
            .border_focused = Color.bright_cyan,
            .border_disabled = Color.bright_black,
            .text = Color.white,
            .text_secondary = Color.bright_black,
            .text_muted = Color.bright_black,
            .text_disabled = Color.bright_black,
            .hover = Color.bright_blue,
            .active = Color.cyan,
            .selected = Color.blue,
            .disabled = Color.bright_black,
            .syntax_keyword = Color.blue,
            .syntax_string = Color.green,
            .syntax_number = Color.cyan,
            .syntax_comment = Color.bright_black,
            .syntax_operator = Color.yellow,
            .syntax_identifier = Color.white,
            .syntax_type = Color.magenta,
            .syntax_function = Color.bright_green,
            .syntax_constant = Color.bright_cyan,
            .syntax_error = Color.red,
        };
    }
    
    /// Light theme
    pub fn light() Theme {
        return Theme{
            .primary = Color.blue,
            .secondary = Color.cyan,
            .accent = Color.green,
            .success = Color.green,
            .warning = Color.yellow,
            .error = Color.red,
            .info = Color.blue,
            .background = Color.white,
            .foreground = Color.black,
            .muted = Color.bright_black,
            .border = Color.black,
            .border_focused = Color.blue,
            .border_disabled = Color.bright_black,
            .text = Color.black,
            .text_secondary = Color.bright_black,
            .text_muted = Color.bright_black,
            .text_disabled = Color.bright_black,
            .hover = Color.blue,
            .active = Color.cyan,
            .selected = Color.bright_blue,
            .disabled = Color.bright_black,
            .syntax_keyword = Color.blue,
            .syntax_string = Color.green,
            .syntax_number = Color.cyan,
            .syntax_comment = Color.bright_black,
            .syntax_operator = Color.yellow,
            .syntax_identifier = Color.black,
            .syntax_type = Color.magenta,
            .syntax_function = Color.bright_green,
            .syntax_constant = Color.bright_cyan,
            .syntax_error = Color.red,
        };
    }
    
    /// High contrast theme
    pub fn high_contrast() Theme {
        return Theme{
            .primary = Color.white,
            .secondary = Color.yellow,
            .accent = Color.green,
            .success = Color.green,
            .warning = Color.yellow,
            .error = Color.red,
            .info = Color.cyan,
            .background = Color.black,
            .foreground = Color.white,
            .muted = Color.white,
            .border = Color.white,
            .border_focused = Color.yellow,
            .border_disabled = Color.bright_black,
            .text = Color.white,
            .text_secondary = Color.white,
            .text_muted = Color.white,
            .text_disabled = Color.bright_black,
            .hover = Color.yellow,
            .active = Color.green,
            .selected = Color.yellow,
            .disabled = Color.bright_black,
            .syntax_keyword = Color.yellow,
            .syntax_string = Color.green,
            .syntax_number = Color.cyan,
            .syntax_comment = Color.bright_black,
            .syntax_operator = Color.white,
            .syntax_identifier = Color.white,
            .syntax_type = Color.magenta,
            .syntax_function = Color.bright_green,
            .syntax_constant = Color.bright_cyan,
            .syntax_error = Color.red,
        };
    }
    
    /// Monokai theme (popular for code)
    pub fn monokai() Theme {
        return Theme{
            .primary = Color.fromRgb(249, 38, 114), // Pink
            .secondary = Color.fromRgb(174, 129, 255), // Purple
            .accent = Color.fromRgb(166, 226, 46), // Green
            .success = Color.fromRgb(166, 226, 46), // Green
            .warning = Color.fromRgb(253, 151, 31), // Orange
            .error = Color.fromRgb(249, 38, 114), // Pink
            .info = Color.fromRgb(102, 217, 239), // Cyan
            .background = Color.fromRgb(39, 40, 34), // Dark gray
            .foreground = Color.fromRgb(248, 248, 242), // Light gray
            .muted = Color.fromRgb(117, 113, 94), // Medium gray
            .border = Color.fromRgb(117, 113, 94), // Medium gray
            .border_focused = Color.fromRgb(102, 217, 239), // Cyan
            .border_disabled = Color.fromRgb(117, 113, 94), // Medium gray
            .text = Color.fromRgb(248, 248, 242), // Light gray
            .text_secondary = Color.fromRgb(117, 113, 94), // Medium gray
            .text_muted = Color.fromRgb(117, 113, 94), // Medium gray
            .text_disabled = Color.fromRgb(117, 113, 94), // Medium gray
            .hover = Color.fromRgb(102, 217, 239), // Cyan
            .active = Color.fromRgb(249, 38, 114), // Pink
            .selected = Color.fromRgb(73, 72, 62), // Dark selection
            .disabled = Color.fromRgb(117, 113, 94), // Medium gray
            .syntax_keyword = Color.fromRgb(249, 38, 114), // Pink
            .syntax_string = Color.fromRgb(230, 219, 116), // Yellow
            .syntax_number = Color.fromRgb(174, 129, 255), // Purple
            .syntax_comment = Color.fromRgb(117, 113, 94), // Medium gray
            .syntax_operator = Color.fromRgb(249, 38, 114), // Pink
            .syntax_identifier = Color.fromRgb(248, 248, 242), // Light gray
            .syntax_type = Color.fromRgb(102, 217, 239), // Cyan
            .syntax_function = Color.fromRgb(166, 226, 46), // Green
            .syntax_constant = Color.fromRgb(174, 129, 255), // Purple
            .syntax_error = Color.fromRgb(249, 38, 114), // Pink
        };
    }
    
    /// Solarized dark theme
    pub fn solarized_dark() Theme {
        return Theme{
            .primary = Color.fromRgb(38, 139, 210), // Blue
            .secondary = Color.fromRgb(42, 161, 152), // Cyan
            .accent = Color.fromRgb(133, 153, 0), // Green
            .success = Color.fromRgb(133, 153, 0), // Green
            .warning = Color.fromRgb(181, 137, 0), // Yellow
            .error = Color.fromRgb(220, 50, 47), // Red
            .info = Color.fromRgb(38, 139, 210), // Blue
            .background = Color.fromRgb(0, 43, 54), // Base03
            .foreground = Color.fromRgb(131, 148, 150), // Base0
            .muted = Color.fromRgb(88, 110, 117), // Base01
            .border = Color.fromRgb(88, 110, 117), // Base01
            .border_focused = Color.fromRgb(42, 161, 152), // Cyan
            .border_disabled = Color.fromRgb(88, 110, 117), // Base01
            .text = Color.fromRgb(131, 148, 150), // Base0
            .text_secondary = Color.fromRgb(88, 110, 117), // Base01
            .text_muted = Color.fromRgb(88, 110, 117), // Base01
            .text_disabled = Color.fromRgb(88, 110, 117), // Base01
            .hover = Color.fromRgb(42, 161, 152), // Cyan
            .active = Color.fromRgb(38, 139, 210), // Blue
            .selected = Color.fromRgb(7, 54, 66), // Base02
            .disabled = Color.fromRgb(88, 110, 117), // Base01
            .syntax_keyword = Color.fromRgb(133, 153, 0), // Green
            .syntax_string = Color.fromRgb(42, 161, 152), // Cyan
            .syntax_number = Color.fromRgb(220, 50, 47), // Red
            .syntax_comment = Color.fromRgb(88, 110, 117), // Base01
            .syntax_operator = Color.fromRgb(133, 153, 0), // Green
            .syntax_identifier = Color.fromRgb(131, 148, 150), // Base0
            .syntax_type = Color.fromRgb(181, 137, 0), // Yellow
            .syntax_function = Color.fromRgb(38, 139, 210), // Blue
            .syntax_constant = Color.fromRgb(211, 54, 130), // Magenta
            .syntax_error = Color.fromRgb(220, 50, 47), // Red
        };
    }
    
    /// Gruvbox dark theme
    pub fn gruvbox_dark() Theme {
        return Theme{
            .primary = Color.fromRgb(131, 165, 152), // Aqua
            .secondary = Color.fromRgb(142, 192, 124), // Green
            .accent = Color.fromRgb(211, 134, 155), // Purple
            .success = Color.fromRgb(142, 192, 124), // Green
            .warning = Color.fromRgb(250, 189, 47), // Yellow
            .error = Color.fromRgb(251, 73, 52), // Red
            .info = Color.fromRgb(131, 165, 152), // Aqua
            .background = Color.fromRgb(40, 40, 40), // bg0
            .foreground = Color.fromRgb(235, 219, 178), // fg0
            .muted = Color.fromRgb(146, 131, 116), // fg4
            .border = Color.fromRgb(146, 131, 116), // fg4
            .border_focused = Color.fromRgb(131, 165, 152), // Aqua
            .border_disabled = Color.fromRgb(146, 131, 116), // fg4
            .text = Color.fromRgb(235, 219, 178), // fg0
            .text_secondary = Color.fromRgb(146, 131, 116), // fg4
            .text_muted = Color.fromRgb(146, 131, 116), // fg4
            .text_disabled = Color.fromRgb(146, 131, 116), // fg4
            .hover = Color.fromRgb(131, 165, 152), // Aqua
            .active = Color.fromRgb(142, 192, 124), // Green
            .selected = Color.fromRgb(60, 56, 54), // bg2
            .disabled = Color.fromRgb(146, 131, 116), // fg4
            .syntax_keyword = Color.fromRgb(251, 73, 52), // Red
            .syntax_string = Color.fromRgb(142, 192, 124), // Green
            .syntax_number = Color.fromRgb(211, 134, 155), // Purple
            .syntax_comment = Color.fromRgb(146, 131, 116), // fg4
            .syntax_operator = Color.fromRgb(250, 189, 47), // Yellow
            .syntax_identifier = Color.fromRgb(235, 219, 178), // fg0
            .syntax_type = Color.fromRgb(250, 189, 47), // Yellow
            .syntax_function = Color.fromRgb(131, 165, 152), // Aqua
            .syntax_constant = Color.fromRgb(211, 134, 155), // Purple
            .syntax_error = Color.fromRgb(251, 73, 52), // Red
        };
    }
};

/// Theme manager for runtime theme switching
pub const ThemeManager = struct {
    current_theme: Theme,
    
    pub fn init(initial_theme: Theme) ThemeManager {
        return ThemeManager{
            .current_theme = initial_theme,
        };
    }
    
    pub fn setTheme(self: *ThemeManager, theme: Theme) void {
        self.current_theme = theme;
    }
    
    pub fn getTheme(self: *const ThemeManager) Theme {
        return self.current_theme;
    }
    
    pub fn getStyle(self: *const ThemeManager, component: ThemeComponent) Style {
        return self.current_theme.getStyle(component);
    }
    
    pub fn setDarkTheme(self: *ThemeManager) void {
        self.setTheme(Themes.dark());
    }
    
    pub fn setLightTheme(self: *ThemeManager) void {
        self.setTheme(Themes.light());
    }
    
    pub fn setHighContrastTheme(self: *ThemeManager) void {
        self.setTheme(Themes.high_contrast());
    }
    
    pub fn setMonokaiTheme(self: *ThemeManager) void {
        self.setTheme(Themes.monokai());
    }
    
    pub fn setSolarizedDarkTheme(self: *ThemeManager) void {
        self.setTheme(Themes.solarized_dark());
    }
    
    pub fn setGruvboxDarkTheme(self: *ThemeManager) void {
        self.setTheme(Themes.gruvbox_dark());
    }
};

test "Theme creation" {
    const theme = Themes.dark();
    try std.testing.expect(theme.primary == Color.blue);
    try std.testing.expect(theme.background == Color.black);
    try std.testing.expect(theme.foreground == Color.white);
}

test "Theme manager" {
    var manager = ThemeManager.init(Themes.dark());
    
    try std.testing.expect(manager.getTheme().primary == Color.blue);
    
    manager.setLightTheme();
    try std.testing.expect(manager.getTheme().background == Color.white);
    
    manager.setHighContrastTheme();
    try std.testing.expect(manager.getTheme().border == Color.white);
}

test "Theme component styles" {
    const theme = Themes.dark();
    
    const button_style = theme.getStyle(.button);
    try std.testing.expect(button_style.fg.? == Color.white);
    try std.testing.expect(button_style.bg.? == Color.blue);
    
    const text_style = theme.getStyle(.text);
    try std.testing.expect(text_style.fg.? == Color.white);
}