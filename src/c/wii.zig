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

/// powerpc-eabi\include\sys\syslimits.h
pub const PATH_MAX = 1024;

pub const mode_t = u32;
const time_t = i64;

pub const timespec = extern struct {
    tv_sec: time_t,
    tv_nsec: isize,
};

pub const STDIN_FILENO = 0;
pub const STDOUT_FILENO = 1;
pub const STDERR_FILENO = 2;

pub const E = errno_t;

/// errno_t copied from linux.zig and modified
/// to match powerpc-eabi\include\sys\errno.h
const errno_t = enum(u16) {
    /// No error occurred.
    /// Same code used for `NSROK`.
    SUCCESS = 0,
    /// Operation not permitted
    PERM = c.EPERM,
    /// No such file or directory
    NOENT = c.ENOENT,
    /// No such process
    SRCH = c.ESRCH,
    /// Interrupted system call
    INTR = c.EINTR,
    /// I/O error
    IO = c.EIO,
    /// No such device or address
    NXIO = c.ENXIO,
    /// Arg list too long
    @"2BIG" = c.E2BIG,
    /// Exec format error
    NOEXEC = c.ENOEXEC,
    /// Bad file number
    BADF = c.EBADF,
    /// No child processes
    CHILD = c.ECHILD,
    /// Try again
    /// Also means: WOULDBLOCK: operation would block
    AGAIN = c.EAGAIN,
    /// Out of memory
    NOMEM = c.ENOMEM,
    /// Permission denied
    ACCES = c.EACCES,
    /// Bad address
    FAULT = c.EFAULT,
    /// Block device required
    /// Requires "__LINUX_ERRNO_EXTENSIONS__"
    NOTBLK = 15,
    /// Device or resource busy
    BUSY = c.EBUSY,
    /// File exists
    EXIST = c.EEXIST,
    /// Cross-device link
    XDEV = c.EXDEV,
    /// No such device
    NODEV = c.ENODEV,
    /// Not a directory
    NOTDIR = c.ENOTDIR,
    /// Is a directory
    ISDIR = c.EISDIR,
    /// Invalid argument
    INVAL = c.EINVAL,
    /// File table overflow
    NFILE = c.ENFILE,
    /// Too many open files
    MFILE = c.EMFILE,
    /// Not a typewriter
    NOTTY = c.ENOTTY,
    /// Text file busy
    TXTBSY = c.ETXTBSY,
    /// File too large
    FBIG = c.EFBIG,
    /// No space left on device
    NOSPC = c.ENOSPC,
    // /// Illegal seek
    SPIPE = c.ESPIPE,
    // /// Read-only file system
    // ROFS = 30,
    // /// Too many links
    // MLINK = 31,
    // /// Broken pipe
    // PIPE = 32,
    // /// Math argument out of domain of func
    // DOM = 33,
    // /// Math result not representable
    // RANGE = 34,
    // /// Resource deadlock would occur
    // DEADLK = 35,
    // /// File name too long
    // NAMETOOLONG = 36,
    // /// No record locks available
    // NOLCK = 37,
    // /// Function not implemented
    // NOSYS = 38,
    // /// Directory not empty
    // NOTEMPTY = 39,
    // /// Too many symbolic links encountered
    // LOOP = 40,
    // /// No message of desired type
    // NOMSG = 42,
    // /// Identifier removed
    // IDRM = 43,
    // /// Channel number out of range
    // CHRNG = 44,
    // /// Level 2 not synchronized
    // L2NSYNC = 45,
    // /// Level 3 halted
    // L3HLT = 46,
    // /// Level 3 reset
    // L3RST = 47,
    // /// Link number out of range
    // LNRNG = 48,
    // /// Protocol driver not attached
    // UNATCH = 49,
    // /// No CSI structure available
    // NOCSI = 50,
    // /// Level 2 halted
    // L2HLT = 51,
    // /// Invalid exchange
    // BADE = 52,
    // /// Invalid request descriptor
    // BADR = 53,
    // /// Exchange full
    // XFULL = 54,
    // /// No anode
    // NOANO = 55,
    // /// Invalid request code
    // BADRQC = 56,
    // /// Invalid slot
    // BADSLT = 57,
    // /// Bad font file format
    // BFONT = 59,
    // /// Device not a stream
    // NOSTR = 60,
    // /// No data available
    // NODATA = 61,
    // /// Timer expired
    // TIME = 62,
    // /// Out of streams resources
    // NOSR = 63,
    // /// Machine is not on the network
    // NONET = 64,
    // /// Package not installed
    // NOPKG = 65,
    // /// Object is remote
    // REMOTE = 66,
    // /// Link has been severed
    // NOLINK = 67,
    // /// Advertise error
    // ADV = 68,
    // /// Srmount error
    // SRMNT = 69,
    // /// Communication error on send
    // COMM = 70,
    // /// Protocol error
    // PROTO = 71,
    // /// Multihop attempted
    // MULTIHOP = 72,
    // /// RFS specific error
    // DOTDOT = 73,
    // /// Not a data message
    // BADMSG = 74,
    // /// Value too large for defined data type
    OVERFLOW = c.EOVERFLOW, // 139
    // /// Name not unique on network
    // NOTUNIQ = 76,
    // /// File descriptor in bad state
    // BADFD = 77,
    // /// Remote address changed
    // REMCHG = 78,
    // /// Can not access a needed shared library
    // LIBACC = 79,
    // /// Accessing a corrupted shared library
    // LIBBAD = 80,
    // /// .lib section in a.out corrupted
    // LIBSCN = 81,
    // /// Attempting to link in too many shared libraries
    // LIBMAX = 82,
    // /// Cannot exec a shared library directly
    // LIBEXEC = 83,
    // /// Illegal byte sequence
    // ILSEQ = 84,
    // /// Interrupted system call should be restarted
    // RESTART = 85,
    // /// Streams pipe error
    // STRPIPE = 86,
    // /// Too many users
    // USERS = 87,
    // /// Socket operation on non-socket
    // NOTSOCK = 88,
    // /// Destination address required
    // DESTADDRREQ = 89,
    // /// Message too long
    // MSGSIZE = 90,
    // /// Protocol wrong type for socket
    // PROTOTYPE = 91,
    // /// Protocol not available
    // NOPROTOOPT = 92,
    // /// Protocol not supported
    // PROTONOSUPPORT = 93,
    // /// Socket type not supported
    // SOCKTNOSUPPORT = 94,
    // /// Operation not supported on transport endpoint
    // /// This code also means `NOTSUP`.
    // OPNOTSUPP = 95,
    // /// Protocol family not supported
    // PFNOSUPPORT = 96,
    // /// Address family not supported by protocol
    // AFNOSUPPORT = 97,
    // /// Address already in use
    // ADDRINUSE = 98,
    // /// Cannot assign requested address
    // ADDRNOTAVAIL = 99,
    // /// Network is down
    // NETDOWN = 100,
    // /// Network is unreachable
    // NETUNREACH = 101,
    // /// Network dropped connection because of reset
    // NETRESET = 102,
    // /// Software caused connection abort
    // CONNABORTED = 103,
    /// Connection reset by peer
    CONNRESET = c.ECONNRESET,
    /// No buffer space available
    NOBUFS = c.ENOBUFS, // 105
    // /// Transport endpoint is already connected
    // ISCONN = 106,
    // /// Transport endpoint is not connected
    NOTCONN = c.ENOTCONN, // 128
    // /// Cannot send after transport endpoint shutdown
    // SHUTDOWN = 108,
    // /// Too many references: cannot splice
    // TOOMANYREFS = 109,
    /// Connection timed out
    TIMEDOUT = c.ETIMEDOUT, // 116
    // /// Connection refused
    // CONNREFUSED = 111,
    // /// Host is down
    // HOSTDOWN = 112,
    // /// No route to host
    // HOSTUNREACH = 113,
    // /// Operation already in progress
    // ALREADY = 114,
    // /// Operation now in progress
    // INPROGRESS = 115,
    // /// Stale NFS file handle
    // STALE = 116,
    // /// Structure needs cleaning
    // UCLEAN = 117,
    // /// Not a XENIX named type file
    // NOTNAM = 118,
    // /// No XENIX semaphores available
    // NAVAIL = 119,
    // /// Is a named type file
    // ISNAM = 120,
    // /// Remote I/O error
    // REMOTEIO = 121,
    // /// Quota exceeded
    // DQUOT = 122,
    // /// No medium found
    // NOMEDIUM = 123,
    // /// Wrong medium type
    // MEDIUMTYPE = 124,
    // /// Operation canceled
    // CANCELED = 125,
    // /// Required key not available
    // NOKEY = 126,
    // /// Key has expired
    // KEYEXPIRED = 127,
    // /// Key has been revoked
    // KEYREVOKED = 128,
    // /// Key was rejected by service
    // KEYREJECTED = 129,
    // // for robust mutexes
    // /// Owner died
    // OWNERDEAD = 130,
    // /// State not recoverable
    // NOTRECOVERABLE = 131,
    // /// Operation not possible due to RF-kill
    // RFKILL = 132,
    // /// Memory page has hardware error
    // HWPOISON = 133,
    // // nameserver query return codes
    // /// DNS server returned answer with no data
    // NSRNODATA = 160,
    // /// DNS server claims query was misformatted
    // NSRFORMERR = 161,
    // /// DNS server returned general failure
    // NSRSERVFAIL = 162,
    // /// Domain name not found
    // NSRNOTFOUND = 163,
    // /// DNS server does not implement requested operation
    // NSRNOTIMP = 164,
    // /// DNS server refused query
    // NSRREFUSED = 165,
    // /// Misformatted DNS query
    // NSRBADQUERY = 166,
    // /// Misformatted domain name
    // NSRBADNAME = 167,
    // /// Unsupported address family
    // NSRBADFAMILY = 168,
    // /// Misformatted DNS reply
    // NSRBADRESP = 169,
    // /// Could not contact DNS servers
    // NSRCONNREFUSED = 170,
    // /// Timeout while contacting DNS servers
    // NSRTIMEOUT = 171,
    // /// End of file
    // NSROF = 172,
    // /// Error reading file
    // NSRFILE = 173,
    // /// Out of memory
    // NSRNOMEM = 174,
    // /// Application terminated lookup
    // NSRDESTRUCTION = 175,
    // /// Domain name is too long
    // NSRQUERYDOMAINTOOLONG = 176,
    // /// Domain name is too long
    // NSRCNAMELOOP = 177,
    _,
};

// devkitPPC\powerpc-eabi\include\time.h
pub const CLOCK = struct {
    pub const REALTIME_COARSE = 0;
    pub const REALTIME = 1;
    pub const MONOTONIC = 4;
    pub const PROCESS_CPUTIME_ID = 2;
    pub const THREAD_CPUTIME_ID = 3;
    pub const MONOTONIC_RAW = 5;
    pub const MONOTONIC_COARSE = 6;
    pub const BOOTTIME = 7;
    pub const REALTIME_ALARM = 8;
    pub const BOOTTIME_ALARM = 9;
    //pub const SGI_CYCLE = 10; // Not defined
    //pub const TAI = 11; // Not defined
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
    pub const SET = 0;
    pub const CUR = 1;
    pub const END = 2;
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
