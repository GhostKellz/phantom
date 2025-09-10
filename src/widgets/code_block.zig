//! CodeBlock widget for syntax-highlighted code display
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Language support for syntax highlighting
pub const Language = enum {
    none,
    zig,
    rust,
    c,
    cpp,
    python,
    javascript,
    typescript,
    go,
    java,
    bash,
    json,
    yaml,
    toml,
    markdown,
    
    pub fn fromString(lang: []const u8) Language {
        const lower = std.ascii.lowerString(lang);
        if (std.mem.eql(u8, lower, "zig")) return .zig;
        if (std.mem.eql(u8, lower, "rust") or std.mem.eql(u8, lower, "rs")) return .rust;
        if (std.mem.eql(u8, lower, "c")) return .c;
        if (std.mem.eql(u8, lower, "cpp") or std.mem.eql(u8, lower, "c++")) return .cpp;
        if (std.mem.eql(u8, lower, "python") or std.mem.eql(u8, lower, "py")) return .python;
        if (std.mem.eql(u8, lower, "javascript") or std.mem.eql(u8, lower, "js")) return .javascript;
        if (std.mem.eql(u8, lower, "typescript") or std.mem.eql(u8, lower, "ts")) return .typescript;
        if (std.mem.eql(u8, lower, "go")) return .go;
        if (std.mem.eql(u8, lower, "java")) return .java;
        if (std.mem.eql(u8, lower, "bash") or std.mem.eql(u8, lower, "sh")) return .bash;
        if (std.mem.eql(u8, lower, "json")) return .json;
        if (std.mem.eql(u8, lower, "yaml") or std.mem.eql(u8, lower, "yml")) return .yaml;
        if (std.mem.eql(u8, lower, "toml")) return .toml;
        if (std.mem.eql(u8, lower, "markdown") or std.mem.eql(u8, lower, "md")) return .markdown;
        return .none;
    }
};

/// Token type for syntax highlighting
pub const TokenType = enum {
    text,
    keyword,
    string,
    number,
    comment,
    operator,
    delimiter,
    identifier,
    type,
    builtin,
    constant,
    function,
    variable,
    attribute,
    error_token,
};

/// Syntax token with type and style
pub const Token = struct {
    text: []const u8,
    type: TokenType,
    style: Style,
};

/// Theme for syntax highlighting
pub const Theme = struct {
    text: Style = Style.default(),
    keyword: Style = Style.default().withFg(style.Color.blue).withBold(),
    string: Style = Style.default().withFg(style.Color.green),
    number: Style = Style.default().withFg(style.Color.cyan),
    comment: Style = Style.default().withFg(style.Color.bright_black).withItalic(),
    operator: Style = Style.default().withFg(style.Color.yellow),
    delimiter: Style = Style.default().withFg(style.Color.white),
    identifier: Style = Style.default(),
    type: Style = Style.default().withFg(style.Color.magenta),
    builtin: Style = Style.default().withFg(style.Color.bright_blue),
    constant: Style = Style.default().withFg(style.Color.bright_cyan),
    function: Style = Style.default().withFg(style.Color.bright_green),
    variable: Style = Style.default().withFg(style.Color.white),
    attribute: Style = Style.default().withFg(style.Color.bright_yellow),
    error_token: Style = Style.default().withFg(style.Color.red).withBold(),
    
    pub fn getStyle(self: *const Theme, token_type: TokenType) Style {
        return switch (token_type) {
            .text => self.text,
            .keyword => self.keyword,
            .string => self.string,
            .number => self.number,
            .comment => self.comment,
            .operator => self.operator,
            .delimiter => self.delimiter,
            .identifier => self.identifier,
            .type => self.type,
            .builtin => self.builtin,
            .constant => self.constant,
            .function => self.function,
            .variable => self.variable,
            .attribute => self.attribute,
            .error_token => self.error_token,
        };
    }
};

