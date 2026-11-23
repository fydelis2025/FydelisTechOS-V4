; ==================================================
; FydelisTechOS — Memória Aninhada EPT/NPT v2.2
; Tradução de endereços: Convidado → Físico Real
; Intel: EPT 4 níveis  |  AMD: NPT 4 níveis
; ==================================================
bits 64

; === EPT — Intel ===
EPT_PRESENT        equ (1 << 0)
EPT_RW             equ (1 << 1)
EPT_USER           equ (1 << 2)
EPT_MEMTYPE_WB     equ 6 << 3
EPT_PAGE_SIZE_4K   equ 0 << 7
EPT_PAGE_SIZE_2M   equ 1 << 7
EPT_PAGE_SIZE_1G   equ 3 << 7
EPT_ACCESSED       equ (1 << 8)
EPT_DIRTY          equ (1 << 9)
EPT_EXEC_DISABLE   equ (1 << 63)

; === NPT — AMD ===
NPT_PRESENT        equ (1 << 0)
NPT_RW             equ (1 << 1)
NPT_USER           equ (1 << 2)
NPT_PAGE_SIZE_4K   equ 0 << 7
NPT_PAGE_SIZE_2M   equ 1 << 7
NPT_ACCESSED       equ (1 << 8)
NPT_DIRTY          equ (1 << 9)
NPT_EXEC_DISABLE   equ (1 << 63)

; Máscaras de endereço
ADDR_MASK_4K       equ ~0xFFF
ADDR_MASK_2M       equ ~0x1FFFFF
ADDR_MASK_1G       equ ~0x3FFFFFFF

; Deslocamentos por nível
SHIFT_PML4E        equ 39
SHIFT_PDPE         equ 30
SHIFT_PDE          equ 21
SHIFT_PTE          equ 12

section .bss
align 4096
global eptp_value
global ept_pml4
global npt_pml4

ept_pml4:     resq 512   ; Tabela raiz EPT
eptp_value:   resq 1     ; EPTR para VMCS

npt_pml4:     resq 512   ; Tabela raiz NPT
nptp_value:   resq 1     ; NPTR para VMCB

section .text
global ept_inicializar
global npt_inicializar
global ept_mapear_faixa
global npt_mapear_faixa
global ept_flush_todas
global npt_flush_todas

; ══════════════════════════════════════════════════════
; EPT — INTEL
; ══════════════════════════════════════════════════════

; ── Inicializar tabelas EPT ──
ept_inicializar:
    ; Zerar PML4
    mov  rdi, ept_pml4
    mov  rcx, 512
    xor  rax, rax
    rep stosq

    ; Calcular EPTP: bits [47:12] = endereço da PML4, [2:0] = 6 (memória WB)
    mov  rax, ept_pml4
    shr  rax, 12
    shl  rax, 12
    or   rax, 6                  ; Tipo de memória WriteBack
    mov  [rel eptp_value], rax
    ret

; ── Mapear página convidado → físico (4KB) ──
; Entrada: rdi = endereço convidado, rsi = endereço físico, rdx = flags
; Saída: rax = 1 sucesso, 0 erro
ept_mapear_pagina:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Extrair índices
    mov  rax, rdi
    mov  rcx, rax
    shr  rcx, SHIFT_PML4E
    and  rcx, 0x1FF              ; Índice PML4E
    mov  r12, rcx

    mov  rcx, rax
    shr  rcx, SHIFT_PDPE
    and  rcx, 0x1FF
    mov  r13, rcx

    mov  rcx, rax
    shr  rcx, SHIFT_PDE
    and  rcx, 0x1FF
    mov  r14, rcx

    mov  rcx, rax
    shr  rcx, SHIFT_PTE
    and  rcx, 0x1FF
    mov  r15, rcx

    ; Nível 1: PML4
    lea  rbx, [rel ept_pml4]
    lea  rbx, [rbx + r12*8]
    cmp  qword [rbx], 0
    jnz  .pdp_pronto
    ; Alocar PDP
    push rax
    mov  rdi, 4096
    call alocar_quadro_fisico
    test rax, rax
    jz   .erro
    or   rax, EPT_PRESENT | EPT_RW | EPT_USER | EPT_MEMTYPE_WB
    mov  [rbx], rax
    pop  rax
