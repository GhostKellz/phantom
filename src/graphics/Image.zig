//! Image - Terminal image display support
//! Provides comprehensive image display using multiple terminal protocols

const std = @import("std");
const vxfw = @import("../vxfw.zig");
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");

const Allocator = std.mem.Allocator;
const Size = geometry.Size;
const Point = geometry.Point;

/// Image display manager supporting multiple protocols
pub const ImageManager = struct {
    allocator: Allocator,
    supported_protocols: std.EnumSet(ImageProtocol),
    default_protocol: ImageProtocol = .auto,
    max_image_size: Size = Size.init(1024, 1024),
    cache: std.HashMap(u64, CachedImage, std.hash_map.HashMap(u64, CachedImage, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).Context, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: Allocator) ImageManager {
        return ImageManager{
            .allocator = allocator,
            .supported_protocols = detectSupportedProtocols(),
            .cache = std.HashMap(u64, CachedImage, std.hash_map.HashMap(u64, CachedImage, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).Context, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *ImageManager) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.cache.deinit();
    }

    /// Display an image using the best available protocol
    pub fn displayImage(self: *ImageManager, image: Image) !ImageCommand {
        const protocol = if (self.default_protocol == .auto)
            self.selectBestProtocol(image)
        else
            self.default_protocol;

        // Check cache first
        const cache_key = image.getHash();
        if (self.cache.get(cache_key)) |cached| {
            if (cached.protocol == protocol) {
                return ImageCommand{ .display_cached = .{ .id = cached.id, .position = image.position } };
            }
        }

        // Generate display command for the protocol
        return switch (protocol) {
            .sixel => try self.displaySixel(image),
            .kitty => try self.displayKitty(image),
            .iterm2 => try self.displayITerm2(image),
            .block_chars => try self.displayBlockChars(image),
            .ascii_art => try self.displayAsciiArt(image),
            .auto => unreachable, // Should be resolved above
        };
    }

    /// Select the best protocol for the given image
    fn selectBestProtocol(self: *const ImageManager, image: Image) ImageProtocol {
        _ = image;

        // Priority order: Kitty > Sixel > iTerm2 > Block chars > ASCII art
        if (self.supported_protocols.contains(.kitty)) return .kitty;
        if (self.supported_protocols.contains(.sixel)) return .sixel;
        if (self.supported_protocols.contains(.iterm2)) return .iterm2;
        if (self.supported_protocols.contains(.block_chars)) return .block_chars;
        return .ascii_art; // Always supported fallback
    }

    /// Display image using Sixel protocol
    fn displaySixel(self: *ImageManager, image: Image) !ImageCommand {
        const sixel_data = try self.convertToSixel(image);
        const command_data = try std.fmt.allocPrint(
            self.allocator,
            "\x1bPq{s}\x1b\\",
            .{sixel_data}
        );

        // Cache the result
        const cache_key = image.getHash();
        const cached = CachedImage{
            .id = cache_key,
            .protocol = .sixel,
            .data = try self.allocator.dupe(u8, command_data),
            .size = image.size,
        };
        try self.cache.put(cache_key, cached);

        return ImageCommand{
            .display_sixel = .{
                .data = command_data,
                .position = image.position,
                .size = image.size,
            }
        };
    }

    /// Display image using Kitty graphics protocol
    fn displayKitty(self: *ImageManager, image: Image) !ImageCommand {
        const base64_data = try self.encodeBase64(image.data);
        defer self.allocator.free(base64_data);

        const command_data = try std.fmt.allocPrint(
            self.allocator,
            "\x1b_Ga=T,f=100,s={d},v={d};{s}\x1b\\",
            .{ image.size.width, image.size.height, base64_data }
        );

        // Cache the result
        const cache_key = image.getHash();
        const cached = CachedImage{
            .id = cache_key,
            .protocol = .kitty,
            .data = try self.allocator.dupe(u8, command_data),
            .size = image.size,
        };
        try self.cache.put(cache_key, cached);

        return ImageCommand{
            .display_kitty = .{
                .data = command_data,
                .position = image.position,
                .size = image.size,
            }
        };
    }

    /// Display image using iTerm2 inline images
    fn displayITerm2(self: *ImageManager, image: Image) !ImageCommand {
        const base64_data = try self.encodeBase64(image.data);
        defer self.allocator.free(base64_data);

        const command_data = try std.fmt.allocPrint(
            self.allocator,
            "\x1b]1337;File=inline=1;width={d};height={d}:{s}\x07",
            .{ image.size.width, image.size.height, base64_data }
        );

        // Cache the result
        const cache_key = image.getHash();
        const cached = CachedImage{
            .id = cache_key,
            .protocol = .iterm2,
            .data = try self.allocator.dupe(u8, command_data),
            .size = image.size,
        };
        try self.cache.put(cache_key, cached);

        return ImageCommand{
            .display_iterm2 = .{
                .data = command_data,
                .position = image.position,
                .size = image.size,
            }
        };
    }

    /// Display image using Unicode block characters
    fn displayBlockChars(self: *ImageManager, image: Image) !ImageCommand {
        const block_art = try self.convertToBlockChars(image);

        return ImageCommand{
            .display_block_chars = .{
                .data = block_art,
                .position = image.position,
                .size = Size.init(
                    @divTrunc(image.size.width, 2), // 2 pixels per char width
                    @divTrunc(image.size.height, 4)  // 4 pixels per char height
                ),
            }
        };
    }

    /// Display image using ASCII art
    fn displayAsciiArt(self: *ImageManager, image: Image) !ImageCommand {
        const ascii_art = try self.convertToAsciiArt(image);

        return ImageCommand{
            .display_ascii = .{
                .data = ascii_art,
                .position = image.position,
                .size = Size.init(
                    @divTrunc(image.size.width, 8), // Rough char width scaling
                    @divTrunc(image.size.height, 16) // Rough char height scaling
                ),
            }
        };
    }

    /// Convert image to Sixel format
    fn convertToSixel(self: *ImageManager, image: Image) ![]u8 {
        var sixel_data = std.array_list.AlignedManaged(u8, null).init(self.allocator);

        // Simple Sixel conversion (real implementation would be more sophisticated)
        // This is a basic example - production code would need proper color quantization

        try sixel_data.appendSlice("\"1;1;");
        try sixel_data.appendSlice(try std.fmt.allocPrint(self.allocator, "{d};{d}", .{ image.size.width, image.size.height }));

        // Color palette setup (simplified)
        try sixel_data.appendSlice("#0;2;0;0;0"); // Black
        try sixel_data.appendSlice("#1;2;100;100;100"); // White

        // Image data conversion (simplified - real implementation needs proper pixel processing)
        var y: u16 = 0;
        while (y < image.size.height) : (y += 6) { // Sixel rows are 6 pixels high
            try sixel_data.appendSlice("#0"); // Select color 0

            var x: u16 = 0;
            while (x < image.size.width) : (x += 1) {
                // Convert 6 vertical pixels to sixel character
                var sixel_char: u8 = 0x3F; // Base sixel character

                // Sample pixels and build sixel character (simplified)
                var bit: u3 = 0;
                while (bit < 6 and y + bit < image.size.height) : (bit += 1) {
                    const pixel_index = (y + bit) * image.size.width + x;
                    if (pixel_index < image.data.len) {
                        const pixel_value = image.data[pixel_index];
                        if (pixel_value > 128) { // Simple threshold
                            sixel_char |= (@as(u8, 1) << bit);
                        }
                    }
                }

                try sixel_data.append(sixel_char);
            }

            try sixel_data.appendSlice("-"); // Carriage return
        }

        return sixel_data.toOwnedSlice();
    }

    /// Convert image to Unicode block characters
    fn convertToBlockChars(self: *ImageManager, image: Image) ![]u8 {
        var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);

        // Block characters for 2x4 pixel blocks
        const block_chars = [_][]const u8{
            " ",    // 0000
            "▗",    // 0001
            "▖",    // 0010
            "▄",    // 0011
            "▝",    // 0100
            "▐",    // 0101
            "▞",    // 0110
            "▟",    // 0111
            "▘",    // 1000
            "▚",    // 1001
            "▌",    // 1010
            "▙",    // 1011
            "▀",    // 1100
            "▜",    // 1101
            "▛",    // 1110
            "█",    // 1111
        };

        var y: u16 = 0;
        while (y < image.size.height) : (y += 4) {
            var x: u16 = 0;
            while (x < image.size.width) : (x += 2) {
                var pattern: u4 = 0;

                // Sample 2x4 pixel block
                const positions = [_][2]u16{
                    .{ 0, 0 }, .{ 1, 0 }, // Top row
                    .{ 0, 1 }, .{ 1, 1 }, // Second row
                    .{ 0, 2 }, .{ 1, 2 }, // Third row
                    .{ 0, 3 }, .{ 1, 3 }, // Bottom row
                };

                for (positions, 0..) |pos, i| {
                    const px = x + pos[0];
                    const py = y + pos[1];

                    if (px < image.size.width and py < image.size.height) {
                        const pixel_index = py * image.size.width + px;
                        if (pixel_index < image.data.len and image.data[pixel_index] > 128) {
                            pattern |= (@as(u4, 1) << @as(u2, @intCast(i)));
                        }
                    }
                }

                try result.appendSlice(block_chars[pattern]);
            }

            if (y + 4 < image.size.height) {
                try result.append('\n');
            }
        }

        return result.toOwnedSlice();
    }

    /// Convert image to ASCII art
    fn convertToAsciiArt(self: *ImageManager, image: Image) ![]u8 {
        var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);

        // ASCII characters by intensity
        const ascii_chars = " .:-=+*#%@";
        const char_count = ascii_chars.len;

        var y: u16 = 0;
        while (y < image.size.height) : (y += 16) { // Scale down significantly
            var x: u16 = 0;
            while (x < image.size.width) : (x += 8) {
                // Sample a block of pixels and get average intensity
                var total_intensity: u32 = 0;
                var pixel_count: u32 = 0;

                var sy: u16 = 0;
                while (sy < 16 and y + sy < image.size.height) : (sy += 1) {
                    var sx: u16 = 0;
                    while (sx < 8 and x + sx < image.size.width) : (sx += 1) {
                        const pixel_index = (y + sy) * image.size.width + (x + sx);
                        if (pixel_index < image.data.len) {
                            total_intensity += image.data[pixel_index];
                            pixel_count += 1;
                        }
                    }
                }

                if (pixel_count > 0) {
                    const avg_intensity = total_intensity / pixel_count;
                    const char_index = (avg_intensity * char_count) / 256;
                    const safe_index = @min(char_index, char_count - 1);
                    try result.append(ascii_chars[safe_index]);
                } else {
                    try result.append(' ');
                }
            }

            if (y + 16 < image.size.height) {
                try result.append('\n');
            }
        }

        return result.toOwnedSlice();
    }

    /// Encode data to base64
    fn encodeBase64(self: *ImageManager, data: []const u8) ![]u8 {
        const encoder = std.base64.standard.Encoder;
        const encoded_len = encoder.calcSize(data.len);
        const encoded = try self.allocator.alloc(u8, encoded_len);
        return encoder.encode(encoded, data);
    }

    /// Clear image cache
    pub fn clearCache(self: *ImageManager) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.cache.clearRetainingCapacity();
    }
};

