const std = @import("std");
const uefi = std.os.uefi;

var con_out: *uefi.protocol.SimpleTextOutput = undefined;

var already_called_puts: bool = false;

pub fn puts(msg: []const u8) void {
    if (!already_called_puts) {
        con_out = uefi.system_table.con_out.?;
        con_out.reset(false) catch {};
        already_called_puts = true;
    }
    for (msg) |c| {
        const c_ = [1:0]u16{c};
        _ = con_out.outputString(&c_) catch {};
    }
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    var msg: []u8 = undefined;
    msg = std.fmt.bufPrint(&buf, fmt, args) catch unreachable;
    puts(msg);
}
