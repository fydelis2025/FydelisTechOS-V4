; ============================================================================
; FydelisTech OS — MBR Estágio 1 (Legacy BIOS -> BootInfo 0x5000)
; Preserva Tabela de Partições (bytes 446..509) e repassa Boot Drive em DL
; Salvador • Bahia
; ============================================================================
BITS 16
ORG 0x7C00

BOOTINFO_ADDR       equ 0x5000
BOOTINFO_MAGIC_LO   equ 0x4442      ; "DB"
BOOTINFO_MAGIC_HI   equ 0x4659      ; "FY" -> "FYDB" (0x46594442)
BOOT_MODE_LEGACY    equ 1

start:
    cli
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, 0x7C00
    sti

    ; Valida drive de boot passado pelo BIOS em DL
    cmp     dl, 0x00
    je      .store_drive
    cmp     dl, 0x80
    jae     .store_drive
    mov     dl, 0x80                ; Fallback seguro para 1o HDD (0x80)
.store_drive:
    mov     [boot_drive], dl

    ; Preenche BootInfo unificado em 0x5000 (Legacy BIOS, Secure Boot = OFF)
    mov     di, BOOTINFO_ADDR
    mov     word [di + 0], BOOTINFO_MAGIC_LO
    mov     word [di + 2], BOOTINFO_MAGIC_HI
    mov     word [di + 4], BOOT_MODE_LEGACY ; boot_mode = 1 (Legacy BIOS)
    mov     word [di + 6], 0
    mov     word [di + 8], 0                ; secure_boot = 0 (N/A em Legacy)
    mov     word [di + 10], 0
    mov     word [di + 12], 0               ; setup_mode = 0
    mov     word [di + 14], 0

    ; Carrega 384 KB (12 blocos x 64 setores) a partir do LBA 4096 para 0x0800:0x0000 (0x8000)
    mov     cx, 12
.load_loop:
    push    cx
    mov     si, dap
    mov     dl, [boot_drive]
    mov     ah, 0x42
    int     0x13
    jc      disk_error

    ; Avança destino em 32 KB (segmento +0x0800) e LBA em +64 setores
    add     word [dap_seg], 0x0800
    add     dword [dap_lba], 64
    adc     dword [dap_lba + 4], 0  ; Propaga carry para LBA 64-bit
    pop     cx
    loop    .load_loop

    ; Repassa o drive de boot em DL e o ponteiro BootInfo em BX para o Estágio 2
    mov     dl, [boot_drive]
    mov     bx, BOOTINFO_ADDR
    jmp     0x0000:0x8000

disk_error:
    mov     si, msg_erro
.print:
    lodsb
    test    al, al
    jz      .halt
    mov     ah, 0x0E
    int     0x10
    jmp     .print
.halt:
    cli
    hlt
    jmp     .halt

align 4
dap:
    db 0x10                         ; Tamanho do pacote DAP (16 bytes)
    db 0                            ; Reservado
    dw 64                           ; 64 setores (32 KB) por leitura
dap_off:
    dw 0x0000                       ; Offset 0x0000
dap_seg:
    dw 0x0800                       ; Segmento inicial 0x0800 -> endereço físico 0x8000
dap_lba:
    dq 4096                         ; LBA inicial (conforme seek=4096 no Makefile)

boot_drive: db 0
msg_erro:   db "ERR MBR", 0

; Preenche apenas a área de código (446 bytes), preservando os 64 bytes da Tabela de Partições
times 446-($-$$) db 0
times 64 db 0                       ; Espaço reservado para 4 entradas de partição MBR (16B cada)
dw 0xAA55