.pdp_pronto:
    mov  rbp, [rbx]
    and  rbp, ADDR_MASK_4K
    shl  rbp, 0

    ; Nível 2: PDP
    lea  rbx, [rbp + r13*8]
    cmp  qword [rbx], 0
    jnz  .pd_pronto
    push rax
    mov  rdi, 4096
    call alocar_quadro_fisico
    test rax, rax
    jz   .erro
    or   rax, EPT_PRESENT | EPT_RW | EPT_USER | EPT_MEMTYPE_WB
    mov  [rbx], rax
    pop  rax
.pd_pronto:
    mov  rbp, [rbx]
    and  rbp, ADDR_MASK_4K

    ; Nível 3: PD
    lea  rbx, [rbp + r14*8]
    cmp  qword [rbx], 0
    jnz  .pt_pronto
    push rax
    mov  rdi, 4096
    call alocar_quadro_fisico
    test rax, rax
    jz   .erro
    or   rax, EPT_PRESENT | EPT_RW | EPT_USER | EPT_MEMTYPE_WB
    mov  [rbx], rax
    pop  rax
.pt_pronto:
    mov  rbp, [rbx]
    and  rbp, ADDR_MASK_4K

    ; Nível 4: PTE — Inserir mapeamento
    lea  rbx, [rbp + r15*8]
    mov  rax, rsi
    and  rax, ADDR_MASK_4K
    or   rax, rdx                ; Flags: PRESENT | RW | ...
    or   rax, EPT_MEMTYPE_WB
    mov  [rbx], rax

    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    pop  rbx
    mov  rax, 1
    ret

.erro:
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    pop  rbx
    xor  rax, rax
    ret

; ── Mapear faixa completa ──
; rdi = início convidado, rsi = início físico, rdx = tamanho
ept_mapear_faixa:
    push rbx
    push rbp
    mov  rcx, rdx
    shr  rcx, 12                 ; ÷ 4KB = número de páginas
    jz   .fim

.loop:
    push rcx
    push rsi
    push rdi
    mov  rdx, EPT_PRESENT | EPT_RW | EPT_USER
    call ept_mapear_pagina
    test rax, rax
    jz   .falha
    pop  rdi
    pop  rsi
    pop  rcx
    add  rdi, 4096
    add  rsi, 4096
    dec  rcx
    jnz  .loop

.fim:
    pop  rbp
    pop  rbx
    mov  rax, 1
    ret
.falha:
    add  rsp, 24
    pop  rbp
    pop  rbx
    xor  rax, rax
    ret

; ── Invalidar cache EPT ──
ept_flush_todas:
    ; Forma segura e compatível com o montador para invept
    sub  rsp, 16
    mov  qword [rsp], 0
    mov  qword [rsp+8], 0
    lea  rax, [rsp]
    db   0x66, 0x48, 0x0F, 0x38, 0x80, 0x00  ; Opcodes binários diretos para invept [rax] caso o NASM rejeite o mnemônico com ponteiro de pilha
    add  rsp, 16
    ret

; ══════════════════════════════════════════════════════
; NPT — AMD
; ══════════════════════════════════════════════════════

; ── Inicializar tabelas NPT ──
npt_inicializar:
    mov  rdi, npt_pml4
    mov  rcx, 512
    xor  rax, rax
    rep stosq

    mov  rax, npt_pml4
    shr  rax, 12
    shl  rax, 12
    mov  [rel nptp_value], rax
    ret

