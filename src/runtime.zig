const std = @import("std");
const builtin = @import("builtin");
const c = @import("c/c.zig");

const c_type = @import("c/wii.zig");
const fd_t = c_type.fd_t;
const STDOUT_FILENO = c_type.STDOUT_FILENO;
const STDERR_FILENO = c_type.STDERR_FILENO;

const root = @import("root");

comptime {
    @export(openat, .{ .name = "openat", .linkage = .weak });

    @export(write, .{ .name = "__wrap_write", .linkage = .weak });

    if (builtin.os.tag == .wasi) {
        @export(stdwasi.errno_export, .{ .name = "errno", .linkage = .weak });

        // time
        @export(stdwasi.clock_time_get, .{ .name = "clock_time_get", .linkage = .weak });

        // fs
        @export(stdwasi.fd_readdir, .{ .name = "fd_readdir", .linkage = .strong });

        if (!builtin.link_libc) {
            @export(main, .{ .name = "main", .linkage = .weak });

            @export(stdwasi.fd_write, .{ .name = "fd_write", .linkage = .weak });
            @export(stdwasi.fd_read, .{ .name = "fd_read", .linkage = .weak });
            @export(stdwasi.fd_seek, .{ .name = "fd_seek", .linkage = .weak });
        }
    } else {
        @export(clock_gettime, .{ .name = "__wrap_clock_gettime", .linkage = .weak });
    }
}

/// main is used to call the "main" function in your root file if you don't link libc
fn main(_: c_int, _: [*]const [*:0]const u8) callconv(.C) void {
    _ = std.start.callMain();
}

const Dir = struct {
    fd_t: c_int,
    dir: ?*c.DIR = null,
    /// only set if fd_readdir ran out of buffer and needs
    /// to read in the entry details on the next fd_readdir call
    dirent: ?*c.dirent = null,
};

const dir_fd_base = 5000;

var dir_fd_list = [_]Dir{
    .{ .fd_t = dir_fd_base + 0, .dir = null },
    .{ .fd_t = dir_fd_base + 1, .dir = null },
    .{ .fd_t = dir_fd_base + 2, .dir = null },
    .{ .fd_t = dir_fd_base + 3, .dir = null },
};

/// openat is polyfilled as it doesn't have an implementation for devkitPPC
fn openat(dirfd: c_int, pathname: [*c]const u8, flags_: c_int, _: std.posix.mode_t) callconv(.C) c_int {
    // TODO(jae): 2024-06-02
    // Make this actually use dirfd
    _ = dirfd; // autofix

    // Convert wasi.O flags into the C library flags if targetting wasi
    var flags: c_int = 0;
    if (builtin.os.tag == .wasi) {
        const wasi_flags: stdwasi.O = @bitCast(flags_);

        // set flags
        if (wasi_flags.APPEND) flags |= c.O_APPEND;
        if (wasi_flags.write and wasi_flags.read) {
            flags |= c.O_RDWR;
        } else {
            if (wasi_flags.write) flags |= c.O_WRONLY;
            if (wasi_flags.read) flags |= c.O_RDONLY;
        }
        if (wasi_flags.DIRECTORY) flags |= c.O_DIRECTORY;
    } else {
        flags = flags_;
    }

    // If opening directory, use hack and provide our own special "fd" in a reserved range
    if (flags & c.O_DIRECTORY != 0) {
        const dirname: [*c]const u8 = if (pathname[0] == 0) "." else pathname;
        const dir = c.opendir(dirname);
        if (dir == null) {
            if (builtin.os.tag == .wasi) {
                stdwasi.convert_system_errno_to_wasi();
            }
            return -1;
        }
        var found_dir_fd: ?*Dir = null;
        for (&dir_fd_list) |*dir_fd| {
            if (dir_fd.dir == null) {
                found_dir_fd = dir_fd;
                break;
            }
        }
        const dir_fd = found_dir_fd orelse {
            set_system_errno(.NFILE);
            return -1;
        };
        dir_fd.dir = dir;
        dir_fd.dirent = null;
        return dir_fd.fd_t;
    }

    // Open file
    const file = c.open(pathname, flags);
    if (file == -1) {
        if (builtin.os.tag == .wasi) {
            stdwasi.convert_system_errno_to_wasi();
        }
        return -1;
    }
    return file;
}

/// printf_buffer collects writes to printf until it ends with a newline character, then
/// we call c.printf so it'll print nicely in the Dolphin emulator console on one line.
// var printf_buffer = std.BoundedArray(u8, 64){};

