const std = @import("std");
const builtin = @import("builtin");
const wii = @import("zig-wii-sdk");

pub fn build(b: *std.Build) !void {
    const target = wii.standardWiiTargetOptions(b);
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
    const elf_output = wii.addInstallWiiArtifact(exe);

    // Convert elf to dol file
    // const dol_output = try wii.addInstallElf2Dol(b, elf_output);

    // Run in Dolphin with "zig build run"
    try wii.runDolphinStep(b, elf_output);

    // Convert crash line address to code line with "zig build line -- 0x800b7308"
    try wii.runAddr2LineStep(b, elf_output);
}