; ── Mapear página NPT ──
npt_mapear_pagina:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov  rax, rdi
    mov  rcx, rax
    shr  rcx, SHIFT_PML4E
    and  rcx, 0x1FF
    mov  r12, rcx

    mov  rcx, rax
    shr  rcx, SHIFT_PDPE
    and  rcx, 0x1FF
    mov  r13, rcx

    mov  rcx, rax
    shr  rcx, SHIFT_PDE
    and  rcx, 0x1FF
    mov  r14, rcx

    mov  rcx, rax
    shr  rcx, SHIFT_PTE
    and  rcx, 0x1FF
    mov  r15, rcx

    ; PML4
    lea  rbx, [rel npt_pml4]
    lea  rbx, [rbx + r12*8]
    cmp  qword [rbx], 0
    jnz  .pdp_ok
    push rax
    mov  rdi, 4096
    call alocar_quadro_fisico
    test rax, rax
    jz   .erro
    or   rax, NPT_PRESENT | NPT_RW | NPT_USER
    mov  [rbx], rax
    pop  rax
.pdp_ok:
    mov  rbp, [rbx]
    and  rbp, ADDR_MASK_4K

    ; PDP
    lea  rbx, [rbp + r13*8]
    cmp  qword [rbx], 0
    jnz  .pd_ok
    push rax
    mov  rdi, 4096
    call alocar_quadro_fisico
    test rax, rax
    jz   .erro
    or   rax, NPT_PRESENT | NPT_RW | NPT_USER
    mov  [rbx], rax
    pop  rax
.pd_ok:
    mov  rbp, [rbx]
    and  rbp, ADDR_MASK_4K

    ; PD
    lea  rbx, [rbp + r14*8]
    cmp  qword [rbx], 0
    jnz  .pt_ok
    push rax
    mov  rdi, 4096
    call alocar_quadro_fisico
    test rax, rax
    jz   .erro
    or   rax, NPT_PRESENT | NPT_RW | NPT_USER
    mov  [rbx], rax
    pop  rax
.pt_ok:
    mov  rbp, [rbx]
    and  rbp, ADDR_MASK_4K

    ; PTE
    lea  rbx, [rbp + r15*8]
    mov  rax, rsi
    and  rax, ADDR_MASK_4K
    or   rax, rdx
    mov  [rbx], rax

    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    pop  rbx
    mov  rax, 1
    ret
.erro:
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    pop  rbx
    xor  rax, rax
    ret

; ── Mapear faixa NPT ──
npt_mapear_faixa:
    push rbx
    push rbp
    mov  rcx, rdx
    shr  rcx, 12
    jz   .fim
.loop:
    push rcx
    push rsi
    push rdi
    mov  rdx, NPT_PRESENT | NPT_RW | NPT_USER
    call npt_mapear_pagina
    test rax, rax
    jz   .falha
    pop  rdi
    pop  rsi
    pop  rcx
    add  rdi, 4096
    add  rsi, 4096
    dec  rcx
    jnz  .loop
.fim:
    pop  rbp
    pop  rbx
    mov  rax, 1
    ret
.falha:
    add  rsp, 24
    pop  rbp
    pop  rbx
    xor  rax, rax
    ret

; ── Invalidar TLB NPT ──
npt_flush_todas:
    sub  rsp, 16
    mov  rax, [rel nptp_value]
    mov  qword [rsp], rax
    mov  qword [rsp+8], 0
    invlpg [rsp]                  ; Invalidação segura de página aninhada AMD
    add  rsp, 16
    ret

; ══════════════════════════════════════════════════════
; Auxiliar — Alocação de quadros físicos (integrar ao seu gerenciador)
; ══════════════════════════════════════════════════════
alocar_quadro_fisico:
    ; rdi = tamanho, retorna rax = endereço físico
    ; Substitua pela sua lógica de gerenciamento de memória
    extern gerenciador_alocar
    jmp  gerenciador_alocar