/// wrap "write" to get printf debugging, if the "fd" is STDOUT or STDERR we call print.
/// otherwise fallback to writing to the file descriptor
fn write(fd: i32, buf_ptr: [*]const u8, count: usize) callconv(.C) isize {
    if (fd == STDOUT_FILENO or fd == STDERR_FILENO) {
        return c.printf("%.*s", count, buf_ptr);
        // NOTE(jae): 2024-06-13
        // std.debug.print doesn't end with \n but other log functions do...
        // so this logic isn't great.
        //
        // if (!builtin.single_threaded) {
        //     return c.printf("%.*s", count, buf_ptr);
        // }
        // const buf = buf_ptr[0..count];
        // printf_buffer.appendSlice(buf) catch |err| switch (err) {
        //     error.Overflow => {
        //         // If buffer is over current remaining print buffer size then
        //         // empty the print buffer and print current buffer
        //         if (printf_buffer.len == 0) {
        //             return c.printf("%.*s", count, buf_ptr);
        //         }
        //         // https://stackoverflow.com/a/3767300
        //         _ = c.printf("%.*s%.*s", @as(u32, @intCast(printf_buffer.len)), printf_buffer.buffer[0..].ptr, count, buf_ptr);
        //         printf_buffer.len = 0;
        //         return @intCast(count);
        //     },
        // };
        // if (printf_buffer.buffer[printf_buffer.len - 1] == '\n') {
        //     // https://stackoverflow.com/a/3767300
        //     _ = c.printf("%.*s", @as(u32, @intCast(printf_buffer.len)), printf_buffer.buffer[0..].ptr);
        //     printf_buffer.len = 0;
        // }
        // return @intCast(count);
    }
    const nwritten = struct {
        extern fn __real_write(fd: fd_t, buf: [*]const u8, nbyte: usize) isize;
    }.__real_write(fd, buf_ptr, count);
    if (nwritten == -1) {
        if (builtin.os.tag == .wasi) {
            stdwasi.convert_system_errno_to_wasi();
        }
        return -1;
    }
    return nwritten;
}

// https://github.com/devkitPro/libogc/blob/78972332fad6c2c2e04a5cfedb26edb2853b4251/gc/ogc/lwp_watchdog.h#L35
const TB_BUS_CLOCK = 162000000; // HW_DOL
// const TB_USPERSEC = 1000000;
const TB_NSPERSEC = 1000000000;
const TB_TIMER_CLOCK = (TB_BUS_CLOCK / 4000); //4th of the bus frequency

fn ticks_to_secs(ticks: u64) u64 {
    return @divFloor(ticks, TB_TIMER_CLOCK * 1000);
}

/// https://github.com/devkitPro/libogc/blob/78972332fad6c2c2e04a5cfedb26edb2853b4251/gc/ogc/lwp_watchdog.h#L38
fn ticks_to_nanosecs(ticks: u64) u64 {
    return @divFloor(ticks * 8000, TB_TIMER_CLOCK / 125);
}

var clock_has_initialized = false;
var clock_start: u64 = 0;

fn clock_init() void {
    if (!clock_has_initialized) {
        clock_start = c.gettime();
        clock_has_initialized = true;
    }
}

/// wrap clock_gettime to as otherwise clock_gettime just returns an error code which just causes a crash if
/// you use std.time.Timer.start()
///
/// Not used for wasi
fn clock_gettime(clk_id: c_int, tp: *std.posix.timespec) callconv(.C) c_int {
    const CLOCK_MONOTONIC = std.posix.CLOCK.MONOTONIC;
    if (clk_id == CLOCK_MONOTONIC) {
        // TODO(jae): Consider making this happen at app startup with a function instead
        clock_init();

        const now = c.gettime() - clock_start;
        tp.tv_sec = @intCast(ticks_to_secs(now) + 946684800);
        tp.tv_nsec = @intCast(@mod(ticks_to_nanosecs(now), TB_NSPERSEC));
        return 0;
    }
    // NOTE(jae): 2024-06-18
    // We're wrapping clock_gettime so we shouldn't convert the error code from c_type.E to wasi.C
    // as other C code could call this.
    //
    // Also Wasi targets call "clock_time_get" anyway
    return struct {
        extern fn __real_clock_gettime(clk_id: c_int, tp: *std.posix.timespec) c_int;
    }.__real_clock_gettime(clk_id, tp);
}

fn set_system_errno(new_errno: std.posix.E) void {
    struct {
        extern threadlocal var errno: c_int;
    }.errno = @intFromEnum(new_errno);
}

