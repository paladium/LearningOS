const std = @import("std");
const uefi = std.os.uefi;

const text_out = @import("./text_out.zig");
const config = @import("./config.zig");
const loader = @import("./loader.zig");
const puts = text_out.puts;
const printf = text_out.printf;

fn bootloader() !void {
    const boot_services = uefi.system_table.boot_services.?;

    const runtime_services = uefi.system_table.runtime_services;
    // UEFI expects strings in particular format, let's convert them
    const kernel_executable_path: [*:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("\\kernel.elf");
    var root_file_system: *const uefi.protocol.File = undefined;
    var memory_map: uefi.tables.MemoryMapSlice = undefined;
    var memory_map_key: uefi.tables.MemoryMapKey = undefined;
    var memory_map_size: usize = 0;
    var descriptor_size: usize = undefined;
    var descriptor_version: u32 = undefined;

    // kernel entry point and start address, we will set them later when parsing
    var kernel_entry_point: u64 = undefined;
    var kernel_start_address: u64 = undefined;
    // this will be our "main" func for kernel
    var kernel_entry: *const fn () callconv(.c) void = undefined;

    // we need to use a particular protocol for the filesystem to load our kernel
    // it could be remote or local
    if (config.debug) {
        puts("Debug: Locating simle file system protocol\r\n");
    }
    const file_system = blk: {
        const res = boot_services.locateProtocol(uefi.protocol.SimpleFileSystem, null) catch |err| {
            puts("Error: Cannot locate simple file system protocol\r\n");
            return err;
        };
        if (res) |fs| {
            break :blk fs;
        } else {
            puts("Error: Simple file system protocol not found\r\n");
            return error.NotFound;
        }
    };
    if (config.debug) {
        puts("Debug: Opening root volume\r\n");
    }
    root_file_system = file_system.openVolume() catch |err| {
        puts("Error: Opening root volume failed\r\n");
        return err;
    };
    // Find free space in the memory for the kernel
    if (config.debug) {
        puts("Debug: Getting memory map to find free memory\r\n");
    }
    var memmap_info = boot_services.getMemoryMapInfo() catch |err| {
        puts("Error: Getting memory map info failed\r\n");
        return err;
    };
    descriptor_size = memmap_info.descriptor_size;
    descriptor_version = memmap_info.descriptor_version;
    memory_map_key = memmap_info.key;
    // need to multiply because getMemoryMapInfo len is divided by descriptor size, to return the amount
    // in descriptor_sizes instead of bytes
    memory_map_size = memmap_info.len * descriptor_size;
    var memory_map_buffer = boot_services.allocatePool(.boot_services_data, memory_map_size) catch |err| {
        puts("Error: Allocating memory map failed\r\n");
        return err;
    };
    memory_map = boot_services.getMemoryMap(memory_map_buffer) catch |err| {
        puts("Error: Getting memory map failed\r\n");
        return err;
    };
    // Now we have memory map we need to find a free base address for the kernel to load
    if (config.debug) {
        puts("Debug: Finding free kernel base address\r\n");
    }
    var mem_index: usize = 0;
    var mem_count: usize = memmap_info.len;
    var mem_point: *uefi.tables.MemoryDescriptor = undefined;
    // base address (min address)
    var base_address: u64 = 0x100000;
    // the count of free 4KB pages we have
    var num_pages: usize = 0;
    if (config.debug) {
        printf("Debug: mem_count is {}\r\n", .{mem_count});
    }
    while (mem_index < mem_count) : (mem_index += 1) {
        if (config.debug) {
            printf("Debug: mem_index is {}\r\n", .{mem_index});
        }
        // calculate new entry we will be pointing to
        mem_point = @ptrFromInt(@intFromPtr(memory_map.ptr) + (mem_index * descriptor_size));
        // let's check if that memory is free
        if (mem_point.type == .conventional_memory and mem_point.physical_start >= base_address) {
            base_address = mem_point.physical_start;
            num_pages = mem_point.number_of_pages;
            if (config.debug) {
                printf("Debug: Found {} free pages at 0x{x}\r\n", .{ num_pages, base_address });
            }
            break;
        }
    }
    // now we are ready to load our kernel image
    if (config.debug) {
        puts("Debug: Loading kernel image\r\n");
    }
    loader.loadKernelImage(
        root_file_system,
        kernel_executable_path,
        base_address,
        &kernel_entry_point,
        &kernel_start_address,
    ) catch |err| {
        puts("Error: Loading kernel image failed\r\n");
        return err;
    };
    if (config.debug) {
        printf("Debug: Set Kernel Entry Point to: '0x{x}\r\n'", .{kernel_entry_point});
    }
    // disable watchdog timer, because otherwise os will just shut down
    if (config.debug) {
        puts("Debug: disabling watchdog timer\r\n");
    }
    boot_services.setWatchdogTimer(0, 0, null) catch |err| {
        puts("Error: Disabling watchdog timer failed\r\n");
        return err;
    };
    // let's now exit boot services to not have supervisor over us
    while (blk: {
        boot_services.exitBootServices(uefi.handle, memory_map_key) catch break :blk true;
        break :blk false;
    }) {
        puts("Getting memory map and trying to exit boot services\r\n");
        memmap_info = boot_services.getMemoryMapInfo() catch |err| {
            puts("Error: Getting memory map info failed\r\n");
            return err;
        };
        descriptor_size = memmap_info.descriptor_size;
        descriptor_version = memmap_info.descriptor_version;
        memory_map_key = memmap_info.key;
        memory_map_size = memmap_info.len * descriptor_size;
        memory_map_buffer = boot_services.allocatePool(.boot_services_data, memory_map_size) catch |err| {
            puts("Error: Allocating memory map failed\r\n");
            return err;
        };
        memory_map = boot_services.getMemoryMap(memory_map_buffer) catch |err| {
            puts("Error: Getting memory map failed\r\n");
            return err;
        };
        memory_map_key = memory_map.info.key;
    }
    // in the linder script we set the start of the kernel to 1M - 0x100000.
    // Free memory can be anywhere, let's enable virtual addressing, so that all addresses
    // inside of the kernel image stay the same
    mem_index = 0;
    mem_count = memory_map_size / descriptor_size;
    while (mem_index < mem_count) : (mem_index += 1) {
        mem_point = @ptrFromInt(@intFromPtr(memory_map.ptr) + (mem_index * descriptor_size));
        // in loader.zig we allocated some pages for the kernel code and data
        // the region is marked with LoaderData, so we can check that current segment is of that type
        if (mem_point.type == .loader_data) {
            mem_point.virtual_start = kernel_start_address;
        } else {
            // if not we just use physical address
            mem_point.virtual_start = mem_point.physical_start;
        }
    }
    // now use that updated memory_map
    try runtime_services.setVirtualAddressMap(memory_map);
    // now let's start our kernel by parsing its start address and calling the func
    kernel_entry = @ptrFromInt(kernel_entry_point);
    kernel_entry();
    return error.LoadError;
}

pub fn main() void {
    bootloader() catch |err| {
        // this should always succeed, but if we are here something is wrong
        puts("Status: ");
        puts(@errorName(err));
        puts("\r\n");
        while (true) {}
    };
}
