const std = @import("std");
const builtin = @import("builtin");
const Windows = @import("src/build_helper.zig").Windows;

const ext = if (builtin.target.os.tag == .windows) ".exe" else "";

var setup_devkitPro: ?std.Build.LazyPath = null;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("zigwii", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
}

pub fn devkitProPath(b: *std.Build) !std.Build.LazyPath {
    if (setup_devkitPro) |devkitPro| {
        return devkitPro;
    }
    const devkitProInstallPath: []const u8 = b.option([]const u8, "devkitpro", "Path to devkitpro") orelse blk: {
        detect_path: {
            switch (builtin.os.tag) {
                .windows => {
                    // For Windows installs, $DEVKITPRO is set to /opt/devkitpro as it's run via msys2
                    // so we auto-discover devkitPro via the registry
                    const key = Windows.RegistryWtf8.openKey(std.os.windows.HKEY_LOCAL_MACHINE, "SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\devkitProUpdater", .{}) catch |err| switch (err) {
                        error.KeyNotFound => break :detect_path,
                    };
                    const install_location: []const u8 = key.getString(b.allocator, "", "InstallLocation") catch |err| switch (err) {
                        error.ValueNameNotFound, error.StringNotFound => break :detect_path,
                        error.OutOfMemory, error.NotAString => return err,
                    };
                    break :blk install_location;
                },
                else => {
                    const install_location = std.process.getEnvVarOwned(b.allocator, "DEVKITPRO") catch |err| switch (err) {
                        error.EnvironmentVariableNotFound => break :detect_path,
                        else => return err,
                    };
                    break :blk install_location;
                },
            }
        }
        std.debug.print("Set DEVKITPRO in your environment variables or add \"devkitpro\" to your zig build settings.", .{});
        return error.MissingDevkitProPath;
    };
    if (devkitProInstallPath.len == 0) {
        std.debug.print("Cannot have empty \"devkitpro\" path", .{});
        return error.MissingDevkitProPath;
    }
    // TODO: Check if folders "devkitPPC", "libogc"
    // This is for detecting if Mac (and possibly Linux) users have run "sudo (dkp-)pacman -S wii-dev"

    // TODO: Check if cmake is installed (not here, only if cmake is needed like for compiling SDL2)
    // - Check if in PATH
    // - For Mac, fallback to: /Applications/CMake.app/Contents/bin
    // https://cmake.org/download/
    // https://github.com/Kitware/CMake/releases/download/v3.29.4/cmake-3.29.4-macos-universal.dmg
    //
    // "sudo (dkp-)pacman -Sy"
    // "sudo (dkp-)pacman -S cmake"
    const devkitPro: std.Build.LazyPath = .{ .cwd_relative = devkitProInstallPath };
    setup_devkitPro = devkitPro;
    return devkitPro;
}

