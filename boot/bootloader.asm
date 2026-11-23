; ==========================================
; FydelisTech OS — MBR Estágio 1 (512 bytes)
; ==========================================
BITS 16
ORG 0x7C00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    
    ; Validação segura do drive de boot passado pelo BIOS
    cmp dl, 0x00
    je .store_drive
    cmp dl, 0x80
    jae .store_drive
    mov dl, 0x80      ; Fallback seguro para primeiro disco rígido se vier inválido
.store_drive:
    mov [boot_drive], dl

    ; Carrega 384 KB (12 blocos x 64 setores) a partir do LBA 4096 para 0x0800:0x0000 (0x8000)
    mov cx, 12
.load_loop:
    push cx
    mov si, dap
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error

    ; Avança destino em 32 KB (segmento +0x0800) e LBA em +64 setores
    add word [dap_seg], 0x0800
    add dword [dap_lba], 64
    adc dword [dap_lba + 4], 0
    pop cx
    loop .load_loop

    jmp 0x0000:0x8000

disk_error:
    mov si, msg_erro
.print:
    lodsb
    test al, al
    jz .halt
    mov ah, 0x0E
    int 0x10
    jmp .print
.halt:
    cli
    hlt
    jmp .halt

align 4
dap:
    db 0x10
    db 0
    dw 64               ; 64 setores (32 KB) por leitura
dap_off:
    dw 0x0000           ; Offset inicial 0x0000
dap_seg:
    dw 0x0800           ; Segmento inicial 0x0800 -> endereço físico 0x8000
dap_lba:
    dq 4096             ; LBA inicial (conforme seek=4096 no Makefile)

boot_drive: db 0
msg_erro:   db "ERR MBR", 0

times 510-($-$$) db 0
dw 0xAA55
