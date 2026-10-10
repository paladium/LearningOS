/*
 * Linker script on how to output our kernel in ELF format
 * */
/*Start at 0x100000*/
KERNEL_PHYS_START = 1M;
KERNEL_STACK_SIZE = 0x4000;

ENTRY(kmain)

SECTIONS {
	. = KERNEL_PHYS_START;
	/*text section will incldue the code that we will execute, align by 4k because bootloader expects it to be in such format*/
	.text : ALIGN(4K) {
		*(.text*)
	}
	.rodata : ALIGN(4K) {
		*(.rodata*)
	}
	.data : ALIGN(4K) {
		*(.data*)
	}
	.bss : ALIGN(4K) {
		*(COMMON),
		*(.bss*)
		. = ALIGN(16);
		. += KERNEL_STACK_SIZE;
	}
}
