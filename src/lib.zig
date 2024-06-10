/// c is the provided C operating system settings for the Wii
///
/// This won't work until PR is merged: https://github.com/ziglang/zig/pull/20241
/// So for now we don't make this public
const c = @import("c/os.zig");

// runtime adds additional functions so that Zig standard functions will work on the Wii
pub const runtime = @import("runtime.zig");
