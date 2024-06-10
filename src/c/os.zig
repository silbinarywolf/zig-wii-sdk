const std = @import("std");
const c = @import("c.zig");

/// os is the C operating system definitions, ie. c/wasi.zig
pub const os = @import("wii.zig");

pub const pthread_mutex_t = @compileError("pthread not supported by Wii library, see runtime.zig for comment. Must compile single threaded");

// pub const pthread_mutex_t = extern struct {
//     // Size of pthread_mutex_t on 32-bit systems is 24-bytes
//     data: [24]u8 align(@alignOf(usize)) = [_]u8{0} ** 24,
// };
// pub const pthread_cond_t = extern struct {
//     data: [48]u8 align(@alignOf(usize)) = [_]u8{0} ** 48,
// };

// NOTE(jae): 2024-06-03
// I think AT is not actually supported for the Wii as it also doesn't support "openat"
// we polyfill that.
pub const AT = struct {
    /// Special value used to indicate openat should use the current working directory
    pub const FDCWD = -2;

    // /// Do not follow symbolic links
    // pub const SYMLINK_NOFOLLOW = 0x100;

    // /// Remove directory instead of unlinking file
    // pub const REMOVEDIR = 0x200;

    // /// Follow symbolic links.
    // pub const SYMLINK_FOLLOW = 0x400;

    // /// Suppress terminal automount traversal
    // pub const NO_AUTOMOUNT = 0x800;

    // /// Allow empty relative pathname
    // pub const EMPTY_PATH = 0x1000;

    // /// Type of synchronisation required from statx()
    // pub const STATX_SYNC_TYPE = 0x6000;

    // /// - Do whatever stat() does
    // pub const STATX_SYNC_AS_STAT = 0x0000;

    // /// - Force the attributes to be sync'd with the server
    // pub const STATX_FORCE_SYNC = 0x2000;

    // /// - Don't sync attributes with the server
    // pub const STATX_DONT_SYNC = 0x4000;

    // /// Apply to the entire subtree
    // pub const RECURSIVE = 0x8000;
};

// NOTE(jae): 2024-06-03
// Copied from lib/std/os/linux.zig, section: .powerpc, .powerpcle, .powerpc64, .powerpc64le
pub const O = packed struct(u32) {
    ACCMODE: std.posix.ACCMODE = .RDONLY,
    _2: u4 = 0,
    CREAT: bool = false,
    EXCL: bool = false,
    NOCTTY: bool = false,
    TRUNC: bool = false,
    APPEND: bool = false,
    NONBLOCK: bool = false,
    DSYNC: bool = false,
    ASYNC: bool = false,
    DIRECTORY: bool = false,
    NOFOLLOW: bool = false,
    LARGEFILE: bool = false,
    DIRECT: bool = false,
    NOATIME: bool = false,
    CLOEXEC: bool = false,
    SYNC: bool = false,
    PATH: bool = false,
    TMPFILE: bool = false,
    _: u9 = 0,
};
