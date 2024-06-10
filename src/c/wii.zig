const builtin = @import("builtin");
const std = @import("std");
const c = @import("c.zig");

// TODO(jae): 2024-06-02
// Avoid relying on "wasi" for Wii builds and explore what the mappings
// need to actually be
const wasi = std.os.wasi;

pub const _errno = struct {
    extern fn __errno() *c_int;
}.__errno;

pub const PATH_MAX = 4096;

pub const mode_t = u32;
pub const time_t = i64;

pub const timespec = extern struct {
    tv_sec: time_t,
    tv_nsec: isize,

    pub fn fromTimestamp(tm: wasi.timestamp_t) timespec {
        const tv_sec: wasi.timestamp_t = tm / 1_000_000_000;
        const tv_nsec = tm - tv_sec * 1_000_000_000;
        return .{
            .tv_sec = @as(time_t, @intCast(tv_sec)),
            .tv_nsec = @as(isize, @intCast(tv_nsec)),
        };
    }

    pub fn toTimestamp(ts: timespec) wasi.timestamp_t {
        return @as(wasi.timestamp_t, @intCast(ts.tv_sec * 1_000_000_000)) +
            @as(wasi.timestamp_t, @intCast(ts.tv_nsec));
    }
};

pub const STDIN_FILENO = 0;
pub const STDOUT_FILENO = 1;
pub const STDERR_FILENO = 2;

pub const E = errno_t;
const errno_t = enum(u16) {
    SUCCESS = 0,
    @"2BIG" = 1,
    ACCES = 2,
    ADDRINUSE = 3,
    ADDRNOTAVAIL = 4,
    AFNOSUPPORT = 5,
    /// This is also the error code used for `WOULDBLOCK`.
    AGAIN = 6,
    ALREADY = 7,
    BADF = 8,
    BADMSG = 9,
    BUSY = 10,
    CANCELED = 11,
    CHILD = 12,
    CONNABORTED = 13,
    CONNREFUSED = 14,
    CONNRESET = 15,
    DEADLK = 16,
    DESTADDRREQ = 17,
    DOM = 18,
    DQUOT = 19,
    EXIST = 20,
    FAULT = 21,
    FBIG = 22,
    HOSTUNREACH = 23,
    IDRM = 24,
    ILSEQ = 25,
    INPROGRESS = 26,
    INTR = 27,
    INVAL = 28,
    IO = 29,
    ISCONN = 30,
    ISDIR = 31,
    LOOP = 32,
    MFILE = 33,
    MLINK = 34,
    MSGSIZE = 35,
    MULTIHOP = 36,
    NAMETOOLONG = 37,
    NETDOWN = 38,
    NETRESET = 39,
    NETUNREACH = 40,
    NFILE = 41,
    NOBUFS = 42,
    NODEV = 43,
    NOENT = 44,
    NOEXEC = 45,
    NOLCK = 46,
    NOLINK = 47,
    NOMEM = 48,
    NOMSG = 49,
    NOPROTOOPT = 50,
    NOSPC = 51,
    NOSYS = 52,
    NOTCONN = 53,
    NOTDIR = 54,
    NOTEMPTY = 55,
    NOTRECOVERABLE = 56,
    NOTSOCK = 57,
    /// This is also the code used for `NOTSUP`.
    OPNOTSUPP = 58,
    NOTTY = 59,
    NXIO = 60,
    OVERFLOW = 61,
    OWNERDEAD = 62,
    PERM = 63,
    PIPE = 64,
    PROTO = 65,
    PROTONOSUPPORT = 66,
    PROTOTYPE = 67,
    RANGE = 68,
    ROFS = 69,
    SPIPE = 70,
    SRCH = 71,
    STALE = 72,
    TIMEDOUT = 73,
    TXTBSY = 74,
    XDEV = 75,
    NOTCAPABLE = 76,
    _,
};

const clockid_t = i32;

