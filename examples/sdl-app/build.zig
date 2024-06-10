const std = @import("std");
const builtin = @import("builtin");
const wii = @import("zig-wii-sdk");

pub fn build(b: *std.Build) !void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .powerpc,
        // NOTE(jae): 2024-06-10
        // used ".wasi" hack to use std.fs.openFile, currently std.fs.createFile won't work with .wasi
        //
        // Ideally we'd just provide our own C override like this PR here:
        // PR here: https://github.com/ziglang/zig/pull/20241
        .os_tag = .wasi,
        .abi = .eabi,
        .cpu_model = .{ .explicit = &std.Target.powerpc.cpu.@"750" },
        .cpu_features_add = std.Target.powerpc.featureSet(&.{.hard_float}),
    });
    const optimize: std.builtin.OptimizeMode = .ReleaseSafe; // = b.standardOptimizeOption(.{});

    const exe = wii.addExecutable(b, .{
        .name = "sdl-app",
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
        .link_libc = true,
        .single_threaded = true,
    });

    // add SDL
    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = .ReleaseFast,
    });
    exe.linkLibrary(sdl_dep.artifact("sdl"));
    exe.root_module.addImport("sdl", sdl_dep.module("sdl"));

    // add zigimg
    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));

    // add zigwii
    const zig_wii_sdk_dep = b.dependency("zig-wii-sdk", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zigwii", zig_wii_sdk_dep.module("zigwii"));

    // Build *.elf app with gcc
    const elf_output = exe.addInstallElf();

    // Convert elf to dol file
    // const dol_output = try wii.addInstallElf2Dol(b, elf_output);

    // Run in Dolphin with "zig build run"
    try wii.runDolphinStep(b, elf_output);

    // Convert crash line address to code line with "zig build line -- 0x800b7308"
    try wii.runAddr2LineStep(b, elf_output);
}