/// CodeBlock widget for syntax-highlighted code display
pub const CodeBlock = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    
    // Content
    code: []const u8,
    language: Language,
    lines: std.ArrayList([]const u8),
    tokens: std.ArrayList(Token),
    
    // Configuration
    show_line_numbers: bool = false,
    line_number_style: Style,
    theme: Theme,
    
    // Scrolling
    scroll_offset_line: usize = 0,
    scroll_offset_col: usize = 0,
    
    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator, code: []const u8, language: Language) !*CodeBlock {
        const code_block = try allocator.create(CodeBlock);
        code_block.* = CodeBlock{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .code = try allocator.dupe(u8, code),
            .language = language,
            .lines = std.ArrayList([]const u8){},
            .tokens = std.ArrayList(Token){},
            .line_number_style = Style.default().withFg(style.Color.yellow),
            .theme = Theme{},
        };
        
        try code_block.updateLines();
        try code_block.tokenize();
        
        return code_block;
    }

    pub fn setCode(self: *CodeBlock, code: []const u8) !void {
        self.allocator.free(self.code);
        self.code = try self.allocator.dupe(u8, code);
        
        try self.updateLines();
        try self.tokenize();
    }

    pub fn setLanguage(self: *CodeBlock, language: Language) !void {
        self.language = language;
        try self.tokenize();
    }

    pub fn setShowLineNumbers(self: *CodeBlock, show: bool) void {
        self.show_line_numbers = show;
    }

    pub fn setLineNumberStyle(self: *CodeBlock, line_number_style: Style) void {
        self.line_number_style = line_number_style;
    }

    pub fn setTheme(self: *CodeBlock, theme: Theme) void {
        self.theme = theme;
    }

    pub fn scrollUp(self: *CodeBlock) void {
        if (self.scroll_offset_line > 0) {
            self.scroll_offset_line -= 1;
        }
    }

    pub fn scrollDown(self: *CodeBlock) void {
        if (self.lines.items.len > 0) {
            const visible_lines = if (self.area.height > 0) self.area.height else 1;
            const max_scroll = if (self.lines.items.len > visible_lines) 
                self.lines.items.len - visible_lines else 0;
            
            if (self.scroll_offset_line < max_scroll) {
                self.scroll_offset_line += 1;
            }
        }
    }

    pub fn scrollLeft(self: *CodeBlock) void {
        if (self.scroll_offset_col > 0) {
            self.scroll_offset_col -= 1;
        }
    }

    pub fn scrollRight(self: *CodeBlock) void {
        self.scroll_offset_col += 1;
    }

    fn updateLines(self: *CodeBlock) !void {
        // Clear existing lines
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearAndFree(self.allocator);
        
        // Split code into lines
        var lines_iter = std.mem.split(u8, self.code, "\n");
        while (lines_iter.next()) |line| {
            const owned_line = try self.allocator.dupe(u8, line);
            try self.lines.append(self.allocator, owned_line);
        }
        
        // Ensure at least one line exists
        if (self.lines.items.len == 0) {
            const empty_line = try self.allocator.dupe(u8, "");
            try self.lines.append(self.allocator, empty_line);
        }
    }

    fn tokenize(self: *CodeBlock) !void {
        self.tokens.clearAndFree(self.allocator);
        
        // Simple tokenization based on language
        switch (self.language) {
            .none => try self.tokenizeNone(),
            .zig => try self.tokenizeZig(),
            .rust => try self.tokenizeRust(),
            .c, .cpp => try self.tokenizeC(),
            .python => try self.tokenizePython(),
            .javascript, .typescript => try self.tokenizeJavaScript(),
            .go => try self.tokenizeGo(),
            .java => try self.tokenizeJava(),
            .bash => try self.tokenizeBash(),
            .json => try self.tokenizeJson(),
            .yaml => try self.tokenizeYaml(),
            .toml => try self.tokenizeToml(),
            .markdown => try self.tokenizeMarkdown(),
        }
    }

    fn tokenizeNone(self: *CodeBlock) !void {
        try self.tokens.append(self.allocator, Token{
            .text = self.code,
            .type = .text,
            .style = self.theme.getStyle(.text),
        });
    }

    fn tokenizeZig(self: *CodeBlock) !void {
        const keywords = [_][]const u8{
            "const", "var", "fn", "pub", "struct", "enum", "union", "if", "else",
            "switch", "while", "for", "break", "continue", "return", "defer",
            "errdefer", "test", "try", "catch", "async", "await", "suspend",
            "resume", "export", "extern", "packed", "align", "comptime",
            "inline", "noinline", "volatile", "allowzero", "noalias",
        };
        
        const types = [_][]const u8{
            "bool", "i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16",
            "u32", "u64", "u128", "usize", "f16", "f32", "f64", "f128",
            "c_short", "c_int", "c_long", "c_longlong", "c_uint", "c_ulong",
            "c_ulonglong", "c_char", "void", "noreturn", "type", "anytype",
            "anyerror", "comptime_int", "comptime_float",
        };
        
        try self.tokenizeGeneric(keywords[0..], types[0..], "//", null);
    }

    fn tokenizeRust(self: *CodeBlock) !void {
        const keywords = [_][]const u8{
            "fn", "let", "mut", "const", "static", "struct", "enum", "impl",
            "trait", "mod", "pub", "use", "crate", "super", "self", "Self",
            "if", "else", "match", "while", "for", "loop", "break", "continue",
            "return", "async", "await", "unsafe", "extern", "type", "where",
            "as", "ref", "move", "box", "dyn", "in",
        };
        
        const types = [_][]const u8{
            "bool", "i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16",
            "u32", "u64", "u128", "usize", "f32", "f64", "char", "str",
            "String", "Vec", "Option", "Result", "Box", "Rc", "Arc",
        };
        
        try self.tokenizeGeneric(keywords[0..], types[0..], "//", null);
    }

    fn tokenizeC(self: *CodeBlock) !void {
        const keywords = [_][]const u8{
            "auto", "break", "case", "char", "const", "continue", "default",
            "do", "double", "else", "enum", "extern", "float", "for", "goto",
            "if", "int", "long", "register", "return", "short", "signed",
            "sizeof", "static", "struct", "switch", "typedef", "union",
            "unsigned", "void", "volatile", "while", "inline", "restrict",
            "_Bool", "_Complex", "_Imaginary", "_Alignas", "_Alignof",
            "_Atomic", "_Static_assert", "_Noreturn", "_Thread_local",
            "_Generic", "_Pragma",
        };
        
        try self.tokenizeGeneric(keywords[0..], &[_][]const u8{}, "//", "/*");
    }

    fn tokenizePython(self: *CodeBlock) !void {
        const keywords = [_][]const u8{
            "and", "as", "assert", "break", "class", "continue", "def", "del",
            "elif", "else", "except", "finally", "for", "from", "global",
            "if", "import", "in", "is", "lambda", "nonlocal", "not", "or",
            "pass", "raise", "return", "try", "while", "with", "yield",
            "async", "await", "True", "False", "None",
        };
        
        try self.tokenizeGeneric(keywords[0..], &[_][]const u8{}, "#", null);
    }

    fn tokenizeJavaScript(self: *CodeBlock) !void {
        const keywords = [_][]const u8{
            "break", "case", "catch", "class", "const", "continue", "debugger",
            "default", "delete", "do", "else", "export", "extends", "finally",
            "for", "function", "if", "import", "in", "instanceof", "new",
            "return", "super", "switch", "this", "throw", "try", "typeof",
            "var", "void", "while", "with", "yield", "let", "static", "enum",
            "implements", "package", "protected", "interface", "private",
            "public", "async", "await", "of", "null", "undefined", "true",
            "false",
        };
        
        try self.tokenizeGeneric(keywords[0..], &[_][]const u8{}, "//", "/*");
    }

    fn tokenizeGo(self: *CodeBlock) !void {
        const keywords = [_][]const u8{
            "break", "case", "chan", "const", "continue", "default", "defer",
            "else", "fallthrough", "for", "func", "go", "goto", "if", "import",
            "interface", "map", "package", "range", "return", "select",
            "struct", "switch", "type", "var", "nil", "true", "false",
            "iota", "append", "cap", "close", "complex", "copy", "delete",
            "imag", "len", "make", "new", "panic", "print", "println",
            "real", "recover",
        };
        
        const types = [_][]const u8{
            "bool", "byte", "complex64", "complex128", "error", "float32",
            "float64", "int", "int8", "int16", "int32", "int64", "rune",
            "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr",
        };
        
        try self.tokenizeGeneric(keywords[0..], types[0..], "//", "/*");
    }

    fn tokenizeJava(self: *CodeBlock) !void {
        const keywords = [_][]const u8{
            "abstract", "assert", "boolean", "break", "byte", "case", "catch",
            "char", "class", "const", "continue", "default", "do", "double",
            "else", "enum", "extends", "final", "finally", "float", "for",
            "goto", "if", "implements", "import", "instanceof", "int",
            "interface", "long", "native", "new", "package", "private",
            "protected", "public", "return", "short", "static", "strictfp",
            "super", "switch", "synchronized", "this", "throw", "throws",
            "transient", "try", "void", "volatile", "while", "true", "false",
            "null",
        };
        
        try self.tokenizeGeneric(keywords[0..], &[_][]const u8{}, "//", "/*");
    }

    fn tokenizeBash(self: *CodeBlock) !void {
        const keywords = [_][]const u8{
            "if", "then", "else", "elif", "fi", "case", "esac", "for", "while",
            "until", "do", "done", "function", "return", "local", "export",
            "readonly", "declare", "typeset", "unset", "shift", "break",
            "continue", "exit", "source", "eval", "exec", "trap", "wait",
            "jobs", "bg", "fg", "disown", "suspend", "nohup", "time",
            "echo", "printf", "read", "test", "true", "false",
        };
        
        try self.tokenizeGeneric(keywords[0..], &[_][]const u8{}, "#", null);
    }

    fn tokenizeJson(self: *CodeBlock) !void {
        const keywords = [_][]const u8{ "true", "false", "null" };
        try self.tokenizeGeneric(keywords[0..], &[_][]const u8{}, "", null);
    }

    fn tokenizeYaml(self: *CodeBlock) !void {
        const keywords = [_][]const u8{ "true", "false", "null", "yes", "no", "on", "off" };
        try self.tokenizeGeneric(keywords[0..], &[_][]const u8{}, "#", null);
    }

    fn tokenizeToml(self: *CodeBlock) !void {
        const keywords = [_][]const u8{ "true", "false" };
        try self.tokenizeGeneric(keywords[0..], &[_][]const u8{}, "#", null);
    }

    fn tokenizeMarkdown(self: *CodeBlock) !void {
        // Simple markdown tokenization
        try self.tokens.append(self.allocator, Token{
            .text = self.code,
            .type = .text,
            .style = self.theme.getStyle(.text),
        });
    }

    fn tokenizeGeneric(self: *CodeBlock, keywords: []const []const u8, types: []const []const u8, line_comment: []const u8, block_comment: ?[]const u8) !void {
        var i: usize = 0;
        var token_start: usize = 0;
        
        while (i < self.code.len) {
            const c = self.code[i];
            
            // Handle line comments
            if (line_comment.len > 0 and i + line_comment.len <= self.code.len and 
                std.mem.eql(u8, self.code[i..i + line_comment.len], line_comment)) {
                
                // Add previous token if any
                if (i > token_start) {
                    try self.addGenericToken(self.code[token_start..i], keywords, types);
                }
                
                // Find end of line comment
                var comment_end = i;
                while (comment_end < self.code.len and self.code[comment_end] != '\n') {
                    comment_end += 1;
                }
                
                try self.tokens.append(self.allocator, Token{
                    .text = self.code[i..comment_end],
                    .type = .comment,
                    .style = self.theme.getStyle(.comment),
                });
                
                i = comment_end;
                token_start = i;
                continue;
            }
            
            // Handle block comments
            if (block_comment != null and i + block_comment.?.len <= self.code.len and 
                std.mem.eql(u8, self.code[i..i + block_comment.?.len], block_comment.?)) {
                
                // Add previous token if any
                if (i > token_start) {
                    try self.addGenericToken(self.code[token_start..i], keywords, types);
                }
                
                // Find end of block comment
                var comment_end = i + block_comment.?.len;
                while (comment_end + 1 < self.code.len) {
                    if (self.code[comment_end] == '*' and self.code[comment_end + 1] == '/') {
                        comment_end += 2;
                        break;
                    }
                    comment_end += 1;
                }
                
                try self.tokens.append(self.allocator, Token{
                    .text = self.code[i..comment_end],
                    .type = .comment,
                    .style = self.theme.getStyle(.comment),
                });
                
                i = comment_end;
                token_start = i;
                continue;
            }
            
            // Handle string literals
            if (c == '"' or c == '\'' or c == '`') {
                // Add previous token if any
                if (i > token_start) {
                    try self.addGenericToken(self.code[token_start..i], keywords, types);
                }
                
                // Find end of string
                var string_end = i + 1;
                while (string_end < self.code.len and self.code[string_end] != c) {
                    if (self.code[string_end] == '\\' and string_end + 1 < self.code.len) {
                        string_end += 2; // Skip escaped character
                    } else {
                        string_end += 1;
                    }
                }
                
                if (string_end < self.code.len) {
                    string_end += 1; // Include closing quote
                }
                
                try self.tokens.append(self.allocator, Token{
                    .text = self.code[i..string_end],
                    .type = .string,
                    .style = self.theme.getStyle(.string),
                });
                
                i = string_end;
                token_start = i;
                continue;
            }
            
            // Handle numbers
            if (std.ascii.isDigit(c)) {
                // Add previous token if any
                if (i > token_start) {
                    try self.addGenericToken(self.code[token_start..i], keywords, types);
                }
                
                // Find end of number
                var number_end = i;
                while (number_end < self.code.len and 
                       (std.ascii.isDigit(self.code[number_end]) or 
                        self.code[number_end] == '.' or 
                        self.code[number_end] == 'e' or 
                        self.code[number_end] == 'E' or 
                        (number_end > i and (self.code[number_end] == '+' or self.code[number_end] == '-')))) {
                    number_end += 1;
                }
                
                try self.tokens.append(self.allocator, Token{
                    .text = self.code[i..number_end],
                    .type = .number,
                    .style = self.theme.getStyle(.number),
                });
                
                i = number_end;
                token_start = i;
                continue;
            }
            
            // Handle operators and delimiters
            if (std.mem.indexOfScalar(u8, "+-*/%=<>!&|^~?:;,.(){}[]", c) != null) {
                // Add previous token if any
                if (i > token_start) {
                    try self.addGenericToken(self.code[token_start..i], keywords, types);
                }
                
                try self.tokens.append(self.allocator, Token{
                    .text = self.code[i..i + 1],
                    .type = if (std.mem.indexOfScalar(u8, "+-*/%=<>!&|^~?:", c) != null) .operator else .delimiter,
                    .style = self.theme.getStyle(if (std.mem.indexOfScalar(u8, "+-*/%=<>!&|^~?:", c) != null) .operator else .delimiter),
                });
                
                i += 1;
                token_start = i;
                continue;
            }
            
            i += 1;
        }
        
        // Add final token if any
        if (token_start < self.code.len) {
            try self.addGenericToken(self.code[token_start..], keywords, types);
        }
    }

    fn addGenericToken(self: *CodeBlock, text: []const u8, keywords: []const []const u8, types: []const []const u8) !void {
        var i: usize = 0;
        var token_start: usize = 0;
        
        while (i <= text.len) {
            const is_end = i == text.len;
            const is_word_boundary = is_end or !std.ascii.isAlphaNumeric(text[i]) and text[i] != '_';
            
            if (is_word_boundary and i > token_start) {
                const word = text[token_start..i];
                var token_type: TokenType = .identifier;
                
                // Check if it's a keyword
                for (keywords) |keyword| {
                    if (std.mem.eql(u8, word, keyword)) {
                        token_type = .keyword;
                        break;
                    }
                }
                
                // Check if it's a type
                if (token_type == .identifier) {
                    for (types) |type_name| {
                        if (std.mem.eql(u8, word, type_name)) {
                            token_type = .type;
                            break;
                        }
                    }
                }
                
                try self.tokens.append(self.allocator, Token{
                    .text = word,
                    .type = token_type,
                    .style = self.theme.getStyle(token_type),
                });
            }
            
            // Add non-word characters as text
            if (!is_end and is_word_boundary) {
                const start = i;
                while (i < text.len and !std.ascii.isAlphaNumeric(text[i]) and text[i] != '_') {
                    i += 1;
                }
                
                if (i > start) {
                    try self.tokens.append(self.allocator, Token{
                        .text = text[start..i],
                        .type = .text,
                        .style = self.theme.getStyle(.text),
                    });
                }
                
                token_start = i;
            } else {
                i += 1;
            }
        }
    }

    fn getLineNumberWidth(self: *const CodeBlock) u16 {
        const line_count = self.lines.items.len;
        var width: u16 = 1;
        var num = line_count;
        while (num >= 10) {
            width += 1;
            num /= 10;
        }
        return width;
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *CodeBlock = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;

        // Calculate text area
        var text_area = area;
        var line_number_width: u16 = 0;
        
        if (self.show_line_numbers) {
            line_number_width = self.getLineNumberWidth() + 1;
            text_area.x += line_number_width;
            text_area.width -= line_number_width;
        }
        
        // Render visible lines
        const visible_lines = @min(area.height, self.lines.items.len);
        var y: u16 = 0;
        
        while (y < visible_lines) {
            const line_index = self.scroll_offset_line + y;
            if (line_index >= self.lines.items.len) break;
            
            const line = self.lines.items[line_index];
            const render_y = area.y + y;
            
            // Render line number
            if (self.show_line_numbers) {
                const line_num_str = std.fmt.allocPrint(self.allocator, "{d}", .{line_index + 1}) catch "";
                defer self.allocator.free(line_num_str);
                
                const line_num_x = area.x + line_number_width - line_num_str.len - 1;
                buffer.writeText(@as(u16, @intCast(line_num_x)), render_y, line_num_str, self.line_number_style);
            }
            
            // Clear line background
            buffer.fill(Rect.init(text_area.x, render_y, text_area.width, 1), Cell.withStyle(self.theme.text));
            
            // Render line content with basic syntax highlighting
            const line_width = @min(line.len, text_area.width);
            if (line_width > 0 and line.len > self.scroll_offset_col) {
                const visible_start = self.scroll_offset_col;
                const visible_end = @min(visible_start + line_width, line.len);
                
                if (visible_start < visible_end) {
                    const visible_text = line[visible_start..visible_end];
                    // For now, just render as text - could be enhanced with per-token rendering
                    buffer.writeText(text_area.x, render_y, visible_text, self.theme.text);
                }
            }
            
            y += 1;
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *CodeBlock = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key| {
                switch (key) {
                    .up => {
                        self.scrollUp();
                        return true;
                    },
                    .down => {
                        self.scrollDown();
                        return true;
                    },
                    .left => {
                        self.scrollLeft();
                        return true;
                    },
                    .right => {
                        self.scrollRight();
                        return true;
                    },
                    .page_up => {
                        const page_size = if (self.area.height > 0) self.area.height else 10;
                        var i: u16 = 0;
                        while (i < page_size) : (i += 1) {
                            self.scrollUp();
                        }
                        return true;
                    },
                    .page_down => {
                        const page_size = if (self.area.height > 0) self.area.height else 10;
                        var i: u16 = 0;
                        while (i < page_size) : (i += 1) {
                            self.scrollDown();
                        }
                        return true;
                    },
                    .home => {
                        self.scroll_offset_line = 0;
                        self.scroll_offset_col = 0;
                        return true;
                    },
                    .end => {
                        const visible_lines = if (self.area.height > 0) self.area.height else 1;
                        self.scroll_offset_line = if (self.lines.items.len > visible_lines) 
                            self.lines.items.len - visible_lines else 0;
                        return true;
                    },
                    .char => |c| {
                        switch (c) {
                            'j' => {
                                self.scrollDown();
                                return true;
                            },
                            'k' => {
                                self.scrollUp();
                                return true;
                            },
                            'h' => {
                                self.scrollLeft();
                                return true;
                            },
                            'l' => {
                                self.scrollRight();
                                return true;
                            },
                            'g' => {
                                self.scroll_offset_line = 0;
                                self.scroll_offset_col = 0;
                                return true;
                            },
                            'G' => {
                                const visible_lines = if (self.area.height > 0) self.area.height else 1;
                                self.scroll_offset_line = if (self.lines.items.len > visible_lines) 
                                    self.lines.items.len - visible_lines else 0;
                                return true;
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }

        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *CodeBlock = @fieldParentPtr("widget", widget);
        self.area = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *CodeBlock = @fieldParentPtr("widget", widget);
        
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit(self.allocator);
        
        self.tokens.deinit(self.allocator);
        self.allocator.free(self.code);
        self.allocator.destroy(self);
    }
};

test "CodeBlock widget creation" {
    const allocator = std.testing.allocator;

    const code = "fn main() {\n    println!(\"Hello, world!\");\n}";
    const code_block = try CodeBlock.init(allocator, code, .rust);
    defer code_block.widget.deinit();

    try std.testing.expect(code_block.language == .rust);
    try std.testing.expect(code_block.lines.items.len == 3);
}

test "Language detection" {
    try std.testing.expect(Language.fromString("zig") == .zig);
    try std.testing.expect(Language.fromString("rust") == .rust);
    try std.testing.expect(Language.fromString("rs") == .rust);
    try std.testing.expect(Language.fromString("unknown") == .none);
}