pub const CLOCK = struct {
    /// system-wide monotonic clock (aka system time)
    pub const MONOTONIC: clockid_t = 0;
    /// system-wide real time clock
    pub const REALTIME: clockid_t = -1;
    /// clock measuring the used CPU time of the current process
    pub const PROCESS_CPUTIME_ID: clockid_t = -2;
    /// clock measuring the used CPU time of the current thread
    pub const THREAD_CPUTIME_ID: clockid_t = -3;
};

pub const IOV_MAX = 1024;
pub const S = struct {
    pub const IEXEC = @compileError("TODO audit this");
    pub const IFBLK = 0x6000;
    pub const IFCHR = 0x2000;
    pub const IFDIR = 0x4000;
    pub const IFIFO = 0xc000;
    pub const IFLNK = 0xa000;
    pub const IFMT = IFBLK | IFCHR | IFDIR | IFIFO | IFLNK | IFREG | IFSOCK;
    pub const IFREG = 0x8000;
    /// There's no concept of UNIX domain socket but we define this value here
    /// in order to line with other OSes.
    pub const IFSOCK = 0x1;
};
pub const fd_t = i32;
pub const pid_t = c_int;
pub const uid_t = u32;
pub const gid_t = u32;
pub const off_t = i64;
pub const ino_t = wasi.inode_t;
pub const dev_t = wasi.device_t;
pub const nlink_t = c_ulonglong;
pub const blksize_t = c_long;
pub const blkcnt_t = c_longlong;

pub const Stat = extern struct {
    dev: dev_t,
    ino: ino_t,
    nlink: nlink_t,
    mode: mode_t,
    uid: uid_t,
    gid: gid_t,
    __pad0: c_uint = 0,
    rdev: dev_t,
    size: off_t,
    blksize: blksize_t,
    blocks: blkcnt_t,
    atim: timespec,
    mtim: timespec,
    ctim: timespec,
    __reserved: [3]c_longlong = [3]c_longlong{ 0, 0, 0 },

    pub fn atime(self: @This()) timespec {
        return self.atim;
    }

    pub fn mtime(self: @This()) timespec {
        return self.mtim;
    }

    pub fn ctime(self: @This()) timespec {
        return self.ctim;
    }

    pub fn fromFilestat(stat: wasi.filestat_t) Stat {
        return .{
            .dev = stat.dev,
            .ino = stat.ino,
            .mode = switch (stat.filetype) {
                .UNKNOWN => 0,
                .BLOCK_DEVICE => S.IFBLK,
                .CHARACTER_DEVICE => S.IFCHR,
                .DIRECTORY => S.IFDIR,
                .REGULAR_FILE => S.IFREG,
                .SOCKET_DGRAM => S.IFSOCK,
                .SOCKET_STREAM => S.IFIFO,
                .SYMBOLIC_LINK => S.IFLNK,
                _ => 0,
            },
            .nlink = stat.nlink,
            .size = @intCast(stat.size),
            .atim = timespec.fromTimestamp(stat.atim),
            .mtim = timespec.fromTimestamp(stat.mtim),
            .ctim = timespec.fromTimestamp(stat.ctim),

            .uid = 0,
            .gid = 0,
            .rdev = 0,
            .blksize = 0,
            .blocks = 0,
        };
    }
};

pub const F = struct {
    pub const GETFD = 1;
    pub const SETFD = 2;
    pub const GETFL = 3;
    pub const SETFL = 4;
};

pub const FD_CLOEXEC = 1;

pub const F_OK = 0;
pub const X_OK = 1;
pub const W_OK = 2;
pub const R_OK = 4;

pub const SEEK = struct {
    pub const SET: wasi.whence_t = .SET;
    pub const CUR: wasi.whence_t = .CUR;
    pub const END: wasi.whence_t = .END;
};

pub const nfds_t = usize;

pub const pollfd = extern struct {
    fd: fd_t,
    events: i16,
    revents: i16,
};

pub const POLL = struct {
    pub const RDNORM = 0x1;
    pub const WRNORM = 0x2;
    pub const IN = RDNORM;
    pub const OUT = WRNORM;
    pub const ERR = 0x1000;
    pub const HUP = 0x2000;
    pub const NVAL = 0x4000;
};
