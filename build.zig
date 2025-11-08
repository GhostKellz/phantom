//! Use `zig init --strip` next time to generate a project without comments.
const std = @import("std");

// Feature configuration structure
const Features = struct {
    basic_widgets: bool,
    data_widgets: bool,
    package_mgmt: bool,
    crypto: bool,
    system: bool,
    advanced: bool,
    terminal_widget: bool,
};

// Resolve feature flags based on preset or explicit options
fn resolveFeatures(preset: []const u8, explicit: struct {
    basic_widgets: ?bool,
    data_widgets: ?bool,
    package_mgmt: ?bool,
    crypto: ?bool,
    system: ?bool,
    advanced: ?bool,
    terminal_widget: ?bool,
}) Features {
    // Start with preset defaults
    var features: Features = undefined;

    if (std.mem.eql(u8, preset, "basic")) {
        features = Features{
            .basic_widgets = true,
            .data_widgets = false,
            .package_mgmt = false,
            .crypto = false,
            .system = false,
            .advanced = false,
            .terminal_widget = false,
        };
    } else if (std.mem.eql(u8, preset, "package-mgr")) {
        features = Features{
            .basic_widgets = true,
            .data_widgets = true,
            .package_mgmt = true,
            .crypto = false,
            .system = false,
            .advanced = true,
            .terminal_widget = true,
        };
    } else if (std.mem.eql(u8, preset, "crypto")) {
        features = Features{
            .basic_widgets = true,
            .data_widgets = true,
            .package_mgmt = false,
            .crypto = true,
            .system = false,
            .advanced = true,
            .terminal_widget = true,
        };
    } else if (std.mem.eql(u8, preset, "system")) {
        features = Features{
            .basic_widgets = true,
            .data_widgets = true,
            .package_mgmt = false,
            .crypto = false,
            .system = true,
            .advanced = true,
            .terminal_widget = true,
        };
    } else if (std.mem.eql(u8, preset, "full")) {
        features = Features{
            .basic_widgets = true,
            .data_widgets = true,
            .package_mgmt = true,
            .crypto = true,
            .system = true,
            .advanced = true,
            .terminal_widget = true,
        };
    } else {
        // Unknown preset, default to full
        std.debug.print("Warning: Unknown preset '{s}', defaulting to 'full'\n", .{preset});
        features = Features{
            .basic_widgets = true,
            .data_widgets = true,
            .package_mgmt = true,
            .crypto = true,
            .system = true,
            .advanced = true,
            .terminal_widget = true,
        };
    }

    // Override with explicit options if provided
    if (explicit.basic_widgets) |val| features.basic_widgets = val;
    if (explicit.data_widgets) |val| features.data_widgets = val;
    if (explicit.package_mgmt) |val| features.package_mgmt = val;
    if (explicit.crypto) |val| features.crypto = val;
    if (explicit.system) |val| features.system = val;
    if (explicit.advanced) |val| features.advanced = val;
    if (explicit.terminal_widget) |val| features.terminal_widget = val;

    return features;
}

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Phantom TUI Build Configuration Options
    // Preset configurations for common use cases
    const preset = b.option([]const u8, "preset", "Use case preset: basic, package-mgr, crypto, system, full (default)") orelse "full";

    // v0.7.0 Event Loop Backend Selection
    const event_loop = b.option([]const u8, "event-loop", "Event loop backend: simple (default) or zigzag (high-performance)") orelse "simple";
    const use_zigzag = std.mem.eql(u8, event_loop, "zigzag");

    // Individual feature flags (auto-configured based on preset, but can be overridden)
    const enable_basic_widgets = b.option(bool, "basic-widgets", "Enable basic widgets (Text, Block, List, Button, Input, TextArea)") orelse null;
    const enable_data_widgets = b.option(bool, "data-widgets", "Enable data display widgets (ProgressBar, Table, TaskMonitor)") orelse null;
    const enable_package_mgmt = b.option(bool, "package-mgmt", "Enable package management widgets (UniversalPackageBrowser, AURDependencies)") orelse null;
    const enable_crypto = b.option(bool, "crypto", "Enable blockchain/crypto widgets (BlockchainPackageBrowser)") orelse null;
    const enable_system = b.option(bool, "system", "Enable system monitoring widgets (SystemMonitor, NetworkTopology, CommandBuilder)") orelse null;
    const enable_advanced = b.option(bool, "advanced", "Enable advanced widgets (StreamingText, CodeBlock, Container)") orelse null;
    const enable_terminal_widget = b.option(bool, "terminal-widget", "Enable experimental terminal widget (PTY-backed)") orelse null;

    // Resolve feature flags based on preset or explicit options
    const features = resolveFeatures(preset, .{
        .basic_widgets = enable_basic_widgets,
        .data_widgets = enable_data_widgets,
        .package_mgmt = enable_package_mgmt,
        .crypto = enable_crypto,
        .system = enable_system,
        .advanced = enable_advanced,
        .terminal_widget = enable_terminal_widget,
    });

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    // Get zsync dependency
    const zsync_dep = b.dependency("zsync", .{
        .target = target,
        .optimize = optimize,
    });
    const zsync_mod = zsync_dep.module("zsync");

    // Get gcode dependency for Unicode processing
    const gcode_dep = b.dependency("gcode", .{
        .target = target,
        .optimize = optimize,
    });
    const gcode_mod = gcode_dep.module("gcode");

    // Get zfont dependency for advanced font rendering
    const zfont_dep = b.dependency("zfont", .{
        .target = target,
        .optimize = optimize,
    });
    const zfont_mod = zfont_dep.module("zfont");

    // Get zigzag dependency for high-performance event loop
    const zigzag_dep = b.dependency("zigzag", .{
        .target = target,
        .optimize = optimize,
    });
    const zigzag_mod = zigzag_dep.module("zigzag");

    // Get grove dependency for Tree-sitter syntax highlighting
    const grove_dep = b.dependency("grove", .{
        .target = target,
        .optimize = optimize,
    });
    const grove_mod = grove_dep.module("grove");

    // Get zontom dependency for TOML parsing
    const zontom_dep = b.dependency("zontom", .{
        .target = target,
        .optimize = optimize,
    });
    const zontom_mod = zontom_dep.module("zontom");

    const mod = b.addModule("phantom", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "zsync", .module = zsync_mod },
            .{ .name = "gcode", .module = gcode_mod },
            .{ .name = "zfont", .module = zfont_mod },
            .{ .name = "zigzag", .module = zigzag_mod },
            .{ .name = "grove", .module = grove_mod },
            .{ .name = "zontom", .module = zontom_mod },
        },
    });

    // Pass feature flags as comptime constants to the module
    // This creates conditional compilation based on build options
    const phantom_mod = b.addModule("phantom_config", .{
        .root_source_file = b.addWriteFiles().add("phantom_config.zig", std.fmt.allocPrint(b.allocator,
            \\pub const enable_basic_widgets = {};
            \\pub const enable_data_widgets = {};
            \\pub const enable_package_mgmt = {};
            \\pub const enable_crypto = {};
            \\pub const enable_system = {};
            \\pub const enable_advanced = {};
            \\pub const enable_terminal_widget = {};
            \\pub const use_zigzag_event_loop = {};
            \\pub const event_loop_backend = "{s}";
        , .{
            features.basic_widgets,
            features.data_widgets,
            features.package_mgmt,
            features.crypto,
            features.system,
            features.advanced,
            features.terminal_widget,
            use_zigzag,
            event_loop,
        }) catch @panic("Failed to create config")),
        .target = target,
    });

    // Add the config module as an import to the main phantom module
    mod.addImport("phantom_config", phantom_mod);

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // business logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "phantom",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (in the case of firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "phantom" is the name you will use in your source code to
                // import this module (e.g. `@import("phantom")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "phantom", .module = mod },
            },
        }),
    });
    exe.linkLibC();

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Package Manager Demo - requires package-mgmt widgets
    if (features.package_mgmt) {
        const pkg_demo = b.addExecutable(.{
            .name = "simple_package_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/simple_package_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        pkg_demo.linkLibC();
        b.installArtifact(pkg_demo);

        const run_pkg_demo = b.addRunArtifact(pkg_demo);
        const pkg_demo_step = b.step("demo-pkg", "Run the package manager demo");
        pkg_demo_step.dependOn(&run_pkg_demo.step);
    }

    // Ghostty Performance Demo - requires system widgets
    if (features.system) {
        const ghostty_demo = b.addExecutable(.{
            .name = "ghostty_performance_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/ghostty_performance_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        ghostty_demo.linkLibC();
        b.installArtifact(ghostty_demo);

        const run_ghostty_demo = b.addRunArtifact(ghostty_demo);
        const ghostty_demo_step = b.step("demo-ghostty", "Run the Ghostty NVIDIA performance demo");
        ghostty_demo_step.dependOn(&run_ghostty_demo.step);
    }

    // AI Chat CLI Demo - requires basic widgets
    if (features.basic_widgets) {
        const ai_chat_demo = b.addExecutable(.{
            .name = "ai_chat_cli",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/ai_chat_cli.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        ai_chat_demo.linkLibC();
        b.installArtifact(ai_chat_demo);

        const run_ai_chat_demo = b.addRunArtifact(ai_chat_demo);
        const ai_chat_demo_step = b.step("demo-ai-chat", "Run the AI Chat CLI demo");
        ai_chat_demo_step.dependOn(&run_ai_chat_demo.step);
    }

    // Performance Benchmark Suite
    {
        const bench = b.addExecutable(.{
            .name = "benchmark_suite",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/benchmark_suite.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        bench.linkLibC();
        b.installArtifact(bench);

        const run_bench = b.addRunArtifact(bench);
        const bench_step = b.step("benchmark", "Run performance benchmarks");
        bench_step.dependOn(&run_bench.step);
    }

    // ZION CLI Demo - requires basic widgets
    if (features.basic_widgets) {
        const zion_demo = b.addExecutable(.{
            .name = "zion_cli_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/zion_cli_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        zion_demo.linkLibC();
        b.installArtifact(zion_demo);

        const run_zion_demo = b.addRunArtifact(zion_demo);
        const zion_demo_step = b.step("demo-zion", "Run the ZION CLI interactive demo");
        zion_demo_step.dependOn(&run_zion_demo.step);
    }

    // Reaper AUR Demo - requires package management widgets
    if (features.package_mgmt) {
        const reaper_demo = b.addExecutable(.{
            .name = "reaper_aur_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/reaper_aur_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        reaper_demo.linkLibC();
        b.installArtifact(reaper_demo);

        const run_reaper_demo = b.addRunArtifact(reaper_demo);
        const reaper_demo_step = b.step("demo-reaper", "Run the Reaper AUR dependencies demo");
        reaper_demo_step.dependOn(&run_reaper_demo.step);
    }

    // Crypto Package Demo - requires crypto widgets
    if (features.crypto) {
        const crypto_demo = b.addExecutable(.{
            .name = "crypto_package_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/crypto_package_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        crypto_demo.linkLibC();
        b.installArtifact(crypto_demo);

        const run_crypto_demo = b.addRunArtifact(crypto_demo);
        const crypto_demo_step = b.step("demo-crypto", "Run the crypto/blockchain package demo");
        crypto_demo_step.dependOn(&run_crypto_demo.step);
    }

    // AUR Dependencies Demo - requires package management widgets
    if (features.package_mgmt) {
        const aur_demo = b.addExecutable(.{
            .name = "aur_dependencies_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/reaper_aur_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        aur_demo.linkLibC();
        b.installArtifact(aur_demo);

        const run_aur_demo = b.addRunArtifact(aur_demo);
        const aur_demo_step = b.step("demo-aur", "Run the AUR dependencies demo");
        aur_demo_step.dependOn(&run_aur_demo.step);
    }

    // Universal Package Browser Demo - requires package management widgets
    if (features.package_mgmt) {
        const package_browser_demo = b.addExecutable(.{
            .name = "package_browser_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/package_manager_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        package_browser_demo.linkLibC();
        b.installArtifact(package_browser_demo);

        const run_package_browser_demo = b.addRunArtifact(package_browser_demo);
        const package_browser_demo_step = b.step("demo-package-browser", "Run the universal package browser demo");
        package_browser_demo_step.dependOn(&run_package_browser_demo.step);
    }

    // Theme Gallery Demo - manifest hot reload showcase
    const theme_gallery_demo = b.addExecutable(.{
        .name = "theme_gallery_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/theme_gallery_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "phantom", .module = mod },
            },
        }),
    });
    theme_gallery_demo.linkLibC();
    b.installArtifact(theme_gallery_demo);

    const run_theme_gallery_demo = b.addRunArtifact(theme_gallery_demo);
    const theme_gallery_demo_step = b.step("demo-theme-gallery", "Run the theme gallery manifest demo");
    theme_gallery_demo_step.dependOn(&run_theme_gallery_demo.step);

    // VXFW Widget Framework Demo - always available
    const vxfw_demo = b.addExecutable(.{
        .name = "vxfw_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/vxfw_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "phantom", .module = mod },
            },
        }),
    });
    vxfw_demo.linkLibC();
    b.installArtifact(vxfw_demo);

    const run_vxfw_demo = b.addRunArtifact(vxfw_demo);
    const vxfw_demo_step = b.step("demo-vxfw", "Run the VXFW widget framework demo");
    vxfw_demo_step.dependOn(&run_vxfw_demo.step);

    // Fuzzy Search Demo - requires advanced widgets
    // TODO: Temporarily disabled due to Zig 0.16 type system compatibility issues
    // See: https://github.com/ziglang/zig/issues/fuzzy-search-error-union
    if (false and features.advanced) {
        const fuzzy_search_demo = b.addExecutable(.{
            .name = "fuzzy_search_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/fuzzy_search_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        fuzzy_search_demo.linkLibC();
        b.installArtifact(fuzzy_search_demo);

        const run_fuzzy_search_demo = b.addRunArtifact(fuzzy_search_demo);
        const fuzzy_search_demo_step = b.step("demo-fuzzy", "Run the fuzzy search theme picker demo");
        fuzzy_search_demo_step.dependOn(&run_fuzzy_search_demo.step);
    }

    // Grim Editor Demo - showcases font system, TextEditor, Unicode, GPU
    const grim_demo = b.addExecutable(.{
        .name = "grim_editor_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/grim_editor_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "phantom", .module = mod },
            },
        }),
    });
    grim_demo.linkLibC();
    b.installArtifact(grim_demo);

    const run_grim_demo = b.addRunArtifact(grim_demo);
    const grim_demo_step = b.step("demo-grim", "Run the Grim editor feature showcase");
    grim_demo_step.dependOn(&run_grim_demo.step);

    // Unicode Performance Benchmarks
    const unicode_bench = b.addExecutable(.{
        .name = "unicode_bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benches/unicode_bench.zig"),
            .target = target,
            .optimize = .ReleaseFast, // Always optimize benchmarks
            .imports = &.{
                .{ .name = "phantom", .module = mod },
                .{ .name = "gcode", .module = gcode_mod },
            },
        }),
    });
    unicode_bench.linkLibC();
    b.installArtifact(unicode_bench);

    const run_unicode_bench = b.addRunArtifact(unicode_bench);
    const unicode_bench_step = b.step("bench-unicode", "Run Unicode performance benchmarks");
    unicode_bench_step.dependOn(&run_unicode_bench.step);

    // Layout Engine Sandbox
    const layout_sandbox = b.addExecutable(.{
        .name = "layout_sandbox",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benches/layout_sandbox.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "phantom", .module = mod },
            },
        }),
    });
    layout_sandbox.linkLibC();
    b.installArtifact(layout_sandbox);

    const run_layout_sandbox = b.addRunArtifact(layout_sandbox);
    const layout_sandbox_step = b.step("bench-layout", "Run layout engine sandbox benchmark");
    layout_sandbox_step.dependOn(&run_layout_sandbox.step);

    // Rendering Performance Benchmarks
    const render_bench = b.addExecutable(.{
        .name = "render_bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benches/render_bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "phantom", .module = mod },
            },
        }),
    });
    render_bench.linkLibC();
    b.installArtifact(render_bench);

    const run_render_bench = b.addRunArtifact(render_bench);
    const render_bench_step = b.step("bench-render", "Run rendering performance benchmarks");
    render_bench_step.dependOn(&run_render_bench.step);

    // Run all benchmarks
    const bench_all_step = b.step("bench", "Run all performance benchmarks");
    bench_all_step.dependOn(unicode_bench_step);
    bench_all_step.dependOn(layout_sandbox_step);
    bench_all_step.dependOn(render_bench_step);

    // Feature Showcase Demo - highlights core widgets
    if (features.advanced or features.basic_widgets) {
        const feature_showcase = b.addExecutable(.{
            .name = "feature_showcase_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/feature_showcase_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        feature_showcase.linkLibC();
        b.installArtifact(feature_showcase);

        const run_feature_showcase = b.addRunArtifact(feature_showcase);
        const feature_showcase_step = b.step("demo-feature-showcase", "Run the feature showcase demo");
        feature_showcase_step.dependOn(&run_feature_showcase.step);
    }

    // Data Visualization Demo - Ratatui parity showcase
    if (features.data_widgets and features.advanced) {
        const data_viz_demo = b.addExecutable(.{
            .name = "data_visualization_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/data_visualization_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        data_viz_demo.linkLibC();
        b.installArtifact(data_viz_demo);

        const run_data_viz_demo = b.addRunArtifact(data_viz_demo);
        const data_viz_demo_step = b.step("demo-data-visualization", "Run the data visualization demo");
        data_viz_demo_step.dependOn(&run_data_viz_demo.step);

        const dashboard_demo = b.addExecutable(.{
            .name = "data_dashboard_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/data_dashboard_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        dashboard_demo.linkLibC();
        b.installArtifact(dashboard_demo);

        const run_dashboard_demo = b.addRunArtifact(dashboard_demo);
        const dashboard_demo_step = b.step("demo-data-dashboard", "Run the data-bound dashboard demo");
        dashboard_demo_step.dependOn(&run_dashboard_demo.step);
    }

    // Stability Test Demo
    if (features.basic_widgets) {
        const stability_test = b.addExecutable(.{
            .name = "stability_test_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/stability_test_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        b.installArtifact(stability_test);

        const run_stability_test = b.addRunArtifact(stability_test);
        const stability_test_step = b.step("demo-stability-test", "Run the stability test demo");
        stability_test_step.dependOn(&run_stability_test.step);
    }

    // Grove Syntax Highlighting Demo
    if (features.advanced) {
        const grove_demo = b.addExecutable(.{
            .name = "grove_syntax_demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/grove_syntax_demo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        grove_demo.linkLibC();
        b.installArtifact(grove_demo);

        const run_grove_demo = b.addRunArtifact(grove_demo);
        const grove_demo_step = b.step("run-grove-demo", "Run the Grove syntax highlighting demo");
        grove_demo_step.dependOn(&run_grove_demo.step);
    }

    if (features.advanced and features.data_widgets) {
        const terminal_session_demo = b.addExecutable(.{
            .name = "terminal_session_integration",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/terminal_session_integration.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "phantom", .module = mod },
                },
            }),
        });
        terminal_session_demo.linkLibC();
        b.installArtifact(terminal_session_demo);

        const run_terminal_session_demo = b.addRunArtifact(terminal_session_demo);
        const terminal_session_demo_step = b.step("demo-terminal-session", "Run the terminal session integration demo");
        terminal_session_demo_step.dependOn(&run_terminal_session_demo.step);
    }

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