const exception_xfb = 0xC1700000;

// panic based off of libogc exception handler https://github.com/devkitPro/libogc/blob/master/libogc/exception.c
pub fn panic(msg: []const u8, stack_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = stack_trace; // autofix
    c.GX_AbortFrame();
    // c.VIDEO_SetFramebuffer(exception_xfb);
    // c.__console_init(exception_xfb, 20, 20, 640, 574, 1280);
    c.CON_EnableGecko(1, 1);

    c.kprintf("\n\n\n\tZig Panic occurred!\n");
    std.debug.print("panic: {s}", .{msg});

    while (true) {
        // c.PAD_ScanPads();

        // 		int buttonsDown = PAD_ButtonsDown(0);

        // 		if( (buttonsDown & PAD_TRIGGER_Z) || SYS_ResetButtonDown() ||
        // 			reload_timer == 0 )
        // 		{
        // 			kprintf("\n\tReload\n\n\n");
        // 			_CPU_ISR_Disable(level);
        // 			__reload ();
        // 		}

        // 		if ( buttonsDown & PAD_BUTTON_A )
        // 		{
        // 			kprintf("\n\tReset\n\n\n");
        // #if defined(HW_DOL)
        // 			SYS_ResetSystem(SYS_HOTRESET,0,FALSE);
        // #else
        // 			__reload ();
        // #endif
        // 		}

        // std.time.sleep(20000);

        // if(reload_timer > 0)
        // 	reload_timer--;
    }
}

