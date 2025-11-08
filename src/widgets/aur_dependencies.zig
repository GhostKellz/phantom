//! AUR Package Dependencies Widget - for Reaper and Arch Linux package management
const std = @import("std");
const ArrayList = std.array_list.Managed;
const Widget = @import("../widget.zig").Widget;
const Buffer = @import("../terminal.zig").Buffer;
const Cell = @import("../terminal.zig").Cell;
const Event = @import("../event.zig").Event;
const geometry = @import("../geometry.zig");
const style = @import("../style.zig");
const emoji = @import("../emoji.zig");

const Rect = geometry.Rect;
const Style = style.Style;

/// Package dependency relationship
pub const DependencyType = enum {
    depends, // Runtime dependency
    makedepends, // Build-time dependency
    optdepends, // Optional dependency
    checkdepends, // Test dependency
    conflicts, // Conflicting package
    provides, // Virtual package provided
    replaces, // Package being replaced

    pub fn getIcon(self: DependencyType) []const u8 {
        return switch (self) {
            .depends => "🔗",
            .makedepends => "🔨",
            .optdepends => "⭐",
            .checkdepends => "🧪",
            .conflicts => "⚠️",
            .provides => "📦",
            .replaces => "🔄",
        };
    }

    pub fn getColor(self: DependencyType) style.Color {
        return switch (self) {
            .depends => style.Color.bright_blue,
            .makedepends => style.Color.bright_yellow,
            .optdepends => style.Color.bright_green,
            .checkdepends => style.Color.bright_cyan,
            .conflicts => style.Color.bright_red,
            .provides => style.Color.bright_magenta,
            .replaces => style.Color.bright_white,
        };
    }
};

/// Package installation status
pub const PackageStatus = enum {
    installed,
    available,
    missing,
    outdated,
    building,
    failed,

    pub fn getEmoji(self: PackageStatus) []const u8 {
        return switch (self) {
            .installed => "✅",
            .available => "📦",
            .missing => "❌",
            .outdated => "🔄",
            .building => "⚙️",
            .failed => "💥",
        };
    }

    pub fn getStyle(self: PackageStatus) Style {
        return switch (self) {
            .installed => Style.withFg(style.Color.bright_green),
            .available => Style.withFg(style.Color.white),
            .missing => Style.withFg(style.Color.bright_red),
            .outdated => Style.withFg(style.Color.bright_yellow),
            .building => Style.withFg(style.Color.bright_cyan),
            .failed => Style.withFg(style.Color.bright_red).withBold(),
        };
    }
};

/// Package dependency information
pub const PackageDependency = struct {
    name: []const u8,
    version_constraint: ?[]const u8 = null, // e.g., ">=1.2.0", "=2.0.0"
    dependency_type: DependencyType,
    status: PackageStatus = .available,
    description: ?[]const u8 = null,
    repo: []const u8 = "aur", // "core", "extra", "community", "aur"
    install_size: u64 = 0, // in KB

    pub fn getDisplayName(self: *const PackageDependency, allocator: std.mem.Allocator) ![]const u8 {
        if (self.version_constraint) |constraint| {
            return std.fmt.allocPrint(allocator, "{s} {s}", .{ self.name, constraint });
        }
        return allocator.dupe(u8, self.name);
    }

    pub fn getFullInfo(self: *const PackageDependency, allocator: std.mem.Allocator) ![]const u8 {
        const display_name = try self.getDisplayName(allocator);
        defer allocator.free(display_name);

        const size_str = if (self.install_size > 0)
            std.fmt.allocPrint(allocator, " ({d} KB)", .{self.install_size}) catch ""
        else
            "";
        defer if (size_str.len > 0) allocator.free(size_str);

        return std.fmt.allocPrint(allocator, "{s} [{s}]{s}", .{ display_name, self.repo, size_str });
    }
};

/// Main package being analyzed
pub const Package = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    maintainer: []const u8,
    repo: []const u8 = "aur",
    status: PackageStatus = .available,
    dependencies: ArrayList(PackageDependency),

    pub fn getTotalDependencies(self: *const Package, dep_type: ?DependencyType) usize {
        if (dep_type) |dt| {
            var count: usize = 0;
            for (self.dependencies.items) |*dep| {
                if (dep.dependency_type == dt) count += 1;
            }
            return count;
        }
        return self.dependencies.items.len;
    }

    pub fn getTotalSize(self: *const Package) u64 {
        var total: u64 = 0;
        for (self.dependencies.items) |*dep| {
            total += dep.install_size;
        }
        return total;
    }
};

