//! Universal Package Browser - AUR, Chaotic AUR, ZigLibs, GitHub repos
const std = @import("std");
const Widget = @import("../app.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const emoji = @import("../emoji.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Package source types
pub const PackageSource = enum {
    aur,            // Standard AUR
    chaotic_aur,    // Chaotic AUR from pacman.conf
    ziglibs,        // ZigLibs GitHub organization
    custom_github,  // Custom GitHub repos
    pacman_repo,    // Official Arch repos (core, extra, community)
    
    pub fn getIcon(self: PackageSource) []const u8 {
        return switch (self) {
            .aur => "📦",
            .chaotic_aur => "🌀",
            .ziglibs => "🦎",
            .custom_github => "🐙",
            .pacman_repo => "🏛️",
        };
    }
    
    pub fn getDisplayName(self: PackageSource) []const u8 {
        return switch (self) {
            .aur => "AUR",
            .chaotic_aur => "Chaotic AUR",
            .ziglibs => "ZigLibs",
            .custom_github => "GitHub",
            .pacman_repo => "Official",
        };
    }
    
    pub fn getColor(self: PackageSource) style.Color {
        return switch (self) {
            .aur => style.Color.bright_blue,
            .chaotic_aur => style.Color.bright_magenta,
            .ziglibs => style.Color.bright_green,
            .custom_github => style.Color.bright_cyan,
            .pacman_repo => style.Color.bright_yellow,
        };
    }
};

/// Package information from various sources
pub const Package = struct {
    name: []const u8,
    version: ?[]const u8 = null,
    description: ?[]const u8 = null,
    maintainer: ?[]const u8 = null,
    source: PackageSource,
    url: ?[]const u8 = null,
    install_size: u64 = 0, // in KB
    download_count: u64 = 0,
    last_updated: []const u8 = "",
    tags: std.ArrayList([]const u8),
    dependencies: std.ArrayList([]const u8),
    is_installed: bool = false,
    
    pub fn getDisplayInfo(self: *const Package, allocator: std.mem.Allocator) ![]const u8 {
        const version_str = self.version orelse "latest";
        const desc_str = self.description orelse "No description";
        
        return std.fmt.allocPrint(allocator, "{s} {s} v{s} - {s}", .{
            self.source.getIcon(), self.name, version_str, desc_str
        });
    }
    
    pub fn getStatusIcon(self: *const Package) []const u8 {
        return if (self.is_installed) "✅" else "📥";
    }
};

/// Repository configuration
pub const Repository = struct {
    name: []const u8,
    source: PackageSource,
    url: []const u8,
    enabled: bool = true,
    api_endpoint: ?[]const u8 = null,
    
    pub fn getDisplayName(self: *const Repository, allocator: std.mem.Allocator) ![]const u8 {
        const status = if (self.enabled) "🟢" else "🔴";
        return std.fmt.allocPrint(allocator, "{s} {s} {s}", .{ status, self.source.getIcon(), self.name });
    }
};

/// Search and filter options
pub const SearchOptions = struct {
    query: []const u8 = "",
    source_filter: ?PackageSource = null,
    installed_only: bool = false,
    sort_by: SortBy = .name,
    limit: usize = 100,
    
    pub const SortBy = enum {
        name,
        popularity,
        last_updated,
        install_size,
    };
};

/// Universal Package Browser widget
pub const UniversalPackageBrowser = struct {
    widget: Widget,
    allocator: std.mem.Allocator,
    
    // Package data
    packages: std.ArrayList(Package),
    filtered_packages: std.ArrayList(usize), // indices into packages
    repositories: std.ArrayList(Repository),
    
    // Search and filtering
    search_options: SearchOptions,
    search_input: std.ArrayList(u8),
    
    // Display state
    selected_package: usize = 0,
    selected_repo: usize = 0,
    scroll_offset: usize = 0,
    current_view: ViewMode = .package_list,
    
    // Loading state
    is_loading: bool = false,
    load_progress: f64 = 0.0,
    status_message: ?[]const u8 = null,
    
    // Configuration paths
    pacman_conf_path: []const u8 = "/etc/pacman.conf",
    custom_repos_config: []const u8 = "~/.config/phantom/repos.json",
    
    // Styling
    header_style: Style,
    package_style: Style,
    selected_style: Style,
    source_style: Style,
    info_style: Style,
    loading_style: Style,
    
    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),
    
    pub const ViewMode = enum {
        package_list,
        package_details,
        repository_list,
        search_input,
    };

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*UniversalPackageBrowser {
        const browser = try allocator.create(UniversalPackageBrowser);
        browser.* = UniversalPackageBrowser{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .packages = std.ArrayList(Package){},
            .filtered_packages = std.ArrayList(usize){},
            .repositories = std.ArrayList(Repository){},
            .search_input = std.ArrayList(u8){},
            .search_options = SearchOptions{},
            .header_style = Style.default().withFg(style.Color.bright_cyan).withBold(),
            .package_style = Style.default().withFg(style.Color.white),
            .selected_style = Style.default().withFg(style.Color.bright_yellow).withBold(),
            .source_style = Style.default().withFg(style.Color.bright_green),
            .info_style = Style.default().withFg(style.Color.bright_black),
            .loading_style = Style.default().withFg(style.Color.bright_blue),
        };
        
        // Initialize default repositories
        try browser.initializeRepositories();
        
        return browser;
    }

    /// Initialize repositories from system configuration
    fn initializeRepositories(self: *UniversalPackageBrowser) !void {
        // Add standard repositories
        try self.addRepository(Repository{
            .name = "AUR",
            .source = .aur,
            .url = "https://aur.archlinux.org",
            .api_endpoint = "https://aur.archlinux.org/rpc/",
        });
        
        try self.addRepository(Repository{
            .name = "ZigLibs",
            .source = .ziglibs,
            .url = "https://github.com/ziglibs",
            .api_endpoint = "https://api.github.com/orgs/ziglibs/repos",
        });
        
        // Parse pacman.conf for additional repositories
        self.parsePacmanConf() catch |err| {
            std.log.warn("Failed to parse pacman.conf: {}\n", .{err});
        };
        
        // Load custom GitHub repositories
        self.loadCustomRepositories() catch |err| {
            std.log.warn("Failed to load custom repositories: {}\n", .{err});
        };
    }

    /// Parse /etc/pacman.conf for repositories like Chaotic AUR
    fn parsePacmanConf(self: *UniversalPackageBrowser) !void {
        const file = std.fs.openFileAbsolute(self.pacman_conf_path, .{}) catch return;
        defer file.close();
        
        var buffer: [8192]u8 = undefined;
        const content = try file.reader(&buffer).readAllAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(content);
        
        var lines = std.mem.splitSequence(u8, content, "\n");
        var current_repo: ?[]const u8 = null;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            
            // Skip comments and empty lines
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            
            // Check for repository section [repo-name]
            if (trimmed.len > 2 and trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
                current_repo = self.allocator.dupe(u8, trimmed[1..trimmed.len - 1]) catch continue;
                continue;
            }
            
            // Look for Server entries
            if (std.mem.startsWith(u8, trimmed, "Server = ") and current_repo != null) {
                const url = trimmed[9..]; // Skip "Server = "
                
                // Check if this looks like Chaotic AUR or other third-party
                if (std.mem.indexOf(u8, url, "chaotic") != null) {
                    try self.addRepository(Repository{
                        .name = try self.allocator.dupe(u8, current_repo.?),
                        .source = .chaotic_aur,
                        .url = try self.allocator.dupe(u8, url),
                    });
                } else if (!std.mem.eql(u8, current_repo.?, "core") and 
                          !std.mem.eql(u8, current_repo.?, "extra") and
                          !std.mem.eql(u8, current_repo.?, "community")) {
                    // Other third-party repos
                    try self.addRepository(Repository{
                        .name = try self.allocator.dupe(u8, current_repo.?),
                        .source = .pacman_repo,
                        .url = try self.allocator.dupe(u8, url),
                    });
                }
            }
        }
    }

    /// Load custom GitHub repositories from config
    fn loadCustomRepositories(self: *UniversalPackageBrowser) !void {
        // Default hardwired repositories (you can customize these)
        const custom_repos = [_]struct { name: []const u8, url: []const u8 }{
            .{ .name = "ghostkellz/phantom", .url = "https://github.com/ghostkellz/phantom" },
            .{ .name = "ghostkellz/zeke", .url = "https://github.com/ghostkellz/zeke" },
            .{ .name = "ghostkellz/flash", .url = "https://github.com/ghostkellz/flash" },
            .{ .name = "ghostkellz/ghostmesh", .url = "https://github.com/ghostkellz/ghostmesh" },
            // Add your other repositories here
        };
        
        for (custom_repos) |repo| {
            try self.addRepository(Repository{
                .name = try self.allocator.dupe(u8, repo.name),
                .source = .custom_github,
                .url = try self.allocator.dupe(u8, repo.url),
                .api_endpoint = try std.fmt.allocPrint(self.allocator, "https://api.github.com/repos/{s}", .{repo.name}),
            });
        }
    }

    /// Add a repository to the list
    pub fn addRepository(self: *UniversalPackageBrowser, repo: Repository) !void {
        try self.repositories.append(self.allocator, repo);
    }

    /// Search packages across all enabled repositories
    pub fn searchPackages(self: *UniversalPackageBrowser, options: SearchOptions) !void {
        self.search_options = options;
        self.is_loading = true;
        self.load_progress = 0.0;
        
        // Clear existing packages
        for (self.packages.items) |*pkg| {
            self.allocator.free(pkg.name);
            if (pkg.version) |v| self.allocator.free(v);
            if (pkg.description) |d| self.allocator.free(d);
            if (pkg.maintainer) |m| self.allocator.free(m);
            if (pkg.url) |u| self.allocator.free(u);
            pkg.tags.deinit();
            pkg.dependencies.deinit();
        }
        self.packages.clearRetainingCapacity();
        
        // Search each enabled repository
        var completed_repos: usize = 0;
        for (self.repositories.items) |*repo| {
            if (!repo.enabled) continue;
            
            switch (repo.source) {
                .aur => self.searchAUR(repo, options) catch |err| {
                    std.log.warn("AUR search failed: {}\n", .{err});
                },
                .chaotic_aur => self.searchChaoticAUR(repo, options) catch |err| {
                    std.log.warn("Chaotic AUR search failed: {}\n", .{err});
                },
                .ziglibs => self.searchZigLibs(repo, options) catch |err| {
                    std.log.warn("ZigLibs search failed: {}\n", .{err});
                },
                .custom_github => self.searchGitHub(repo, options) catch |err| {
                    std.log.warn("GitHub search failed: {}\n", .{err});
                },
                .pacman_repo => self.searchPacmanRepo(repo, options) catch |err| {
                    std.log.warn("Pacman repo search failed: {}\n", .{err});
                },
            }
            
            completed_repos += 1;
            self.load_progress = (@as(f64, @floatFromInt(completed_repos)) / @as(f64, @floatFromInt(self.repositories.items.len))) * 100.0;
        }
        
        self.is_loading = false;
        self.updateFilters();
    }

    /// Search AUR packages
    fn searchAUR(self: *UniversalPackageBrowser, repo: *const Repository, options: SearchOptions) !void {
        _ = repo;
        
        // Mock AUR data for demo (in real implementation, use HTTP client)
        const aur_packages = [_]struct { name: []const u8, desc: []const u8, version: []const u8 }{
            .{ .name = "reaper", .desc = "Digital Audio Workstation", .version = "6.70" },
            .{ .name = "discord", .desc = "All-in-one voice and text chat", .version = "0.0.27" },
            .{ .name = "visual-studio-code-bin", .desc = "Code editor", .version = "1.80.0" },
            .{ .name = "google-chrome", .desc = "Web browser", .version = "114.0" },
            .{ .name = "spotify", .desc = "Music streaming", .version = "1.2.11" },
            .{ .name = "steam", .desc = "Gaming platform", .version = "1.0.0.74" },
            .{ .name = "zoom", .desc = "Video conferencing", .version = "5.15.2" },
            .{ .name = "obs-studio", .desc = "Streaming and recording", .version = "29.1.3" },
        };
        
        for (aur_packages) |aur_pkg| {
            if (options.query.len > 0 and std.mem.indexOf(u8, aur_pkg.name, options.query) == null) {
                continue;
            }
            
            const pkg = Package{
                .name = try self.allocator.dupe(u8, aur_pkg.name),
                .version = try self.allocator.dupe(u8, aur_pkg.version),
                .description = try self.allocator.dupe(u8, aur_pkg.desc),
                .source = .aur,
                .tags = std.ArrayList([]const u8){},
                .dependencies = std.ArrayList([]const u8).init(self.allocator),
            };
            
            try self.packages.append(self.allocator, pkg);
        }
    }

    /// Search ZigLibs repositories
    fn searchZigLibs(self: *UniversalPackageBrowser, repo: *const Repository, options: SearchOptions) !void {
        _ = repo;
        
        // Mock ZigLibs data
        const ziglib_packages = [_]struct { name: []const u8, desc: []const u8 }{
            .{ .name = "zig-clap", .desc = "Simple command line argument parsing library" },
            .{ .name = "zig-network", .desc = "Cross-platform networking library" },
            .{ .name = "zig-args", .desc = "Simple argument parser" },
            .{ .name = "zig-datetime", .desc = "Date and time manipulation" },
            .{ .name = "zig-json", .desc = "JSON parsing and serialization" },
            .{ .name = "zig-regex", .desc = "Regular expression engine" },
            .{ .name = "zig-uuid", .desc = "UUID generation and parsing" },
            .{ .name = "zig-base64", .desc = "Base64 encoding and decoding" },
        };
        
        for (ziglib_packages) |zlib_pkg| {
            if (options.query.len > 0 and std.mem.indexOf(u8, zlib_pkg.name, options.query) == null) {
                continue;
            }
            
            const pkg = Package{
                .name = try self.allocator.dupe(u8, zlib_pkg.name),
                .description = try self.allocator.dupe(u8, zlib_pkg.desc),
                .source = .ziglibs,
                .tags = std.ArrayList([]const u8){},
                .dependencies = std.ArrayList([]const u8).init(self.allocator),
            };
            
            try self.packages.append(self.allocator, pkg);
        }
    }

    /// Search Chaotic AUR
    fn searchChaoticAUR(self: *UniversalPackageBrowser, repo: *const Repository, options: SearchOptions) !void {
        _ = repo;
        _ = options;
        
        // Mock Chaotic AUR packages
        const chaotic_packages = [_]struct { name: []const u8, desc: []const u8 }{
            .{ .name = "chaotic-keyring", .desc = "Chaotic AUR keyring" },
            .{ .name = "chaotic-mirrorlist", .desc = "Chaotic AUR mirror list" },
            .{ .name = "wine-staging-git", .desc = "Wine staging development" },
            .{ .name = "brave-bin", .desc = "Brave web browser" },
        };
        
        for (chaotic_packages) |chaotic_pkg| {
            const pkg = Package{
                .name = try self.allocator.dupe(u8, chaotic_pkg.name),
                .description = try self.allocator.dupe(u8, chaotic_pkg.desc),
                .source = .chaotic_aur,
                .tags = std.ArrayList([]const u8){},
                .dependencies = std.ArrayList([]const u8).init(self.allocator),
            };
            
            try self.packages.append(self.allocator, pkg);
        }
    }

    /// Search GitHub repositories
    fn searchGitHub(self: *UniversalPackageBrowser, repo: *const Repository, options: SearchOptions) !void {
        _ = options;
        
        // Extract owner/repo from URL
        const github_url = repo.url;
        if (std.mem.indexOf(u8, github_url, "github.com/")) |start| {
            const repo_part = github_url[start + 11..]; // Skip "github.com/"
            
            const pkg = Package{
                .name = try self.allocator.dupe(u8, repo_part),
                .description = try std.fmt.allocPrint(self.allocator, "GitHub repository: {s}", .{repo.name}),
                .source = .custom_github,
                .url = try self.allocator.dupe(u8, repo.url),
                .tags = std.ArrayList([]const u8){},
                .dependencies = std.ArrayList([]const u8).init(self.allocator),
            };
            
            try self.packages.append(self.allocator, pkg);
        }
    }

    /// Search official Pacman repositories
    fn searchPacmanRepo(self: *UniversalPackageBrowser, repo: *const Repository, options: SearchOptions) !void {
        _ = repo;
        _ = options;
        
        // Mock pacman repo packages
        const pacman_packages = [_]struct { name: []const u8, desc: []const u8 }{
            .{ .name = "gcc", .desc = "The GNU Compiler Collection" },
            .{ .name = "python", .desc = "Python programming language" },
            .{ .name = "git", .desc = "Fast distributed version control system" },
            .{ .name = "vim", .desc = "Vi Improved text editor" },
        };
        
        for (pacman_packages) |pac_pkg| {
            const pkg = Package{
                .name = try self.allocator.dupe(u8, pac_pkg.name),
                .description = try self.allocator.dupe(u8, pac_pkg.desc),
                .source = .pacman_repo,
                .tags = std.ArrayList([]const u8){},
                .dependencies = std.ArrayList([]const u8).init(self.allocator),
            };
            
            try self.packages.append(self.allocator, pkg);
        }
    }

    /// Update filtered package list based on current search options
    fn updateFilters(self: *UniversalPackageBrowser) void {
        self.filtered_packages.clearRetainingCapacity();
        
        for (self.packages.items, 0..) |*pkg, i| {
            // Apply source filter
            if (self.search_options.source_filter) |filter| {
                if (pkg.source != filter) continue;
            }
            
            // Apply installed filter
            if (self.search_options.installed_only and !pkg.is_installed) continue;
            
            // Apply search query
            if (self.search_options.query.len > 0) {
                const found_in_name = std.mem.indexOf(u8, pkg.name, self.search_options.query) != null;
                const found_in_desc = if (pkg.description) |desc| 
                    std.mem.indexOf(u8, desc, self.search_options.query) != null 
                else false;
                
                if (!found_in_name and !found_in_desc) continue;
            }
            
            self.filtered_packages.append(self.allocator, i) catch break;
        }
        
        // Reset selection if out of bounds
        if (self.selected_package >= self.filtered_packages.items.len) {
            self.selected_package = 0;
        }
    }

    /// Set search query and update results
    pub fn setSearchQuery(self: *UniversalPackageBrowser, query: []const u8) !void {
        self.search_input.clearRetainingCapacity();
        try self.search_input.appendSlice(self.allocator, query);
        
        self.search_options.query = self.search_input.items;
        self.updateFilters();
    }

    /// Get currently selected package
    pub fn getSelectedPackage(self: *const UniversalPackageBrowser) ?*const Package {
        if (self.filtered_packages.items.len == 0 or self.selected_package >= self.filtered_packages.items.len) {
            return null;
        }
        
        const pkg_index = self.filtered_packages.items[self.selected_package];
        return &self.packages.items[pkg_index];
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *UniversalPackageBrowser = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;

        var y: u16 = area.y;
        
        // Header
        if (y < area.y + area.height) {
            buffer.fill(Rect.init(area.x, y, area.width, 1), Cell.withStyle(self.header_style));
            const header = "📦 UNIVERSAL PACKAGE BROWSER";
            buffer.writeText(area.x, y, header, self.header_style);
            
            // Show current view and stats
            const stats = std.fmt.allocPrint(self.allocator, "  ({d} packages, {d} repos)", .{ 
                self.filtered_packages.items.len, self.repositories.items.len 
            }) catch return;
            defer self.allocator.free(stats);
            
            if (area.x + header.len + stats.len < area.x + area.width) {
                buffer.writeText(area.x + @as(u16, @intCast(header.len)), y, stats, self.info_style);
            }
            y += 1;
        }

        // Search bar
        if (y < area.y + area.height) {
            self.renderSearchBar(buffer, area.x, y, area.width);
            y += 1;
        }

        // Loading indicator
        if (self.is_loading and y < area.y + area.height) {
            self.renderLoadingIndicator(buffer, area.x, y, area.width);
            y += 1;
        }

        // Main content based on current view
        const content_area = Rect.init(area.x, y, area.width, area.y + area.height - y);
        switch (self.current_view) {
            .package_list => self.renderPackageList(buffer, content_area),
            .package_details => self.renderPackageDetails(buffer, content_area),
            .repository_list => self.renderRepositoryList(buffer, content_area),
            .search_input => self.renderSearchInput(buffer, content_area),
        }
    }

    fn renderSearchBar(self: *UniversalPackageBrowser, buffer: *Buffer, x: u16, y: u16, width: u16) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.package_style));
        
        const search_prompt = "🔍 Search: ";
        buffer.writeText(x, y, search_prompt, self.header_style);
        
        const input_x = x + @as(u16, @intCast(search_prompt.len));
        const available_width = if (width > search_prompt.len) width - @as(u16, @intCast(search_prompt.len)) else 0;
        
        if (available_width > 0) {
            const query = self.search_input.items;
            const display_len = @min(query.len, available_width - 10); // Leave space for filter info
            
            if (display_len > 0) {
                buffer.writeText(input_x, y, query[0..display_len], self.package_style);
            }
            
            // Show active filters
            if (self.search_options.source_filter) |filter| {
                const filter_text = std.fmt.allocPrint(self.allocator, " [{s}]", .{filter.getDisplayName()}) catch return;
                defer self.allocator.free(filter_text);
                
                const filter_x = x + width - @as(u16, @intCast(filter_text.len));
                if (filter_x > input_x + display_len) {
                    buffer.writeText(filter_x, y, filter_text, Style.default().withFg(filter.getColor()));
                }
            }
        }
    }

    fn renderLoadingIndicator(self: *UniversalPackageBrowser, buffer: *Buffer, x: u16, y: u16, width: u16) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.loading_style));
        
        const loading_text = std.fmt.allocPrint(self.allocator, "⏳ Loading packages... {d:.0}%", .{self.load_progress}) catch return;
        defer self.allocator.free(loading_text);
        
        buffer.writeText(x, y, loading_text, self.loading_style);
        
        // Progress bar
        const bar_width = @min(width / 2, 40);
        const bar_x = x + width - bar_width;
        const fill_width = @as(u16, @intFromFloat(@as(f64, @floatFromInt(bar_width)) * (self.load_progress / 100.0)));
        
        for (0..bar_width) |i| {
            const char: u21 = if (i < fill_width) '█' else '░';
            buffer.setCell(bar_x + @as(u16, @intCast(i)), y, Cell.init(char, self.loading_style));
        }
    }

    fn renderPackageList(self: *UniversalPackageBrowser, buffer: *Buffer, area: Rect) void {
        var current_y = area.y;
        const visible_height = area.height;
        
        // Column headers
        if (current_y < area.y + area.height) {
            buffer.fill(Rect.init(area.x, current_y, area.width, 1), Cell.withStyle(self.header_style));
            buffer.writeText(area.x, current_y, "Status  Source    Name                    Version     Description", self.header_style);
            current_y += 1;
        }
        
        // Package list
        for (self.filtered_packages.items, 0..) |pkg_index, display_index| {
            if (display_index < self.scroll_offset) continue;
            if (current_y >= area.y + visible_height) break;
            
            const pkg = &self.packages.items[pkg_index];
            const is_selected = display_index == self.selected_package;
            
            self.renderPackageLine(buffer, area.x, current_y, area.width, pkg, is_selected);
            current_y += 1;
        }
        
        // Help text at bottom
        if (area.height > 2) {
            const help_y = area.y + area.height - 1;
            buffer.fill(Rect.init(area.x, help_y, area.width, 1), Cell.withStyle(self.info_style));
            const help_text = "Enter: details | Space: install | /: search | Tab: filter | r: repos | q: quit";
            const help_len = @min(help_text.len, area.width);
            buffer.writeText(area.x, help_y, help_text[0..help_len], self.info_style);
        }
    }

    fn renderPackageLine(self: *UniversalPackageBrowser, buffer: *Buffer, x: u16, y: u16, width: u16, pkg: *const Package, is_selected: bool) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.package_style));
        
        const line_style = if (is_selected) self.selected_style else pkg.source.getColor();
        const bg_style = if (is_selected) Style.withBg(style.Color.bright_black) else self.package_style;
        
        var current_x = x;
        
        // Status icon
        const status = pkg.getStatusIcon();
        buffer.writeText(current_x, y, status, line_style);
        current_x += 3;
        
        // Source icon
        const source_icon = pkg.source.getIcon();
        buffer.writeText(current_x, y, source_icon, Style.default().withFg(pkg.source.getColor()));
        current_x += 3;
        
        // Source name
        const source_name = pkg.source.getDisplayName();
        const source_len = @min(source_name.len, 8);
        buffer.writeText(current_x, y, source_name[0..source_len], Style.default().withFg(pkg.source.getColor()));
        current_x += 10;
        
        // Package name
        const name_len = @min(pkg.name.len, 20);
        buffer.writeText(current_x, y, pkg.name[0..name_len], line_style);
        current_x += 24;
        
        // Version
        if (pkg.version) |version| {
            const ver_len = @min(version.len, 10);
            buffer.writeText(current_x, y, version[0..ver_len], self.info_style);
        }
        current_x += 12;
        
        // Description
        if (pkg.description) |desc| {
            const remaining_width = if (current_x < x + width) x + width - current_x else 0;
            const desc_len = @min(desc.len, remaining_width);
            if (desc_len > 0) {
                buffer.writeText(current_x, y, desc[0..desc_len], self.package_style);
            }
        }
        
        // Highlight selected row
        if (is_selected) {
            for (x..x + width) |col| {
                const cell = buffer.getCell(@as(u16, @intCast(col)), y);
                buffer.setCell(@as(u16, @intCast(col)), y, Cell.init(cell.char, bg_style.withFg(cell.style.fg)));
            }
        }
    }

    fn renderPackageDetails(self: *UniversalPackageBrowser, buffer: *Buffer, area: Rect) void {
        if (self.getSelectedPackage()) |pkg| {
            var y = area.y;
            
            // Package header
            const header = std.fmt.allocPrint(self.allocator, "{s} {s} {s}", .{ 
                pkg.source.getIcon(), pkg.name, pkg.version orelse "latest" 
            }) catch return;
            defer self.allocator.free(header);
            
            buffer.writeText(area.x, y, header, self.header_style);
            y += 2;
            
            // Description
            if (pkg.description) |desc| {
                buffer.writeText(area.x, y, "Description:", self.header_style);
                y += 1;
                
                // Word wrap description
                const words = std.mem.splitSequence(u8, desc, " ");
                var line = std.ArrayList(u8){};
                defer line.deinit(self.allocator);
                
                var word_iter = words;
                while (word_iter.next()) |word| {
                    if (line.items.len + word.len + 1 > area.width - 2) {
                        buffer.writeText(area.x + 2, y, line.items, self.package_style);
                        y += 1;
                        line.clearRetainingCapacity();
                    }
                    
                    if (line.items.len > 0) {
                        line.append(self.allocator, ' ') catch break;
                    }
                    line.appendSlice(self.allocator, word) catch break;
                }
                
                if (line.items.len > 0) {
                    buffer.writeText(area.x + 2, y, line.items, self.package_style);
                    y += 2;
                }
            }
            
            // Additional info
            const info_lines = [_][]const u8{
                std.fmt.allocPrint(self.allocator, "Source: {s} {s}", .{ pkg.source.getIcon(), pkg.source.getDisplayName() }) catch return,
                if (pkg.maintainer) |m| std.fmt.allocPrint(self.allocator, "Maintainer: {s}", .{m}) catch return else "Maintainer: Unknown",
                if (pkg.url) |u| std.fmt.allocPrint(self.allocator, "URL: {s}", .{u}) catch return else "",
                std.fmt.allocPrint(self.allocator, "Install Size: {d} KB", .{pkg.install_size}) catch return,
            };
            
            for (info_lines) |line| {
                if (line.len > 0 and y < area.y + area.height) {
                    buffer.writeText(area.x, y, line, self.info_style);
                    self.allocator.free(line);
                    y += 1;
                }
            }
        } else {
            buffer.writeText(area.x, area.y, "No package selected", self.info_style);
        }
    }

    fn renderRepositoryList(self: *UniversalPackageBrowser, buffer: *Buffer, area: Rect) void {
        var y = area.y;
        
        buffer.writeText(area.x, y, "📚 CONFIGURED REPOSITORIES", self.header_style);
        y += 2;
        
        for (self.repositories.items, 0..) |*repo, i| {
            if (y >= area.y + area.height) break;
            
            const is_selected = i == self.selected_repo;
            const line_style = if (is_selected) self.selected_style else self.package_style;
            
            const repo_display = repo.getDisplayName(self.allocator) catch continue;
            defer self.allocator.free(repo_display);
            
            buffer.writeText(area.x, y, repo_display, line_style);
            y += 1;
            
            if (y < area.y + area.height) {
                const url_text = std.fmt.allocPrint(self.allocator, "    {s}", .{repo.url}) catch continue;
                defer self.allocator.free(url_text);
                
                buffer.writeText(area.x, y, url_text, self.info_style);
                y += 1;
            }
        }
    }

    fn renderSearchInput(self: *UniversalPackageBrowser, buffer: *Buffer, area: Rect) void {
        var y = area.y;
        
        buffer.writeText(area.x, y, "🔍 SEARCH PACKAGES", self.header_style);
        y += 2;
        
        buffer.writeText(area.x, y, "Query: ", self.package_style);
        buffer.writeText(area.x + 7, y, self.search_input.items, self.selected_style);
        y += 2;
        
        buffer.writeText(area.x, y, "Press Enter to search, Esc to cancel", self.info_style);
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *UniversalPackageBrowser = @fieldParentPtr("widget", widget);
        
        switch (event) {
            .key => |key_event| {
                if (!key_event.pressed) return false;
                
                switch (key_event.key) {
                    .up => {
                        switch (self.current_view) {
                            .package_list => {
                                if (self.selected_package > 0) {
                                    self.selected_package -= 1;
                                }
                            },
                            .repository_list => {
                                if (self.selected_repo > 0) {
                                    self.selected_repo -= 1;
                                }
                            },
                            else => {},
                        }
                        return true;
                    },
                    .down => {
                        switch (self.current_view) {
                            .package_list => {
                                if (self.selected_package + 1 < self.filtered_packages.items.len) {
                                    self.selected_package += 1;
                                }
                            },
                            .repository_list => {
                                if (self.selected_repo + 1 < self.repositories.items.len) {
                                    self.selected_repo += 1;
                                }
                            },
                            else => {},
                        }
                        return true;
                    },
                    .enter => {
                        switch (self.current_view) {
                            .package_list => {
                                self.current_view = .package_details;
                            },
                            .search_input => {
                                self.searchPackages(self.search_options) catch {};
                                self.current_view = .package_list;
                            },
                            else => {
                                self.current_view = .package_list;
                            },
                        }
                        return true;
                    },
                    .escape => {
                        self.current_view = .package_list;
                        return true;
                    },
                    .char => |char| {
                        switch (char) {
                            '/' => {
                                self.current_view = .search_input;
                                return true;
                            },
                            'r' => {
                                self.current_view = .repository_list;
                                return true;
                            },
                            'q' => {
                                // Quit signal (handled by application)
                                return true;
                            },
                            else => {
                                if (self.current_view == .search_input) {
                                    self.search_input.append(self.allocator, char) catch {};
                                    return true;
                                }
                            },
                        }
                    },
                    .backspace => {
                        if (self.current_view == .search_input and self.search_input.items.len > 0) {
                            _ = self.search_input.pop();
                            return true;
                        }
                    },
                    .tab => {
                        // Cycle through source filters
                        const filters = [_]?PackageSource{ null, .aur, .chaotic_aur, .ziglibs, .custom_github, .pacman_repo };
                        var current_index: usize = 0;
                        
                        for (filters, 0..) |filter, i| {
                            if (std.meta.eql(filter, self.search_options.source_filter)) {
                                current_index = i;
                                break;
                            }
                        }
                        
                        current_index = (current_index + 1) % filters.len;
                        self.search_options.source_filter = filters[current_index];
                        self.updateFilters();
                        return true;
                    },
                    else => {},
                }
            },
            else => {},
        }
        
        return false;
    }

    fn resize(widget: *Widget, area: Rect) void {
        const self: *UniversalPackageBrowser = @fieldParentPtr("widget", widget);
        self.area = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *UniversalPackageBrowser = @fieldParentPtr("widget", widget);
        
        // Free packages
        for (self.packages.items) |*pkg| {
            self.allocator.free(pkg.name);
            if (pkg.version) |v| self.allocator.free(v);
            if (pkg.description) |d| self.allocator.free(d);
            if (pkg.maintainer) |m| self.allocator.free(m);
            if (pkg.url) |u| self.allocator.free(u);
            pkg.tags.deinit();
            pkg.dependencies.deinit();
        }
        self.packages.deinit(self.allocator);
        
        // Free repositories
        for (self.repositories.items) |*repo| {
            self.allocator.free(repo.name);
            self.allocator.free(repo.url);
            if (repo.api_endpoint) |endpoint| self.allocator.free(endpoint);
        }
        self.repositories.deinit(self.allocator);
        
        self.filtered_packages.deinit(self.allocator);
        self.search_input.deinit(self.allocator);
        
        if (self.status_message) |msg| {
            self.allocator.free(msg);
        }
        
        self.allocator.destroy(self);
    }
};

test "UniversalPackageBrowser widget creation" {
    const allocator = std.testing.allocator;

    const browser = try UniversalPackageBrowser.init(allocator);
    defer browser.widget.deinit();

    // Test search functionality
    try browser.setSearchQuery("reaper");
    try browser.searchPackages(SearchOptions{ .query = "reaper" });
    
    try std.testing.expect(browser.packages.items.len > 0);
    try std.testing.expect(browser.repositories.items.len >= 2); // At least AUR and ZigLibs
}
