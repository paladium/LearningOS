// The core logic to load our kernel
const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;

const config = @import("./config.zig");
const text_out = @import("./text_out.zig");
const efi_additional = @import("./efi_additional.zig");
const puts = text_out.puts;
const printf = text_out.printf;

pub fn readFile(
    file: *uefi.protocol.File,
    position: u64,
    buffer: []u8,
) !void {
    file.setPosition(position) catch |err| {
        puts("Error: Setting file position failed\r\n");
        return err;
    };
    _ = try file.read(buffer);
}

// read uefi file and allocate free memory for it
pub fn readAndAllocate(
    file: *uefi.protocol.File,
    position: u64,
    size: usize,
    buffer: *[]u8,
) !void {
    const boot_services = uefi.system_table.boot_services.?;
    // this memory will be allocated and never freed as it will hold our kernel data
    buffer.* = boot_services.allocatePool(.loader_data, size) catch |err| {
        puts("Error: Allocating space for file failed\r\n");
        return err;
    };
    try readFile(file, position, buffer.*);
}

pub fn loadSegment(
    file: *uefi.protocol.File,
    segment_file_offset: u64,
    segment_file_size: usize,
    segment_memory_size: usize,
    segment_virtual_address: u64,
) !void {
    if (segment_virtual_address & 4095 != 0) {
        puts("Warning: segment_virtual_address is not well aligned, returning\r\n");
        return;
    }
    var segment_buffer: []u8 = &.{};
    // we allocate pages - 4KB regions of memory, convert to number of pages
    const segment_page_count = efi_additional.efiSizeToPages(segment_memory_size);
    // we should zero-full all unused bytes
    // we should figure out where we should start and how many bytes
    var zero_fill_start: u64 = 0;
    var zero_fill_count: usize = 0;
    const boot_services = uefi.system_table.boot_services.?;
    if (config.debug) {
        printf("Debug: Allocating {} pages at address '0x{x}'\r\n", .{ segment_page_count, segment_virtual_address });
    }
    const segbuf = (boot_services.allocatePages(
        .{ .address = @ptrFromInt(segment_virtual_address) },
        .loader_data,
        segment_page_count,
    )) catch |err| {
        puts("Error: Allocating pages for ELF segment failed\r\n");
        return err;
    };
    // this part is needed because we need to write to a slice of bytes, but we only have a slices of arrays
    segment_buffer.ptr = @ptrCast(segbuf.ptr);
    segment_buffer.len = segbuf.len * 4096;

    // now let's read segment data in segment buffer
    if (segment_file_size > 0) {
        if (config.debug) {
            printf("Debug: Reading segment data with file size '0x{x}'\r\n", .{segment_file_size});
        }
        readFile(file, segment_file_offset, segment_buffer) catch |err| {
            puts("Error: Reading segment data failed\r\n");
            return err;
        };
    }
    zero_fill_start = segment_virtual_address + segment_file_size;
    zero_fill_count = segment_memory_size - segment_file_size;
    if (zero_fill_count > 0) {
        if (config.debug) {
            printf("Debug: Zero-filling {} bytes at address '0x{x}'\r\n", .{ zero_fill_count, zero_fill_start });
        }
        // this is only a problem for ELF, no other things like this
        @memset(@as([*]u8, @ptrFromInt(zero_fill_start))[0..zero_fill_count], 0);
        puts("Debug: Zero-filling bytes succeeded\r\n");
    }
}

// load all ELF program segments
pub fn loadProgramSegments(
    file: *uefi.protocol.File,
    program_headers: []const elf.Elf64_Phdr,
    base_physical_address: u64,
    kernel_start_address: *u64,
) !void {
    var n_segments_loaded: u64 = 0;
    var set_start_address: bool = true;
    var base_address_diffence: u64 = 0;
    if (program_headers.len == 0) {
        puts("Error: No program segments to load\r\n");
        return error.InvalidParameter;
    }
    if (config.debug) {
        printf("Debug: Loading {} segments\r\n", .{program_headers.len});
    }
    for (program_headers, 0..) |prog_hdr, i| {
        if (prog_hdr.p_type == elf.PT_LOAD) {
            if (config.debug) {
                printf("Debug: Loading program segment {}\r\n", .{i});
            }
            if (set_start_address) {
                set_start_address = false;
                kernel_start_address.* = prog_hdr.p_vaddr;
                base_address_diffence = prog_hdr.p_vaddr - base_physical_address;
                if (config.debug) {
                    printf("Debug: Set kernel start address to 0x{x} and base address different to 0x{x}\r\n", .{ kernel_start_address.*, base_address_diffence });
                }
            }
            loadSegment(file, prog_hdr.p_offset, prog_hdr.p_filesz, prog_hdr.p_memsz, prog_hdr.p_vaddr - base_address_diffence) catch |err| {
                printf("Error: Loading program segment {} failed\r\n", .{i});
                return err;
            };
            n_segments_loaded += 1;
        }
    }
    if (n_segments_loaded == 0) {
        puts("Error: No loadable program segments found in executable\r\n");
        return error.NotFound;
    }
}

