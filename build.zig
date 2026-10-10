const Build = @import("std").Build;
const Target = @import("std").Target;

pub fn build(b: *Build) void {
    const bootloader_query = Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
        .abi = .msvc,
        .ofmt = .coff,
    };
    const kernel_query = Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,
    };
    const optimize = b.standardOptimizeOption(.{});
    const bootloader_mod = b.createModule(.{
        .root_source_file = b.path("src/bootloader/main.zig"),
        .target = b.resolveTargetQuery(bootloader_query),
        .optimize = optimize,
    });
    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = b.resolveTargetQuery(kernel_query),
        .optimize = optimize,
    });
    const bootloader_exe = b.addExecutable(.{
        .name = "bootx64",
        .root_module = bootloader_mod,
    });
    const kernel_exe = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = kernel_mod,
        .use_lld = true,
        .use_llvm = true,
    });
    kernel_exe.entry = .disabled;
    kernel_exe.setLinkerScript(b.path("src/kernel/kernel.ld"));
    b.installArtifact(bootloader_exe);
    b.installArtifact(kernel_exe);

    const ovmf_dep = b.dependency("ovmf", .{});

    const boot_dir = b.addWriteFiles();
    _ = boot_dir.addCopyFile(bootloader_exe.getEmittedBin(), b.pathJoin(&.{
        "efi",
        "boot",
        bootloader_exe.out_filename,
    }));
    _ = boot_dir.addCopyFile(
        kernel_exe.getEmittedBin(),
        kernel_exe.out_filename,
    );
    const qemu_cmd = b.addSystemCommand(&.{"qemu-system-x86_64"});
    qemu_cmd.addArg("-serial");
    qemu_cmd.addArg("mon:stdio");
    qemu_cmd.addArg("-display");
    qemu_cmd.addArg("gtk");
    qemu_cmd.addArg("-s");
    qemu_cmd.addArg("-drive");
    qemu_cmd.addPrefixedFileArg(
        "format=raw,if=pflash,readonly=on,file=",
        ovmf_dep.path("x64/code.fd"),
    );
    qemu_cmd.addArg("-drive");
    qemu_cmd.addPrefixedFileArg(
        "format=raw,if=pflash,file=",
        ovmf_dep.path("x64/vars.fd"),
    );
    qemu_cmd.addArg("-drive");
    qemu_cmd.addPrefixedDirectoryArg(
        "format=raw,index=3,media=disk,file=fat:rw:",
        boot_dir.getDirectory(),
    );
    const qemu_step = b.step("qemu", "Run the kernel via QEMU");
    qemu_step.dependOn(&qemu_cmd.step);
}
