; ==================================================
; FydelisTechOS — Memória Virtual v2.1
; Arquitetura: x86_64 | Sintaxe: NASM
; ==================================================
bits 64
align 4096

; ========== Tabelas de Paginação ==========
section .bss
global pml4_table, pdpt_table, pd_table, pt_table

pml4_table:   resb 4096   ; Nível 4 — PML4
pdpt_table:   resb 4096   ; Nível 3 — PDPT
pd_table:     resb 4096   ; Nível 2 — PD
pt_table:     resb 4096   ; Nível 1 — PT

; ========== Código ==========
section .text
global init_virtual_memory
global load_page_tables
global page_fault_handler

; ─────────────────────────────────────
; Inicializar tabelas de paginação
; ─────────────────────────────────────
init_virtual_memory:
    ; Limpar todas as tabelas usando endereçamento relativo
    lea  rdi, [rel pml4_table]
    mov  rcx, 512 * 4
    xor  rax, rax
    rep stosq

    ; PML4[0] → aponta para PDPT (Presente + Gravável)
    lea  rax, [rel pdpt_table]
    or   rax, 0b11
    lea  rbx, [rel pml4_table]
    mov  [rbx], rax

    ; PDPT[0] → aponta para PD
    lea  rax, [rel pd_table]
    or   rax, 0b11
    lea  rbx, [rel pdpt_table]
    mov  [rbx], rax

    ; PD[0] → aponta para PT
    lea  rax, [rel pt_table]
    or   rax, 0b11
    lea  rbx, [rel pd_table]
    mov  [rbx], rax

    ; PT → Mapear primeiros 2MB (512 páginas × 4KB)
    lea  rdi, [rel pt_table]
    mov  rcx, 512
    mov  rbx, 0x00000000
.loop_pt:
    mov  rax, rbx
    or   rax, 0b11
    mov  [rdi], rax
    add  rdi, 8
    add  rbx, 4096
    dec  rcx
    jnz  .loop_pt

    ret

; ─────────────────────────────────────
; Ativar paginação
; ─────────────────────────────────────
load_page_tables:
    ; Carregar PML4 no CR3 usando ponteiro relativo
    lea  rax, [rel pml4_table]
    mov  cr3, rax

    ; Ativar PAE (CR4 bit 5)
    mov  rax, cr4
    or   rax, 1 << 5
    mov  cr4, rax

    ; Ativar modo longo (EFER.LME)
    mov  ecx, 0xC0000080
    rdmsr
    or   eax, 1 << 8
    wrmsr

    ; Ligar paginação (CR0 bit 31)
    mov  rax, cr0
    or   rax, 1 << 31
    mov  cr0, rax

    ret

; ─────────────────────────────────────
; Tratador de Falta de Página (#14)
; ─────────────────────────────────────
page_fault_handler:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    mov  rax, cr2        ; Endereço que causou o erro
    push rax
    mov  rax, [rsp + 15*8 + 8]
    push rax

    ; call page_fault_dispatch

    add  rsp, 16
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  r11
    pop  r10
    pop  r9
    pop  r8
    pop  rbp
    pop  rdi
    pop  rsi
    pop  rdx
    pop  rcx
    pop  rbx
    pop  rax
    add  rsp, 8
    iretq
