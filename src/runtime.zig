const std = @import("std");
const builtin = @import("builtin");
const c = @import("c/c.zig");

const std_c = @import("c/wii.zig");
const fd_t = std_c.fd_t;
const STDOUT_FILENO = std_c.STDOUT_FILENO;
const STDERR_FILENO = std_c.STDERR_FILENO;

comptime {
    @export(openat, .{ .name = "openat", .linkage = .weak });
    @export(write, .{ .name = "__wrap_write", .linkage = .weak });
    @export(clock_gettime, .{ .name = "__wrap_clock_gettime", .linkage = .weak });
    if (builtin.os.tag == .wasi) {
        @export(wasi_errno, .{ .name = "errno", .linkage = .strong });
    }
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
var printf_buffer: [64]u8 = undefined;
var printf_buffer_len: u32 = 0;

/// wrap "write" to get printf debugging, if the "fd" is STDOUT or STDERR we call print.
/// otherwise fallback to writing to the file descriptor
fn write(fd: i32, buf_ptr: [*]const u8, count: usize) callconv(.C) isize {
    if (fd == STDOUT_FILENO or fd == STDERR_FILENO) {
        if (!builtin.single_threaded) {
            return c.printf("%.*s", count, buf_ptr);
        }
        // If buffer is over current remaining print buffer size then
        // empty the print buffer and print current buffer
        const remaining_buffer_len = printf_buffer[printf_buffer_len..].len;
        const buf_len = count;
        if (buf_len >= remaining_buffer_len) {
            // https://stackoverflow.com/a/3767300
            _ = c.printf("%.*s%.*s", printf_buffer_len, printf_buffer[0..printf_buffer_len].ptr, count, buf_ptr);
            printf_buffer_len = 0;
            return @intCast(count);
        }
        // If have space, place in the buffer
        const remaining_buffer = printf_buffer[printf_buffer_len..];
        const buf = buf_ptr[0..count];
        @memcpy(remaining_buffer, buf);
        printf_buffer_len += count;
        if (buf[buf.len - 1] == '\n') {
            // https://stackoverflow.com/a/3767300
            _ = c.printf("%.*s", printf_buffer_len, printf_buffer[0..printf_buffer_len].ptr);
            printf_buffer_len = 0;
        }
        return @intCast(count);
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

var ticks_started = false;
var ticks_start: u64 = 0;

/// wrap clock_gettime to as otherwise clock_gettime just returns an error code which just causes a crash if
/// you use std.time.Timer.start()
fn clock_gettime(clk_id: c_int, tp: *std.posix.timespec) callconv(.C) c_int {
    const CLOCK_MONOTONIC = if (builtin.os.tag == .wasi) @intFromEnum(std.posix.CLOCK.MONOTONIC) else std.posix.CLOCK.MONOTONIC;
    if (clk_id == CLOCK_MONOTONIC) {
        if (!ticks_started) {
            // Sometimes c.gettime returns 0 so take a page from the SDL Wii port and store
            // the first c.gettime call
            // https://github.com/devkitPro/SDL/blob/c82262c2a361781d88c7bb1995b3b3f183cc514e/src/timer/ogc/SDL_systimer.c#L39
            ticks_start = c.gettime();
            ticks_started = true;
        }
        const now = c.gettime() - ticks_start;
        tp.tv_sec = @intCast(ticks_to_secs(now) + 946684800);
        tp.tv_nsec = @intCast(@mod(ticks_to_nanosecs(now), TB_NSPERSEC));
        return 0;
    }
    return struct {
        extern fn __real_clock_gettime(clk_id: c_int, tp: *std.posix.timespec) c_int;
    }.__real_clock_gettime(clk_id, tp);
}

/// wasi_errno calls the underlying Wii toolchain errno for builds targetting .wasi
fn wasi_errno() callconv(.C) *c_int {
    const _errno = struct {
        extern fn __errno() *c_int;
    }.__errno;
    return _errno();
}

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