/// View mode for dependency visualization
pub const ViewMode = enum {
    tree, // Hierarchical tree view
    list, // Flat list view
    graph, // Dependency graph
    summary, // Summary statistics
};

/// AUR Dependencies widget
pub const AURDependencies = struct {
    widget: Widget,
    allocator: std.mem.Allocator,

    // Package data
    current_package: ?Package = null,
    dependency_tree: ArrayList(Package), // For recursive dependencies

    // Display options
    view_mode: ViewMode = .tree,
    show_optional: bool = true,
    show_build_deps: bool = true,
    show_installed_only: bool = false,
    filter_repo: ?[]const u8 = null, // Filter by repository

    // Interactive state
    selected_dependency: usize = 0,
    expanded_nodes: ArrayList(bool), // For tree view
    scroll_offset: usize = 0,

    // Search and filtering
    search_query: ArrayList(u8),
    filtered_dependencies: ArrayList(usize), // indices

    // Styling
    header_style: Style,
    package_style: Style,
    dependency_style: Style,
    selected_style: Style,
    info_style: Style,

    // Layout
    area: Rect = Rect.init(0, 0, 0, 0),

    const vtable = Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinit,
    };

    pub fn init(allocator: std.mem.Allocator) !*AURDependencies {
        const widget = try allocator.create(AURDependencies);
        widget.* = AURDependencies{
            .widget = Widget{ .vtable = &vtable },
            .allocator = allocator,
            .dependency_tree = ArrayList(Package).init(allocator),
            .expanded_nodes = ArrayList(bool).init(allocator),
            .search_query = ArrayList(u8).init(allocator),
            .filtered_dependencies = ArrayList(usize).init(allocator),
            .header_style = Style.withFg(style.Color.bright_cyan).withBold(),
            .package_style = Style.withFg(style.Color.bright_white).withBold(),
            .dependency_style = Style.withFg(style.Color.white),
            .selected_style = Style.withFg(style.Color.bright_yellow).withBold(),
            .info_style = Style.withFg(style.Color.bright_black),
        };

        return widget;
    }

    /// Set the package to analyze
    pub fn setPackage(self: *AURDependencies, package: Package) !void {
        // Free existing package data
        if (self.current_package) |*pkg| {
            self.allocator.free(pkg.name);
            self.allocator.free(pkg.version);
            self.allocator.free(pkg.description);
            self.allocator.free(pkg.maintainer);
            self.allocator.free(pkg.repo);
            for (pkg.dependencies.items) |*dep| {
                self.allocator.free(dep.name);
                if (dep.version_constraint) |vc| self.allocator.free(vc);
                if (dep.description) |desc| self.allocator.free(desc);
                self.allocator.free(dep.repo);
            }
            pkg.dependencies.deinit();
        }

        // Store owned copy
        self.current_package = Package{
            .name = try self.allocator.dupe(u8, package.name),
            .version = try self.allocator.dupe(u8, package.version),
            .description = try self.allocator.dupe(u8, package.description),
            .maintainer = try self.allocator.dupe(u8, package.maintainer),
            .repo = try self.allocator.dupe(u8, package.repo),
            .status = package.status,
            .dependencies = ArrayList(PackageDependency).init(self.allocator),
        };

        // Copy dependencies
        for (package.dependencies.items) |*dep| {
            const owned_dep = PackageDependency{
                .name = try self.allocator.dupe(u8, dep.name),
                .version_constraint = if (dep.version_constraint) |vc| try self.allocator.dupe(u8, vc) else null,
                .dependency_type = dep.dependency_type,
                .status = dep.status,
                .description = if (dep.description) |desc| try self.allocator.dupe(u8, desc) else null,
                .repo = try self.allocator.dupe(u8, dep.repo),
                .install_size = dep.install_size,
            };
            try self.current_package.?.dependencies.append(owned_dep);
        }

        // Initialize expanded nodes
        self.expanded_nodes.clearRetainingCapacity();
        for (0..self.current_package.?.dependencies.items.len) |_| {
            try self.expanded_nodes.append(true); // Expand all by default
        }

        // Update filtered list
        self.updateFilters();
    }

    /// Set view mode
    pub fn setViewMode(self: *AURDependencies, mode: ViewMode) void {
        self.view_mode = mode;
        self.updateFilters();
    }

    /// Toggle display options
    pub fn setDisplayOptions(self: *AURDependencies, options: struct {
        optional: bool = true,
        build_deps: bool = true,
        installed_only: bool = false,
    }) void {
        self.show_optional = options.optional;
        self.show_build_deps = options.build_deps;
        self.show_installed_only = options.installed_only;
        self.updateFilters();
    }

    /// Set repository filter
    pub fn filterByRepo(self: *AURDependencies, repo: ?[]const u8) void {
        if (self.filter_repo) |old_repo| {
            self.allocator.free(old_repo);
        }
        self.filter_repo = if (repo) |r| self.allocator.dupe(u8, r) catch null else null;
        self.updateFilters();
    }

    fn updateFilters(self: *AURDependencies) void {
        self.filtered_dependencies.clearRetainingCapacity();

        if (self.current_package) |*package| {
            for (package.dependencies.items, 0..) |*dep, i| {
                // Apply filters
                if (!self.show_optional and dep.dependency_type == .optdepends) continue;
                if (!self.show_build_deps and dep.dependency_type == .makedepends) continue;
                if (self.show_installed_only and dep.status != .installed) continue;
                if (self.filter_repo) |repo| {
                    if (!std.mem.eql(u8, dep.repo, repo)) continue;
                }

                // Apply search filter
                if (self.search_query.items.len > 0) {
                    if (std.mem.indexOf(u8, dep.name, self.search_query.items) == null) continue;
                }

                self.filtered_dependencies.append(i) catch break;
            }
        }

        // Reset selection if out of bounds
        if (self.selected_dependency >= self.filtered_dependencies.items.len) {
            self.selected_dependency = 0;
        }
    }

    fn render(widget: *Widget, buffer: *Buffer, area: Rect) void {
        const self: *AURDependencies = @fieldParentPtr("widget", widget);
        self.area = area;

        if (area.height == 0 or area.width == 0) return;

        var y: u16 = area.y;

        // Header with package info
        if (y < area.y + area.height) {
            self.renderHeader(buffer, area.x, y, area.width);
            y += 1;
        }

        // Package details
        if (self.current_package) |*package| {
            if (y < area.y + area.height) {
                self.renderPackageInfo(buffer, area.x, y, area.width, package);
                y += 1;
            }

            // Dependency statistics
            if (y < area.y + area.height) {
                self.renderStatistics(buffer, area.x, y, area.width, package);
                y += 2;
            }

            // Dependencies list/tree
            const deps_area = Rect.init(area.x, y, area.width, area.y + area.height - y);
            switch (self.view_mode) {
                .tree => self.renderTreeView(buffer, deps_area, package),
                .list => self.renderListView(buffer, deps_area, package),
                .graph => self.renderGraphView(buffer, deps_area, package),
                .summary => self.renderSummaryView(buffer, deps_area, package),
            }
        } else {
            // No package loaded
            const no_pkg_msg = "📦 No package selected. Use setPackage() to analyze dependencies.";
            if (y < area.y + area.height) {
                buffer.writeText(area.x, y, no_pkg_msg, self.info_style);
            }
        }
    }

    fn renderHeader(self: *AURDependencies, buffer: *Buffer, x: u16, y: u16, width: u16) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.header_style));

        const header = "📦 AUR DEPENDENCIES ANALYZER";
        buffer.writeText(x, y, header, self.header_style);

        // View mode indicator
        const mode_text = switch (self.view_mode) {
            .tree => "🌳 Tree",
            .list => "📝 List",
            .graph => "🕸️ Graph",
            .summary => "📊 Summary",
        };

        if (x + header.len + 4 + mode_text.len < x + width) {
            buffer.writeText(x + @as(u16, @intCast(header.len)) + 4, y, mode_text, self.info_style);
        }
    }

    fn renderPackageInfo(self: *AURDependencies, buffer: *Buffer, x: u16, y: u16, width: u16, package: *const Package) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.package_style));

        const pkg_info = std.fmt.allocPrint(self.allocator, "{s} {s} v{s} ({s})", .{ package.status.getEmoji(), package.name, package.version, package.repo }) catch return;
        defer self.allocator.free(pkg_info);

        const info_len = @min(pkg_info.len, width);
        buffer.writeText(x, y, pkg_info[0..info_len], package.status.getStyle());
    }

    fn renderStatistics(self: *AURDependencies, buffer: *Buffer, x: u16, y: u16, width: u16, package: *const Package) void {
        // Dependency counts by type
        const stats = [_]struct { name: []const u8, count: usize, emoji: []const u8 }{
            .{ .name = "Runtime", .count = package.getTotalDependencies(.depends), .emoji = "🔗" },
            .{ .name = "Build", .count = package.getTotalDependencies(.makedepends), .emoji = "🔨" },
            .{ .name = "Optional", .count = package.getTotalDependencies(.optdepends), .emoji = "⭐" },
            .{ .name = "Test", .count = package.getTotalDependencies(.checkdepends), .emoji = "🧪" },
        };

        var current_x = x;
        for (stats) |stat| {
            const stat_text = std.fmt.allocPrint(self.allocator, "{s}{s}:{d} ", .{ stat.emoji, stat.name, stat.count }) catch continue;
            defer self.allocator.free(stat_text);

            if (current_x + stat_text.len < x + width) {
                buffer.writeText(current_x, y, stat_text, self.dependency_style);
                current_x += @as(u16, @intCast(stat_text.len));
            }
        }

        // Total install size
        const total_size = package.getTotalSize();
        const size_text = std.fmt.allocPrint(self.allocator, "💾 Total: {d} KB", .{total_size}) catch return;
        defer self.allocator.free(size_text);

        if (current_x + size_text.len < x + width) {
            buffer.writeText(current_x, y, size_text, self.info_style);
        }
    }

    fn renderTreeView(self: *AURDependencies, buffer: *Buffer, area: Rect, package: *const Package) void {
        _ = package;

        var current_y = area.y;
        const visible_height = area.height;

        // Render filtered dependencies with tree structure
        for (self.filtered_dependencies.items, 0..) |dep_index, display_index| {
            if (display_index < self.scroll_offset) continue;
            if (current_y >= area.y + visible_height) break;

            const dep = &self.current_package.?.dependencies.items[dep_index];
            const is_selected = display_index == self.selected_dependency;

            self.renderDependencyLine(buffer, area.x, current_y, area.width, dep, is_selected, 0);
            current_y += 1;
        }
    }

    fn renderListView(self: *AURDependencies, buffer: *Buffer, area: Rect, package: *const Package) void {
        self.renderTreeView(buffer, area, package); // Same as tree for now
    }

    fn renderGraphView(self: *AURDependencies, buffer: *Buffer, area: Rect, package: *const Package) void {
        _ = package;

        // Simple graph visualization
        buffer.writeText(area.x, area.y, "🕸️ Graph view - Coming soon!", self.info_style);
        buffer.writeText(area.x, area.y + 1, "Dependencies would be shown as connected nodes", self.dependency_style);
    }

    fn renderSummaryView(self: *AURDependencies, buffer: *Buffer, area: Rect, package: *const Package) void {
        var y = area.y;

        // Repository breakdown
        var repo_counts = std.HashMap([]const u8, usize, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer repo_counts.deinit();

        for (package.dependencies.items) |*dep| {
            const result = repo_counts.getOrPut(dep.repo) catch continue;
            if (result.found_existing) {
                result.value_ptr.* += 1;
            } else {
                result.value_ptr.* = 1;
            }
        }

        buffer.writeText(area.x, y, "📊 REPOSITORY BREAKDOWN:", self.header_style);
        y += 1;

        var repo_iter = repo_counts.iterator();
        while (repo_iter.next()) |entry| {
            if (y >= area.y + area.height) break;

            const repo_line = std.fmt.allocPrint(self.allocator, "  {s}: {d} packages", .{ entry.key_ptr.*, entry.value_ptr.* }) catch continue;
            defer self.allocator.free(repo_line);

            buffer.writeText(area.x, y, repo_line, self.dependency_style);
            y += 1;
        }
    }

    fn renderDependencyLine(self: *AURDependencies, buffer: *Buffer, x: u16, y: u16, width: u16, dep: *const PackageDependency, is_selected: bool, indent: u16) void {
        buffer.fill(Rect.init(x, y, width, 1), Cell.withStyle(self.dependency_style));

        var current_x = x + indent;

        // Tree structure
        if (indent > 0) {
            buffer.writeText(current_x - 2, y, "├─", self.info_style);
        }

        // Status and type icons
        const status_icon = dep.status.getEmoji();
        const type_icon = dep.dependency_type.getIcon();
        buffer.writeText(current_x, y, status_icon, dep.status.getStyle());
        current_x += 2;
        buffer.writeText(current_x, y, type_icon, Style.withFg(dep.dependency_type.getColor()));
        current_x += 2;

        // Package name and version
        const display_name = dep.getDisplayName(self.allocator) catch return;
        defer self.allocator.free(display_name);

        const line_style = if (is_selected) self.selected_style else dep.status.getStyle();
        const available_width = if (current_x < x + width) x + width - current_x else 0;
        const name_len = @min(display_name.len, available_width);

        if (name_len > 0) {
            buffer.writeText(current_x, y, display_name[0..name_len], line_style);
            current_x += @as(u16, @intCast(name_len));
        }

        // Repository and size info
        if (current_x + 10 < x + width) {
            const info_text = std.fmt.allocPrint(self.allocator, " [{s}]", .{dep.repo}) catch return;
            defer self.allocator.free(info_text);

            buffer.writeText(current_x + 1, y, info_text, self.info_style);
        }
    }

    fn handleEvent(widget: *Widget, event: Event) bool {
        const self: *AURDependencies = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key_event| {
                if (!key_event.pressed) return false;

                switch (key_event.key) {
                    .up => {
                        if (self.selected_dependency > 0) {
                            self.selected_dependency -= 1;
                        }
                        return true;
                    },
                    .down => {
                        if (self.selected_dependency + 1 < self.filtered_dependencies.items.len) {
                            self.selected_dependency += 1;
                        }
                        return true;
                    },
                    .tab => {
                        // Cycle view modes
                        self.view_mode = switch (self.view_mode) {
                            .tree => .list,
                            .list => .graph,
                            .graph => .summary,
                            .summary => .tree,
                        };
                        return true;
                    },
                    .char => |char| {
                        switch (char) {
                            'o' => {
                                self.show_optional = !self.show_optional;
                                self.updateFilters();
                                return true;
                            },
                            'b' => {
                                self.show_build_deps = !self.show_build_deps;
                                self.updateFilters();
                                return true;
                            },
                            'i' => {
                                self.show_installed_only = !self.show_installed_only;
                                self.updateFilters();
                                return true;
                            },
                            '/' => {
                                // Start search mode (would need additional state)
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
        const self: *AURDependencies = @fieldParentPtr("widget", widget);
        self.area = area;
    }

    fn deinit(widget: *Widget) void {
        const self: *AURDependencies = @fieldParentPtr("widget", widget);

        // Free current package
        if (self.current_package) |*package| {
            self.allocator.free(package.name);
            self.allocator.free(package.version);
            self.allocator.free(package.description);
            self.allocator.free(package.maintainer);
            self.allocator.free(package.repo);
            for (package.dependencies.items) |*dep| {
                self.allocator.free(dep.name);
                if (dep.version_constraint) |vc| self.allocator.free(vc);
                if (dep.description) |desc| self.allocator.free(desc);
                self.allocator.free(dep.repo);
            }
            package.dependencies.deinit();
        }

        // Free filter repo
        if (self.filter_repo) |repo| {
            self.allocator.free(repo);
        }

        self.dependency_tree.deinit();
        self.expanded_nodes.deinit();
        self.search_query.deinit();
        self.filtered_dependencies.deinit();
        self.allocator.destroy(self);
    }
};

test "AURDependencies widget creation" {
    const allocator = std.testing.allocator;

    const widget = try AURDependencies.init(allocator);
    defer widget.widget.deinit();

    // Create test package
    var deps = ArrayList(PackageDependency).init(allocator);
    defer deps.deinit();

    try deps.append(PackageDependency{
        .name = "glibc",
        .dependency_type = .depends,
        .status = .installed,
        .repo = "core",
        .install_size = 12345,
    });

    const test_package = Package{
        .name = "reaper",
        .version = "6.70",
        .description = "Digital Audio Workstation",
        .maintainer = "aur-user",
        .repo = "aur",
        .status = .available,
        .dependencies = deps,
    };

    try widget.setPackage(test_package);
    widget.setViewMode(.summary);
    widget.setDisplayOptions(.{ .optional = false, .build_deps = true });

    try std.testing.expect(widget.current_package != null);
    try std.testing.expect(widget.view_mode == .summary);
}
