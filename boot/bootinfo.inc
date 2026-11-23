; ============================================================================
; BOOTINFO.INC — Estrutura Híbrida Legacy BIOS / UEFI + Secure Boot
; FydelisTech OS v4.2 · x86_64
; ============================================================================
%define BOOT_MODE_LEGACY    1
%define BOOT_MODE_UEFI      2

%define SECURE_BOOT_OFF     0
%define SECURE_BOOT_ON      1

struc BootInfo
    .magic:          resd 1      ; 0x46594442 ("FYDB")
    .boot_mode:      resd 1      ; 1 = Legacy BIOS, 2 = UEFI
    .secure_boot:    resd 1      ; 0 = Desabilitado/N/A, 1 = Habilitado
    .setup_mode:     resd 1      ; 1 = UEFI Setup Mode (sem PK registrada), 0 = User Mode
    .fb_addr:        resq 1      ; Endereco fisico do Framebuffer (VESA LFB ou UEFI GOP)
    .fb_width:       resd 1      ; Largura em pixels
    .fb_height:      resd 1      ; Altura em pixels
    .fb_pitch:       resd 1      ; Bytes por linha (stride)
    .fb_bpp:         resd 1      ; Bits por pixel (32)
    .rsdp_addr:      resq 1      ; Ponteiro ACPI RSDP (XSDP/RSDP)
    .mmap_addr:      resq 1      ; Mapa de memoria fisico
    .mmap_entries:   resd 1      ; Quantidade de entradas
    .reservado:      resd 1
endstruc
