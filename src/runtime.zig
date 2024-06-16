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
    @export(clock_gettime, .{ .name = "__wrap_clock_gettime", .linkage = .weak });

    if (builtin.os.tag == .wasi) {
        @export(stdwasi.errno_wasi, .{ .name = "errno", .linkage = .weak });

        // time
        @export(stdwasi.clock_time_get, .{ .name = "clock_time_get", .linkage = .weak });

        // fs
        // @export(stdwasi.fd_readdir, .{ .name = "fd_readdir", .linkage = .strong });

        if (!builtin.link_libc) {
            @export(main, .{ .name = "main", .linkage = .weak });

            @export(stdwasi.fd_write, .{ .name = "fd_write", .linkage = .weak });
            @export(stdwasi.fd_read, .{ .name = "fd_read", .linkage = .weak });
            @export(stdwasi.fd_seek, .{ .name = "fd_seek", .linkage = .weak });
        }
    }
}

/// main is used to call the "main" function in your root file if you don't link libc
fn main(_: c_int, _: [*]const [*:0]const u8) callconv(.C) void {
    _ = std.start.callMain();
}

/// openat is polyfilled as it doesn't have an implementation for devkitPPC
fn openat(dirfd: c_int, pathname: [*c]const u8, flags: c_int, _: std.posix.mode_t) callconv(.C) c_int {
    // TODO(jae): 2024-06-02
    // Make this actually use dirfd
    _ = dirfd; // autofix
    const file = c.open(pathname, flags);
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
    return struct {
        extern fn __real_write(fd: fd_t, buf: [*]const u8, nbyte: usize) isize;
    }.__real_write(fd, buf_ptr, count);
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
fn clock_gettime(clk_id: c_int, tp: *std.posix.timespec) callconv(.C) c_int {
    const CLOCK_MONOTONIC = if (builtin.os.tag == .wasi) @intFromEnum(std.posix.CLOCK.MONOTONIC) else std.posix.CLOCK.MONOTONIC;
    if (clk_id == CLOCK_MONOTONIC) {
        // TODO(jae): Consider making this happen at app startup with a function instead
        clock_init();

        const now = c.gettime() - clock_start;
        tp.tv_sec = @intCast(ticks_to_secs(now) + 946684800);
        tp.tv_nsec = @intCast(@mod(ticks_to_nanosecs(now), TB_NSPERSEC));
        return 0;
    }
    return struct {
        extern fn __real_clock_gettime(clk_id: c_int, tp: *std.posix.timespec) c_int;
    }.__real_clock_gettime(clk_id, tp);
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

    /// errno_wasi calls the underlying Wii toolchain errno for builds targetting .wasi
    fn errno_wasi() callconv(.C) *c_int {
        const _errno = struct {
            extern fn __errno() *c_int;
        }.__errno;
        return _errno();
    }

    /// errno_c uses the c_type.E rather than posix
    fn errno_c(rc: anytype) c_type.E {
        return if (rc == -1) @enumFromInt(rc) else .SUCCESS;
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

    // TODO: Implement for wasi
    // fn fd_readdir(fd: wasi.fd_t, buf: [*]u8, buf_len: usize, cookie: wasi.dircookie_t, bufused: *usize) callconv(.C) wasi.errno_t {
    //     _ = fd; // autofix
    //     _ = buf; // autofix
    //     _ = buf_len; // autofix
    //     _ = cookie; // autofix
    //     _ = bufused; // autofix
    //     return wasi.errno_t.FAULT;
    // }

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
