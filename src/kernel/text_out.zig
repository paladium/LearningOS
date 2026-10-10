const uart = @import("./uart.zig");
const std = @import("std");

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    var msg: []u8 = undefined;
    msg = std.fmt.bufPrint(&buf, fmt, args) catch unreachable;
    uart.uart_puts(msg);
}