/// Gives standard options for targetting Wii hardware
pub fn standardWiiTargetOptions(b: *std.Build) std.Build.ResolvedTarget {
    return b.resolveTargetQuery(.{
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
}

pub const StaticLib = struct {
    path: std.Build.LazyPath,
    basename: []const u8,
    system_libs: std.ArrayList(std.Build.Module.SystemLib),

    pub fn dirname(self: StaticLib) std.Build.LazyPath {
        return self.path.dirname();
    }
};

pub fn addInstallWiiArtifact(compile: *std.Build.Step.Compile) std.Build.LazyPath {
    const b = compile.root_module.owner;
    if (compile.kind != .obj and compile.kind != .lib) {
        @panic("expected Wii compile step artifact to be .obj or .lib");
    }
    return buildExecutable(b, compile) catch |err| @panic(@errorName(err));
}

pub const ExecutableOptions = struct {
    name: []const u8,
    /// If you want the executable to run on the same computer as the one
    /// building the package, pass the `host` field of the package's `Build`
    /// instance.
    target: std.Build.ResolvedTarget,
    root_source_file: ?std.Build.LazyPath = null,
    // version: ?std.SemanticVersion = null,
    optimize: std.builtin.OptimizeMode = .Debug,
    // code_model: std.builtin.CodeModel = .default,
    // linkage: ?std.builtin.LinkMode = null,
    // max_rss: usize = 0,
    link_libc: ?bool = null,
    single_threaded: ?bool = null,
    // pic: ?bool = null,
    // strip: ?bool = null,
    // unwind_tables: ?bool = null,
    // omit_frame_pointer: ?bool = null,
    // sanitize_thread: ?bool = null,
    // error_tracing: ?bool = null,
    // use_llvm: ?bool = null,
    // use_lld: ?bool = null,
    // zig_lib_dir: ?std.Build.LazyPath = null,
};

pub fn addExecutable(b: *std.Build, options: ExecutableOptions) *std.Build.Step.Compile {
    const target = options.target;
    const exe = b.addObject(.{
        .name = options.name,
        .root_source_file = options.root_source_file,
        .optimize = options.optimize,
        .target = target,
        .link_libc = options.link_libc,
        .single_threaded = options.single_threaded,
        // TODO(jae): 2024-06-12
        // Polyfill WASI-specific functions if targetting wasi
        .pic = if (target.result.os.tag == .wasi) true else null,
    });
    exe.bundle_compiler_rt = true; // fixes missing "__nekf2", etc when using std.json
    if (options.link_libc) |link_libc| {
        if (!link_libc) {
            exe.wasi_exec_model = .reactor; // hack to avoid clash with _start from libogc
        }
    }
    return exe;
}

/// getOutputPath
/// ie. "C:/Zig-SDK/examples/sdl-app/zig-out/bin/my-cool-app.elf"
fn getOutputPath(b: *std.Build, file: std.Build.LazyPath) []const u8 {
    const path = blk: {
        switch (file) {
            .generated => {
                break :blk file.getPath(b);
            },
            else => @panic("expected generated file"),
        }
    };
    return path;
}

/// getNameWithoutExtension
/// ie. "zig-out/bin/my-cool-app.elf" -> "my-cool-app"
fn getNameWithoutExtension(b: *std.Build, file: std.Build.LazyPath) []const u8 {
    const path = blk: {
        switch (file) {
            .generated => {
                break :blk file.getPath(b);
            },
            else => break :blk file.getDisplayName(),
        }
    };
    const filename = std.fs.path.basename(path);
    const index = std.mem.lastIndexOfScalar(u8, filename, '.') orelse return filename;
    return filename[0..index];
}

pub fn addInstallElf2Dol(b: *std.Build, elf_file: std.Build.LazyPath) !std.Build.LazyPath {
    const devkitPro = try devkitProPath(b);
    const name = getNameWithoutExtension(b, elf_file);

    // Convert elf to dol file
    const elf2dol = b.addSystemCommand(&(.{
        devkitPro.path(b, "tools/bin/elf2dol" ++ ext).getPath(b),
    }));
    elf2dol.addFileArg(elf_file);
    const dol_output = elf2dol.addOutputFileArg("app.dol");

    // Copy to zig-out/bin/%s.dol
    const dol = b.addInstallBinFile(dol_output, try std.fmt.allocPrint(b.allocator, "{s}.dol", .{name}));
    b.getInstallStep().dependOn(&dol.step);

    // Get path to installed dol
    const dol_installed_file = try b.allocator.create(std.Build.GeneratedFile);
    dol_installed_file.* = .{
        .path = b.getInstallPath(dol.dir, dol.dest_rel_path),
        .step = &dol.step,
    };
    const dol_installed: std.Build.LazyPath = .{
        .generated = .{
            .file = dol_installed_file,
        },
    };
    return dol_installed;
}

/// Add step "run" to allow you to run Dolphin with "zig build run"
pub fn runDolphinStep(b: *std.Build, elf_or_dol_path: std.Build.LazyPath) !void {
    const dolphin: []const u8 = switch (builtin.target.os.tag) {
        .macos => "Dolphin",
        .windows => "Dolphin.exe",
        else => "dolphin-emu",
    };
    const run_step = b.step("run", "Run in Dolphin");
    const emulator = b.addSystemCommand(&.{ dolphin, "-a", "LLE", "-e" });
    emulator.addFileArg(elf_or_dol_path);
    run_step.dependOn(&emulator.step);
}

/// Add step "line" to allow you to "addr2line" to convert a crash address to a line of code
/// ie. zig build line -- 0x800b7308
pub fn runAddr2LineStep(b: *std.Build, elf_or_dol_path: std.Build.LazyPath) !void {
    const devkitPro = try devkitProPath(b);
    const output_path = getOutputPath(b, elf_or_dol_path);

    // debug stack dump addresses using powerpc-eabi-addr2line
    const line_step = b.step("line", "Get line from crash address");
    if (b.args) |args| {
        for (args) |arg| {
            const addr2line = b.addSystemCommand(&(.{
                devkitPro.path(b, "devkitPPC/bin/powerpc-eabi-addr2line" ++ ext).getPath(b),
            }));
            addr2line.addArg("-e");
            // NOTE(jae): 2024-06-04
            // Don't use output as we don't want to rebuild the elf when calling this for debugging purposes
            // addr2line.addFileArg(elf_output);
            addr2line.addArg(output_path);
            addr2line.addArg(arg);
            line_step.dependOn(&addr2line.step);
        }
    }
}

pub const BuildExecutableOptions = struct {
    libraries: []const StaticLib,
    system_libraries: []const []const u8,
};

/// build .elf executable with devkitPro's GCC compiler
fn buildExecutable(b: *std.Build, exe: *std.Build.Step.Compile) !std.Build.LazyPath {
    const devkitPro = try devkitProPath(b);

    // extract static and system libraries and compile seperately
    var static_libraries = std.ArrayListUnmanaged(StaticLib){};
    var system_libraries = std.ArrayListUnmanaged([]const u8){};
    {
        var i: usize = 0;
        while (i < exe.root_module.link_objects.items.len) {
            var remove_link_object = false;
            const link_object = exe.root_module.link_objects.items[i];
            switch (link_object) {
                .other_step => |other_step| {
                    switch (other_step.kind) {
                        .lib => {
                            // add static library
                            const lib = try buildStaticLib(b, other_step);
                            try static_libraries.append(b.allocator, lib);

                            // remove this static library from depending steps
                            for (exe.root_module.depending_steps.keys()) |compile| {
                                var j: usize = 0;
                                while (j < compile.step.dependencies.items.len) : (j += 1) {
                                    const dep = compile.step.dependencies.items[j];
                                    if (dep == &other_step.step) {
                                        _ = compile.step.dependencies.orderedRemove(j);
                                        break;
                                    }
                                }
                            }
                            remove_link_object = true;
                        },
                        .obj => @panic(".obj on executable not supported"),
                        .exe, .@"test" => @panic(".exe or .test on executable not supported"),
                    }
                },
                .system_lib => |system_lib| {
                    try system_libraries.append(b.allocator, system_lib.name);
                    remove_link_object = true;
                },
                else => {
                    std.debug.panic("{s} not supported for executable", .{@tagName(link_object)});
                },
            }
            if (remove_link_object) {
                _ = exe.root_module.link_objects.orderedRemove(i);
                continue; // don't increment "i"
            }
            i += 1;
        }
    }

    const gcc = b.addSystemCommand(&(.{
        devkitPro.path(b, "devkitPPC/bin/powerpc-eabi-gcc" ++ ext).getPath(b),
    }));
    gcc.addArtifactArg(exe);
    // NOTE(jae): 2024-06-10
    // Tried to add "runtime.zig" as its own object file but got errors.
    // gcc.addArtifactArg(try addRuntimeObject(b, exe));
    gcc.addArgs(&(.{
        // "-z noexecstack", resolves warning: "missing .note.GNU-stack section implies executable stack"
        "-z",
        "noexecstack",
        "-g",
        "-DGEKKO",
        // search patch for rvl for changes made to gcc
        // https://raw.githubusercontent.com/devkitPro/buildscripts/c62e968c1eff366ed0c3812b59a4c4aa544bf87f/dkppc/patches/gcc-13.2.0.patch
        "-mrvl", // #define __wii__ and HW_RVL, targets the Wii, ie. Nintendo Revolution (RVL)
        "-mcpu=750",
        "-meabi",
        "-mhard-float",
        // wrap calls to "write" in std library so we can monkey patch it and make any STDOUT/STDERR logging
        // call "printf" instead so they appear in Dolphin emulator debug logs
        "-Wl,-wrap,write",
        // wrap clock_gettime to as otherwise clock_gettime just returns an error code which just causes a crash if
        // you use std.time.Timer.start()
        "-Wl,-wrap,clock_gettime",
    }));

    // add optimization flag
    if (exe.root_module.optimize) |optimize| {
        switch (optimize) {
            .ReleaseFast => gcc.addArg("-O2"),
            else => {},
        }
    }

    // Output *.map file
    // -Wl,-Map,zig.map
    {
        const wl_args = "-Wl,-Map,";
        const map_basename = try std.fmt.allocPrint(b.allocator, "{s}.map", .{exe.name});
        const map_output = gcc.addPrefixedOutputFileArg(wl_args, map_basename);
        const map_file = b.addInstallBinFile(map_output, map_basename);
        b.getInstallStep().dependOn(&map_file.step);
    }

    // EXPERIMENTAL: Compile with "addObject" using .ofmt = .c.
    // Currently has error: error: too many arguments to function 'openat'
    // const zig_header_path: std.Build.LazyPath = .{ .cwd_relative = "C:/zig/current/lib" };
    // gcc.addPrefixedDirectoryArg("-I", zig_header_path);

    // add macros and system include paths
    {
        // this iterates over all dependencies which includes "root"
        var it = exe.root_module.iterateDependencies(null, false);
        while (it.next()) |item| {
            const m = item.module;

            // add devkitpro / wii macros to module
            //
            // devkitPPC's GCC compiler defines these macros either via patching the compiler directly
            // or via the MACHDEP wii_rules (-DGEKKO)
            m.addCMacro("__wii__", "1");
            m.addCMacro("HW_RVL", "1");
            m.addCMacro("GEKKO", "1");
            m.addCMacro("__DEVKITPPC__", "1");
            m.addCMacro("__DEVKITPRO__", "1");

            // add system includes
            m.addSystemIncludePath(devkitPro.path(b, "libogc/include"));
            m.addSystemIncludePath(devkitPro.path(b, "devkitPPC/powerpc-eabi/include"));
        }
    }

    // Add library search paths
    gcc.addPrefixedDirectorySourceArg("-L", devkitPro.path(b, "libogc/lib/wii")); // core libraries
    // NOTE(jae): 2024-06-09
    // Not enabling by default as it would make builds be system dependant. The only thing this SDK relies on
    // at time of writing is devkitPro being installed
    // gcc.addPrefixedDirectorySourceArg("-L", devkitPro.path(b, "portlibs/wii/lib")); // add ported libraries

    // Link libraries
    for (static_libraries.items) |static_lib| {
        gcc.addPrefixedDirectorySourceArg("-L", static_lib.dirname());
        const lib_arg = std.fmt.allocPrint(b.allocator, "-l:{s}", .{std.fs.path.basename(static_lib.basename)}) catch @panic("OOM");
        gcc.addArg(lib_arg);
    }

    // Link system libraries defined on the libraries
    for (static_libraries.items) |static_lib| {
        for (static_lib.system_libs.items) |system_lib| {
            const lib_arg = try std.mem.concat(b.allocator, u8, &[_][]const u8{ "-l", system_lib.name });
            gcc.addArg(lib_arg);
        }
    }
    // Link system libraries on root module
    for (system_libraries.items) |system_library| {
        const lib_arg = try std.mem.concat(b.allocator, u8, &[_][]const u8{ "-l", system_library });
        gcc.addArg(lib_arg);
    }
    // Always link "ogc", otherwise the following error occurs:
    // - cannot find entry symbol _start; defaulting to 80004024
    gcc.addArg("-logc");

    // Example of various Wii system libraries provided by devkitPro
    // gcc.addArgs(&(.{ "-laesnd", "-lfat", "-lwiiuse", "-lbte", "-lwiikeyboard" }));
    // gcc.addArgs(&(.{ "-logc", "-lm" }));

    // Output binary
    gcc.addArgs(&(.{"-o"}));
    const elf_output = gcc.addOutputFileArg("app.elf");

    // Copy to zig-out/bin/%s.elf
    const elf = b.addInstallBinFile(elf_output, try std.fmt.allocPrint(b.allocator, "{s}.elf", .{exe.name}));
    b.getInstallStep().dependOn(&elf.step);

    // Get path to installed elf
    const elf_installed_file = try b.allocator.create(std.Build.GeneratedFile);
    elf_installed_file.* = .{
        .path = b.getInstallPath(elf.dir, elf.dest_rel_path),
        .step = &elf.step,
    };
    const elf_installed: std.Build.LazyPath = .{
        .generated = .{
            .file = elf_installed_file,
        },
    };

    return elf_installed;
}

pub fn buildStaticLib(b: *std.Build, lib: *std.Build.Step.Compile) !StaticLib {
    const devkitPro = try devkitProPath(b);
    const ar = b.addSystemCommand(&(.{
        devkitPro.path(b, "devkitPPC/bin/powerpc-eabi-ar" ++ ext).getPath(b),
    }));
    ar.addArg("rcs");
    // NOTE(jae): 2024-06-07
    // prefix the library name with "zig" to avoid any possibility of clashing with other system libraries
    const output_basename = try std.fmt.allocPrint(b.allocator, "libzig{s}.a", .{lib.name});
    const lib_output = ar.addOutputFileArg(output_basename);

    if (lib.root_module.root_source_file) |root_source_file| {
        _ = root_source_file; // autofix
        @panic("compiling Zig code as a static library is not supported");
    }

    var c_source_list = std.ArrayList(std.Build.Module.CSourceFile).init(b.allocator);
    var system_libs = std.ArrayList(std.Build.Module.SystemLib).init(b.allocator);
    for (lib.root_module.link_objects.items) |link_object| {
        switch (link_object) {
            .c_source_file => |c_source_file| {
                try c_source_list.append(c_source_file.*);
            },
            .c_source_files => |c_source_files| {
                const root = c_source_files.root;
                for (c_source_files.files) |c_file| {
                    try c_source_list.append(.{
                        .file = root.path(b, c_file),
                        .flags = c_source_files.flags,
                    });
                }
            },
            .system_lib => |sys_lib| {
                try system_libs.append(sys_lib);
            },
            else => {
                std.debug.panic("{s} not supported for static library", .{@tagName(link_object)});
            },
        }
    }
    for (c_source_list.items) |c_source| {
        const gcc = b.addSystemCommand(&(.{
            devkitPro.path(b, "devkitPPC/bin/powerpc-eabi-gcc" ++ ext).getPath(b),
        }));
        gcc.addArg("-g");
        if (lib.root_module.optimize) |optimize| {
            switch (optimize) {
                .ReleaseFast => gcc.addArg("-O2"),
                else => {},
            }
        }
        gcc.addArg("-DGEKKO");
        for (lib.root_module.c_macros.items) |c_macro| {
            gcc.addArg(c_macro);
        }
        gcc.addArgs(&(.{
            // search patch for rvl for changes made to gcc
            // https://raw.githubusercontent.com/devkitPro/buildscripts/c62e968c1eff366ed0c3812b59a4c4aa544bf87f/dkppc/patches/gcc-13.2.0.patch
            "-mrvl", // #define __wii__ and HW_RVL, targets the Wii, ie. Nintendo Revolution (RVL)
            "-mcpu=750",
            "-meabi",
            "-mhard-float",
        }));

        // Add system include paths
        gcc.addPrefixedDirectoryArg("-I", devkitPro.path(b, "libogc/include"));
        gcc.addPrefixedDirectoryArg("-I", devkitPro.path(b, "devkitPPC/powerpc-eabi/include"));

        // Add include paths
        for (lib.root_module.include_dirs.items) |include_dir| {
            switch (include_dir) {
                .path => |path| {
                    gcc.addPrefixedDirectoryArg("-I", path);
                },
                .config_header_step => |config_header| {
                    const path: std.Build.LazyPath = .{
                        .generated = .{
                            .file = &config_header.output_file,
                        },
                    };
                    gcc.addPrefixedDirectoryArg("-I", path.dirname());
                },
                else => {
                    std.debug.panic("{s} not supported for static library", .{@tagName(include_dir)});
                },
            }
        }

        // Add C source flags
        for (c_source.flags) |flag| {
            gcc.addArg(flag);
        }

        // make name pretty
        // ie. "sdl: compile SDL_string.c"
        const c_source_file = c_source.file;
        const basename = std.fs.path.basename(switch (c_source_file) {
            .dependency => |dep| if (dep.sub_path.len != 0) dep.sub_path else c_source_file.getDisplayName(),
            else => c_source_file.getDisplayName(),
        });

        // Output binary
        gcc.addArgs(&(.{"-c"}));
        gcc.addArgs(&(.{"-o"}));
        const o_basename = try std.mem.concat(b.allocator, u8, &[_][]const u8{ basename, ".o" });
        const o_output = gcc.addOutputFileArg(o_basename);
        gcc.addFileArg(c_source.file);

        // make name pretty
        // ie. "sdl: compile SDL_string.c"
        gcc.setName(try std.fmt.allocPrint(
            b.allocator,
            "{s}: compile {s}",
            .{ lib.name, basename },
        ));

        // add to library archive file (.a)
        ar.addFileArg(o_output);
    }
    return StaticLib{
        .path = lib_output,
        .basename = output_basename,
        .system_libs = system_libs,
    };
}

const DevkitProBashOptions = struct {
    /// cwd to run the bash script in, for example if you want to run a build process
    /// like cmake commands against SDL2, you'd want this to be the path to the SDL2 repository
    cwd: std.Build.LazyPath,
    shell_script_file: std.Build.LazyPath,
};

/// EXPERIMENTAL: Not public as we only use this to invoke things like "cmake" to build SDL2
/// as per the readme docs.
///
/// runDevkitProBash will run a bash file via the devkitPro environment
fn runDevkitProBash(b: *std.Build, options: DevkitProBashOptions) *std.Build.Step.Run {
    const devkitPro = try devkitProPath(b);

    const bash: *std.Build.Step.Run = bash_blk: {
        switch (builtin.os.tag) {
            .windows => {
                // Run msys2 bash
                const bash = b.addSystemCommand(&(.{
                    devkitPro.path(b, "msys2/usr/bin/bash").getPath(b),
                }));
                bash.setEnvironmentVariable("MSYSTEM", "MSYS"); // Matches configuration in /c/devkitPro/msys2/msys2.ini
                bash.setEnvironmentVariable("CHERE_INVOKING", "1"); // Invoke from current working directory
                bash.addArgs(&.{"-li"}); // Must run msys2 bash with login (-li) to setup various environment variables
                break :bash_blk bash;
            },
            else => {
                // Use dkp-pacman bash
                const bash = b.addSystemCommand(&(.{
                    devkitPro.path(b, "pacman/bin/bash").getPath(b),
                }));
                bash.addArgs(&.{"-li"}); // setup environment, honestly not sure if needed
                const path_location = try std.process.getEnvVarOwned(b.allocator, "PATH");
                // TODO: Find cmake in $PATH first, if not found, fallback to this for Mac OS
                const cmake_location = "/Applications/CMake.app/Contents/bin";
                const new_path = try std.fmt.allocPrint(b.allocator, "{s}:{s}", .{ path_location, cmake_location });
                bash.setEnvironmentVariable("PATH", new_path);
                break :bash_blk bash;
            },
        }
    };
    bash.setCwd(options.cwd); // ie. set working directory as the SDL2 repository
    bash.addFileArg(options.shell_script_file); // b.path("build_sdl.sh"));
    bash.setName(options.shell_script_file.getDisplayName());

    // If you build a directory with cmake, you'd want to make that path use the command as a step dependency
    // like this
    // const generated_file = b.allocator.create(std.Build.GeneratedFile) catch @panic("OOM");
    // generated_file.* = .{
    //     .path = sdl_build_path.getPath(b),
    //     .step = &cmd.step,
    // };
    // break :blk std.Build.LazyPath{ .generated = .{ .file = generated_file } };

    return bash;
}

// EXPERIMENTAL: Include runtime.zig as its own ".o" file so the user doesn't need to include it.
//
// We get this error:
// devkitPPC/bin/../lib/gcc/powerpc-eabi/13.1.0/../../../../powerpc-eabi/bin/ld.exe:
// errno: TLS reference in zig-app.o mismatches non-TLS definition in runtime.o section .text
fn addRuntimeObject(b: *std.Build, exe: *std.Build.Step.Compile) !*std.Build.Step.Compile {
    const devkitPro = try devkitProPath(b);
    const this_dep_dir: std.Build.LazyPath = .{ .cwd_relative = cwd };

    // add runtime.zig as runtime.o
    var runtime_lib = b.addObject(.{
        .name = "runtime",
        .root_source_file = this_dep_dir.path(b, "src/runtime.zig"),
        .optimize = .ReleaseFast,
        .target = exe.root_module.resolved_target.?,
        .link_libc = false,
        .single_threaded = false,
    });

    // add devkitpro / wii macros to module
    //
    // devkitPPC's GCC compiler defines these macros either via patching the compiler directly
    // or via the MACHDEP wii_rules (-DGEKKO)
    runtime_lib.root_module.addCMacro("__wii__", "1");
    runtime_lib.root_module.addCMacro("HW_RVL", "1");
    runtime_lib.root_module.addCMacro("GEKKO", "1");
    runtime_lib.root_module.addCMacro("__DEVKITPPC__", "1");
    runtime_lib.root_module.addCMacro("__DEVKITPRO__", "1");

    // add system includes
    runtime_lib.root_module.addSystemIncludePath(devkitPro.path(b, "libogc/include"));
    runtime_lib.root_module.addSystemIncludePath(devkitPro.path(b, "devkitPPC/powerpc-eabi/include"));

    return runtime_lib;
}

// NOTE(jae): 2024-06-04
// Experiment with compiling the entire Wii .elf file with Zig/LLVM/LD
// if (true) {
//     exe.linkLibC();
//     // Searching "rvl" to see what patches gcc uses
//     //
//     // CPP_OS_RVL_SPEC=-D__wii__ -DHW_RVL -ffunction-sections -fdata-sections
//     // https://raw.githubusercontent.com/devkitPro/buildscripts/c62e968c1eff366ed0c3812b59a4c4aa544bf87f/dkppc/patches/gcc-13.2.0.patch
//     // exe.name = try std.fmt.allocPrint(b.allocator, "{s}.elf", .{exe.name});
//     exe.setLinkerScript(devkitPro.path(b, "devkitPPC/powerpc-eabi/lib/rvl.ld"));
//     exe.setLibCFile(b.path("libc.txt"));
//     exe.addLibraryPath(devkitPro.path(b, "devkitPPC/powerpc-eabi/lib"));
//     exe.addLibraryPath(devkitPro.path(b, "libogc/lib/wii"));
//     exe.addLibraryPath(devkitPro.path(b, "devkitPPC/lib/gcc/powerpc-eabi/13.1.0"));
//     // exe.linkLibrary(sdl_dep.artifact("sdl"));
//     // exe.linkSystemLibrary("sysbase");
//     exe.link_function_sections = true; // CPP_OS_RVL_SPEC
//     exe.link_data_sections = true; // CPP_OS_RVL_SPEC
//     exe.link_gc_sections = true; // LINK_OS_OGC_SPEC
//     b.installArtifact(exe);
//
//     const dol = b.addInstallBinFile(exe.getEmittedBin(), try std.fmt.allocPrint(b.allocator, "{s}-experimental.elf", .{exe.name}));
//     b.getInstallStep().dependOn(&dol.step);
//     return;
// }

// Old hack to build libraries with devkit
// fn devkitLinkLibrary(run: *std.Build.Step.Run, artifact: *std.Build.Step.Compile) void {
//     const b = run.step.owner;
//
//     if (artifact.root_module.lib_paths.items.len > 0) {
//         // Use native libraries attached to the compile artifact if they exist
//         // This is a bit of a hack to expose a library built with cmake/msys2 in a downstream package
//         for (artifact.root_module.lib_paths.items) |lib_path| {
//             run.addPrefixedDirectorySourceArg("-L", lib_path);
//         }
//         var found_system_lib = false;
//         for (artifact.root_module.link_objects.items) |link_object| {
//             switch (link_object) {
//                 .system_lib => |system_lib| {
//                     const lib_arg = std.fmt.allocPrint(b.allocator, "-l:lib{s}.a", .{system_lib.name}) catch @panic("OOM");
//                     run.addArg(lib_arg);
//                     found_system_lib = true;
//                 },
//                 else => {
//                     continue;
//                 },
//             }
//         }
//         if (!found_system_lib) {
//             std.debug.panic("unable to find system library for: {s}", .{artifact.name});
//         }
//     } else {
//         const bin_file = artifact.getEmittedBin();
//         bin_file.addStepDependencies(&run.step);
//
//         // Use built library directly
//         run.addPrefixedDirectorySourceArg("-L", artifact.getEmittedBinDirectory());
//         const lib_arg = std.fmt.allocPrint(b.allocator, "-l:lib{s}.a", .{artifact.name}) catch @panic("OOM");
//         run.addArg(lib_arg);
//     }
// }

// pub fn addPrefixedArtifactArg(run: *std.Build.Step.Run, prefix: []const u8, artifact: *std.Build.Step.Compile) void {
//     const b = run.step.owner;
//
//     const bin_file = artifact.getEmittedBin();
//     const prefixed_file_source: std.Build.Step.Run.PrefixedLazyPath = .{
//         .prefix = b.dupe(prefix),
//         .lazy_path = bin_file.dupe(b),
//     };
//     run.argv.append(b.allocator, .{ .lazy_path = prefixed_file_source }) catch @panic("OOM");
//     bin_file.addStepDependencies(&run.step);
// }

/// cwd is the working directory of the zig-wii-sdk
const cwd = _cwd();

inline fn _cwd() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}
