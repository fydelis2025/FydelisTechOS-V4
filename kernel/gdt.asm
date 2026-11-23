; ============================================================================
; GDT & TSS — FYDELISTECH OS (x86_64 Long Mode)
; Ring 0 = Kernel | Ring 3 = Usuario
; ============================================================================
bits 64
default rel

%define RSP0_STACK_SIZE 16384           ; 16 KB dedicados para pilha de Ring 0 (TSS.RSP0)

section .text
global gdt_init
global gdt_flush
global tss_set_rsp0

; ============================================================================
; INICIALIZACAO DA GDT + TSS
; ============================================================================
gdt_init:
    push rbx
    push rdi

    ; 1. Zera a estrutura TSS (104 bytes) e configura RSP0 no topo da pilha dedicada
    lea rdi, [rel tss64]
    xor eax, eax
    mov ecx, 104 / 4
    rep stosd

    lea rax, [rel rsp0_stack_top]
    mov [rel tss64 + 4], rax            ; RSP0 inicial em endereço válido e alinhado
    mov word [rel tss64 + 102], 104     ; Sem I/O Permission Bitmap

    ; 2. Preenche endereco base da TSS (64 bits) no descritor de 16 bytes (0x28)
    lea rax, [rel tss64]
    lea rdx, [rel gdt_tss]

    mov word [rdx + 2], ax              ; Base [15:0]
    shr rax, 16
    mov byte [rdx + 4], al              ; Base [23:16]
    mov byte [rdx + 5], 0x89            ; Presente + Ring 0 + 64-bit TSS Available
    mov byte [rdx + 7], ah              ; Base [31:24]
    shr rax, 16
    mov dword [rdx + 8], eax            ; Base [63:32]
    mov dword [rdx + 12], 0             ; Reservado

    ; 3. Preenche endereco base linear da GDT no GDTR
    lea rax, [rel gdt]
    mov qword [rel gdt_descriptor + 2], rax

    lgdt [rel gdt_descriptor]
    call gdt_flush

    ; 4. Carrega Task Register (seletor 0x28 = indice 5 * 8)
    mov ax, 0x28
    ltr ax

    pop rdi
    pop rbx
    ret

gdt_flush:
    mov ax, 0x10                        ; Seletor Kernel Data (indice 2 * 8)
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    lea rax, [rel .flush]
    push qword 0x08                     ; Seletor Kernel Code 64-bit (indice 1 * 8)
    push rax
    retfq                               ; Recarrega CS e RIP em Long Mode

.flush:
    ret

; Atualiza pilha de Ring 0 usada em transicoes Ring 3 -> Ring 0
; RDI = novo RSP0
tss_set_rsp0:
    mov [rel tss64 + 4], rdi
    ret

; ============================================================================
; ESTRUTURAS DA GDT E TSS (Alinhadas em 16 bytes)
; ============================================================================
section .data
align 16
gdt:
    dq 0x0000000000000000               ; 0x00 (0) — Nulo
    dq 0x00AF9A000000FFFF               ; 0x08 (1) — Kernel Code 64-bit (Ring 0, L=1)
    dq 0x00CF92000000FFFF               ; 0x10 (2) — Kernel Data (Ring 0, L=0, G=1)
    dq 0x00CFF2000000FFFF               ; 0x18 (3) — User Data   (Ring 3, L=0, G=1)
    dq 0x00AFFA000000FFFF               ; 0x20 (4) — User Code 64-bit (Ring 3, L=1)

gdt_tss:                                ; 0x28 (5 e 6) — Descritor TSS 64-bit (16 bytes)
    dw 103                              ; Limite = sizeof(tss64) - 1
    dw 0                                ; Base [15:0]
    db 0                                ; Base [23:16]
    db 0x89                             ; Tipo: 64-bit TSS Available (Presente, Ring 0)
    db 0x00                             ; Flags / Limite [19:16]
    db 0                                ; Base [31:24]
    dd 0                                ; Base [63:32]
    dd 0                                ; Reservado
gdt_fim:

align 16
gdt_descriptor:
    dw gdt_fim - gdt - 1                ; Limite da GDT
    dq 0                                ; Base linear 64-bit (preenchida em gdt_init)

section .bss
align 16
tss64:
    resb 104                            ; Estrutura TSS x86_64 (104 bytes)

align 16
rsp0_stack_bottom:
    resb RSP0_STACK_SIZE
rsp0_stack_top:
