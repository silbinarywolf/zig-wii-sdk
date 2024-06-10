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
    if (builtin.os.tag == .wasi) {
        @export(wasi_errno, .{ .name = "errno", .linkage = .strong });
    }
}

/// openat is polyfilled as it doesn't have an implementation for devkitPPC
fn openat(dirfd: c_int, pathname: [*c]const u8, flags: c_int) callconv(.C) c_int {
    // TODO(jae): 2024-06-02
    // Make this actually use dirfd
    _ = dirfd; // autofix
    const file = c.open(pathname, flags);
    return file;
}

/// wrap "write" to get printf debugging, if the "fd" is STDOUT or STDERR we call print.
/// otherwise fallback to writing to the file descriptor
fn write(fd: i32, buf: [*]const u8, count: usize) callconv(.C) isize {
    if (fd == STDOUT_FILENO or fd == STDERR_FILENO) {
        // https://stackoverflow.com/a/3767300
        return @intCast(c.printf("%.*s", count, buf));
    }
    const __real_write = struct {
        extern fn __real_write(fd: fd_t, buf: [*]const u8, nbyte: usize) isize;
    }.__real_write;
    return __real_write(fd, buf, count);
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
