# zig os explanation

This contains all the concepts used in the zig os, so it will be long to make sure I fully understand how os setup works. Once I understand the basics, I can try to implement it myself with simplest building blocks.

## Bootloader
This is a small program that finds the kernel, loads it into memory and starts it - hands over control to it.

The reason why we need it is hardware doesn't know how to load custom kernel, it needs some predefined script according to a format to be used.

Two types of bootloader - first stage initialises devices - hardware and second stage like grub prepare to run the actual kernel.

UEFI is a replacement for BIOS which. Our bootloader will be run as an uefi.

ABI is application binary interface - specifies how functions will be called.

Output format can be COFF (windows/unix executable), also can be ELF - easy to parse/linux-based

Linker - take compiled object files and libraries and combine them into a single executable.

UEFI system table = A pointer to the EFI System Table that is passed to the EFI image's entry point. It is initialised just before calling main using std.start (_start method) may also use other entry point declarations in certain situations, such as wWinMain or EfiMain. Refer to the lib/std/start.zig logic for details of these declarations.

```
UEFI fd exposes a few functionalities by giving our efi entrypoint two parameters, that are pointer of EFI_HANDLE and EFI_SYSTEM_TABLE. The one that is useful to us is the latter one, it'll let us write to the console.
```

System table is defined here - https://github.com/ziglang/zig/blob/738d2be9d6b6ef3ff3559130c05159ef53336224/lib/std/os/uefi/tables/system_table.zig#L18

https://animeshz.github.io/site/blogs/demystifying-uefi.html

Protocols are file system, network ones. They are indentified by GUIDs which is similar to UUIDs - 128 bit number.

Bootloader logic:
1. Find kernel image
2. Prepare memory to have virtual addressing
3. Start the kernel

ELF - Executable and linkable format - format for programs. ELF cheatsheet - https://gist.github.com/x0nu11byt3/bcb35c3de461e5fb66173071a2379779

## Initial start
It all starts with a build script, it setups how to build bootloader.
