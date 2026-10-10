pub fn inb(port: u16) u8 {
    return asm volatile ("in %[port], %[ret]"
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

pub fn outb(port: u16, val: u8) void {
    asm volatile ("out %[val], %[port]"
        :
        : [val] "{al}" (val),
          [port] "{dx}" (port),
    );
}