/// Detect supported image protocols
fn detectSupportedProtocols() std.EnumSet(ImageProtocol) {
    var protocols = std.EnumSet(ImageProtocol).initEmpty();

    // Check environment variables and terminal capabilities
    if (std.os.getenv("TERM")) |term| {
        if (std.mem.indexOf(u8, term, "kitty")) |_| {
            protocols.insert(.kitty);
        }
        if (std.mem.indexOf(u8, term, "xterm")) |_| {
            protocols.insert(.sixel);
        }
    }

    if (std.os.getenv("TERM_PROGRAM")) |term_program| {
        if (std.mem.eql(u8, term_program, "iTerm.app")) {
            protocols.insert(.iterm2);
        }
    }

    // Always support fallback methods
    protocols.insert(.block_chars);
    protocols.insert(.ascii_art);

    return protocols;
}

/// Image protocols supported by terminals
pub const ImageProtocol = enum {
    auto,        // Automatic selection
    sixel,       // Sixel graphics
    kitty,       // Kitty graphics protocol
    iterm2,      // iTerm2 inline images
    block_chars, // Unicode block characters
    ascii_art,   // ASCII art fallback
};

/// Image data structure
pub const Image = struct {
    data: []const u8,           // Raw pixel data (grayscale for now)
    size: Size,                 // Image dimensions
    position: Point = Point.init(0, 0), // Display position
    format: ImageFormat = .grayscale,

    pub const ImageFormat = enum {
        grayscale,
        rgb,
        rgba,
    };

    /// Create image from grayscale data
    pub fn fromGrayscale(data: []const u8, width: u16, height: u16) Image {
        return Image{
            .data = data,
            .size = Size.init(width, height),
            .format = .grayscale,
        };
    }

    /// Create image from RGB data
    pub fn fromRgb(data: []const u8, width: u16, height: u16) Image {
        return Image{
            .data = data,
            .size = Size.init(width, height),
            .format = .rgb,
        };
    }

    /// Get hash for caching
    pub fn getHash(self: Image) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(self.data);
        hasher.update(std.mem.asBytes(&self.size));
        hasher.update(std.mem.asBytes(&self.format));
        return hasher.final();
    }
};