/// provide os.tag == .wasi functions
const stdwasi = struct {
    const wasi = std.os.wasi;
    const clockid_t = wasi.clockid_t;
    const timestamp_t = wasi.timestamp_t;
    const errno_t = wasi.errno_t;
    const ciovec_t = wasi.ciovec_t;
    const iovec_t = wasi.iovec_t;
    const filedelta_t = wasi.filedelta_t;
    const whence_t = wasi.whence_t;
    const filesize_t = wasi.filesize_t;

    const O = packed struct(u32) {
        APPEND: bool = false,
        DSYNC: bool = false,
        NONBLOCK: bool = false,
        RSYNC: bool = false,
        SYNC: bool = false,
        _5: u7 = 0,
        CREAT: bool = false,
        DIRECTORY: bool = false,
        EXCL: bool = false,
        TRUNC: bool = false,
        _16: u8 = 0,
        NOFOLLOW: bool = false,
        EXEC: bool = false,
        read: bool = false,
        SEARCH: bool = false,
        write: bool = false,
        _: u3 = 0,
    };

    /// errno_export calls the underlying Wii toolchain errno for builds targetting .wasi
    fn errno_export() callconv(.C) *c_int {
        const _errno = struct {
            extern fn __errno() *c_int;
        }.__errno;
        return _errno();
    }

    // convert_system_errno_to_wasi converts error codes from posix.E values to wasi.E
    fn convert_system_errno_to_wasi() void {
        const errno: c_int = if (builtin.os.tag == .wasi) errno_export().* else @intFromEnum(std.posix.errno(-1));
        const system_errno: c_type.E = @enumFromInt(errno);
        // TODO(jae): 2024-06-19
        // Handle other conversions
        const wasi_errno: wasi.errno_t = switch (system_errno) {
            .SUCCESS => .SUCCESS,
            .PERM => .PERM,
            .NOENT => .NOENT,
            .INTR => .INTR,
            .IO => .IO,
            else => .FAULT, // TODO: Handle other conversions
        };
        set_errno(wasi_errno);
    }

    fn set_errno(new_errno: stdwasi.errno_t) void {
        struct {
            extern threadlocal var errno: c_int;
        }.errno = @intFromEnum(new_errno);
    }

    /// errno_c uses the c_type.E rather than posix or wasi as they're C calls
    fn errno_c(rc: anytype) c_type.E {
        return if (rc == -1) @enumFromInt(errno_export().*) else .SUCCESS;
    }

    /// clock_time_get calls gettime() from the Wii toolchain to get the nanoseconds
    fn clock_time_get(clock_id: clockid_t, precision: timestamp_t, timestamp: *timestamp_t) callconv(.C) errno_t {
        // TODO(jae): Consider making this happen at app startup with a function instead
        clock_init();

        _ = clock_id; // autofix
        _ = precision; // autofix
        const now = c.gettime() - clock_start;
        timestamp.* = ticks_to_nanosecs(now);
        return wasi.errno_t.SUCCESS;
    }

    fn fd_readdir(fd: wasi.fd_t, buf_ptr: [*]u8, buf_len: usize, cookie: wasi.dircookie_t, bufused: *usize) callconv(.C) wasi.errno_t {
        _ = cookie; // autofix
        if (fd < dir_fd_base) {
            // NOTE(jae): 2024-18-06
            // Zig currently crashes if you provide .BADF so we do this
            return wasi.errno_t.NOTCAPABLE;
        }
        var found_dir_fd: ?*Dir = null;
        for (&dir_fd_list) |*dir_fd| {
            if (dir_fd.fd_t == fd) {
                found_dir_fd = dir_fd;
                break;
            }
        }
        const dir_fd = found_dir_fd orelse {
            return wasi.errno_t.NOTCAPABLE;
        };
        var buf = buf_ptr[0..buf_len];
        var buf_index: u32 = 0;

        // If continuing from previous entry
        if (dir_fd.dirent) |it| {
            // clear from current dir
            dir_fd.dirent = null;

            // add entry
            const name = std.mem.span(@as([*:0]u8, @ptrCast(it.d_name[0..])));
            const entry_and_name_len = @sizeOf(wasi.dirent_t) + name.len;
            const entry: wasi.dirent_t = .{
                .ino = it.d_ino,
                .namlen = @intCast(name.len),
                .next = buf_index + entry_and_name_len,
                .type = switch (it.d_type) {
                    c.DT_REG => .REGULAR_FILE,
                    c.DT_DIR => .DIRECTORY,
                    else => unreachable,
                },
            };

            @memcpy(buf[buf_index .. buf_index + @sizeOf(wasi.dirent_t)], std.mem.asBytes(&entry));
            buf_index += @sizeOf(wasi.dirent_t);

            const dest_name = buf[buf_index .. buf_index + name.len];
            @memcpy(dest_name, name);
            buf_index += name.len;
        }

        while (true) {
            set_errno(.SUCCESS); // Set errno to zero to distinguish errors when calling readdir and it returns NULL
            const it: *c.dirent = c.readdir(dir_fd.dir) orelse {
                const errno = errno_c(-1);
                if (errno == .SUCCESS) {
                    bufused.* = 0;
                    return .SUCCESS;
                }
                // TODO: translate from c_type.E to wasi
                return .BADF;
            };
            const name = std.mem.span(@as([*:0]u8, @ptrCast(it.d_name[0..])));
            const entry_and_name_len = @sizeOf(wasi.dirent_t) + name.len;
            const entry: wasi.dirent_t = .{
                .ino = it.d_ino,
                .namlen = @intCast(name.len),
                .next = buf_index + entry_and_name_len,
                .type = switch (it.d_type) {
                    c.DT_REG => .REGULAR_FILE,
                    c.DT_DIR => .DIRECTORY,
                    else => unreachable,
                },
            };
            if (buf_index + entry_and_name_len >= buf.len) {
                dir_fd.dirent = it;
                break;
            }
            @memcpy(buf[buf_index .. buf_index + @sizeOf(wasi.dirent_t)], std.mem.asBytes(&entry));
            buf_index += @sizeOf(wasi.dirent_t);

            const dest_name = buf[buf_index .. buf_index + name.len];
            @memcpy(dest_name, name);
            buf_index += name.len;
        }
        bufused.* += buf_index;
        return .SUCCESS;
    }

    fn fd_write(fd: fd_t, iovs: [*]const ciovec_t, iovs_len: usize, nwritten: *usize) callconv(.C) errno_t {
        const c_write = struct {
            extern fn write(fd: fd_t, buf: [*]const u8, nbyte: usize) isize;
        }.write;

        const iovs_list = iovs[0..iovs_len];
        const curr_iovs = iovs_list[0];
        const buf = curr_iovs.base[0..curr_iovs.len];
        const rc = c_write(fd, buf[0..].ptr, buf.len);
        switch (errno_c(rc)) {
            .SUCCESS => {
                nwritten.* = @intCast(rc);
                return .SUCCESS;
            },
            .INTR => return .INTR,
            .INVAL => return .INVAL,
            .FAULT => return .FAULT,
            .AGAIN => return .AGAIN,
            .BADF => return .BADF, // Can be a race condition.
            .IO => return .IO,
            .ISDIR => return .ISDIR,
            .NOBUFS => return .NOBUFS,
            .NOMEM => return .NOMEM,
            .NOTCONN => return .NOTCONN,
            .CONNRESET => return .CONNRESET,
            .TIMEDOUT => return .TIMEDOUT,
            else => |err| return unexpectedErrno(err),
        }
    }

    extern fn read(fd: fd_t, buf: [*]u8, nbyte: usize) callconv(.C) isize;
    fn fd_read(fd: fd_t, iovs: [*]const iovec_t, iovs_len: usize, nread: *usize) callconv(.C) errno_t {
        const iovs_list = iovs[0..iovs_len];
        const curr_iovs = iovs_list[0];
        const buf = curr_iovs.base[0..curr_iovs.len];

        const rc = read(fd, buf[0..].ptr, buf.len);
        switch (errno_c(rc)) {
            .SUCCESS => {
                nread.* = @intCast(rc);
                return .SUCCESS;
            },
            .INTR => return .INTR,
            .INVAL => return .INVAL,
            .FAULT => return .FAULT,
            .AGAIN => return .AGAIN,
            .BADF => return .BADF, // Can be a race condition.
            .IO => return .IO,
            .ISDIR => return .ISDIR,
            .NOBUFS => return .NOBUFS,
            .NOMEM => return .NOMEM,
            .NOTCONN => return .NOTCONN,
            .CONNRESET => return .CONNRESET,
            .TIMEDOUT => return .TIMEDOUT,
            else => |err| return unexpectedErrno(err),
        }
    }

    extern fn lseek(fd: fd_t, offset: c.off_t, whence: usize) c.off_t;
    fn fd_seek(fd: fd_t, offset: filedelta_t, whence: whence_t, newoffset: *filesize_t) callconv(.C) errno_t {
        const new_whence: usize = switch (whence) {
            .SET => c_type.SEEK.SET,
            .CUR => c_type.SEEK.CUR,
            .END => c_type.SEEK.END,
        };
        const rc = lseek(fd, @bitCast(offset), new_whence);
        switch (errno_c(rc)) {
            .SUCCESS => {
                newoffset.* = @intCast(rc);
                return .SUCCESS;
            },
            .BADF => return .BADF, // always a race condition
            .INVAL => return .INVAL,
            .OVERFLOW => return .OVERFLOW,
            .SPIPE => return .SPIPE,
            .NXIO => return .NXIO,
            else => |err| return unexpectedErrno(err),
        }
    }

    /// Call this when you made a syscall or something that sets errno
    /// and you get an unexpected error.
    pub fn unexpectedErrno(err: c_type.E) errno_t {
        if (std.posix.unexpected_error_tracing) {
            std.debug.print("unexpected errno: {d}\n", .{@intFromEnum(err)});
            std.debug.dumpCurrentStackTrace(null);
        }
        // TODO: Either transform error enum type by tagName from system C to wasi or...
        // idk just keep this as unreachable
        unreachable;
    }
};

