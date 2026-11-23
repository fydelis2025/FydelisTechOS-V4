ENTRY(_entry16)

SECTIONS
{
    /* Carregado exatamente em 0x8000 pelo MBR (LBA 4096) e pelo BOOTX64.EFI */
    . = 0x8000;

    .text :
    {
        *(.text._start)
        *(.text .text.*)
    }

    .rodata : ALIGN(16)
    {
        *(.rodata .rodata.*)
    }

    .data : ALIGN(16)
    {
        *(.data .data.*)
    }

    .bss : ALIGN(16)
    {
        __bss_start = .;
        *(COMMON)
        *(.bss .bss.*)
        __bss_end = .;
    }

    /DISCARD/ :
    {
        *(.comment)
        *(.eh_frame)
        *(.note.*)
    }
}