/// Cached image data
const CachedImage = struct {
    id: u64,
    protocol: ImageProtocol,
    data: []u8,
    size: Size,

    pub fn deinit(self: *CachedImage, allocator: Allocator) void {
        allocator.free(self.data);
    }
};

/// Commands for image display
pub const ImageCommand = union(enum) {
    display_sixel: SixelDisplay,
    display_kitty: KittyDisplay,
    display_iterm2: ITerm2Display,
    display_block_chars: BlockCharDisplay,
    display_ascii: AsciiDisplay,
    display_cached: CachedDisplay,

    pub const SixelDisplay = struct {
        data: []u8,
        position: Point,
        size: Size,
    };

    pub const KittyDisplay = struct {
        data: []u8,
        position: Point,
        size: Size,
    };

    pub const ITerm2Display = struct {
        data: []u8,
        position: Point,
        size: Size,
    };

    pub const BlockCharDisplay = struct {
        data: []u8,
        position: Point,
        size: Size,
    };

    pub const AsciiDisplay = struct {
        data: []u8,
        position: Point,
        size: Size,
    };

    pub const CachedDisplay = struct {
        id: u64,
        position: Point,
    };
};

/// Widget for displaying images
pub const ImageWidget = struct {
    image_manager: *ImageManager,
    image: ?Image = null,
    current_command: ?ImageCommand = null,
    background_style: style.Style = style.Style.default(),

    pub fn init(image_manager: *ImageManager) ImageWidget {
        return ImageWidget{
            .image_manager = image_manager,
        };
    }

    /// Set the image to display
    pub fn setImage(self: *ImageWidget, image: Image) !void {
        self.image = image;
        self.current_command = try self.image_manager.displayImage(image);
    }

    /// Clear the current image
    pub fn clearImage(self: *ImageWidget) void {
        self.image = null;
        self.current_command = null;
    }

    pub fn widget(self: *const ImageWidget) vxfw.Widget {
        return .{
            .userdata = @constCast(self),
            .drawFn = typeErasedDrawFn,
            .eventHandlerFn = typeErasedEventHandler,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *const ImageWidget = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
        const self: *ImageWidget = @ptrCast(@alignCast(ptr));
        return self.handleEvent(ctx);
    }

    pub fn draw(self: *const ImageWidget, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const width = ctx.getWidth();
        const height = ctx.getHeight();

        var surface = try vxfw.Surface.initArena(
            ctx.arena,
            self.widget(),
            Size.init(width, height)
        );

        // Fill background
        surface.fillStyle(self.background_style);

        if (self.current_command) |command| {
            switch (command) {
                .display_block_chars => |block_display| {
                    // Draw the block character representation
                    _ = surface.writeText(0, 0, block_display.data, style.Style.default());
                },
                .display_ascii => |ascii_display| {
                    // Draw the ASCII art representation
                    _ = surface.writeText(0, 0, ascii_display.data, style.Style.default());
                },
                else => {
                    // For protocol-based displays, we would output the command data
                    // This is handled in the command processing phase
                },
            }
        } else if (self.image == null) {
            // Show placeholder text
            const placeholder = "No image loaded";
            const x_offset = if (width > placeholder.len) (width - @as(u16, @intCast(placeholder.len))) / 2 else 0;
            const y_offset = height / 2;
            _ = surface.writeText(x_offset, y_offset, placeholder, style.Style.default());
        }

        return surface;
    }

    pub fn handleEvent(self: *ImageWidget, ctx: vxfw.EventContext) Allocator.Error!vxfw.CommandList {
        var commands = ctx.createCommandList();

        switch (ctx.event) {
            .init => {
                // Initialize image display if we have one
                if (self.image) |image| {
                    const command = self.image_manager.displayImage(image) catch return commands;

                    // Convert to vxfw command based on protocol
                    switch (command) {
                        .display_sixel => |sixel| {
                            try commands.append(vxfw.Command{ .write_stdout = sixel.data });
                        },
                        .display_kitty => |kitty| {
                            try commands.append(vxfw.Command{ .write_stdout = kitty.data });
                        },
                        .display_iterm2 => |iterm2| {
                            try commands.append(vxfw.Command{ .write_stdout = iterm2.data });
                        },
                        else => {
                            // Block chars and ASCII are handled in draw()
                            try commands.append(vxfw.Command.redraw);
                        },
                    }
                }
            },
            else => {},
        }

        return commands;
    }
};

test "Image creation" {
    const test_data = [_]u8{ 0, 128, 255, 64, 192 };
    const image = Image.fromGrayscale(&test_data, 5, 1);

    try std.testing.expectEqual(@as(u16, 5), image.size.width);
    try std.testing.expectEqual(@as(u16, 1), image.size.height);
    try std.testing.expectEqual(Image.ImageFormat.grayscale, image.format);
}

test "ImageManager initialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var manager = ImageManager.init(arena.allocator());
    defer manager.deinit();

    // Should have at least fallback protocols
    try std.testing.expect(manager.supported_protocols.contains(.block_chars));
    try std.testing.expect(manager.supported_protocols.contains(.ascii_art));
}

test "Protocol detection" {
    const protocols = detectSupportedProtocols();

    // Should always support fallback methods
    try std.testing.expect(protocols.contains(.block_chars));
    try std.testing.expect(protocols.contains(.ascii_art));
}