// NOTE(jae): 2024-06-05
// Consider adding pthread polyfill based on https://wiibrew.org/wiki/Pthread
// This might allow building Wii applications without needing them to be single threaded

// const STACKSIZE = 8 * 1024;

// typedef lwp_t pthread_t;
// typedef mutex_t pthread_mutex_t;
// typedef void* pthread_mutexattr_t;
// typedef int pthread_attr_t;

// inline int pthread_create(pthread_t *thread, const pthread_attr_t *attr, void *(*start_routine)(void*), void *arg);
// //int pthread_cancel(pthread_t thread);

// inline int pthread_mutex_init(pthread_mutex_t *mutex, const pthread_mutexattr_t *attr);
// inline int pthread_mutex_destroy(pthread_mutex_t *mutex);
// inline int pthread_mutex_lock(pthread_mutex_t *mutex);
// inline int pthread_mutex_unlock(pthread_mutex_t *mutex);

// //imp
// inline int pthread_create(pthread_t *thread, const pthread_attr_t *attr, void *(*start_routine)(void*), void *arg)
// {
// 	*thread = 0;
// 	return LWP_CreateThread(thread, start_routine, arg, 0, STACKSIZE, 64);
// }

// inline int pthread_mutex_init(pthread_mutex_t *mutex, const pthread_mutexattr_t *attr)
// {
// 	return LWP_MutexInit(mutex, 0);
// }
// inline int pthread_mutex_destroy(pthread_mutex_t *mutex){ return LWP_MutexDestroy(*mutex);}

// inline int pthread_mutex_lock(pthread_mutex_t *mutex) { return LWP_MutexLock(*mutex); }
// inline int pthread_mutex_trylock(pthread_mutex_t *mutex){ return LWP_MutexTryLock(*mutex);}
// inline int pthread_mutex_unlock(pthread_mutex_t *mutex) { return LWP_MutexUnlock(*mutex); }
