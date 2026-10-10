// This implements UART (Universal Async Receiver-Transmitter)
// UART is a serial interface

const port_io = @import("./port_io.zig");
pub const uart_port_com1 = 0x3f8;

pub fn uart_initialize() void {
    // no need for interrupts
    port_io.outb(uart_port_com1 + 1, 0x00);
    // set dlab bit
    port_io.outb(uart_port_com1 + 3, 0x80);
    // BAUD - which frequency we want to communicate
    port_io.outb(uart_port_com1 + 0, 0x03);
    port_io.outb(uart_port_com1 + 1, 0x00);
    // now set flags in line control register, default = 8 bits, no parity, one stop bit
    port_io.outb(uart_port_com1 + 3, 0x03);
    // set some things in fifo control register
    port_io.outb(uart_port_com1 + 2, 0xc7);
    // set some bits on model control register
    port_io.outb(uart_port_com1 + 4, 0x0b);
}

pub inline fn uart_is_transmit_buffer_empty() bool {
    // ask if sixth bit in register is set, 0x20 = 0b100000
    return (port_io.inb(uart_port_com1 + 5) & 0x20) != 0;
}

pub inline fn uart_putchar(char: u8) void {
    while (!uart_is_transmit_buffer_empty()) {}
    port_io.outb(uart_port_com1, char);
}

pub fn uart_puts(str: []const u8) void {
    for (str) |char| {
        uart_putchar(char);
    }
}
