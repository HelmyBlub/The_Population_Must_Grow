const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});
    // const optimize: std.builtin.OptimizeMode = .ReleaseFast;
    const exe = b.addExecutable(.{
        .name = "thePopulationMustGrow",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (builtin.mode == .ReleaseFast) {
        // exe.subsystem = .Windows;
    }
    exe.addIncludePath(b.path("dependencies"));
    exe.addCSourceFile(.{ .file = b.path("dependencies/minimp3_ex.c") });

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    exe.root_module.linkLibrary(sdl_lib);
    b.installArtifact(exe);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.addIncludePath(b.path("dependencies"));
    unit_tests.addCSourceFile(.{ .file = b.path("dependencies/minimp3_ex.c") });
    unit_tests.root_module.linkLibrary(sdl_lib);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const zigimg_dependency = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    compileShared(exe, zigimg_dependency);
    compileShared(unit_tests, zigimg_dependency);
}

fn compileShared(compile: *std.Build.Step.Compile, zigimg: *std.Build.Dependency) void {
    const vulkan_sdk = "C:/Zeugs/VulkanSDK/1.4.304.1/";
    compile.addIncludePath(.{ .cwd_relative = vulkan_sdk ++ "Include" });
    compile.addIncludePath(.{ .cwd_relative = vulkan_sdk ++ "Include/vulkan" });
    compile.addLibraryPath(.{ .cwd_relative = vulkan_sdk ++ "lib" });
    compile.linkSystemLibrary("vulkan-1");

    compile.root_module.addImport("zigimg", zigimg.module("zigimg"));
}
