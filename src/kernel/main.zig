const builtin = @import("std").builtin;
const uart = @import("./uart.zig");
const std = @import("std");
const printf = @import("./text_out.zig").printf;
export fn kmain() void {
    uart.uart_initialize();
    uart.uart_puts("\x1b[2J");
    uart.uart_puts("Hello world from kernel\n");
}

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, return_address: ?usize) noreturn {
    uart.uart_puts("\n !!! Kernel panic !!! \n");
    uart.uart_puts(msg);
    if (return_address) |addr| {
        const ptr: *align(1) const i64 = @ptrFromInt(addr);
        const aligned: *align(1) const u64 = @ptrCast(ptr);
        printf("\nReturn address is 0x{x}\n", .{@intFromPtr(aligned)});
    }

    uart.uart_puts("\n");
    while (true) {}
}