pub fn loadKernelImage(
    root_file_system: *const uefi.protocol.File,
    kernel_image_filename: [*:0]const u16,
    base_physical_address: u64,
    kernel_entry_point: *u64,
    kernel_start_address: *u64,
) !void {
    const boot_services = uefi.system_table.boot_services.?;
    var kernel_img_file: *uefi.protocol.File = undefined;
    // buffer for ELF executable header
    var header_buffer: []u8 = undefined;
    if (config.debug) {
        puts("Debug: Opening kernel image\r\n");
    }
    kernel_img_file = root_file_system.open(kernel_image_filename, .read, .{ .read_only = true }) catch |err| {
        puts("Error: Opening kernel file failed\r\n");
        return err;
    };

    defer kernel_img_file.close() catch {};

    {
        if (config.debug) {
            puts("Debug: Checking ELF identity\r\n");
        }
        readAndAllocate(kernel_img_file, 0, elf.EI_NIDENT, &header_buffer) catch |err| {
            puts("Error: Reading ELF identity failed\r\n");
            return err;
        };
        defer boot_services.freePool(@alignCast(header_buffer.ptr)) catch {};
        // we are checking magic key - \x7fELF
        if ((header_buffer[0] != 0x7f) or
            (header_buffer[1] != 0x45) or
            (header_buffer[2] != 0x4c) or
            (header_buffer[3] != 0x46))
        {
            puts("Error: Invalid ELF magic\r\n");
            return error.InvalidParameter;
        }
        if (header_buffer[elf.EI_CLASS] != elf.ELFCLASS64) {
            puts("Error: Can only 64-bit binaries\r\n");
            return error.Unsupported;
        }
        if (header_buffer[elf.EI_DATA] != elf.ELFDATA2LSB) {
            puts("Error: Can only load little-endian binaries\r\n");
            return error.IncompatibleVersion;
        }
        if (config.debug) {
            puts("Debug: ELF identity is good, continuing loading\r\n");
        }
    }

    if (config.debug) {
        puts("Debug: Loading ELF header\r\n");
    }

    readAndAllocate(kernel_img_file, 0, @sizeOf(elf.Elf64_Ehdr), &header_buffer) catch |err| {
        puts("Error: Reading ELF header failed\r\n");
        return err;
    };
    defer boot_services.freePool(@alignCast(header_buffer.ptr)) catch {};
    // parse the ELF header
    var hdr_reader: std.Io.Reader = .fixed(header_buffer[0..64]);
    const header = elf.Header.read(&hdr_reader) catch |err| {
        switch (err) {
            error.InvalidElfMagic => {
                puts("Error: Invalid ELF magic\r\n");
            },
            error.InvalidElfVersion => {
                puts("Error: Invalid ELF version\r\n");
            },
            error.InvalidElfEndian => {
                puts("Error: Invalid ELF endianness\r\n");
            },
            else => {},
        }
        return err;
    };
    if (config.debug) {
        printf("Debug: Loading ELF header succeeded, entry point is 0x{x}\r\n", .{header.entry});
    }
    kernel_entry_point.* = header.entry;
    if (config.debug) {
        puts("Debug: Loading program headers\r\n");
    }
    var program_headers_buffer: []u8 = undefined;
    readAndAllocate(kernel_img_file, header.phoff, header.phentsize * header.phnum, &program_headers_buffer) catch |err| {
        puts("Error: Reading ELF program headers failed\r\n");
        return err;
    };
    defer boot_services.freePool(@alignCast(program_headers_buffer.ptr)) catch {};
    const program_headers = @as([*]const elf.Elf64_Phdr, @ptrCast(@alignCast(program_headers_buffer)))[0..header.phnum];
    try loadProgramSegments(kernel_img_file, program_headers, base_physical_address, kernel_start_address);
}
