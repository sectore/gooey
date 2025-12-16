const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the zig-objc dependency
    const objc_dep = b.dependency("zig_objc", .{
        .target = target,
        .optimize = optimize,
    });

    // Create the gooey module
    const mod = b.addModule("gooey", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("objc", objc_dep.module("objc"));

    // Link macOS frameworks to the module (needed for tests too)
    mod.linkFramework("AppKit", .{});
    mod.linkFramework("Metal", .{});
    mod.linkFramework("QuartzCore", .{});
    mod.linkFramework("CoreFoundation", .{});
    mod.linkFramework("CoreVideo", .{});
    mod.linkFramework("CoreText", .{});
    mod.linkFramework("CoreGraphics", .{});
    mod.link_libc = true;

    // =========================================================================
    // Main Demo (Showcase)
    // =========================================================================

    const exe = b.addExecutable(.{
        .name = "gooey",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/examples/showcase.zig"), // Changed!
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gooey", .module = mod },
                .{ .name = "objc", .module = objc_dep.module("objc") },
            },
        }),
    });

    // const zgpu = b.dependency("zgpu", .{});
    // exe.root_module.addImport("zgpu", zgpu.module("root"));

    // if (target.result.os.tag != .emscripten) {
    //     exe.linkLibrary(zgpu.artifact("zdawn"));
    // }

    // b.installArtifact(exe);

    // Run step (default demo)
    const run_step = b.step("run", "Run the login form demo");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    // Enable Metal HUD for FPS/GPU stats
    //run_cmd.setEnvironmentVariable("MTL_HUD_ENABLED", "1");

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // =========================================================================
    // Pomodoro Example
    // =========================================================================

    const pomodoro_exe = b.addExecutable(.{
        .name = "pomodoro",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/examples/pomodoro.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gooey", .module = mod },
                .{ .name = "objc", .module = objc_dep.module("objc") },
            },
        }),
    });

    b.installArtifact(pomodoro_exe);

    // Run pomodoro example
    const run_pomodoro_step = b.step("run-pomodoro", "Run the pomodoro example");
    const run_pomodoro_cmd = b.addRunArtifact(pomodoro_exe);
    run_pomodoro_step.dependOn(&run_pomodoro_cmd.step);
    run_pomodoro_cmd.step.dependOn(b.getInstallStep());

    // =========================================================================
    // Liquid Glass Example
    // =========================================================================

    const glass_exe = b.addExecutable(.{
        .name = "glass",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/examples/glass.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gooey", .module = mod },
                .{ .name = "objc", .module = objc_dep.module("objc") },
            },
        }),
    });

    b.installArtifact(glass_exe);

    // Run glass example
    const run_glass_step = b.step("run-glass", "Run the glass example");
    const run_glass_cmd = b.addRunArtifact(glass_exe);
    run_glass_step.dependOn(&run_glass_cmd.step);
    run_glass_cmd.step.dependOn(b.getInstallStep());

    // =========================================================================
    // Counter Example
    // =========================================================================

    const counter_exe = b.addExecutable(.{
        .name = "counter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/examples/counter.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gooey", .module = mod },
                .{ .name = "objc", .module = objc_dep.module("objc") },
            },
        }),
    });

    b.installArtifact(counter_exe);

    // Run counter example
    const run_counter_step = b.step("run-counter", "Run the counter example");
    const run_counter_cmd = b.addRunArtifact(counter_exe);
    run_counter_step.dependOn(&run_counter_cmd.step);
    run_counter_cmd.step.dependOn(b.getInstallStep());

    // =========================================================================
    // Layout Example
    // =========================================================================

    const layout_exe = b.addExecutable(.{
        .name = "layout",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/examples/layout.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gooey", .module = mod },
                .{ .name = "objc", .module = objc_dep.module("objc") },
            },
        }),
    });

    b.installArtifact(layout_exe);

    // Run layout example
    const run_layout_step = b.step("run-layout", "Run the layout example");
    const run_layout_cmd = b.addRunArtifact(layout_exe);
    run_layout_step.dependOn(&run_layout_cmd.step);
    run_layout_cmd.step.dependOn(b.getInstallStep());

    // =========================================================================
    // Dynamic Counters Example
    // =========================================================================

    const dynamic_counters_exe = b.addExecutable(.{
        .name = "dynamic_counters",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/examples/dynamic_counters.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gooey", .module = mod },
                .{ .name = "objc", .module = objc_dep.module("objc") },
            },
        }),
    });

    b.installArtifact(dynamic_counters_exe);

    // Run dynamic_counters example
    const run_dynamic_counters_step = b.step("run-dynamic-counters", "Run the dynamic_counters example");
    const run_dynamic_counters_cmd = b.addRunArtifact(dynamic_counters_exe);
    run_dynamic_counters_step.dependOn(&run_dynamic_counters_cmd.step);
    run_dynamic_counters_cmd.step.dependOn(b.getInstallStep());

    const actions_exe = b.addExecutable(.{
        .name = "actions_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/examples/actions.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gooey", .module = mod },
                .{ .name = "objc", .module = objc_dep.module("objc") },
            },
        }),
    });

    b.installArtifact(actions_exe);

    // Run focus demo
    const run_actions_step = b.step("run-actions", "Run the actions demo");
    const run_actions_cmd = b.addRunArtifact(actions_exe);
    run_actions_step.dependOn(&run_actions_cmd.step);
    run_actions_cmd.step.dependOn(b.getInstallStep());

    // =========================================================================
    // WebAssembly Build (browser)
    // =========================================================================

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const wasm_exe = b.addExecutable(.{
        .name = "gooey",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/platform/wgpu/web/main.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
        }),
    });

    // Add shaders directory so @embedFile can find them
    wasm_exe.root_module.addAnonymousImport("unified_wgsl", .{
        .root_source_file = b.path("src/platform/wgpu/shaders/unified.wgsl"),
    });
    wasm_exe.root_module.addAnonymousImport("text_wgsl", .{
        .root_source_file = b.path("src/platform/wgpu/shaders/text.wgsl"),
    });

    // Create geometry module (no dependencies)
    const geometry_module = b.createModule(.{
        .root_source_file = b.path("src/core/geometry.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });

    // Create scene module first (it has no dependencies)
    const scene_module = b.createModule(.{
        .root_source_file = b.path("src/core/scene.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "geometry", .module = geometry_module },
        },
    });

    // Create unified module with scene dependency
    const unified_module = b.createModule(.{
        .root_source_file = b.path("src/platform/wgpu/unified.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "scene", .module = scene_module },
        },
    });

    // Add modules to wasm executable
    wasm_exe.root_module.addImport("scene", scene_module);
    wasm_exe.root_module.addImport("unified", unified_module);

    // WASM-specific settings
    wasm_exe.entry = .disabled; // No _start, we use exports
    wasm_exe.rdynamic = true; // Export all pub functions

    // Install to web/ directory
    const wasm_install = b.addInstallArtifact(wasm_exe, .{
        .dest_dir = .{ .override = .{ .custom = "web" } },
    });

    // Copy HTML shell to output directory
    const html_install = b.addInstallFile(
        b.path("web/index.html"),
        "web/index.html",
    );

    const wasm_step = b.step("wasm", "Build WebAssembly module");
    wasm_step.dependOn(&wasm_install.step);
    wasm_step.dependOn(&html_install.step);

    // =========================================================================
    // Tests
    // =========================================================================

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
