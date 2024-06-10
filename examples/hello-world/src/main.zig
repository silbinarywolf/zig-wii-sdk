const std = @import("std");
const builtin = @import("builtin");

const assert = std.debug.assert;

comptime {
    // add additional functionality so standard Zig functions work
    _ = @import("zigwii").runtime;
}

pub fn main() !void {
    // See README.md and the "Debugging in Dolphin" heading to see this print
    std.debug.print("hello world!", .{});
}
